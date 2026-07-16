// lib/core/kernels/prediction/prediction_market_kernel.dart
import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../crypto/signature.dart';
import '../../dag/dag_engine.dart';
import '../../dag/transaction_model.dart';
import '../../p2p/webrtc_engine.dart';
import '../../prediction/escrow_address.dart';
import '../../prediction/prediction_event.dart';
import '../../prediction/profit_calculator.dart';
import '../../prediction/share_order.dart';
import '../../storage/repositories/outcome_position_repository.dart';
import '../../storage/repositories/prediction_event_repository.dart';
import '../../storage/repositories/trade_repository.dart';
import '../../storage/repositories/share_order_repository.dart';
import '../../market/trade_model.dart';
import '../../market/order_model.dart' show OrderSide;
import '../../utils/id_generator.dart';
import '../../utils/node_identity.dart';
import '../../utils/logger.dart';
import '../../wallet/address_generator.dart';
import '../../supabase/supabase_config.dart';

/// Marché prédictif binaire "winner takes all" au-dessus du DAG Doro.
///
/// Doro n'a pas de VM à contrats intelligents : ce kernel implémente donc
/// l'escrow et le règlement comme des RÈGLES PROTOCOLAIRES appliquées
/// identiquement par chaque pair honnête (exactement comme
/// `Genesis.isMintAddress` est déjà une exception protocolaire dans
/// `DagEngine`), plutôt que comme du code exécuté par un contrat.
///
/// Cycle de vie d'un event :
///  1. createAndPublishEvent — question + oracle désigné, signé, gossipé.
///  2. mintCompleteSet — un utilisateur dépose 1 DORO (par part) dans
///     l'escrow (adresse sans clé privée, voir EscrowAddress) via une
///     VRAIE tx DAG signée, ce qui la débite immédiatement de son solde
///     (send). Comme aucune clé privée n'existe pour l'escrow, aucun
///     `receive` ne pourra jamais créditer ce montant ailleurs que par la
///     règle de paiement des gagnants ci-dessous — les fonds sont donc
///     réellement bloqués. Il diffuse ensuite une preuve signée
///     (`set_minted`) que chaque pair vérifie contre SON PROPRE
///     `dag.ledger` avant de créditer 1 part OUI + 1 part NON.
///  3. Les parts OUI/NON s'échangent ensuite via le carnet d'ordres
///     existant (MarketKernel) en utilisant `currency ==
///     "EVENT:`<eventId>`:YES"` ou `"...:NO"`, prix exprimé en unités
///     atomiques DORO — aucune modification de MarketKernel nécessaire.
///  4. resolveEvent — seul le détenteur de `oracleAddress` peut signer
///     la résolution. Chaque pair vérifie cette signature avant de
///     marquer l'event résolu localement.
///  5. claimPayout — un détenteur de parts gagnantes diffuse une
///     réclamation signée ; CHAQUE pair qui la reçoit, vérifie qu'elle
///     est fondée (event résolu + parts gagnantes réellement détenues
///     dans SON état local + pas déjà réclamées), applique alors un
///     crédit direct sur `dag.balances` pour le réclamant — un "mint"
///     protocolaire strictement plafonné par les parts gagnantes non
///     encore réclamées, jamais par une signature de l'escrow (qui ne
///     peut pas exister).
class PredictionMarketKernel {
  final NodeIdentityKeyPair identity;
  final WebRTCNetworkEngine p2p;
  final DagEngine dag;
  final PredictionEventRepository eventRepo;
  final OutcomePositionRepository positionRepo;
  final TradeRepository tradeRepo;
  final ShareOrderRepository shareOrderRepo;

  final CryptoService _crypto = CryptoService();

  final Set<String> _seenEvents = {};
  final Set<String> _seenMints = {}; // dédupliqué par txId de dépôt
  final Set<String> _seenClaims = {}; // dédupliqué par claimId
  bool _payoutsRestored = false; // garde-fou de restoreClaimedPayouts()

  final _eventChanges = StreamController<void>.broadcast();
  Stream<void> get eventChanges => _eventChanges.stream;
  final _positionChanges = StreamController<void>.broadcast();
  Stream<void> get positionChanges => _positionChanges.stream;
  final _orderChanges = StreamController<void>.broadcast();
  Stream<void> get orderChanges => _orderChanges.stream;

  SupabaseClient? _supabase;
  SupabaseClient? _adminSupabase;
  RealtimeChannel? _eventsChannel;
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _tradesChannel;

  void initSupabase(SupabaseClient client) {
    if (_supabase != null) return;
    _supabase = client;
    if (SupabaseConfig.serviceRoleKey.isNotEmpty) {
      _adminSupabase = SupabaseClient(SupabaseConfig.url, SupabaseConfig.serviceRoleKey);
      Logger.info("PredictionMarketKernel: admin client créé avec service_role");
    } else {
      Logger.warn("PredictionMarketKernel: pas de service_role — CRUD Supabase désactivé");
    }
    _subscribeRealtime();
    _hydratePredictionsFromServer();
  }

