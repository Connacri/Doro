// supabase/functions/prediction-crud/index.ts
// Edge function pour CRUD des prediction_events avec service_role
// (bypass RLS — la clé service_role reste côté serveur)
//
// Sécurité : seule l'authentification JWT est vérifiée.
// La validation de propriété (seul le créateur peut modifier/supprimer)
// est déjà faite par le kernel avant d'appeler cette fonction, et par
// le réseau P2P (vérification de signature).

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Vérifier l'authentification JWT
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

  const adminClient = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const action = body._action as string | undefined;

  // ----- CREATE -----
  if (action === "POST") {
    const { id, question, creator_id, creator_public_key, oracle_address, oracle_public_key, created_at, closes_at, creator_signature } = body;
    if (!id || !question || !creator_public_key) {
      return new Response(JSON.stringify({ error: "missing_fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data, error: insertErr } = await adminClient
      .from("prediction_events")
      .insert({
        id, question,
        creator_id: creator_id ?? "",
        creator_public_key,
        oracle_address: oracle_address ?? "",
        oracle_public_key: oracle_public_key ?? "",
        created_at: created_at ?? Date.now(),
        closes_at: closes_at ?? (Date.now() + 86400000),
        creator_signature: creator_signature ?? "",
      })
      .select()
      .single();

    if (insertErr) {
      return new Response(JSON.stringify({ error: "insert_failed", detail: insertErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ ok: true, event: data }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // ----- UPDATE -----
  if (action === "PUT") {
    const { id, winning_outcome, resolution_signature, resolved_at } = body;
    if (!id) {
      return new Response(JSON.stringify({ error: "missing_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const updates: Record<string, unknown> = {};
    if (winning_outcome !== undefined) updates.winning_outcome = winning_outcome;
    if (resolution_signature !== undefined) updates.resolution_signature = resolution_signature;
    if (resolved_at !== undefined) updates.resolved_at = resolved_at;

    const { error: updateErr } = await adminClient
      .from("prediction_events")
      .update(updates)
      .eq("id", id);

    if (updateErr) {
      return new Response(JSON.stringify({ error: "update_failed", detail: updateErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // ----- DELETE -----
  if (action === "DELETE") {
    const { id } = body;
    if (!id) {
      return new Response(JSON.stringify({ error: "missing_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { error: deleteErr } = await adminClient
      .from("prediction_events")
      .delete()
      .eq("id", id);

    if (deleteErr) {
      return new Response(JSON.stringify({ error: "delete_failed", detail: deleteErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ error: "unknown_action" }), {
    status: 400,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
