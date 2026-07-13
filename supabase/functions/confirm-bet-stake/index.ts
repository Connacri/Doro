// supabase/functions/confirm-bet-stake/index.ts
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// HMAC-SHA256 signature helper for Binance API
async function signBinanceQuery(queryString: string, apiSecret: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(apiSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signatureBytes = await crypto.subtle.sign(
    "HMAC",
    key,
    enc.encode(queryString)
  );
  return Array.from(new Uint8Array(signatureBytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  // Handle CORS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Authenticate user session
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ error: "unauthenticated" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Parse body
  let body: { stakeId?: string; txId?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { stakeId, txId } = body;
  if (!stakeId || !txId) {
    return new Response(JSON.stringify({ error: "missing_fields" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const adminClient = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // 11. Idempotency Check: verify if this tx_id has ever been used in processed_deposits
  const { data: duplicateTx, error: dupErr } = await adminClient
    .from("processed_deposits")
    .select("tx_id")
    .eq("tx_id", txId)
    .maybeSingle();

  if (duplicateTx) {
    console.warn(`Idempotency Check failed: TxID ${txId} has already been processed.`);
    return new Response(
      JSON.stringify({
        error: "idempotency_error",
        message: "Ce hash de transaction a déjà été utilisé pour un autre pari.",
      }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Retrieve the corresponding bet stake
  const { data: betStake, error: stakeErr } = await adminClient
    .from("bet_stakes")
    .select("*")
    .eq("id", stakeId)
    .single();

  if (stakeErr || !betStake) {
    return new Response(JSON.stringify({ error: "bet_stake_not_found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // If already confirmed, don't re-process
  if (betStake.status === "confirmed") {
    return new Response(JSON.stringify({ ok: true, status: "confirmed", message: "✅ Mise déjà confirmée." }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Get Binance credentials
  const apiKey = Deno.env.get("BINANCE_API_KEY");
  const apiSecret = Deno.env.get("BINANCE_API_SECRET");

  // Fallback for local testing / sandbox mode when credentials are not configured
  if (!apiKey || !apiSecret) {
    console.warn("Binance API keys not configured. Falling back to sandbox/mock mode.");
    
    // For test simulation: if txId starts with "MOCK_SUCCESS_", confirm it, otherwise keep it pending
    if (txId.startsWith("MOCK_SUCCESS_") || txId === "success") {
      await adminClient
        .from("bet_stakes")
        .update({ status: "confirmed", tx_id: txId })
        .eq("id", stakeId);

      await adminClient.from("processed_deposits").insert({
        tx_id: txId,
        bet_stake_id: stakeId,
        amount: betStake.amount_exact,
      });

      return new Response(
        JSON.stringify({ ok: true, status: "confirmed", message: "✅ Mise confirmée (Mode Sandbox)" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } else if (txId.startsWith("MOCK_FAIL_")) {
      await adminClient
        .from("bet_stakes")
        .update({ status: "rejected" })
        .eq("id", stakeId);

      return new Response(
        JSON.stringify({ error: "deposit_rejected", message: "Sandbox: Dépôt rejeté" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } else {
      // Propagation delay simulation for non-mock hashes
      return new Response(
        JSON.stringify({ status: "pending", message: "Dépôt non encore détecté (Mode Sandbox). Réessayez." }),
        { status: 202, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  }

  // 9. Fetch Binance Deposit History
  try {
    const timestamp = Date.now();
    const queryString = `coin=USDT&timestamp=${timestamp}`;
    const signature = await signBinanceQuery(queryString, apiSecret);
    const url = `https://api.binance.com/sapi/v1/capital/deposit/hisrec?${queryString}&signature=${signature}`;

    const binanceResponse = await fetch(url, {
      method: "GET",
      headers: {
        "X-MBX-APIKEY": apiKey,
      },
    });

    if (!binanceResponse.ok) {
      const errText = await binanceResponse.text();
      console.error(`Binance API response error: ${binanceResponse.status} - ${errText}`);
      throw new Error(`Binance API returned code ${binanceResponse.status}`);
    }

    interface BinanceDeposit {
      txId: string;
      amount: string;
      status: number; // 0: pending, 6: credited but cannot withdraw, 1: success
      coin: string;
    }

    const depositHistory: BinanceDeposit[] = await binanceResponse.json();

    // 10. Find matching deposit and verify all 3 conditions together
    const matchingDeposit = depositHistory.find(
      (dep) => dep.txId.toLowerCase() === txId.toLowerCase()
    );

    if (!matchingDeposit) {
      // 12b. Propagation delay: transaction not yet visible in Binance API
      console.info(`TxID ${txId} not found in Binance deposit history yet.`);
      return new Response(
        JSON.stringify({
          status: "pending",
          message: "La transaction n'est pas encore visible sur Binance. Veuillez réessayer dans quelques secondes.",
        }),
        { status: 202, headers: { ...corsHeaders, "Content-Type": "application/json" } } // 202 Accepted = pending
      );
    }

    const condA = matchingDeposit.txId.toLowerCase() === txId.toLowerCase();
    const condB = parseFloat(matchingDeposit.amount) === parseFloat(betStake.amount_exact);
    const condC = matchingDeposit.status === 1; // 1 = success (confirmed)

    if (condA && condB && condC) {
      // 12a. Validation success
      // Perform database updates inside Supabase
      const { error: updateStakeErr } = await adminClient
        .from("bet_stakes")
        .update({ status: "confirmed", tx_id: txId })
        .eq("id", stakeId);

      if (updateStakeErr) {
        throw new Error(`Failed to update stake status: ${updateStakeErr.message}`);
      }

      const { error: insertDepErr } = await adminClient
        .from("processed_deposits")
        .insert({
          tx_id: txId,
          bet_stake_id: stakeId,
          amount: parseFloat(matchingDeposit.amount),
        });

      if (insertDepErr) {
        // Rollback stake status if deposit logging fails
        await adminClient
          .from("bet_stakes")
          .update({ status: "pending_payment", tx_id: null })
          .eq("id", stakeId);
        throw new Error(`Failed to insert processed deposit: ${insertDepErr.message}`);
      }

      console.info(`✅ Bet stake ${stakeId} successfully validated and confirmed via Binance Pay.`);

      return new Response(
        JSON.stringify({
          ok: true,
          status: "confirmed",
          message: "✅ Mise confirmée ! Votre pari est désormais actif.",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } else {
      // 12c. Reject if amount or status is invalid
      let rejectMessage = "Dépôt non valide.";
      if (!condB) {
        rejectMessage = `Le montant du dépôt (${matchingDeposit.amount} USDT) ne correspond pas au montant exact attendu (${betStake.amount_exact} USDT).`;
      } else if (!condC) {
        rejectMessage = "La transaction n'a pas encore été entièrement confirmée sur la blockchain par Binance.";
      }

      console.error(`Validation rejection for Bet Stake ${stakeId}: ${rejectMessage}`);

      // Optional: update stake status to rejected or leave pending for manual audit
      await adminClient
        .from("bet_stakes")
        .update({ status: "rejected" })
        .eq("id", stakeId);

      return new Response(
        JSON.stringify({
          error: "validation_failed",
          message: rejectMessage,
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  } catch (error) {
    console.error(`confirm-bet-edge-function error: ${error.message}`);
    return new Response(
      JSON.stringify({
        error: "internal_server_error",
        message: "Une erreur est survenue lors de la validation. L'incident a été enregistré pour vérification manuelle.",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
