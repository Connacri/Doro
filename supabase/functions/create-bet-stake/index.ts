// supabase/functions/create-bet-stake/index.ts
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

  // Authenticate caller
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
  const authUid = userData.user.id;

  // Read request body
  let body: { betId?: string; optionLabel?: string; baseAmount?: number; stakerId?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { betId, optionLabel, baseAmount, stakerId } = body;
  if (!betId || !optionLabel || !baseAmount || !stakerId) {
    return new Response(JSON.stringify({ error: "missing_fields" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Verify that the stakerId (public key) matches the authUid's profile
  const adminClient = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: profile, error: profileErr } = await adminClient
    .from("profiles")
    .select("public_key")
    .eq("auth_uid", authUid)
    .single();

  if (profileErr || !profile || profile.public_key !== stakerId) {
    return new Response(JSON.stringify({ error: "forbidden", message: "Clé publique incorrecte pour cet utilisateur." }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Generate a unique amount_exact (6 decimals, TRC20 precision)
  // We add a tiny randomized decimal fraction: X.XXXXYY, where XX is a random suffix between 0001 and 9999
  let amountExact = baseAmount;
  let attempts = 0;
  const maxAttempts = 20;
  let isUnique = false;

  while (!isUnique && attempts < maxAttempts) {
    attempts++;
    // Add random micro-cents between 0.000001 and 0.009999 USDT
    const randomSuffix = (Math.floor(Math.random() * 9999) + 1) / 1000000;
    // Format to 6 decimal places strictly to prevent floating point issues
    amountExact = parseFloat((baseAmount + randomSuffix).toFixed(6));

    // Check if there is an active pending stake with this exact amount
    const { data: existingStake, error: checkErr } = await adminClient
      .from("bet_stakes")
      .select("id")
      .eq("amount_exact", amountExact)
      .eq("status", "pending_payment")
      .maybeSingle();

    if (!checkErr && !existingStake) {
      isUnique = true;
    }
  }

  if (!isUnique) {
    return new Response(JSON.stringify({ error: "unique_amount_generation_failed", message: "Impossible de générer un montant de transaction unique. Veuillez réessayer." }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Insert the pending bet stake
  const { data: newStake, error: insertErr } = await adminClient
    .from("bet_stakes")
    .insert({
      bet_id: betId,
      staker_id: stakerId,
      option_label: optionLabel,
      amount: baseAmount,
      amount_exact: amountExact,
      status: "pending_payment",
    })
    .select()
    .single();

  if (insertErr || !newStake) {
    return new Response(JSON.stringify({ error: "insert_failed", detail: insertErr?.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Get deposit address from environment variables
  const depositAddress = Deno.env.get("BINANCE_DEPOSIT_ADDRESS") ?? "TYv371G8v3X2rQY91rX24819Q871Y7Y197"; // TRC20 address fallback

  return new Response(
    JSON.stringify({
      ok: true,
      bet_stake_id: newStake.id,
      amount_exact: amountExact,
      deposit_address: depositAddress,
    }),
    {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});
