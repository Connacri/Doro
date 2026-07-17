import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../objectbox.g.dart';

import '../entities/bet_entity.dart';
import '../entities/bet_stake_entity.dart';
import '../entities/bet_vote_entity.dart';
import '../entities/chat_message_entity.dart';
import '../entities/contact_entity.dart';
import '../entities/order_entity.dart';
import '../entities/peer_entity.dart';
import '../entities/peer_profile_entity.dart';
import '../entities/profile_entity.dart';
import '../entities/trade_entity.dart';
import '../entities/tx_entity.dart';
import '../entities/wallet_entity.dart';

class ObjectBoxStore {
  Store? _store;

  Future<void> init({String? directory}) async {
    final String storeDir;
    if (directory != null) {
      storeDir = directory;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      storeDir = p.join(docsDir.path, "doro-db");
    }
    if (!Directory(storeDir).existsSync()) {
      await Directory(storeDir).create(recursive: true);
    }
    _store = await openStore(directory: storeDir);
  }

  Store get store => _store!;

  Box<T> getBox<T>() => _store!.box<T>();

  void close() {
    _store?.close();
  }

  Future<void> clearAll() async {
    getBox<BetEntity>().removeAll();
    getBox<BetStakeEntity>().removeAll();
    getBox<BetVoteEntity>().removeAll();
    getBox<ChatMessageEntity>().removeAll();
    getBox<ContactEntity>().removeAll();
    getBox<OrderEntity>().removeAll();
    getBox<PeerEntity>().removeAll();
    getBox<PeerProfileEntity>().removeAll();
    getBox<ProfileEntity>().removeAll();
    getBox<TradeEntity>().removeAll();
    getBox<TxEntity>().removeAll();
    getBox<WalletEntity>().removeAll();
  }
}
