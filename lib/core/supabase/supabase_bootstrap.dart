// lib/core/supabase/supabase_bootstrap.dart
//
// Initialise la messagerie/le profil Supabase de façon ASYNCHRONE et
// NON BLOQUANTE pour le reste de l'app : le wallet, le DAG, le marché
// OTC (tout ce qui tourne sur P2PNode) n'ont aucune raison d'attendre
// que Supabase réponde pour s'afficher.
//
// Historique du bug corrigé : auparavant, `app.dart` bloquait TOUT
// l'écran sur un CircularProgressIndicator tant que le messenger
// Supabase n'était pas prêt. Si `--dart-define` était oublié, ou si le
// réseau/edge-function était lent ou en échec, l'app restait figée
// indéfiniment — même pour consulter son wallet. Ce fichier centralise
// l'init avec des timeouts explicites et un état observable
// (initializing/ready/unavailable/error) que l'UI peut afficher sans
// bloquer le reste de l'app.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';
import 'supabase_identity_service.dart';
import 'presence_service.dart';
import 'profile_service.dart';
import '../kernels/messenger/supabase_messenger_kernel.dart';
import '../crypto/signature.dart';
import '../storage/objectbox/store.dart';
import '../utils/node_identity.dart';
import '../utils/logger.dart';
import '../p2p/p2p_node.dart';

enum SupabaseBootstrapStatus { initializing, ready, unavailable, error }

class SupabaseBootstrap extends ChangeNotifier {
  final NodeIdentityKeyPair identity;
  final ObjectBoxStore db;
  final P2PNode? node;

  SupabaseBootstrap({required this.identity, required this.db, this.node});

  SupabaseBootstrapStatus status = SupabaseBootstrapStatus.initializing;
  String? errorMessage;

  SupabaseMessengerKernel? messenger;
  PresenceService? presence;
  ProfileService? profileService;

  bool get isReady => status == SupabaseBootstrapStatus.ready;

  bool _clientInitialized = false;

  /// Délai maximum toléré pour la liaison d'identité (session anonyme +
  /// edge function bind-identity) avant d'abandonner et de passer en
  /// mode dégradé — évite qu'un réseau lent bloque indéfiniment la
  /// messagerie (le reste de l'app, lui, n'attend jamais ce délai).
  static const _bindTimeout = Duration(seconds: 12);

  Future<void> start() async {
    await SupabaseConfig.initialize();

    if (!SupabaseConfig.isConfigured) {
      status = SupabaseBootstrapStatus.unavailable;
      errorMessage = "Configuration Supabase manquante (--dart-define=SUPABASE_URL / SUPABASE_ANON_KEY).";
      Logger.error(errorMessage!);
      notifyListeners();
      return;
    }

    status = SupabaseBootstrapStatus.initializing;
    errorMessage = null;
    notifyListeners();
    Logger.info("Connexion à Supabase (${SupabaseConfig.url})…");

    try {
      if (!_clientInitialized) {
        bool alreadyInitialized = false;
        try {
          Supabase.instance.client;
          alreadyInitialized = true;
        } catch (_) {}

        if (!alreadyInitialized) {
          await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey)
              .timeout(_bindTimeout);
        }
        _clientInitialized = true;
        Logger.info("Client Supabase initialisé.");
      }
      final supabase = Supabase.instance.client;

      Logger.info("Liaison de l'identité (session anonyme + signature Ed25519)…");
      final identityService = SupabaseIdentityService(supabase, CryptoService());
      await identityService
          .ensureBound(publicKeyHex: identity.nodeId, keyPair: identity.keyPair)
          .timeout(_bindTimeout);
      Logger.info("Identité liée côté serveur.");

      messenger = SupabaseMessengerKernel(nodeId: identity.nodeId, supabase: supabase, db: db);
      presence = PresenceService(supabase, identity.nodeId)..start();
      profileService = ProfileService(supabase, identity.nodeId);

      if (node != null) {
        node!.initSupabase(supabase);
      }

      status = SupabaseBootstrapStatus.ready;
      Logger.info("SupabaseBootstrap: messagerie prête.");
    } on TimeoutException {
      errorMessage = "Le serveur Supabase ne répond pas (délai dépassé). Vérifie ta connexion.";
      status = SupabaseBootstrapStatus.error;
      Logger.error(errorMessage!);
    } catch (e) {
      errorMessage = "Échec de connexion à la messagerie : $e";
      status = SupabaseBootstrapStatus.error;
      Logger.error(errorMessage!);
    }
    notifyListeners();
  }

  /// Relance l'init depuis zéro — appelé depuis le bouton "Réessayer"
  /// des écrans Chat/Profil en cas d'échec ou de config absente.
  Future<void> retry() async {
    messenger?.dispose();
    presence?.dispose();
    messenger = null;
    presence = null;
    profileService = null;
    await start();
  }

  @override
  void dispose() {
    messenger?.dispose();
    presence?.dispose();
    super.dispose();
  }
}
