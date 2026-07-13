// supabase/functions/confirm-wager-payment/index.ts
//
// Étapes 8-12 du flow de paiement Binance Pay :
//   8.  Reçoit tx_id, cherche le wager "pending_payment" correspondant.
//   9.  Appelle Binance GET /sapi/v1/capital/deposit/hisrec?coin=USDT
//       et cherche le dépôt dont txId == tx_id soumis.
//   10. Vérifie ENSEMBLE (pas une seule) :
//       a) le txId existe dans l'historique des dépôts Binance
//       b) amount du dépôt == amount_unique attendu (égalité stricte)
//       c) status du dépôt == 1 ("success", assez de confirmations réseau)
//   11. Vérifie l'idempotency via processed_deposits (tx_id unique).
//   12a. Si les 3 conditions passent : pending_payment -> confirmed,
//        insère dans processed_deposits, notifie via Realtime (l'UPDATE
//        de la ligne `wagers` déclenche automatiquement le changement
//        Realtime déjà activé en migration).
//   12b. Si le txId n'existe pas encore côté Binance (propagation en
//        cours) : répond "pending", le client retente.
//   12c. Si montant ne correspond pas ou txId déjà utilisé ailleurs :
//        rejette avec message clair, log l'incident pour investigation.

import { createClient } from "jsr:@supabase/supabase-js@2";

const BINANCE_API_KEY = Deno.env.get("BINANCE_API_KEY") ?? "";
const BINANCE_API_SECRET = Deno.env.get("BINANCE_API_SECRET") ?? "";
const BINANCE_BASE_URL = "https://api.binance.com";
const AMOUNT_EPSILON = 0.0000005; // tolérance flottante autour de l'égalité stricte 6 décimales

