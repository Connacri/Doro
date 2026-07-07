// lib/features/simulator/sim_engine.dart
//
// Port fidèle du simulateur autonome `index.html` (multi-nœuds, DAG ledger,
// chaos engine, gossip, marché OTC, chat) — c'est un bac à sable de
// démonstration/pédagogie, totalement indépendant du vrai réseau P2P de
// l'app (WebRTC/signaling). Chaque "nœud" ici est un objet en mémoire
// simulant un pair avec son propre ledger local, exactement comme dans le
// fichier HTML d'origine.
import 'dart:math';

const String mintAddress = '0xMINT_GENESIS_TREASURY';

const List<String> chatTexts = [
  "Salut ! tu as reçu mes DORO ?", "Oui bien reçu !", "Parfait, le réseau marche bien.",
  "Tu peux me renvoyer un message ?", "Bien sûr, le chat P2P fonctionne.",
  "Je viens de miner un bloc.", "J'ai vu passer ta tx dans mon ledger.",
  "Test de latence... reçu ?", "Reçu ! 5 étoiles ⭐", "Le DAG est bien cohérent.",
  "Je fais tourner un nœud depuis 10 min.", "Moi aussi, tout est synchro.",
  "T'as vu le cours du DORO ?", "Encore stable, c'est solide.",
  "Marché OTC actif aujourd'hui !", "Je mets un ordre d'achat.",
  "Gossip protocol en pleine forme.", "Aucune divergence détectée.",
  "Je propage le message à mes pairs.", "Reçu et retransmis.",
  "Belle démo multi-nœuds !", "On va monter à 10 nœuds ?",
  "Le consensus BFT tient bien.", "Les poids de vote sont justes.",
  "Envoi de fonds inter-nœuds OK.", "Réception auto confirmée.",
];

final Random _rng = Random();
int rand(int min, int max) => min + _rng.nextInt(max - min + 1);
T pick<T>(List<T> list) => list[rand(0, list.length - 1)];
String shortAddr(String a) => a.length > 14 ? "${a.substring(0, 5)}…${a.substring(a.length - 3)}" : a;

int _idCounter = 1;
String newId(String prefix) => "$prefix-${_idCounter++}";

class SimTx {
  final String id;
  final String type; // 'send' | 'receive'
  final String from;
  final String to;
  final int amount;
  final int nonce;
  final String? linkedSendId;

  SimTx({
    required this.id,
    required this.type,
    required this.from,
    required this.to,
    required this.amount,
    required this.nonce,
    this.linkedSendId,
  });
}

class SimOrder {
  final String id;
  final String nodeId;
  final String nodeName;
  final String side; // buy/sell
  final int amount;
  final int price;
  final int timestamp;
  int filled;
  bool cancelled;

  SimOrder({
    required this.id,
    required this.nodeId,
    required this.nodeName,
    required this.side,
    required this.amount,
    required this.price,
    required this.timestamp,
    this.filled = 0,
    this.cancelled = false,
  });
}

class SimTrade {
  final String id;
  final String buyerId;
  final String buyerName;
  final String sellerId;
  final String sellerName;
  final int amount;
  final int price;
  final int timestamp;

  SimTrade({
    required this.id,
    required this.buyerId,
    required this.buyerName,
    required this.sellerId,
    required this.sellerName,
    required this.amount,
    required this.price,
    required this.timestamp,
  });
}

class SimMessage {
  final String from;
  final String fromName;
  final String text;
  final int timestamp;

  SimMessage({required this.from, required this.fromName, required this.text, required this.timestamp});
}

class SimNodeStats {
  int txCreated = 0;
  int txAccepted = 0;
  int txRejected = 0;
  int msgReceived = 0;
  int msgSent = 0;
  int ordersPlaced = 0;
}

class LogEntry {
  final String time;
  final String text;
  final String cls; // ok/rej/pend/info
  LogEntry(this.time, this.text, this.cls);
}

/// Chaque pair a son propre état local (ledger, soldes, messages...) —
/// exactement le principe du fichier d'origine : pas de vérité globale,
/// tout se propage par gossip.
class SimNode {
  final String name;
  final String address;
  bool online = true;

  final Map<String, SimTx> ledger = {};
  final Map<String, int> lastNonce = {};
  final Map<String, int> balances = {};
  final Set<String> claimedSendIds = {};
  final Map<String, List<SimTx>> pendingReceives = {};
  bool genesisMinted = false;
  final List<SimMessage> messages = [];
  final Map<String, SimOrder> knownOrders = {};
  final List<SimTrade> knownTrades = [];
  final Set<String> connectedTo = {};
  final SimNodeStats stats = SimNodeStats();