  void _subscribeRealtime() {
    if (_supabase == null) return;
    Logger.info("PredictionMarketKernel: Subscribing to Supabase Realtime...");

    _eventsChannel = _supabase!
        .channel('public:prediction_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'prediction_events',
          callback: _onEventChange,
        )
        .subscribe();

    _ordersChannel = _supabase!
        .channel('public:share_orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'share_orders',
          callback: _onOrderChange,
        )
        .subscribe();

    _tradesChannel = _supabase!
        .channel('public:prediction_trades')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'prediction_trades',
          callback: _onTradeChange,
        )
        .subscribe();
  }

  void _onEventChange(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    if (row.isEmpty) return;

    try {
      final event = PredictionEvent(
        id: row['id'] as String,
        question: row['question'] as String,
        creatorId: row['creator_id'] as String,
        creatorPublicKey: row['creator_public_key'] as String,
        oracleAddress: row['oracle_address'] as String,
        oraclePublicKey: row['oracle_public_key'] as String,
        createdAt: row['created_at'] is String ? int.parse(row['created_at']) : row['created_at'] as int,
        closesAt: row['closes_at'] is String ? int.parse(row['closes_at']) : row['closes_at'] as int,
        creatorSignature: row['creator_signature'] as String,
        winningOutcome: row['winning_outcome'] == null
            ? null
            : (row['winning_outcome'] == "yes" ? PredictionOutcome.yes : PredictionOutcome.no),
        resolutionSignature: row['resolution_signature'] as String?,
        resolvedAt: row['resolved_at'] is String ? int.parse(row['resolved_at']) : row['resolved_at'] as int?,
      );

      final local = eventRepo.get(event.id);
      if (local == null) {
        if (await _verify(event.creationHash, event.creatorPublicKey, event.creatorSignature)) {
          eventRepo.save(event);
          _seenEvents.add(event.id);
          _eventChanges.add(null);
        }
      } else if (!local.isResolved && event.isResolved) {
        eventRepo.save(event);
        _eventChanges.add(null);
      }
    } catch (e) {
      Logger.error("PredictionMarketKernel: Error parsing event from Supabase Realtime: $e");
    }
  }

  void _onOrderChange(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    if (row.isEmpty) return;

    try {
      final order = ShareOrder(
        id: row['id'] as String,
        eventId: row['event_id'] as String,
        outcome: row['outcome'] as String,
        makerId: row['maker_id'] as String,
        makerPublicKey: row['maker_public_key'] as String,
        side: (row['side'] as String) == "buy" ? OrderSide.buy : OrderSide.sell,
        shares: BigInt.parse(row['shares'] as String),
        filledShares: BigInt.parse(row['filled_shares'] as String),
        pricePerShare: BigInt.parse(row['price_per_share'] as String),
        timestamp: row['timestamp'] is String ? int.parse(row['timestamp']) : row['timestamp'] as int,
        signature: row['signature'] as String,
        cancelled: row['cancelled'] as bool? ?? false,
      );

      shareOrderRepo.save(order);
      _orderChanges.add(null);
    } catch (e) {
      Logger.error("PredictionMarketKernel: Error parsing order from Supabase Realtime: $e");
    }
  }

  void _onTradeChange(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    if (row.isEmpty) return;

    try {
      final trade = Trade(
        id: row['id'] as String,
        orderId: row['order_id'] as String,
        sellerId: row['seller_id'] as String,
        buyerId: row['buyer_id'] as String,
        amount: BigInt.parse(row['amount'] as String),
        pricePerUnit: BigInt.parse(row['price_per_unit'] as String),
        currency: row['currency'] as String,
        timestamp: row['timestamp'] is String ? int.parse(row['timestamp']) : row['timestamp'] as int,
        status: TradeStatus.values.firstWhere((s) => s.name == row['status']),
        txId: row['tx_id'] as String?,
      );

      tradeRepo.save(trade);
      processTrades(tradeRepo.all());
      _orderChanges.add(null);
    } catch (e) {
      Logger.error("PredictionMarketKernel: Error parsing trade from Supabase Realtime: $e");
    }
  }

  Future<void> _hydratePredictionsFromServer() async {
    if (_supabase == null) return;
    try {
      Logger.info("PredictionMarketKernel: Hydrating predictions from Supabase...");

      final eventsData = await _supabase!.from('prediction_events').select();
      for (final row in eventsData) {
        final event = PredictionEvent(
          id: row['id'] as String,
          question: row['question'] as String,
          creatorId: row['creator_id'] as String,
          creatorPublicKey: row['creator_public_key'] as String,
          oracleAddress: row['oracle_address'] as String,
          oraclePublicKey: row['oracle_public_key'] as String,
          createdAt: row['created_at'] is String ? int.parse(row['created_at']) : row['created_at'] as int,
          closesAt: row['closes_at'] is String ? int.parse(row['closes_at']) : row['closes_at'] as int,
          creatorSignature: row['creator_signature'] as String,
          winningOutcome: row['winning_outcome'] == null
              ? null
              : (row['winning_outcome'] == "yes" ? PredictionOutcome.yes : PredictionOutcome.no),
          resolutionSignature: row['resolution_signature'] as String?,
          resolvedAt: row['resolved_at'] is String ? int.parse(row['resolved_at']) : row['resolved_at'] as int?,
        );
        if (!eventRepo.exists(event.id)) {
          eventRepo.save(event);
        } else {
          final local = eventRepo.get(event.id);
          if (local != null && !local.isResolved && event.isResolved) {
            eventRepo.save(event);
          }
        }
      }
      _eventChanges.add(null);

      final ordersData = await _supabase!.from('share_orders').select();
      for (final row in ordersData) {
        final order = ShareOrder(
          id: row['id'] as String,
          eventId: row['event_id'] as String,
          outcome: row['outcome'] as String,
          makerId: row['maker_id'] as String,
          makerPublicKey: row['maker_public_key'] as String,
          side: (row['side'] as String) == "buy" ? OrderSide.buy : OrderSide.sell,
          shares: BigInt.parse(row['shares'] as String),
          filledShares: BigInt.parse(row['filled_shares'] as String),
          pricePerShare: BigInt.parse(row['price_per_share'] as String),
          timestamp: row['timestamp'] is String ? int.parse(row['timestamp']) : row['timestamp'] as int,
          signature: row['signature'] as String,
          cancelled: row['cancelled'] as bool? ?? false,
        );
        shareOrderRepo.save(order);
      }
      _orderChanges.add(null);

      final tradesData = await _supabase!.from('prediction_trades').select();
      for (final row in tradesData) {
        final trade = Trade(
          id: row['id'] as String,
          orderId: row['order_id'] as String,
          sellerId: row['seller_id'] as String,
          buyerId: row['buyer_id'] as String,
          amount: BigInt.parse(row['amount'] as String),
          pricePerUnit: BigInt.parse(row['price_per_unit'] as String),
          currency: row['currency'] as String,
          timestamp: row['timestamp'] is String ? int.parse(row['timestamp']) : row['timestamp'] as int,
          status: TradeStatus.values.firstWhere((s) => s.name == row['status']),
          txId: row['tx_id'] as String?,
        );
        tradeRepo.save(trade);
      }
      processTrades(tradeRepo.all());
      _orderChanges.add(null);

      Logger.info("PredictionMarketKernel: Hydrated ${eventsData.length} events, ${ordersData.length} orders, ${tradesData.length} trades.");
    } catch (e) {
      Logger.error("PredictionMarketKernel: Error hydrating from Supabase: $e");
    }
  }

  PredictionMarketKernel({
    required this.identity,
    required this.p2p,
    required this.dag,
    required this.eventRepo,
    required this.positionRepo,
    required this.tradeRepo,
    required this.shareOrderRepo,
  }) {
    p2p.messages.listen((msg) {
      final data = msg.data;
      if (data is! Map<String, dynamic>) return;
      switch (data["type"]) {
        case "event_publish": _handleEventPublish(data); break;
        case "event_delete": _handleEventDelete(data); break;
        case "event_resolve": _handleEventResolve(data); break;
        case "set_minted": _handleSetMinted(data); break;
        case "claim_payout": _handleClaimPayout(data); break;
        case "share_order_publish": _handleShareOrderPublish(data); break;
        case "share_order_cancel": _handleShareOrderCancel(data); break;
        case "share_order_fill": _handleShareOrderFill(data); break;
      }
    });
  }

  // ---------------------------------------------------------------------
  // 0. Restauration au démarrage
  // ---------------------------------------------------------------------

  /// À appeler une fois au démarrage, juste après
  /// `WalletKernel.loadPersistedLedger()`.
  ///
  /// BUG CORRIGÉ : `claimPayout`/`_handleClaimPayout` créditent
  /// `dag.balances` directement (`dag.balances.credit(...)`), sans jamais
  /// passer par une `Transaction` signée — impossible de faire autrement
  /// ici, puisqu'aucune clé privée n'existe pour signer un `send` DEPUIS
  /// l'escrow (voir `EscrowAddress`). Résultat : ce crédit n'était QUE en
  /// mémoire. Or `dag.balances` est entièrement reconstruit à chaque
  /// démarrage par `loadPersistedLedger()`, qui ne rejoue QUE
  /// `TxRepository` — donc après un redémarrage, un gain de prediction
  /// market disparaissait de `dag.balances` (solde dépensable) alors même
  /// que `OutcomePositionEntity.sharesClaimed` restait marqué comme
  /// définitivement réclamé côté `OutcomePositionRepository` (persisté,
  /// lui). La part gagnante n'était donc ni dépensable, ni re-réclamable :
  /// le montant s'évaporait silencieusement.
  ///
  /// Le fix ne cherche pas à fabriquer une fausse tx signée par l'escrow
  /// (impossible et non désirable — voir le commentaire de classe
  /// ci-dessus). Il exploite plutôt le fait que `sharesClaimed` EST déjà
  /// durablement persisté par `OutcomePositionRepository.markClaimed` :
  /// c'est la seule source de vérité qui manquait à `dag.balances`, donc
  /// on la rejoue ici, une fois, pour reconstruire exactement le même
  /// crédit qu'au moment du claim d'origine. Le montant est calculé
  /// depuis un ÉTAT final déjà persisté (pas depuis un rejeu
  /// d'évènements) — mais `dag.balances.credit` reste une opération
  /// additive, donc PAS naturellement idempotente : voir le garde-fou
  /// `_payoutsRestored` ci-dessous, qui rend un second appel accidentel
  /// sur la même instance inoffensif.
  void restoreClaimedPayouts() {
    // Contrairement à `DagEngine.addValidated` (idempotent par tx.id), un
    // crédit direct sur `dag.balances` ne l'est pas — un double appel sur
    // la même instance doublerait le crédit. Un seul appel par instance
    // de kernel (donc par démarrage de P2PNode) est le contrat attendu ;
    // ce garde-fou rend un second appel accidentel inoffensif plutôt que
    // silencieusement incorrect.
    if (_payoutsRestored) return;
    _payoutsRestored = true;

    final claimed = positionRepo.allClaimed();
    if (claimed.isEmpty) return;
    var restoredCount = 0;
    for (final position in claimed) {
      final payout = position.sharesClaimed * ProfitCalculator.fullContractValue;
      if (payout <= BigInt.zero) continue;
      dag.balances.credit(position.holderAddress, payout);
      restoredCount++;
    }
    Logger.info(
      "PredictionMarketKernel: $restoredCount position(s) réclamée(s) restaurée(s) dans dag.balances",
    );
  }

  // ---------------------------------------------------------------------
  // 1. Création de l'événement
  // ---------------------------------------------------------------------

  Future<PredictionEvent> createAndPublishEvent({
    required String question,
    required String oracleAddress,
    required String oraclePublicKey,
    required Duration opensFor,
    required KeyPair creatorKeyPair,
    String? creatorAddress,
    String? creatorPublicKey,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final addr = creatorAddress ?? identity.nodeId;
    final pubKey = creatorPublicKey ?? identity.publicKeyHex;
    final unsigned = PredictionEvent(
      id: IdGenerator.generateId("event"),
      question: question,
      creatorId: addr,
      creatorPublicKey: pubKey,
      oracleAddress: oracleAddress,
      oraclePublicKey: oraclePublicKey,
      createdAt: now,
      closesAt: now + opensFor.inMilliseconds,
      creatorSignature: "",
    );
    final sig = await _crypto.sign(utf8.encode(unsigned.creationHash), keyPair: creatorKeyPair);
    final event = PredictionEvent(
      id: unsigned.id, question: unsigned.question, creatorId: unsigned.creatorId,
      creatorPublicKey: unsigned.creatorPublicKey,
      oracleAddress: unsigned.oracleAddress, oraclePublicKey: unsigned.oraclePublicKey,
      createdAt: unsigned.createdAt, closesAt: unsigned.closesAt,
      creatorSignature: _bytesToHex(sig.bytes),
    );

    _seenEvents.add(event.id);
    eventRepo.save(event);
    p2p.broadcast({"type": "event_publish", ...event.toJson()});
    _eventChanges.add(null);

    if (_adminSupabase != null) {
      unawaited(_adminSupabase!.from('prediction_events').insert({
        'id': event.id,
        'question': event.question,
        'creator_id': event.creatorId,
        'creator_public_key': event.creatorPublicKey,
        'oracle_address': event.oracleAddress,
        'oracle_public_key': event.oraclePublicKey,
        'created_at': event.createdAt,
        'closes_at': event.closesAt,
        'creator_signature': event.creatorSignature,
      }).catchError((e) {
        Logger.error("Supabase insert event error: $e");
      }));
    }

    return event;
  }

  Future<void> _handleEventPublish(Map<String, dynamic> data) async {
    late final PredictionEvent event;
    try {
      event = PredictionEvent.fromJson(data);
    } catch (e) {
      Logger.warn("Événement de pari malformé ignoré : $e");
      return;
    }
    if (_seenEvents.contains(event.id) || eventRepo.exists(event.id)) return;
    if (AddressGenerator.generate(event.creatorPublicKey) != event.creatorId) {
      Logger.warn("Événement ${event.id} rejeté : creatorId incohérent avec la clé publique");
      return;
    }
    if (!await _verify(event.creationHash, event.creatorPublicKey, event.creatorSignature)) {
      Logger.warn("Événement ${event.id} rejeté : signature créateur invalide");
      return;
    }
    if (EscrowAddress.isEscrow(event.oracleAddress)) {
      Logger.warn("Événement ${event.id} rejeté : oracle ne peut pas être une adresse d'escrow");
      return;
    }

    _seenEvents.add(event.id);
    eventRepo.save(event);
    p2p.broadcast(data);
    _eventChanges.add(null);
  }

  // ---------------------------------------------------------------------
  // 2. Émission d'un "complete set" (1 part OUI + 1 part NON pour 1 DORO)
  // ---------------------------------------------------------------------

  /// `walletPublicKeyHex` = clé publique du wallet qui paie (peut différer
  /// de l'identité réseau `identity` si l'utilisateur a plusieurs wallets).
  Future<String?> mintCompleteSet({
    required PredictionEvent event,
    required BigInt shares,
    required String holderAddress,
    required String holderPublicKeyHex,
    required KeyPair holderKeyPair,
  }) async {
    if (shares <= BigInt.zero) return null;
    if (DateTime.now().millisecondsSinceEpoch >= event.closesAt) {
      Logger.warn("Émission refusée : événement ${event.id} fermé aux nouvelles parts");
      return null;
    }
    final escrow = EscrowAddress.forEvent(event.id);
    final depositAmount = shares * ProfitCalculator.fullContractValue;

    if (!dag.balances.canSpend(holderAddress, depositAmount)) {
      Logger.warn("Émission refusée : solde insuffisant pour déposer $depositAmount en escrow");
      return null;
    }

    final lastNonce = dag.lastNonceOf(holderAddress);
    final depositTx = await _buildSignedSend(
      from: holderAddress,
      to: escrow,
      amount: depositAmount,
      nonce: lastNonce + 1,
      senderPublicKeyHex: holderPublicKeyHex,
      keyPair: holderKeyPair,
    );

    final result = dag.addValidated(depositTx);
    if (result != DagAcceptResult.accepted) {
      Logger.warn("Dépôt en escrow rejeté localement : $result");
      return null;
    }
    p2p.broadcast({"type": "tx", ...depositTx.toJson()});

    // Je fais confiance à mon propre dépôt immédiatement (je viens de le
    // valider moi-même) — les autres pairs, eux, exigeront la preuve
    // `set_minted` ci-dessous avant de créditer quoi que ce soit.
    _creditCompleteSet(event.id, holderAddress, shares);

    final mintMsg = await _signedMintMessage(event.id, depositTx.id, shares, holderAddress, holderKeyPair);
    p2p.broadcast(mintMsg);

    return depositTx.id;
  }

  Future<Map<String, dynamic>> _signedMintMessage(
    String eventId, String txId, BigInt shares, String holderAddress, KeyPair keyPair,
  ) async {
    final message = "mint:$eventId:$txId:${shares.toString()}:$holderAddress";
    final sig = await _crypto.sign(utf8.encode(message), keyPair: keyPair);
    return {
      "type": "set_minted",
      "eventId": eventId,
      "txId": txId,
      "shares": shares.toString(),
      "holderAddress": holderAddress,
      "signature": _bytesToHex(sig.bytes),
    };
  }

  Future<void> _handleSetMinted(Map<String, dynamic> data) async {
    final eventId = data["eventId"] as String?;
    final txId = data["txId"] as String?;
    final sharesStr = data["shares"] as String?;
    final holderAddress = data["holderAddress"] as String?;
    final signature = data["signature"] as String?;
    if (eventId == null || txId == null || sharesStr == null || holderAddress == null || signature == null) return;
    if (_seenMints.contains(txId)) return;

    final event = eventRepo.get(eventId);
    if (event == null) return;

    late final BigInt shares;
    try {
      shares = BigInt.parse(sharesStr);
    } catch (_) {
      return;
    }
    if (shares <= BigInt.zero) return;

    final message = "mint:$eventId:$txId:${shares.toString()}:$holderAddress";
    // La signature du dépôt utilise la clé du wallet PAYEUR, dont
    // l'adresse est `holderAddress` lui-même (adresse = clé publique,
    // voir AddressGenerator) — on peut donc vérifier directement contre
    // sa propre adresse comme clé publique hex (sans le préfixe "0x").
    if (!await _verify(message, holderAddress.replaceFirst("0x", ""), signature)) {
      Logger.warn("Preuve de mint rejetée pour tx $txId : signature invalide");
      return;
    }

    // Preuve de dépôt on-chain OBLIGATOIRE — exactement le même contrôle
    // que MarketKernel._paymentProven pour les trades OTC.
    final tx = dag.ledger[txId];
    if (tx == null) {
      Logger.warn("Mint rejeté : tx $txId introuvable dans mon DAG local");
      return;
    }
    final escrow = EscrowAddress.forEvent(eventId);
    if (tx.from != holderAddress || tx.to != escrow || tx.type != TxType.send) {
      Logger.warn("Mint rejeté : tx $txId ne correspond pas à un dépôt escrow valide");
      return;
    }
    if (tx.amount != shares * ProfitCalculator.fullContractValue) {
      Logger.warn("Mint rejeté : montant déposé incohérent avec le nombre de parts annoncé");
      return;
    }

    _seenMints.add(txId);
    _creditCompleteSet(eventId, holderAddress, shares);
    p2p.broadcast(data);
  }

  void _creditCompleteSet(String eventId, String holderAddress, BigInt shares) {
    positionRepo.addShares(eventId, "yes", holderAddress, shares);
    positionRepo.addShares(eventId, "no", holderAddress, shares);
    _positionChanges.add(null);
  }

  // ---------------------------------------------------------------------
  // 3. Résolution (oracle uniquement)
  // ---------------------------------------------------------------------

  Future<void> resolveEvent({
    required PredictionEvent event,
    required PredictionOutcome outcome,
    required KeyPair oracleKeyPair,
  }) async {
    final message = PredictionEvent.resolutionMessage(event.id, outcome);
    final sig = await _crypto.sign(utf8.encode(message), keyPair: oracleKeyPair);
    final signatureHex = _bytesToHex(sig.bytes);

    final resolved = event.copyWithResolution(
      outcome: outcome, signature: signatureHex, resolvedAt: DateTime.now().millisecondsSinceEpoch,
    );
    eventRepo.save(resolved);
    p2p.broadcast({
      "type": "event_resolve", "eventId": event.id, "outcome": outcome.name,
      "signature": signatureHex, "oraclePublicKey": event.oraclePublicKey,
      "resolvedAt": resolved.resolvedAt,
    });
    _eventChanges.add(null);

    if (_adminSupabase != null) {
      unawaited(_adminSupabase!.from('prediction_events').update({
        'winning_outcome': outcome.name,
        'resolution_signature': signatureHex,
        'resolved_at': resolved.resolvedAt,
      }).eq('id', event.id).catchError((e) {
        Logger.error("Supabase update event error: $e");
      }));
    }
  }

  Future<PredictionEvent> updateEvent({
    required PredictionEvent event,
    required String question,
    required String oracleAddress,
    required String oraclePublicKey,
    required int closesAt,
    required KeyPair creatorKeyPair,
  }) async {
    if (event.isResolved) {
      throw StateError("Impossible de modifier un événement déjà résolu");
    }

    final unsigned = PredictionEvent(
      id: event.id,
      question: question,
      creatorId: event.creatorId,
      creatorPublicKey: event.creatorPublicKey,
      oracleAddress: oracleAddress,
      oraclePublicKey: oraclePublicKey,
      createdAt: event.createdAt,
      closesAt: closesAt,
      creatorSignature: "",
    );
    final sig = await _crypto.sign(utf8.encode(unsigned.creationHash), keyPair: creatorKeyPair);
    final updated = PredictionEvent(
      id: unsigned.id, question: unsigned.question,
      creatorId: unsigned.creatorId, creatorPublicKey: unsigned.creatorPublicKey,
      oracleAddress: unsigned.oracleAddress, oraclePublicKey: unsigned.oraclePublicKey,
      createdAt: unsigned.createdAt, closesAt: unsigned.closesAt,
      creatorSignature: _bytesToHex(sig.bytes),
    );

    eventRepo.save(updated);
    p2p.broadcast({"type": "event_update", ...updated.toJson()});
    _eventChanges.add(null);

    if (_adminSupabase != null) {
      unawaited(_adminSupabase!.from('prediction_events').update({
        'question': updated.question,
        'oracle_address': updated.oracleAddress,
        'oracle_public_key': updated.oraclePublicKey,
        'closes_at': updated.closesAt,
        'creator_signature': updated.creatorSignature,
      }).eq('id', updated.id).catchError((e) {
        Logger.error("Supabase update event fields error: $e");
      }));
    }

    return updated;
  }

  Future<void> deleteEvent(PredictionEvent event) async {
    if (event.isResolved) {
      Logger.warn("Impossible de supprimer un événement déjà résolu");
      return;
    }

    eventRepo.delete(event.id);
    _seenEvents.remove(event.id);
    p2p.broadcast({"type": "event_delete", "eventId": event.id});
    _eventChanges.add(null);

    if (_adminSupabase != null) {
      unawaited(_adminSupabase!.from('prediction_events').delete().eq('id', event.id).catchError((e) {
        Logger.error("Supabase delete event error: $e");
      }));
    }
  }

  Future<void> _handleEventDelete(Map<String, dynamic> data) async {
    final eventId = data["eventId"] as String?;
    if (eventId == null) return;

    final event = eventRepo.get(eventId);
    if (event == null || event.isResolved) return;

    eventRepo.delete(eventId);
    _seenEvents.remove(eventId);
    p2p.broadcast(data);
    _eventChanges.add(null);
  }

  Future<void> _handleEventResolve(Map<String, dynamic> data) async {
    final eventId = data["eventId"] as String?;
    final outcomeName = data["outcome"] as String?;
    final signature = data["signature"] as String?;
    final oraclePublicKey = data["oraclePublicKey"] as String?;
    final resolvedAt = data["resolvedAt"] as int?;
    if (eventId == null || outcomeName == null || signature == null || oraclePublicKey == null) return;

    final event = eventRepo.get(eventId);
    if (event == null || event.isResolved) return;
    if (AddressGenerator.generate(oraclePublicKey) != event.oracleAddress) {
      Logger.warn("Résolution de $eventId rejetée : signataire n'est pas l'oracle désigné");
      return;
    }

    final outcome = outcomeName == "yes" ? PredictionOutcome.yes : PredictionOutcome.no;
    final message = PredictionEvent.resolutionMessage(eventId, outcome);
    if (!await _verify(message, oraclePublicKey, signature)) {
      Logger.warn("Résolution de $eventId rejetée : signature oracle invalide");
      return;
    }

    eventRepo.save(event.copyWithResolution(
      outcome: outcome, signature: signature, resolvedAt: resolvedAt ?? DateTime.now().millisecondsSinceEpoch,
    ));
    p2p.broadcast(data);
    _eventChanges.add(null);
  }

  // ---------------------------------------------------------------------
  // 4. Réclamation du paiement — 1 DORO par part gagnante
  // ---------------------------------------------------------------------

  /// Retourne le montant crédité (en unités atomiques DORO), ou `null` si
  /// rien n'était réclamable.
  Future<BigInt?> claimPayout({
    required PredictionEvent event,
    required String holderAddress,
    required KeyPair holderKeyPair,
  }) async {
    if (!event.isResolved) return null;
    final outcomeKey = event.winningOutcome == PredictionOutcome.yes ? "yes" : "no";
    final position = positionRepo.get(event.id, outcomeKey, holderAddress);
    final claimable = position.sharesClaimable;
    if (claimable <= BigInt.zero) return null;

    final claimId = IdGenerator.generateId("claim");
    final message = "claim:${event.id}:$claimId:${claimable.toString()}:$holderAddress";
    final sig = await _crypto.sign(utf8.encode(message), keyPair: holderKeyPair);

    final payout = claimable * ProfitCalculator.fullContractValue;

    // J'applique mon propre paiement tout de suite (je viens de vérifier
    // moi-même que j'ai bien ces parts) — les autres pairs re-vérifieront
    // indépendamment avant d'appliquer le même crédit de leur côté.
    _seenClaims.add(claimId);
    positionRepo.markClaimed(event.id, outcomeKey, holderAddress, claimable);
    dag.balances.credit(holderAddress, payout);
    _positionChanges.add(null);

    p2p.broadcast({
      "type": "claim_payout", "eventId": event.id, "claimId": claimId,
      "outcome": outcomeKey, "shares": claimable.toString(),
      "holderAddress": holderAddress, "signature": _bytesToHex(sig.bytes),
    });

    return payout;
  }

  Future<void> _handleClaimPayout(Map<String, dynamic> data) async {
    final eventId = data["eventId"] as String?;
    final claimId = data["claimId"] as String?;
    final outcomeKey = data["outcome"] as String?;
    final sharesStr = data["shares"] as String?;
    final holderAddress = data["holderAddress"] as String?;
    final signature = data["signature"] as String?;
    if (eventId == null || claimId == null || outcomeKey == null || sharesStr == null || holderAddress == null || signature == null) {
      return;
    }
    if (_seenClaims.contains(claimId)) return;

    final event = eventRepo.get(eventId);
    if (event == null || !event.isResolved) return;
    final expectedOutcome = event.winningOutcome == PredictionOutcome.yes ? "yes" : "no";
    if (outcomeKey != expectedOutcome) {
      Logger.warn("Réclamation $claimId rejetée : ne correspond pas à l'issue gagnante");
      return;
    }

    late final BigInt claimedShares;
    try {
      claimedShares = BigInt.parse(sharesStr);
    } catch (_) {
      return;
    }
    if (claimedShares <= BigInt.zero) return;

    final message = "claim:$eventId:$claimId:${claimedShares.toString()}:$holderAddress";
    if (!await _verify(message, holderAddress.replaceFirst("0x", ""), signature)) {
      Logger.warn("Réclamation $claimId rejetée : signature invalide");
      return;
    }

    // Plafonné par ce que MON état local sait réellement détenu et non
    // encore réclamé — un pair malveillant ne peut jamais faire créditer
    // plus que les parts gagnantes légitimement émises via mint prouvé.
    final position = positionRepo.get(eventId, outcomeKey, holderAddress);
    if (claimedShares > position.sharesClaimable) {
      Logger.warn("Réclamation $claimId rejetée : dépasse les parts réclamables connues localement");
      return;
    }

    _seenClaims.add(claimId);
    positionRepo.markClaimed(eventId, outcomeKey, holderAddress, claimedShares);
    dag.balances.credit(holderAddress, claimedShares * ProfitCalculator.fullContractValue);
    p2p.broadcast(data);
    _positionChanges.add(null);
  }

  // ---------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------

  Future<Transaction> _buildSignedSend({
    required String from,
    required String to,
    required BigInt amount,
    required int nonce,
    required String senderPublicKeyHex,
    required KeyPair keyPair,
  }) async {
    final unsigned = Transaction(
      id: IdGenerator.generateId("tx"),
      from: from, to: to, amount: amount,
      parents: dag.tips().take(2).toList(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      nonce: nonce, senderPublicKey: senderPublicKeyHex, signature: "",
    );
    final sig = await _crypto.sign(utf8.encode(unsigned.hash), keyPair: keyPair);
    return Transaction(
      id: unsigned.id, from: unsigned.from, to: unsigned.to, amount: unsigned.amount,
      parents: unsigned.parents, timestamp: unsigned.timestamp, nonce: unsigned.nonce,
      senderPublicKey: unsigned.senderPublicKey, signature: _bytesToHex(sig.bytes),
    );
  }

  Future<bool> _verify(String message, String publicKeyHex, String signatureHex) async {
    try {
      final publicKey = SimplePublicKey(_hexToBytes(publicKeyHex), type: KeyPairType.ed25519);
      final signature = Signature(_hexToBytes(signatureHex), publicKey: publicKey);
      return await _crypto.verify(utf8.encode(message), signature: signature);
    } catch (e) {
      return false;
    }
  }

  String _bytesToHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  final Set<String> _processedTrades = {};

  void processTrades(List<Trade> trades) {
    for (final t in trades) {
      if (t.status != TradeStatus.confirmed) continue;
      if (_processedTrades.contains(t.id)) continue;
      if (!t.currency.startsWith("EVENT:")) continue;

      final parts = t.currency.split(":");
      if (parts.length != 3) continue;
      final eventId = parts[1];
      final outcome = parts[2].toLowerCase();

      _processedTrades.add(t.id);

      positionRepo.addShares(eventId, outcome, t.sellerId, -t.amount);
      positionRepo.addShares(eventId, outcome, t.buyerId, t.amount);

      Logger.info("PredictionMarketKernel: Transferred ${t.amount} $outcome shares of event $eventId from ${t.sellerId} to ${t.buyerId}");
      _positionChanges.add(null);
    }
  }

  // ---------------------------------------------------------------------
  // 6. Carnet d'ordres trustless de parts (ShareOrder)
  // ---------------------------------------------------------------------

  Future<ShareOrder> createAndPublishShareOrder({
    required String eventId,
    required String outcome,
    required String makerId,
    required String makerPublicKeyHex,
    required OrderSide side,
    required BigInt shares,
    required BigInt pricePerShare,
    required KeyPair makerKeyPair,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final id = IdGenerator.generateId("order");
    
    final message = "publish:$id:$eventId:$outcome:$makerId:${side.name}:${shares.toString()}:${pricePerShare.toString()}:$timestamp";
    final sig = await _crypto.sign(utf8.encode(message), keyPair: makerKeyPair);
    final signatureHex = _bytesToHex(sig.bytes);

    final order = ShareOrder(
      id: id,
      eventId: eventId,
      outcome: outcome,
      makerId: makerId,
      makerPublicKey: makerPublicKeyHex,
      side: side,
      shares: shares,
      filledShares: BigInt.zero,
      pricePerShare: pricePerShare,
      timestamp: timestamp,
      signature: signatureHex,
    );

    shareOrderRepo.save(order);
    _orderChanges.add(null);

    p2p.broadcast({
      "type": "share_order_publish",
      "order": order.toJson(),
    });

    if (_supabase != null) {
      unawaited(_supabase!.from('share_orders').insert({
        'id': order.id,
        'event_id': order.eventId,
        'outcome': order.outcome,
        'maker_id': order.makerId,
        'maker_public_key': order.makerPublicKey,
        'side': order.side.name,
        'shares': order.shares.toString(),
        'filled_shares': order.filledShares.toString(),
        'price_per_share': order.pricePerShare.toString(),
        'timestamp': order.timestamp,
        'signature': order.signature,
        'cancelled': order.cancelled,
      }).catchError((e) {
        Logger.error("Supabase insert share order error: $e");
      }));
    }

    return order;
  }

  Future<bool> cancelShareOrder({
    required String orderId,
    required KeyPair makerKeyPair,
  }) async {
    final order = shareOrderRepo.get(orderId);
    if (order == null) return false;
    if (order.cancelled) return true;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final message = "cancel:$orderId:$timestamp";
    final sig = await _crypto.sign(utf8.encode(message), keyPair: makerKeyPair);
    final signatureHex = _bytesToHex(sig.bytes);

    final updated = order.copyWith(cancelled: true);
    shareOrderRepo.save(updated);
    _orderChanges.add(null);

    p2p.broadcast({
      "type": "share_order_cancel",
      "orderId": orderId,
      "timestamp": timestamp,
      "signerPublicKey": order.makerPublicKey,
      "signature": signatureHex,
    });

    if (_supabase != null) {
      unawaited(_supabase!.from('share_orders').update({
        'cancelled': true,
      }).eq('id', orderId).catchError((e) {
        Logger.error("Supabase update share order (cancel) error: $e");
      }));
    }

    return true;
  }

  Future<String?> fillShareOrder({
    required ShareOrder order,
    required BigInt sharesToFill,
    required String buyerAddress,
    required String buyerPublicKeyHex,
    required KeyPair buyerKeyPair,
  }) async {
    if (sharesToFill <= BigInt.zero || sharesToFill > order.remaining) return null;

    final cost = (sharesToFill * order.pricePerShare) ~/ BigInt.from(10).pow(18);
    if (!dag.balances.canSpend(buyerAddress, cost)) {
      Logger.warn("Solde insuffisant pour payer $cost DORO");
      return null;
    }

    final lastNonce = dag.lastNonceOf(buyerAddress);
    final payTx = await _buildSignedSend(
      from: buyerAddress,
      to: order.makerId,
      amount: cost,
      nonce: lastNonce + 1,
      senderPublicKeyHex: buyerPublicKeyHex,
      keyPair: buyerKeyPair,
    );

    final result = dag.addValidated(payTx);
    if (result != DagAcceptResult.accepted) {
      Logger.warn("Paiement rejeté par le DAG local : $result");
      return null;
    }

    p2p.broadcast({"type": "tx", ...payTx.toJson()});

    positionRepo.addShares(order.eventId, order.outcome, buyerAddress, sharesToFill);
    positionRepo.addShares(order.eventId, order.outcome, order.makerId, -sharesToFill);

    final updatedOrder = order.copyWith(filledShares: order.filledShares + sharesToFill);
    shareOrderRepo.save(updatedOrder);

    _orderChanges.add(null);
    _positionChanges.add(null);

    final message = "fill:${order.id}:${payTx.id}:${sharesToFill.toString()}:$buyerAddress";
    final sig = await _crypto.sign(utf8.encode(message), keyPair: buyerKeyPair);
    final signatureHex = _bytesToHex(sig.bytes);

    p2p.broadcast({
      "type": "share_order_fill",
      "orderId": order.id,
      "txId": payTx.id,
      "shares": sharesToFill.toString(),
      "buyerAddress": buyerAddress,
      "signerPublicKey": buyerPublicKeyHex,
      "signature": signatureHex,
    });

    if (_supabase != null) {
      unawaited(_supabase!.from('share_orders').update({
        'filled_shares': updatedOrder.filledShares.toString(),
      }).eq('id', order.id).catchError((e) {
        Logger.error("Supabase update share order (fill) error: $e");
      }));

      unawaited(_supabase!.from('prediction_trades').insert({
        'id': payTx.id,
        'order_id': order.id,
        'seller_id': order.makerId,
        'buyer_id': buyerAddress,
        'amount': sharesToFill.toString(),
        'price_per_unit': order.pricePerShare.toString(),
        'currency': 'EVENT:${order.eventId}:${order.outcome}',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': 'confirmed',
        'tx_id': payTx.id,
      }).catchError((e) {
        Logger.error("Supabase insert prediction trade error: $e");
      }));
    }

    return payTx.id;
  }

  final Set<String> _seenOrderPublishes = {};
  final Set<String> _seenOrderCancels = {};
  final Set<String> _seenOrderFills = {};

  Future<void> _handleShareOrderPublish(Map<String, dynamic> data) async {
    final orderJson = data["order"] as Map<String, dynamic>?;
    if (orderJson == null) return;
    final order = ShareOrder.fromJson(orderJson);
    if (_seenOrderPublishes.contains(order.id)) return;
    _seenOrderPublishes.add(order.id);

    final message = "publish:${order.id}:${order.eventId}:${order.outcome}:${order.makerId}:${order.side.name}:${order.shares.toString()}:${order.pricePerShare.toString()}:${order.timestamp.toString()}";
    if (!await _verify(message, order.makerPublicKey, order.signature)) {
      Logger.warn("Signature d'ordre de part invalide pour ${order.id}");
      return;
    }

    shareOrderRepo.save(order);
    _orderChanges.add(null);
  }

  Future<void> _handleShareOrderCancel(Map<String, dynamic> data) async {
    final orderId = data["orderId"] as String?;
    final timestamp = data["timestamp"] as int?;
    final signerPublicKey = data["signerPublicKey"] as String?;
    final signature = data["signature"] as String?;

    if (orderId == null || timestamp == null || signerPublicKey == null || signature == null) return;
    final cancelKey = "$orderId:$timestamp";
    if (_seenOrderCancels.contains(cancelKey)) return;
    _seenOrderCancels.add(cancelKey);

    final order = shareOrderRepo.get(orderId);
    if (order == null) return;

    if (order.makerPublicKey != signerPublicKey) {
      Logger.warn("Tentative d'annulation d'ordre de part par un non-maker");
      return;
    }

    final message = "cancel:$orderId:$timestamp";
    if (!await _verify(message, signerPublicKey, signature)) {
      Logger.warn("Signature d'annulation d'ordre de part invalide pour $orderId");
      return;
    }

    final updated = order.copyWith(cancelled: true);
    shareOrderRepo.save(updated);
    _orderChanges.add(null);
  }

  Future<void> _handleShareOrderFill(Map<String, dynamic> data) async {
    final orderId = data["orderId"] as String?;
    final txId = data["txId"] as String?;
    final sharesStr = data["shares"] as String?;
    final buyerAddress = data["buyerAddress"] as String?;
    final signerPublicKey = data["signerPublicKey"] as String?;
    final signature = data["signature"] as String?;

    if (orderId == null || txId == null || sharesStr == null || buyerAddress == null || signerPublicKey == null || signature == null) return;
    final fillKey = "$orderId:$txId";
    if (_seenOrderFills.contains(fillKey)) return;
    _seenOrderFills.add(fillKey);

    final order = shareOrderRepo.get(orderId);
    if (order == null) return;

    final shares = BigInt.parse(sharesStr);
    if (shares <= BigInt.zero || shares > order.remaining) return;

    final message = "fill:$orderId:$txId:${shares.toString()}:$buyerAddress";
    if (!await _verify(message, signerPublicKey, signature)) {
      Logger.warn("Signature de remplissage d'ordre de part invalide");
      return;
    }

    final computedBuyer = AddressGenerator.generate(signerPublicKey);
    if (computedBuyer != buyerAddress) {
      Logger.warn("L'adresse de l'acheteur ne correspond pas à la clé publique de signature");
      return;
    }

    final tx = dag.ledger[txId];
    if (tx == null) {
      Logger.warn("Paiement $txId introuvable dans le DAG local pour l'ordre de part $orderId");
      return;
    }

    final expectedCost = (shares * order.pricePerShare) ~/ BigInt.from(10).pow(18);
    if (tx.from != buyerAddress || tx.to != order.makerId || tx.amount < expectedCost || tx.type != TxType.send) {
      Logger.warn("La transaction de paiement $txId ne valide pas les critères requis pour l'ordre de part $orderId");
      return;
    }

    positionRepo.addShares(order.eventId, order.outcome, buyerAddress, shares);
    positionRepo.addShares(order.eventId, order.outcome, order.makerId, -shares);

    final updated = order.copyWith(filledShares: order.filledShares + shares);
    shareOrderRepo.save(updated);

    _orderChanges.add(null);
    _positionChanges.add(null);
  }

  void dispose() {
    _eventsChannel?.unsubscribe();
    _ordersChannel?.unsubscribe();
    _tradesChannel?.unsubscribe();
    _eventChanges.close();
    _positionChanges.close();
    _orderChanges.close();
  }
}
