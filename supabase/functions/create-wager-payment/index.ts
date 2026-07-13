// supabase/functions/create-wager-payment/index.ts
//
// Étapes 1-4 du flow de paiement Binance Pay :
//   1. User choisit bet/prediction + option + montant → Flutter
//   2. Backend crée le wager avec un amount_unique (6 décimales,
//      précision TRC20) garanti sans collision parmi les paiements en
//      attente sur l'adresse de dépôt centrale.
//   3-4. Backend renvoie adresse + amount_unique + wager_id à Flutter,
//      qui affiche le QR code + le montant exact à copier.
//
// Le montant unique désambiguïse les dépôts puisque TOUS les users
// paient vers la même adresse centrale : on ajoute un micro-supplément
// (jusqu'à 0.000999 USDT) à amount_requested, tiré au sort, en vérifiant
// qu'aucun autre wager "pending_payment" n'a déjà ce montant exact.

import { createClient } from "jsr:@supabase/supabase-js@2";

const DEPOSIT_ADDRESS = Deno.env.get("BINANCE_USDT_TRC20_DEPOSIT_ADDRESS") ?? "";
const MAX_UNIQUENESS_ATTEMPTS = 25;

function randomMicroSuffix(): number {
  // 1 à 999 micro-unités (0.000001 à 0.000999 USDT) pour désambiguïser.
  return 1 + Math.floor(Math.random() * 999);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405 });
  }
  if (!DEPOSIT_ADDRESS) {
    return new Response(JSON.stringify({ error: "deposit_address_not_configured" }), { status: 500 });
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

  let body: {
    betId?: string;
    predictionEventId?: string;
    chosenOption?: string;
    amount?: number;
  };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400 });
  }

  const { betId, predictionEventId, chosenOption, amount } = body;
  if ((!betId && !predictionEventId) || (betId && predictionEventId)) {
    return new Response(
      JSON.stringify({ error: "must_reference_exactly_one_of_bet_or_prediction" }),
      { status: 400 },
    );
  }
  if (!chosenOption || !amount || amount <= 0) {
    return new Response(JSON.stringify({ error: "missing_or_invalid_fields" }), { status: 400 });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Résout le public_key de l'user courant (RLS current_pubkey() équivalent côté serveur).
  const { data: profile, error: profileErr } = await admin
    .from("profiles")
    .select("public_key")
    .eq("auth_uid", userData.user.id)
    .single();
  if (profileErr || !profile) {
    return new Response(JSON.stringify({ error: "profile_not_found" }), { status: 404 });
  }

  // Vérifie que le bet/prediction existe et accepte encore des mises.
  if (betId) {
    const { data: bet, error: betErr } = await admin
      .from("bets")
      .select("id,status,staking_deadline")
      .eq("id", betId)
      .single();
    if (betErr || !bet) {
      return new Response(JSON.stringify({ error: "bet_not_found" }), { status: 404 });
    }
    if (bet.status !== "open" || new Date(bet.staking_deadline) < new Date()) {
      return new Response(JSON.stringify({ error: "bet_closed" }), { status: 409 });
    }
  } else {
    const { data: pred, error: predErr } = await admin
      .from("prediction_events")
      .select("id,closes_at,winning_outcome")
      .eq("id", predictionEventId)
      .single();
    if (predErr || !pred) {
      return new Response(JSON.stringify({ error: "prediction_not_found" }), { status: 404 });
    }
    if (pred.winning_outcome || Number(pred.closes_at) < Date.now()) {
      return new Response(JSON.stringify({ error: "prediction_closed" }), { status: 409 });
    }
  }

  // Génère un amount_unique sans collision parmi les paiements en attente.
  const base = Math.round(amount * 1_000_000); // micro-unités
  let amountUnique: number | null = null;
  let wagerRow: Record<string, unknown> | null = null;

  for (let attempt = 0; attempt < MAX_UNIQUENESS_ATTEMPTS; attempt++) {
    const candidateMicro = base + randomMicroSuffix();
    const candidate = candidateMicro / 1_000_000;

    const { data: inserted, error: insertErr } = await admin
      .from("wagers")
      .insert({
        bet_id: betId ?? null,
        prediction_event_id: predictionEventId ?? null,
        user_public_key: profile.public_key,
        chosen_option: chosenOption,
        amount_requested: amount,
        amount_unique: candidate,
        deposit_address: DEPOSIT_ADDRESS,
        status: "pending_payment",
      })
      .select()
      .single();

    if (!insertErr) {
      amountUnique = candidate;
      wagerRow = inserted;
      break;
    }
    // Code 23505 = violation de contrainte unique (amount_unique déjà pris) → on retente.
    if (insertErr.code !== "23505") {
      return new Response(JSON.stringify({ error: "insert_failed", detail: insertErr.message }), { status: 500 });
    }
  }

  if (!amountUnique || !wagerRow) {
    return new Response(JSON.stringify({ error: "could_not_generate_unique_amount_try_again" }), { status: 503 });
  }

  return new Response(
    JSON.stringify({
      wagerId: wagerRow.id,
      depositAddress: DEPOSIT_ADDRESS,
      amountExact: amountUnique.toFixed(6),
      currency: "USDT",
      network: "TRC20",
      status: "pending_payment",
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