  SimNode(this.name, this.address);

  int balanceOf(String addr) => balances[addr] ?? 0;
  bool isMint(String addr) => addr == mintAddress;
  bool canSpend(String addr, int amount) => isMint(addr) ? true : balanceOf(addr) >= amount;
  void debit(String addr, int amount) {
    if (!isMint(addr)) balances[addr] = balanceOf(addr) - amount;
  }
  void credit(String addr, int amount) => balances[addr] = balanceOf(addr) + amount;

  int connectionCount(SimNetwork sim) =>
      connectedTo.where((a) => sim.nodes.containsKey(a) && sim.nodes[a]!.online).length;

  List<String> onlinePeers(SimNetwork sim) =>
      connectedTo.where((a) => sim.nodes.containsKey(a) && sim.nodes[a]!.online).toList();

  /// Retourne un code de résultat, identique à la version JS :
  /// 'accepted' | 'alreadyKnown' | 'rejectedDuplicateGenesis' | 'rejectedReplay' |
  /// 'rejectedInsufficientBalance' | 'rejectedInvalidReceive' | 'rejectedUnknownSend' |
  /// 'rejectedDuplicateReceive'
  String addValidated(SimTx tx, SimNetwork sim, {void Function(String, String)? log}) {
    if (ledger.containsKey(tx.id)) return 'alreadyKnown';

    if (isMint(tx.from)) {
      if (genesisMinted) return 'rejectedDuplicateGenesis';
    } else {
      final last = lastNonce[tx.from];
      if (last != null && tx.nonce <= last) return 'rejectedReplay';
      if (tx.type == 'send') {
        if (!canSpend(tx.from, tx.amount)) return 'rejectedInsufficientBalance';
      } else {
        final linkedId = tx.linkedSendId;
        if (linkedId == null) return 'rejectedInvalidReceive';
        final sendTx = ledger[linkedId];
        if (sendTx == null) {
          pendingReceives.putIfAbsent(linkedId, () => []).add(tx);
          return 'rejectedUnknownSend';
        }
        if (sendTx.type != 'send' || sendTx.to != tx.from) return 'rejectedInvalidReceive';
        if (claimedSendIds.contains(linkedId)) return 'rejectedDuplicateReceive';
        if (sendTx.amount != tx.amount) return 'rejectedInvalidReceive';
      }
    }

    ledger[tx.id] = tx;
    stats.txAccepted++;
    if (isMint(tx.from)) {
      genesisMinted = true;
      credit(tx.to, tx.amount);
    } else {
      lastNonce[tx.from] = tx.nonce;
      if (tx.type == 'send') {
        debit(tx.from, tx.amount);
      } else {
        credit(tx.from, tx.amount);
        claimedSendIds.add(tx.linkedSendId!);
      }
    }

    if (tx.type == 'send') {
      final waiting = pendingReceives.remove(tx.id);
      if (waiting != null) {
        for (final rx in waiting) {
          final r = addValidated(rx, sim, log: log);
          if (r == 'accepted') log?.call("↻ Receive en attente débloqué chez $name : ${rx.id}", 'pend');
        }
      }
    }
    return 'accepted';
  }

  void autoClaim(SimTx sendTx, SimNetwork sim, {required bool autoClaimEnabled, void Function(String, String)? log}) {
    if (!autoClaimEnabled) return;
    final nonce = (lastNonce[sendTx.to] ?? 0) + 1;
    final rx = SimTx(
      id: newId('receive'),
      type: 'receive',
      from: sendTx.to,
      to: sendTx.to,
      amount: sendTx.amount,
      nonce: nonce,
      linkedSendId: sendTx.id,
    );
    final r = addValidated(rx, sim, log: log);
    if (r == 'accepted') log?.call("🤖 $name → Auto-receive pour ${shortAddr(sendTx.id)}", 'ok');
  }

  bool sendMessage(String toAddr, String text, SimNetwork sim) {
    if (!online) return false;
    final target = sim.nodes[toAddr];
    if (target == null || !target.online || !connectedTo.contains(toAddr)) return false;
    final msg = SimMessage(from: address, fromName: name, text: text, timestamp: DateTime.now().millisecondsSinceEpoch);
    sim.deliverMessage(this, target, msg);
    stats.msgSent++;
    return true;
  }

