// lib/core/kernels/messenger/supabase_messenger_kernel.dart
//
// Remplace intégralement MessengerKernel (WebRTC/P2P) par Supabase :
// Postgres pour la persistance (source de vérité serveur), Realtime
// pour la diffusion instantanée. La liaison identité <-> pubkey est
// gérée en amont par SupabaseIdentityService.
//
// L'API publique (isFriend, friends(), sendFriendRequest, ..., streams
// `messages`/`friendEvents`) reproduit volontairement celle de
// l'ancien MessengerKernel pour que ChatProvider / chat_screen.dart /
// amis_screen.dart n'aient (idéalement) rien à changer.
//
// Différence clé : ObjectBox reste utilisé comme CACHE LOCAL / offline
// (lecture instantanée à l'ouverture de l'app, historique dispo hors
// ligne) mais Supabase Postgres devient la source de vérité. Toute
// écriture part vers Supabase ; Realtime remonte les changements des
// autres appareils/pairs et met à jour le cache local.
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../storage/objectbox/store.dart';
import '../../storage/entities/chat_message_entity.dart';
import '../../storage/entities/contact_entity.dart';
import '../../../objectbox.g.dart';
import '../../utils/logger.dart';

class SupabaseMessengerKernel {
  final String nodeId; // = public_key hex, identique à l'ancien nodeId
  final SupabaseClient supabase;
  final ObjectBoxStore db;

  late final Box<ChatMessageEntity> _msgBox;
  late final Box<ContactEntity> _contactBox;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final _friendEventsController = StreamController<void>.broadcast();
  Stream<void> get friendEvents => _friendEventsController.stream;

  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _friendRequestsChannel;
  RealtimeChannel? _friendshipsChannel;

  SupabaseMessengerKernel({
    required this.nodeId,
    required this.supabase,
    required this.db,
  }) {
    _msgBox = db.getBox<ChatMessageEntity>();
    _contactBox = db.getBox<ContactEntity>();
    _subscribeRealtime();
    _hydrateFriendsFromServer();
  }

  // ---------------------------------------------------------------
  // REALTIME
  // ---------------------------------------------------------------

