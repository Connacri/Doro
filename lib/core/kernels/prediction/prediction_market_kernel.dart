// lib/core/kernels/prediction/prediction_market_kernel.dart
import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
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

  final _eventChanges = StreamController<void>.broadcast();
  Stream<void> get eventChanges => _eventChanges.stream;
  final _positionChanges = StreamController<void>.broadcast();
  Stream<void> get positionChanges => _positionChanges.stream;
  final _orderChanges = StreamController<void>.broadcast();
  Stream<void> get orderChanges => _orderChanges.stream;

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
  // 1. Création de l'événement
  // ---------------------------------------------------------------------

  Future<PredictionEvent> createAndPublishEvent({
    required String question,
    required String oracleAddress,
    required String oraclePublicKey,
    required Duration opensFor,
    required KeyPair creatorKeyPair,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final unsigned = PredictionEvent(
      id: IdGenerator.generateId("event"),
      question: question,
      creatorId: identity.nodeId,
      creatorPublicKey: identity.publicKeyHex,
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
    _eventChanges.close();
    _positionChanges.close();
    _orderChanges.close();
  }
}