  SimOrder? postOrder(String side, int amount, int price, SimNetwork sim, {void Function(String, String)? log}) {
    if (!online) return null;
    final order = SimOrder(
      id: newId('order'),
      nodeId: address,
      nodeName: name,
      side: side,
      amount: amount,
      price: price,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    knownOrders[order.id] = order;
    stats.ordersPlaced++;
    sim.broadcastOrder(this, order);
    log?.call("📋 $name : ordre $side $amount DORO @ $price", 'info');
    return order;
  }

  void matchOrders(SimNetwork sim, {required bool autoClaimEnabled, void Function(String, String)? log}) {
    if (!online) return;
    final active = knownOrders.values.where((o) => !o.cancelled && o.filled < o.amount).toList();
    final buys = active.where((o) => o.side == 'buy').toList()..sort((a, b) => b.price.compareTo(a.price));
    final sells = active.where((o) => o.side == 'sell').toList()..sort((a, b) => a.price.compareTo(b.price));

    for (final buy in buys) {
      for (final sell in sells) {
        if (sell.nodeId == buy.nodeId) continue;
        if (buy.price >= sell.price) {
          final qty = min(buy.amount - buy.filled, sell.amount - sell.filled);
          if (qty <= 0) continue;
          buy.filled += qty;
          sell.filled += qty;
          final trade = SimTrade(
            id: newId('trade'),
            buyerId: buy.nodeId,
            buyerName: buy.nodeName,
            sellerId: sell.nodeId,
            sellerName: sell.nodeName,
            amount: qty,
            price: sell.price,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
          knownTrades.add(trade);
          sim.broadcastTrade(this, trade);
          log?.call("🤝 TRADE : ${buy.nodeName} achète $qty DORO à ${sell.nodeName} pour ${sell.price}", 'ok');

          final sellNode = sim.nodes[sell.nodeId];
          if (sellNode != null) {
            final nonce = (lastNonce[buy.nodeId] ?? 0) + 1;
            final payTx = SimTx(
              id: newId('send'),
              type: 'send',
              from: buy.nodeId,
              to: sell.nodeId,
              amount: qty * sell.price,
              nonce: nonce,
            );
            final r = addValidated(payTx, sim, log: log);
            if (r == 'accepted') {
              sim.metrics.txTotal++;
              sim.metrics.txOk++;
              log?.call("💸 Paiement Trade : ${shortAddr(buy.nodeId)} → ${shortAddr(sell.nodeId)} ${qty * sell.price} DORO", 'ok');
              sim.broadcastTx(this, payTx);
              if (autoClaimEnabled) autoClaim(payTx, sim, autoClaimEnabled: autoClaimEnabled, log: log);
            }
          }
        }
      }
    }
  }
}

class SimMetrics {
  int txTotal = 0;
  int txOk = 0;
  int txRej = 0;
  int msgTotal = 0;
  int tradeTotal = 0;
  final int startTime = DateTime.now().millisecondsSinceEpoch;
}

/// Gère tous les nœuds, la topologie, le gossip et le chaos engine.
class SimNetwork {
  final Map<String, SimNode> nodes = {};
  String? selectedAddress;
  final SimMetrics metrics = SimMetrics();
  final List<LogEntry> globalLog = [];

  void Function()? onChange; // déclenche un setState côté UI

  void log(String text, [String cls = '']) {
    final time = DateTime.now().toString().substring(11, 19);
    globalLog.insert(0, LogEntry(time, text, cls));
    if (globalLog.length > 500) globalLog.removeRange(500, globalLog.length);
    onChange?.call();
  }

  SimNode? get selected => nodes[selectedAddress];

  SimNode addNode(String name) {
    final addr = '0x${_rng.nextInt(0xFFFFFFF).toRadixString(16)}${_rng.nextInt(0xFFFFFFF).toRadixString(16)}';
    final node = SimNode(name, addr);
    nodes[addr] = node;
    selectedAddress ??= addr;
    log("🆕 Nœud créé : $name (${shortAddr(addr)})", 'info');
    rebuildTopology();
    return node;
  }

  void removeNode(String addr) {
    final node = nodes[addr];
    if (node == null) return;
    for (final other in nodes.values) {
      other.connectedTo.remove(addr);
    }
    nodes.remove(addr);
    if (selectedAddress == addr) {
      selectedAddress = nodes.isNotEmpty ? nodes.keys.first : null;
    }
    log("🗑️ Nœud supprimé : ${node.name}", 'rej');
    rebuildTopology();
  }

  void rebuildTopology() {
    final online = nodes.values.where((n) => n.online).toList();
    for (final node in online) {
      final potentials = online.where((n) => n.address != node.address).toList()..shuffle(_rng);
      final targetCount = max(2, (potentials.length * 0.7).ceil());
      for (final p in potentials.take(targetCount)) {
        node.connectedTo.add(p.address);
      }
    }
  }

  void toggleNode(String addr) {
    final node = nodes[addr];
    if (node == null) return;
    node.online = !node.online;
    if (!node.online) {
      for (final other in nodes.values) {
        other.connectedTo.remove(addr);
      }
      log("🔴 ${node.name} → HORS LIGNE", 'rej');
    } else {
      rebuildTopology();
      log("🟢 ${node.name} → EN LIGNE", 'ok');
    }
  }

  void broadcastTx(SimNode fromNode, SimTx tx, {bool chaosOn = false, int lossPct = 0, int latMs = 0, bool autoClaimEnabled = false}) {
    for (final peerAddr in fromNode.onlinePeers(this)) {
      final peer = nodes[peerAddr];
      if (peer == null || !peer.online) continue;
      if (chaosOn && rand(0, 99) < lossPct) continue;
      final delay = chaosOn ? Duration(milliseconds: rand(0, latMs)) : Duration.zero;
      Future.delayed(delay, () {
        if (!peer.online) return;
        final r = peer.addValidated(tx, this, log: log);
        if (r == 'accepted' && tx.type == 'send') {
          metrics.txTotal++;
          peer.autoClaim(tx, this, autoClaimEnabled: autoClaimEnabled, log: log);
        }
        onChange?.call();
      });
    }
  }

  bool deliverMessage(SimNode fromNode, SimNode toNode, SimMessage msg) {
    if (!toNode.online || !fromNode.connectedTo.contains(toNode.address)) return false;
    toNode.messages.add(msg);
    toNode.stats.msgReceived++;
    metrics.msgTotal++;
    if (toNode.messages.length > 200) toNode.messages.removeRange(0, 50);
    log("💬 ${fromNode.name} → ${toNode.name} : ${msg.text.length > 40 ? msg.text.substring(0, 40) : msg.text}", 'info');
    return true;
  }

  void broadcastOrder(SimNode fromNode, SimOrder order) {
    for (final peerAddr in fromNode.onlinePeers(this)) {
      final peer = nodes[peerAddr];
      if (peer == null || !peer.online) continue;
      peer.knownOrders[order.id] = order;
    }
  }

  void broadcastTrade(SimNode fromNode, SimTrade trade) {
    for (final peerAddr in fromNode.onlinePeers(this)) {
      final peer = nodes[peerAddr];
      if (peer == null || !peer.online) continue;
      peer.knownTrades.add(trade);
    }
  }

  void resetNode(String addr) {
    final old = nodes[addr];
    if (old == null) return;
    final node = SimNode(old.name, addr);
    node.connectedTo.addAll(old.connectedTo);
    node.online = old.online;
    nodes[addr] = node;
    log("↺ ${node.name} réinitialisé (ledger vierge)", 'pend');
  }

  void chaosTick({required int discPct, required int partPct}) {
    final online = nodes.values.where((n) => n.online).toList();
    for (final node in online) {
      if (rand(0, 99) < discPct && online.length > 2) {
        toggleNode(node.address);
        Future.delayed(Duration(milliseconds: rand(2000, 8000)), () {
          final n = nodes[node.address];
          if (n != null && !n.online) toggleNode(node.address);
        });
        break;
      }
    }
    if (rand(0, 99) < partPct && online.length >= 4) {
      final half = online.length ~/ 2;
      final partA = online.sublist(0, half);
      final partB = online.sublist(half);
      for (final a in partA) {
        for (final b in partB) {
          a.connectedTo.remove(b.address);
          b.connectedTo.remove(a.address);
        }
      }
      log("🔀 PARTITION : ${partA.length} nœuds isolés de ${partB.length} nœuds", 'rej');
      Future.delayed(Duration(milliseconds: rand(5000, 15000)), () {
        rebuildTopology();
        log("🔁 PARTITION RÉSOLUE : tous les nœuds reconnectés", 'ok');
      });
    }
  }

  String nameOf(String addr) {
    if (addr == mintAddress) return '🌱 mint';
    final n = nodes[addr];
    return n != null ? n.name : shortAddr(addr);
  }
}