  void _subscribeRealtime() {
    // Messages où je suis émetteur OU destinataire (2 souscriptions,
    // Realtime ne supporte pas le OR sur des colonnes différentes).
    _messagesChannel = supabase
        .channel('messages:$nodeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_pubkey',
            value: nodeId,
          ),
          callback: _onMessageChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'from_pubkey',
            value: nodeId,
          ),
          callback: _onMessageChange,
        )
        .subscribe();

    _friendRequestsChannel = supabase
        .channel('friend_requests:$nodeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friend_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_pubkey',
            value: nodeId,
          ),
          callback: (_) => _friendEventsController.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friend_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'from_pubkey',
            value: nodeId,
          ),
          callback: (_) => _friendEventsController.add(null),
        )
        .subscribe();

    _friendshipsChannel = supabase
        .channel('friendships:$nodeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          callback: (payload) {
            final row = payload.newRecord;
            final a = row['pubkey_a'] as String?;
            final b = row['pubkey_b'] as String?;
            if (a == null || b == null) return;
            if (a != nodeId && b != nodeId) return; // filtre côté client (pas de OR possible)
            final peer = a == nodeId ? b : a;
            _addLocalFriend(peer);
            _friendEventsController.add(null);
          },
        )
        .subscribe();
  }

  void _onMessageChange(PostgresChangePayload payload) {
    final row = payload.newRecord;
    if (row.isEmpty) return;
    final fromId = row['from_pubkey'] as String?;
    final toId = row['to_pubkey'] as String?;
    final time = row['created_at'] as String?;
    final status = row['status'] as String? ?? 'sent';
    final id = row['id'] as String?;
    final deletedForEveryone = row['deleted_for_everyone'] as bool? ?? false;
    final text = deletedForEveryone ? '' : (row['body'] as String?);
    if (fromId == null || toId == null || text == null || time == null) return;

    final peerKey = fromId == nodeId ? toId : fromId;
    final effectiveStatus = deletedForEveryone ? 'deleted' : status;

    final existing = _msgBox
        .query(ChatMessageEntity_.peerKey.equals(peerKey).and(ChatMessageEntity_.timestamp.equals(time)))
        .build()
        .findFirst();
    if (existing != null) {
      existing.status = effectiveStatus;
      _msgBox.put(existing);
    } else {
      _msgBox.put(ChatMessageEntity(fromId: fromId, text: text, timestamp: time, peerKey: peerKey, status: effectiveStatus));
    }

    _messageController.add({
      'from': fromId,
      'data': {
        'type': 'chat',
        'id': id,
        'from': fromId,
        'to': toId,
        'text': text,
        'time': time,
        'status': effectiveStatus,
      },
    });

    // Accusé de réception automatique si je suis le destinataire d'un
    // nouveau message encore 'sent'.
    if (toId == nodeId && status == 'sent' && id != null) {
      _markStatus(id, 'delivered');
    }
  }

  Future<void> _hydrateFriendsFromServer() async {
    try {
      final rows = await supabase
          .from('friendships')
          .select('pubkey_a, pubkey_b')
          .or('pubkey_a.eq.$nodeId,pubkey_b.eq.$nodeId');
      for (final row in rows as List) {
        final a = row['pubkey_a'] as String;
        final b = row['pubkey_b'] as String;
        _addLocalFriend(a == nodeId ? b : a);
      }
      _friendEventsController.add(null);
    } catch (e) {
      Logger.info('SupabaseMessengerKernel: hydrateFriends a échoué (offline ?) $e');
    }
  }

  void _addLocalFriend(String peerId, {String? name}) {
    final existing = _contactBox.query(ContactEntity_.publicKey.equals(peerId)).build().findFirst();
    if (existing != null) return;
    _contactBox.put(ContactEntity(publicKey: peerId, name: name ?? _shortId(peerId)));
  }

  // ---------------------------------------------------------------
  // AMIS (miroir de l'ancienne API MessengerKernel)
  // ---------------------------------------------------------------

  bool isFriend(String publicKey) =>
      _contactBox.query(ContactEntity_.publicKey.equals(publicKey)).build().findFirst() != null;

  List<ContactEntity> friends() => _contactBox.getAll()..sort((a, b) => a.name.compareTo(b.name));

  Future<void> sendFriendRequest(String toPeerId, {String? name}) async {
    if (toPeerId == nodeId || isFriend(toPeerId)) return;
    try {
      await supabase.from('friend_requests').insert({
        'from_pubkey': nodeId,
        'to_pubkey': toPeerId,
        'display_name': name ?? '',
      });
      Logger.info('SupabaseMessengerKernel: demande d\'ami envoyée à $toPeerId');
    } on PostgrestException catch (e) {
      // Unique(from,to) violé => déjà envoyée ; si une demande inverse
      // existe déjà côté serveur (l'autre m'a aussi demandé), on
      // l'accepte directement pour matcher l'ancien comportement P2P.
      if (e.code == '23505') {
        Logger.info('SupabaseMessengerKernel: demande déjà en attente pour $toPeerId');
        return;
      }
      final reciprocal = await supabase
          .from('friend_requests')
          .select('id')
          .eq('from_pubkey', toPeerId)
          .eq('to_pubkey', nodeId)
          .maybeSingle();
      if (reciprocal != null) {
        await acceptFriendRequest(toPeerId);
        return;
      }
      rethrow;
    }
    _friendEventsController.add(null);
  }

  Future<void> acceptFriendRequest(String fromPeerId) async {
    await supabase
        .from('friend_requests')
        .update({'status': 'accepted'})
        .eq('from_pubkey', fromPeerId)
        .eq('to_pubkey', nodeId);
    // Le trigger SQL crée la friendship + purge la demande ; on
    // rafraîchit localement sans attendre le round-trip Realtime.
    _addLocalFriend(fromPeerId);
    _friendEventsController.add(null);
  }

  Future<void> declineFriendRequest(String fromPeerId) async {
    await supabase
        .from('friend_requests')
        .update({'status': 'declined'})
        .eq('from_pubkey', fromPeerId)
        .eq('to_pubkey', nodeId);
    _friendEventsController.add(null);
  }

  Future<void> cancelFriendRequest(String toPeerId) async {
    await supabase
        .from('friend_requests')
        .delete()
        .eq('from_pubkey', nodeId)
        .eq('to_pubkey', toPeerId);
    _friendEventsController.add(null);
  }

  Future<void> removeFriend(String publicKey) async {
    final a = nodeId.compareTo(publicKey) < 0 ? nodeId : publicKey;
    final b = nodeId.compareTo(publicKey) < 0 ? publicKey : nodeId;
    await supabase.from('friendships').delete().eq('pubkey_a', a).eq('pubkey_b', b);
    final existing = _contactBox.query(ContactEntity_.publicKey.equals(publicKey)).build().findFirst();
    if (existing != null) _contactBox.remove(existing.id);
    _friendEventsController.add(null);
  }

  // ---------------------------------------------------------------
  // CHAT (miroir de l'ancienne API MessengerKernel)
  // ---------------------------------------------------------------

  Future<void> sendPrivateChat(String toPeerId, String text) async {
    final optimisticTime = DateTime.now().toIso8601String();
    // Écriture optimiste locale immédiate (UX identique à l'ancienne
    // version P2P : le message apparaît avant confirmation serveur).
    _msgBox.put(ChatMessageEntity(fromId: nodeId, text: text, timestamp: optimisticTime, peerKey: toPeerId));

    try {
      await supabase.from('messages').insert({
        'from_pubkey': nodeId,
        'to_pubkey': toPeerId,
        'body': text,
      });
      Logger.info('SupabaseMessengerKernel: message envoyé à $toPeerId');
    } on PostgrestException catch (e) {
      // RLS refuse (pas encore amis) ou hors-ligne : le message reste en
      // cache local marqué 'sent', il sera visible mais pas confirmé.
      Logger.info('SupabaseMessengerKernel: envoi refusé/en attente ($e)');
    }
  }

  Future<void> sendChatReadConfirmation(String peerId, String timestamp) async {
    await supabase
        .from('messages')
        .update({'status': 'read', 'read_at': DateTime.now().toIso8601String()})
        .eq('from_pubkey', peerId)
        .eq('to_pubkey', nodeId)
        .lte('created_at', timestamp)
        .neq('status', 'read');
  }

  Future<void> _markStatus(String messageId, String status) async {
    final field = status == 'delivered' ? 'delivered_at' : 'read_at';
    await supabase
        .from('messages')
        .update({'status': status, field: DateTime.now().toIso8601String()})
        .eq('id', messageId);
  }

  List<Map<String, dynamic>> historyWith(String peerKey) {
    return (_msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().find()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)))
        .map<Map<String, dynamic>>((e) => {
              'from': e.fromId,
              'text': e.text,
              'time': e.timestamp,
              'status': e.status,
            })
        .toList();
  }

  /// Supprime un message pour tout le monde ("unsend", comme WhatsApp),
  /// dans une fenêtre de 2h après l'envoi — cf. policy
  /// `messages_unsend_by_sender` + RPC `delete_message_for_everyone`.
  /// Realtime notifie l'autre pair qui doit afficher un tombstone type
  /// "Message supprimé" (body vidé côté serveur).
  Future<bool> unsendMessage(String messageId) async {
    final ok = await supabase.rpc('delete_message_for_everyone', params: {'msg_id': messageId});
    return ok == true;
  }

  /// Vide la conversation avec [peerKey] uniquement pour moi (comme
  /// WhatsApp "Effacer la discussion" : n'affecte pas l'autre pair).
  /// Nettoie aussi le cache local ObjectBox.
  Future<void> clearConversationForMeOnServer(String peerKey) async {
    await supabase.rpc('clear_conversation_for_me', params: {'peer': peerKey});
    clearHistory(peerKey);
  }

  /// Recharge l'historique complet d'une conversation depuis Supabase et
  /// met à jour le cache local — à appeler à l'ouverture d'un chat pour
  /// rattraper ce qui a pu être manqué hors-ligne. Utilise la vue
  /// `visible_messages` (respecte l'unsend et le "supprimer pour moi").
  Future<void> syncHistoryWith(String peerKey) async {
    try {
      final rows = await supabase
          .from('visible_messages')
          .select()
          .or('and(from_pubkey.eq.$nodeId,to_pubkey.eq.$peerKey),and(from_pubkey.eq.$peerKey,to_pubkey.eq.$nodeId)')
          .order('created_at');
      // On repart d'un cache propre pour ce pair afin que les messages
      // "unsend"/supprimés localement disparaissent aussi de l'affichage.
      clearHistory(peerKey);
      for (final row in rows as List) {
        final fromId = row['from_pubkey'] as String;
        final time = row['created_at'] as String;
        final existing = _msgBox
            .query(ChatMessageEntity_.peerKey.equals(peerKey).and(ChatMessageEntity_.timestamp.equals(time)))
            .build()
            .findFirst();
        if (existing == null) {
          _msgBox.put(ChatMessageEntity(
            fromId: fromId,
            text: row['body'] as String,
            timestamp: time,
            peerKey: peerKey,
            status: row['status'] as String? ?? 'sent',
          ));
        }
      }
    } catch (e) {
      Logger.info('SupabaseMessengerKernel: syncHistoryWith a échoué (offline ?) $e');
    }
  }

  Map<String, dynamic>? lastMessageWith(String peerKey) {
    final all = _msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().find();
    if (all.isEmpty) return null;
    all.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final e = all.last;
    return {'from': e.fromId, 'text': e.text, 'time': e.timestamp};
  }

  Set<String> peersWithHistory() => _msgBox.getAll().map((e) => e.peerKey).toSet();

  void clearHistory(String peerKey) {
    _msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().remove();
  }

  void clearAllHistory() => _msgBox.removeAll();

  String _shortId(String key) =>
      key.length > 14 ? '${key.substring(0, 8)}…${key.substring(key.length - 4)}' : key;

  void dispose() {
    _messagesChannel?.unsubscribe();
    _friendRequestsChannel?.unsubscribe();
    _friendshipsChannel?.unsubscribe();
    _messageController.close();
    _friendEventsController.close();
  }
}
