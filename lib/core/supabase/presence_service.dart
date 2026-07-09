// lib/core/supabase/presence_service.dart
//
// En ligne/hors ligne + "en train d'écrire" via Supabase Realtime
// Presence — aucune table nécessaire, c'est un état éphémère tenu en
// mémoire par le serveur Realtime tant que le canal est souscrit.
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceService {
  final SupabaseClient _client;
  final String nodeId;
  RealtimeChannel? _channel;

  final _onlineController = StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get onlinePeers => _onlineController.stream;

  final _typingController = StreamController<({String peer, bool typing})>.broadcast();
  Stream<({String peer, bool typing})> get typingEvents => _typingController.stream;

  final Set<String> _online = {};

  void start() {
    _channel = _client.channel(
      'presence:global',
      opts: const RealtimeChannelConfig(self: false),
    );

    _channel!
      ..onPresenceSync((_) => _syncOnline())
      ..onPresenceJoin((_) => _syncOnline())
      ..onPresenceLeave((_) => _syncOnline())
      ..onBroadcast(
        event: 'typing',
        callback: (payload) {
          final peer = payload['from'] as String?;
          final typing = payload['typing'] as bool? ?? false;
          if (peer != null && peer != nodeId) {
            _typingController.add((peer: peer, typing: typing));
          }
        },
      )
      ..subscribe((status, _) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await _channel!.track({'pubkey': nodeId, 'online_at': DateTime.now().toIso8601String()});
        }
      });
  }

  void _syncOnline() {
    final state = _channel?.presenceState() ?? [];
    final peers = <String>{};
    for (final entry in state) {
      for (final p in entry.presences) {
        final key = p.payload['pubkey'] as String?;
        if (key != null) peers.add(key);
      }
    }
    _online
      ..clear()
      ..addAll(peers);
    _onlineController.add(Set.unmodifiable(_online));
  }

  bool isOnline(String peerPubkey) => _online.contains(peerPubkey);

  /// À appeler depuis le champ de saisie (avec un throttle/debounce côté
  /// UI, ex. toutes les 2s pendant que l'utilisateur tape, puis un
  /// dernier envoi typing:false à l'arrêt).
  void sendTyping(String toPeer, bool typing) {
    _channel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'from': nodeId, 'to': toPeer, 'typing': typing},
    );
  }

  PresenceService(this._client, this.nodeId);

  void dispose() {
    _channel?.unsubscribe();
    _onlineController.close();
    _typingController.close();
  }
}