interface BinanceDeposit {
  amount: string;
  coin: string;
  network: string;
  status: number; // 0=pending confirmations réseau, 6=credited but cannot withdraw, 1=success
  address: string;
  txId: string;
  insertTime: number;
}

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sigBuf = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sigBuf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function fetchBinanceDeposits(coin: string): Promise<BinanceDeposit[]> {
  const timestamp = Date.now();
  const query = `coin=${coin}&timestamp=${timestamp}&recvWindow=20000`;
  const signature = await hmacSha256Hex(BINANCE_API_SECRET, query);
  const url = `${BINANCE_BASE_URL}/sapi/v1/capital/deposit/hisrec?${query}&signature=${signature}`;

  const res = await fetch(url, {
    headers: { "X-MBX-APIKEY": BINANCE_API_KEY },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`binance_api_error ${res.status}: ${text}`);
  }
  return (await res.json()) as BinanceDeposit[];
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405 });
  }
  if (!BINANCE_API_KEY || !BINANCE_API_SECRET) {
    return new Response(JSON.stringify({ error: "binance_credentials_not_configured" }), { status: 500 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ error: "unauthenticated" }), { status: 401 });
  }

  let body: { wagerId?: string; txId?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400 });
  }
  const { wagerId, txId } = body;
  if (!wagerId || !txId) {
    return new Response(JSON.stringify({ error: "missing_fields" }), { status: 400 });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // --- Étape 8 : récupère le wager "pending_payment" ---
  const { data: wager, error: wagerErr } = await admin
    .from("wagers")
    .select("id,user_public_key,amount_unique,status,deposit_address")
    .eq("id", wagerId)
    .single();

  if (wagerErr || !wager) {
    return new Response(JSON.stringify({ error: "wager_not_found" }), { status: 404 });
  }

  // Seul le propriétaire du wager peut soumettre son txId.
  const { data: profile } = await admin
    .from("profiles")
    .select("public_key")
    .eq("auth_uid", userData.user.id)
    .single();
  if (!profile || profile.public_key !== wager.user_public_key) {
    return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
  }

  if (wager.status === "confirmed") {
    return new Response(JSON.stringify({ status: "confirmed", alreadyConfirmed: true }), { status: 200 });
  }
  if (wager.status !== "pending_payment") {
    return new Response(JSON.stringify({ error: "wager_not_pending", status: wager.status }), { status: 409 });
  }

  // --- Étape 11 (partie 1) : anti réutilisation du txId, avant même l'appel Binance ---
  const { data: alreadyUsed } = await admin
    .from("processed_deposits")
    .select("tx_id,wager_id")
    .eq("tx_id", txId)
    .maybeSingle();

  if (alreadyUsed && alreadyUsed.wager_id !== wager.id) {
    await admin
      .from("wagers")
      .update({ status: "rejected", reject_reason: "tx_id_already_used", tx_id: txId })
      .eq("id", wager.id)
      .eq("status", "pending_payment");
    console.error(`[confirm-wager-payment] INCIDENT: txId ${txId} déjà utilisé pour wager ${alreadyUsed.wager_id}, tenté sur ${wager.id}`);
    return new Response(
      JSON.stringify({ error: "tx_id_already_used", message: "Ce hash de transaction a déjà été utilisé pour un autre pari." }),
      { status: 409 },
    );
  }

  // --- Étape 9 : interroge l'historique des dépôts Binance ---
  let deposits: BinanceDeposit[];
  try {
    deposits = await fetchBinanceDeposits("USDT");
  } catch (e) {
    console.error("[confirm-wager-payment] Binance API error:", e);
    return new Response(JSON.stringify({ error: "binance_unreachable", retry: true }), { status: 502 });
  }

  const matchingDeposit = deposits.find((d) => d.txId === txId);

  // --- Étape 12b : txId pas encore visible côté Binance (propagation réseau) ---
  if (!matchingDeposit) {
    return new Response(
      JSON.stringify({ status: "pending", message: "Transaction pas encore visible, réessaie dans quelques secondes.", retry: true }),
      { status: 202 },
    );
  }

  // --- Étape 10 : les 3 conditions ENSEMBLE ---
  const depositAmount = parseFloat(matchingDeposit.amount);
  const expectedAmount = parseFloat(String(wager.amount_unique));
  const amountMatches = Math.abs(depositAmount - expectedAmount) < AMOUNT_EPSILON;
  const isSuccess = matchingDeposit.status === 1;
  const txExists = true; // on est dans le bloc où matchingDeposit existe

  if (!txExists || !amountMatches || !isSuccess) {
    // --- Étape 12c : montant ne correspond pas / pas encore confirmé réseau ---
    if (!isSuccess) {
      // Confirmations réseau en cours, pas une erreur définitive → on invite à retenter.
      return new Response(
        JSON.stringify({ status: "pending", message: "Dépôt détecté, en attente de confirmations réseau.", retry: true }),
        { status: 202 },
      );
    }
    await admin
      .from("wagers")
      .update({ status: "rejected", reject_reason: "amount_mismatch", tx_id: txId })
      .eq("id", wager.id)
      .eq("status", "pending_payment");
    console.error(
      `[confirm-wager-payment] INCIDENT: montant reçu ${depositAmount} != attendu ${expectedAmount} pour wager ${wager.id} (tx ${txId})`,
    );
    return new Response(
      JSON.stringify({ error: "amount_mismatch", message: "Le montant reçu ne correspond pas au montant attendu pour ce pari." }),
      { status: 409 },
    );
  }

  // --- Étape 11 (partie 2) : insertion idempotente dans processed_deposits ---
  const { error: idemErr } = await admin
    .from("processed_deposits")
    .insert({ tx_id: txId, wager_id: wager.id, amount: depositAmount });

  if (idemErr) {
    // Violation de contrainte unique = quelqu'un d'autre a traité ce txId entretemps (race condition).
    console.error(`[confirm-wager-payment] INCIDENT: race condition idempotency sur txId ${txId}:`, idemErr.message);
    return new Response(
      JSON.stringify({ error: "tx_id_already_used", message: "Ce hash de transaction a déjà été traité." }),
      { status: 409 },
    );
  }

  // --- Étape 12a : tout est bon → confirme le wager ---
  const { error: confirmErr } = await admin
    .from("wagers")
    .update({ status: "confirmed", tx_id: txId, confirmed_at: new Date().toISOString() })
    .eq("id", wager.id)
    .eq("status", "pending_payment"); // garde-fou anti double confirmation concurrente

  if (confirmErr) {
    console.error("[confirm-wager-payment] Échec update final:", confirmErr.message);
    return new Response(JSON.stringify({ error: "confirm_update_failed" }), { status: 500 });
  }

  return new Response(
    JSON.stringify({ status: "confirmed", wagerId: wager.id, txId, amount: depositAmount }),
    { headers: { "Content-Type": "application/json" } },
  );
});
