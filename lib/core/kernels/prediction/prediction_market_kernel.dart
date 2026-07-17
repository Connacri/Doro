import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../crypto/signature.dart';
import '../../dag/dag_engine.dart';
import '../../dag/transaction_model.dart';
import '../../prediction/escrow_address.dart';
import '../../prediction/prediction_event.dart';
import '../../prediction/profit_calculator.dart';
import '../../prediction/share_order.dart';
import '../../prediction/outcome_position.dart';
import '../../market/trade_model.dart';
import '../../market/order_model.dart' show OrderSide;
import '../../utils/id_generator.dart';
import '../../utils/node_identity.dart';
import '../../utils/logger.dart';
import '../../supabase/supabase_config.dart';

class PredictionMarketKernel {
  final NodeIdentityKeyPair identity;
  final DagEngine dag;

  final CryptoService _crypto = CryptoService();

  final Set<String> _seenEvents = {};
  final Set<String> _seenClaims = {};
  bool _payoutsRestored = false;

  final _eventChanges = StreamController<void>.broadcast();
  Stream<void> get eventChanges => _eventChanges.stream;
  final _positionChanges = StreamController<void>.broadcast();
  Stream<void> get positionChanges => _positionChanges.stream;
  final _orderChanges = StreamController<void>.broadcast();
  Stream<void> get orderChanges => _orderChanges.stream;

  // In-memory caches (hydrated from Supabase)
  final Map<String, PredictionEvent> _events = {};
  final Map<String, ShareOrder> _orders = {};
  final Map<String, OutcomePosition> _positions = {};
  final Map<String, Trade> _trades = {};
  final Set<String> _processedTrades = {};

  SupabaseClient? _supabase;
  SupabaseClient? _adminSupabase;
  RealtimeChannel? _eventsChannel;
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _tradesChannel;
  RealtimeChannel? _positionsChannel;

  bool get isReady => _supabase != null;

  PredictionMarketKernel({
    required this.identity,
    required this.dag,
  });

  void initSupabase(SupabaseClient client) {
    if (_supabase != null) return;
    _supabase = client;
    if (SupabaseConfig.serviceRoleKey.isNotEmpty) {
      _adminSupabase = SupabaseClient(SupabaseConfig.url, SupabaseConfig.serviceRoleKey);
      Logger.info("PredictionMarketKernel: admin client créé avec service_role");
    } else {
      Logger.info("PredictionMarketKernel: pas de service_role (utilisation du client standard avec RLS)");
    }
    _subscribeRealtime();
    _hydrateFromServer();
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

    _positionsChannel = _supabase!
        .channel('public:outcome_positions')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'outcome_positions',
          callback: _onPositionChange,
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
      final existing = _events[event.id];
      if (existing == null) {
        if (await _verify(event.creationHash, event.creatorPublicKey, event.creatorSignature)) {
          _events[event.id] = event;
          _seenEvents.add(event.id);
          _eventChanges.add(null);
        }
      } else if (!existing.isResolved && event.isResolved) {
        _events[event.id] = event;
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
      _orders[order.id] = order;
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
      _trades[trade.id] = trade;
      _processTrades();
      _orderChanges.add(null);
    } catch (e) {
      Logger.error("PredictionMarketKernel: Error parsing trade from Supabase Realtime: $e");
    }
  }

  void _onPositionChange(PostgresChangePayload payload) async {
    final row = payload.newRecord;
    if (row.isEmpty) return;
    try {
      final position = OutcomePosition(
        eventId: row['event_id'] as String,
        outcome: row['outcome'] as String,
        holderAddress: row['holder_address'] as String,
        shares: BigInt.parse(row['shares'] as String),
        sharesClaimed: BigInt.parse(row['shares_claimed'] as String),
      );
      final key = _posKey(position.eventId, position.outcome, position.holderAddress);
      _positions[key] = position;
      _positionChanges.add(null);
    } catch (e) {
      Logger.error("PredictionMarketKernel: Error parsing position from Supabase Realtime: $e");
    }
  }

