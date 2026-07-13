// supabase/functions/bind-identity/index.ts
// (déployée telle quelle sur le projet rwzsnlfuqmfxouhfbeoi via MCP)
//
// Lie la session anonyme Supabase courante (auth.uid()) a une cle
// publique Ed25519 dont l'utilisateur prouve la possession par une
// signature. SEUL endroit du systeme qui utilise service_role --
// injectee automatiquement par Supabase, jamais stockee dans l'app ni
// dans un secret GitHub.

import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_SKEW_MS = 5 * 60 * 1000;

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.substr(i * 2, 2), 16);
  }
  return out;
}

async function verifyEd25519(publicKeyHex: string, message: string, signatureHex: string): Promise<boolean> {
  try {
    const keyBytes = hexToBytes(publicKeyHex);
    const sigBytes = hexToBytes(signatureHex);
    const key = await crypto.subtle.importKey("raw", keyBytes, { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify("Ed25519", key, sigBytes, new TextEncoder().encode(message));
  } catch (_e) {
    return false;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405 });
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
  const authUid = userData.user.id;

  let body: { publicKeyHex?: string; timestamp?: number; signatureHex?: string; displayName?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), { status: 400 });
  }

  const { publicKeyHex, timestamp, signatureHex, displayName } = body;
  if (!publicKeyHex || !timestamp || !signatureHex) {
    return new Response(JSON.stringify({ error: "missing_fields" }), { status: 400 });
  }
  if (Math.abs(Date.now() - timestamp) > MAX_SKEW_MS) {
    return new Response(JSON.stringify({ error: "timestamp_out_of_range" }), { status: 400 });
  }

  const message = `DORO_BIND:${authUid}:${timestamp}`;
  const validSig = await verifyEd25519(publicKeyHex, message, signatureHex);
  if (!validSig) {
    return new Response(JSON.stringify({ error: "invalid_signature" }), { status: 401 });
  }

  const adminClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Vérifier si cette clé publique est déjà liée à un compte
  const { data: existingByKey, error: getErr } = await adminClient
    .from("profiles")
    .select("auth_uid, display_name")
    .eq("public_key", publicKeyHex)
    .maybeSingle();

  if (getErr) {
    return new Response(JSON.stringify({ error: "bind_failed", detail: getErr.message }), { status: 500 });
  }

  if (existingByKey) {
    if (existingByKey.auth_uid === authUid) {
      // Déjà lié au bon compte, on met juste à jour last_seen et éventuellement display_name
      const { error: updateErr } = await adminClient
        .from("profiles")
        .update({
          display_name: displayName ?? existingByKey.display_name,
          last_seen: new Date().toISOString(),
        })
        .eq("auth_uid", authUid);

      if (updateErr) {
        return new Response(JSON.stringify({ error: "bind_failed", detail: updateErr.message }), { status: 500 });
      }
    } else {
      // Lié à un ancien compte (ex. session anonyme expirée/recréée).
      // On transfère la liaison vers le nouvel authUid pour ne pas perdre les données dépendantes (friendships, etc.) liées à public_key.
      
      // Supprimer un éventuel profil vide temporaire créé pour le nouvel authUid pour éviter les conflits
      const { error: delErr } = await adminClient
        .from("profiles")
        .delete()
        .eq("auth_uid", authUid);

      if (delErr) {
        return new Response(JSON.stringify({ error: "bind_failed", detail: delErr.message }), { status: 500 });
      }

      // Transférer la ligne existante vers le nouvel authUid
      const { error: transferErr } = await adminClient
        .from("profiles")
        .update({
          auth_uid: authUid,
          display_name: displayName ?? existingByKey.display_name,
          last_seen: new Date().toISOString(),
        })
        .eq("public_key", publicKeyHex);

      if (transferErr) {
        return new Response(JSON.stringify({ error: "bind_failed", detail: transferErr.message }), { status: 500 });
      }
    }
  } else {
    // Nouvelle clé publique, on fait un upsert standard
    const { error: upsertErr } = await adminClient
      .from("profiles")
      .upsert(
        {
          auth_uid: authUid,
          public_key: publicKeyHex,
          display_name: displayName ?? null,
          last_seen: new Date().toISOString(),
        },
        { onConflict: "auth_uid" },
      );

    if (upsertErr) {
      return new Response(JSON.stringify({ error: "bind_failed", detail: upsertErr.message }), { status: 500 });
    }
  }

  return new Response(JSON.stringify({ ok: true, publicKey: publicKeyHex }), {
    headers: { "Content-Type": "application/json" },
  });
});
