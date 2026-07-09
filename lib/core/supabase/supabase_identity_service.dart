// lib/core/supabase/supabase_identity_service.dart
//
// Pont entre l'identité Ed25519 de Doro (clé privée dans le secure
// storage, cf. KeypairStore) et l'auth Supabase.
//
// Flow :
//   1. Session anonyme Supabase (clé anon uniquement, jamais de secret).
//   2. Signature Ed25519 locale du message "DORO_BIND:&lt;auth_uid&gt;:&lt;ts&gt;".
//   3. Appel de l'edge function bind-identity qui vérifie la signature
//      et lie auth.uid() <-> public_key côté serveur (service_role,
//      jamais exposée au client).
//
// Après ça, toutes les requêtes Postgrest/Realtime du client passent
// par la session anonyme, et les policies RLS retrouvent la pubkey de
// l'appelant via `current_pubkey()` côté base.
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/signature.dart';
import '../utils/logger.dart';

class SupabaseIdentityService {
  final SupabaseClient _client;
  final CryptoService _crypto;

  SupabaseIdentityService(this._client, this._crypto);

  SupabaseClient get client => _client;

  /// À appeler une fois au démarrage, avec la paire de clés Ed25519 de
  /// l'identité du node (`NodeIdentity.getOrCreate()` — la même clé qui
  /// sert de `nodeId`/adresse partout ailleurs dans l'app). La clé
  /// privée ne quitte jamais l'app : elle sert uniquement à signer le
  /// message de preuve, jamais transmise telle quelle.
  Future<String> ensureBound({
    required String publicKeyHex,
    required KeyPair keyPair,
    String? displayName,
  }) async {
    // 1) Session anonyme (créée une seule fois, persistée par le SDK).
    if (_client.auth.currentSession == null) {
      await _client.auth.signInAnonymously();
    }
    final authUid = _client.auth.currentUser?.id;
    if (authUid == null) {
      throw StateError('SupabaseIdentityService: session anonyme absente après signInAnonymously()');
    }

    // Déjà lié à cette session ? On évite un appel réseau inutile.
    final existing = await _client
        .from('profiles')
        .select('public_key')
        .eq('auth_uid', authUid)
        .maybeSingle();
    if (existing != null && existing['public_key'] == publicKeyHex) {
      return authUid;
    }

    // 2) Signature Ed25519 locale — la clé privée ne quitte jamais l'app.
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final message = 'DORO_BIND:$authUid:$timestamp';
    final signature = await _crypto.signString(message, keyPair: keyPair);
    final signatureHex = signature.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // 3) Vérification + liaison côté serveur (edge function, service_role).
    final res = await _client.functions.invoke(
      'bind-identity',
      body: {
        'publicKeyHex': publicKeyHex,
        'timestamp': timestamp,
        'signatureHex': signatureHex,
        if (displayName != null) 'displayName': displayName,
      },
    );

    if (res.status != 200) {
      final body = res.data is Map ? jsonEncode(res.data) : res.data.toString();
      throw StateError('SupabaseIdentityService: bind-identity a échoué (${res.status}) $body');
    }

    Logger.info('SupabaseIdentityService: identité liée pour $publicKeyHex');
    return authUid;
  }

  Future<void> signOut() => _client.auth.signOut();
}