  Future<void> _hydrateFromServer() async {
    if (_supabase == null) return;
    try {
      Logger.info("PredictionMarketKernel: Hydrating from Supabase...");

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
        _events[event.id] = event;
        _seenEvents.add(event.id);
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
        _orders[order.id] = order;
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
        _trades[trade.id] = trade;
      }
      _processTrades();
      _orderChanges.add(null);

      final positionsData = await _supabase!.from('outcome_positions').select();
      for (final row in positionsData) {
        final position = OutcomePosition(
          eventId: row['event_id'] as String,
          outcome: row['outcome'] as String,
          holderAddress: row['holder_address'] as String,
          shares: BigInt.parse(row['shares'] as String),
          sharesClaimed: BigInt.parse(row['shares_claimed'] as String),
        );
        final key = _posKey(position.eventId, position.outcome, position.holderAddress);
        _positions[key] = position;
      }
      _positionChanges.add(null);

      Logger.info("PredictionMarketKernel: Hydrated ${_events.length} events, ${_orders.length} orders, ${_trades.length} trades, ${_positions.length} positions.");
    } catch (e) {
      Logger.error("PredictionMarketKernel: Error hydrating from Supabase: $e");
    }
  }

  // ---------------------------------------------------------------
  // Getters for UI (read from in-memory cache)
  // ---------------------------------------------------------------

  List<PredictionEvent> get openEvents =>
      _events.values.where((e) => !e.isResolved).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<PredictionEvent> get resolvedEvents =>
      _events.values.where((e) => e.isResolved).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<ShareOrder> openShareOrdersFor(String eventId) =>
      _orders.values.where((o) => o.eventId == eventId && o.isOpen).toList();

  PredictionEvent? getEvent(String id) => _events[id];

  OutcomePosition positionFor(String eventId, String outcome, String holder) {
    final key = _posKey(eventId, outcome, holder);
    return _positions[key] ?? OutcomePosition(eventId: eventId, outcome: outcome, holderAddress: holder, shares: BigInt.zero, sharesClaimed: BigInt.zero);
  }

  List<OutcomePosition> positionsForEvent(String eventId) =>
      _positions.values.where((p) => p.eventId == eventId).toList();

  List<OutcomePosition> allClaimedPositions() =>
      _positions.values.where((p) => p.sharesClaimed > BigInt.zero).toList();

  // ---------------------------------------------------------------
  // 0. Restore payouts at startup
  // ---------------------------------------------------------------

  void restoreClaimedPayouts() {
    if (_payoutsRestored) return;
    _payoutsRestored = true;
    final claimed = allClaimedPositions();
    if (claimed.isEmpty) return;
    var restoredCount = 0;
    for (final position in claimed) {
      final payout = position.sharesClaimed * ProfitCalculator.fullContractValue;
      if (payout <= BigInt.zero) continue;
      dag.balances.credit(position.holderAddress, payout);
      restoredCount++;
    }
    Logger.info("PredictionMarketKernel: $restoredCount position(s) réclamée(s) restaurée(s) dans dag.balances");
  }

  // ---------------------------------------------------------------
  // 1. Create event
  // ---------------------------------------------------------------

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
    _events[event.id] = event;
    _eventChanges.add(null);

    if (_adminSupabase != null) {
      await _adminSupabase!.from('prediction_events').insert({
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
      });
    }

    return event;
  }

  // ---------------------------------------------------------------
  // 2. Mint complete set
  // ---------------------------------------------------------------

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

    _creditCompleteSet(event.id, holderAddress, shares);

    return depositTx.id;
  }

  void _creditCompleteSet(String eventId, String holderAddress, BigInt shares) {
    _addShares(eventId, "yes", holderAddress, shares);
    _addShares(eventId, "no", holderAddress, shares);
    _positionChanges.add(null);
  }

  Future<void> _addShares(String eventId, String outcome, String holder, BigInt deltaShares) async {
    final key = _posKey(eventId, outcome, holder);
    final existing = _positions[key];
    final currentShares = existing?.shares ?? BigInt.zero;
    final newShares = currentShares + deltaShares;
    final finalShares = newShares < BigInt.zero ? BigInt.zero : newShares;

    _positions[key] = OutcomePosition(
      eventId: eventId, outcome: outcome, holderAddress: holder,
      shares: finalShares, sharesClaimed: existing?.sharesClaimed ?? BigInt.zero,
    );

    if (_adminSupabase != null) {
      final existingRow = await _adminSupabase!.from('outcome_positions')
          .select().eq('position_key', key).maybeSingle();
      if (existingRow != null) {
        await _adminSupabase!.from('outcome_positions')
            .update({'shares': finalShares.toString()}).eq('position_key', key)
            .catchError((e) => Logger.error("Supabase update position error: $e"));
      } else {
        await _adminSupabase!.from('outcome_positions').insert({
          'position_key': key,
          'event_id': eventId,
          'outcome': outcome,
          'holder_address': holder,
          'shares': finalShares.toString(),
          'shares_claimed': '0',
        }).catchError((e) => Logger.error("Supabase insert position error: $e"));
      }
    }
  }

  // ---------------------------------------------------------------
  // 3. Resolve event
  // ---------------------------------------------------------------

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
    _events[event.id] = resolved;
    _eventChanges.add(null);

    if (_adminSupabase != null) {
      await _adminSupabase!.from('prediction_events').update({
        'winning_outcome': outcome.name,
        'resolution_signature': signatureHex,
        'resolved_at': resolved.resolvedAt,
      }).eq('id', event.id).catchError((e) {
        Logger.error("Supabase update event error: $e");
      });
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

    _events[event.id] = updated;
    _eventChanges.add(null);

    if (_adminSupabase != null) {
      await _adminSupabase!.from('prediction_events').update({
        'question': updated.question,
        'oracle_address': updated.oracleAddress,
        'oracle_public_key': updated.oraclePublicKey,
        'closes_at': updated.closesAt,
        'creator_signature': updated.creatorSignature,
      }).eq('id', updated.id).catchError((e) {
        Logger.error("Supabase update event fields error: $e");
      });
    }

    return updated;
  }

  Future<void> deleteEvent(PredictionEvent event) async {
    if (event.isResolved) {
      Logger.warn("Impossible de supprimer un événement déjà résolu");
      return;
    }

    _events.remove(event.id);
    _seenEvents.remove(event.id);
    _eventChanges.add(null);

    if (_adminSupabase != null) {
      await _adminSupabase!.from('prediction_events').delete().eq('id', event.id).catchError((e) {
        Logger.error("Supabase delete event error: $e");
      });
    }
  }

  // ---------------------------------------------------------------
  // 4. Claim payout
  // ---------------------------------------------------------------

  Future<BigInt?> claimPayout({
    required PredictionEvent event,
    required String holderAddress,
    required KeyPair holderKeyPair,
  }) async {
    if (!event.isResolved) return null;
    final outcomeKey = event.winningOutcome == PredictionOutcome.yes ? "yes" : "no";
    final position = positionFor(event.id, outcomeKey, holderAddress);
    final claimable = position.sharesClaimable;
    if (claimable <= BigInt.zero) return null;

    final claimId = IdGenerator.generateId("claim");
    final payout = claimable * ProfitCalculator.fullContractValue;

    _seenClaims.add(claimId);
    _markClaimed(event.id, outcomeKey, holderAddress, claimable);
    dag.balances.credit(holderAddress, payout);
    _positionChanges.add(null);

    return payout;
  }

  Future<void> _markClaimed(String eventId, String outcome, String holder, BigInt claimedNow) async {
    final key = _posKey(eventId, outcome, holder);
    final existing = _positions[key];
    if (existing == null) return;
    final newClaimed = existing.sharesClaimed + claimedNow;
    final newShares = existing.shares - claimedNow;
    _positions[key] = OutcomePosition(
      eventId: eventId, outcome: outcome, holderAddress: holder,
      shares: newShares < BigInt.zero ? BigInt.zero : newShares,
      sharesClaimed: newClaimed,
    );

    if (_adminSupabase != null) {
      await _adminSupabase!.from('outcome_positions')
          .update({
            'shares': (newShares < BigInt.zero ? BigInt.zero : newShares).toString(),
            'shares_claimed': newClaimed.toString(),
          }).eq('position_key', key)
          .catchError((e) => Logger.error("Supabase update position (claim) error: $e"));
    }
  }

  // ---------------------------------------------------------------
  // 5. Share order management
  // ---------------------------------------------------------------

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

    _orders[order.id] = order;
    _orderChanges.add(null);

    if (_supabase != null) {
      await _supabase!.from('share_orders').insert({
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
      });
    }

    return order;
  }

  Future<bool> cancelShareOrder({
    required String orderId,
    required KeyPair makerKeyPair,
  }) async {
    final order = _orders[orderId];
    if (order == null) return false;
    if (order.cancelled) return true;

    final updated = order.copyWith(cancelled: true);
    _orders[orderId] = updated;
    _orderChanges.add(null);

    if (_supabase != null) {
      await _supabase!.from('share_orders').update({
        'cancelled': true,
      }).eq('id', orderId).catchError((e) {
        Logger.error("Supabase update share order (cancel) error: $e");
      });
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

    await _addShares(order.eventId, order.outcome, buyerAddress, sharesToFill);
    await _addShares(order.eventId, order.outcome, order.makerId, -sharesToFill);

    final updatedOrder = order.copyWith(filledShares: order.filledShares + sharesToFill);
    _orders[order.id] = updatedOrder;

    _orderChanges.add(null);
    _positionChanges.add(null);

    if (_supabase != null) {
      await _supabase!.from('share_orders').update({
        'filled_shares': updatedOrder.filledShares.toString(),
      }).eq('id', order.id).catchError((e) {
        Logger.error("Supabase update share order (fill) error: $e");
      });

      await _supabase!.from('prediction_trades').insert({
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
      });
    }

    return payTx.id;
  }

  void _processTrades() {
    for (final t in _trades.values) {
      if (t.status != TradeStatus.confirmed) continue;
      if (_processedTrades.contains(t.id)) continue;
      if (!t.currency.startsWith("EVENT:")) continue;

      final parts = t.currency.split(":");
      if (parts.length != 3) continue;
      final eventId = parts[1];
      final outcome = parts[2].toLowerCase();

      _processedTrades.add(t.id);
      _addShares(eventId, outcome, t.sellerId, -t.amount);
      _addShares(eventId, outcome, t.buyerId, t.amount);
      _positionChanges.add(null);
    }
  }

  // ---------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------

  static String _posKey(String eventId, String outcome, String holder) => "$eventId:$outcome:$holder";

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

  void dispose() {
    _eventsChannel?.unsubscribe();
    _ordersChannel?.unsubscribe();
    _tradesChannel?.unsubscribe();
    _positionsChannel?.unsubscribe();
    _eventChanges.close();
    _positionChanges.close();
    _orderChanges.close();
  }
}
