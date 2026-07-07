// lib/features/simulator/simulator_screen.dart
//
// Port fidèle de l'UI de `index.html` : nœuds & réseau, chaos engine,
// automatisation, vue détaillée d'un nœud (envoi de paiement, ledger,
// messagerie), marché OTC, scénarios guidés, métriques live, journal.
// Trois colonnes de l'original regroupées en onglets pour mobile.
import 'dart:async';
import 'package:flutter/material.dart';
import 'sim_engine.dart';

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> with TickerProviderStateMixin {
  final SimNetwork sim = SimNetwork();
  final _newNodeCtrl = TextEditingController();

  // Chaos engine
  bool chaosOn = false;
  double chaosDisc = 3, chaosLoss = 5, chaosLat = 300, chaosPart = 0;

  // Automatisation
  bool autoChat = true, autoTx = true, autoMarket = true, autoClaim = true;
  double autoSpeed = 5;

  Timer? _chatTimer, _txTimer, _marketTimer, _chaosTimer, _metricsTimer;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    sim.onChange = () {
      if (mounted) setState(() {});
    };
    _bootDemo();
    _startAuto();
    _metricsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      sim.metrics.tradeTotal = sim.nodes.values.fold(0, (a, n) => a + n.knownTrades.length);
      if (mounted) setState(() {});
    });
  }

  void _bootDemo() {
    final names = ['Alice', 'Bob', 'Charlie', 'Diana'];
    for (final n in names) {
      sim.addNode(n);
    }
    final addrs = sim.nodes.keys.toList();
    for (var i = 0; i < addrs.length; i++) {
      for (var j = i + 1; j < addrs.length; j++) {
        sim.nodes[addrs[i]]!.connectedTo.add(addrs[j]);
        sim.nodes[addrs[j]]!.connectedTo.add(addrs[i]);
      }
    }
    final alice = sim.nodes.values.first;
    final genesisTx = SimTx(id: newId('genesis'), type: 'send', from: mintAddress, to: alice.address, amount: 50000000000, nonce: 0);
    alice.addValidated(genesisTx, sim, log: sim.log);
    sim.metrics.txTotal++;
    sim.log("🌱 Genesis minted → ${alice.name} (50 000 000 000 DORO)", 'ok');
    sim.log("🚀 Simulateur multi-nœuds prêt ! 4 nœuds de démo créés.", 'info');
    sim.log("💡 Sélectionne un nœud dans l'onglet Réseau pour voir sa vue détaillée.", 'info');
    sim.log("⚡ Active le chaos pour observer les divergences entre nœuds.", 'info');
  }

  void _stopAuto() {
    _chatTimer?.cancel();
    _txTimer?.cancel();
    _marketTimer?.cancel();
    _chaosTimer?.cancel();
  }

  void _startAuto() {
    _stopAuto();
    const base = 3000;
    final speed = autoSpeed.clamp(1, 10);
    if (autoChat) {
      _chatTimer = Timer.periodic(Duration(milliseconds: (base / speed).round()), (_) => _autoChatTick());
    }
    if (autoTx) {
      _txTimer = Timer.periodic(Duration(milliseconds: (base * 1.5 / speed).round()), (_) => _autoTxTick());
    }
    if (autoMarket) {
      _marketTimer = Timer.periodic(Duration(milliseconds: (base * 2 / speed).round()), (_) => _autoMarketTick());
    }
    if (chaosOn) {
      _chaosTimer = Timer.periodic(Duration(milliseconds: (base * 2 / speed).round()), (_) {
        sim.chaosTick(discPct: chaosDisc.round(), partPct: chaosPart.round());
      });
    }
  }

  void _autoChatTick() {
    final online = sim.nodes.values.where((n) => n.online && n.connectionCount(sim) > 0).toList();
    if (online.length < 2) return;
    final sender = pick(online);
    final peers = sender.onlinePeers(sim).where((a) => a != sender.address).toList();
    if (peers.isEmpty) return;
    sender.sendMessage(pick(peers), pick(chatTexts), sim);
    setState(() {});
  }

  void _autoTxTick() {
    final online = sim.nodes.values.where((n) => n.online && n.connectionCount(sim) > 0).toList();
    if (online.length < 2) return;
    final sender = pick(online);
    final targets = online.where((n) => n.address != sender.address).toList();
    if (targets.isEmpty) return;
    final target = pick(targets);
    final maxAmt = ((sender.balanceOf(sender.address) * 0.2).floor()).clamp(0, 50);
    if (maxAmt < 1) return;
    final amount = rand(1, maxAmt);
    final nonce = (sender.lastNonce[sender.address] ?? 0) + 1;
    final tx = SimTx(id: newId('send'), type: 'send', from: sender.address, to: target.address, amount: amount, nonce: nonce);
    final r = sender.addValidated(tx, sim, log: sim.log);
    if (r == 'accepted') {
      sim.metrics.txTotal++;
      sim.metrics.txOk++;
      sim.log("🤖 ${sender.name} → ${target.name} $amount DORO (auto)", 'ok');
      sim.broadcastTx(sender, tx, chaosOn: chaosOn, lossPct: chaosLoss.round(), latMs: chaosLat.round(), autoClaimEnabled: autoClaim);
      sender.autoClaim(tx, sim, autoClaimEnabled: autoClaim, log: sim.log);
    } else {
      sim.metrics.txRej++;
    }
    setState(() {});
  }

  void _autoMarketTick() {
    final online = sim.nodes.values.where((n) => n.online).toList();
    if (online.length < 3) return;
    final trader = pick(online);
    final side = rand(0, 1) == 0 ? 'buy' : 'sell';
    trader.postOrder(side, rand(1, 20), rand(1, 10), sim, log: sim.log);
    for (final node in online) {
      node.matchOrders(sim, autoClaimEnabled: autoClaim, log: sim.log);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _stopAuto();
    _metricsTimer?.cancel();
    _newNodeCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _createNode() {
    final name = _newNodeCtrl.text.trim().isEmpty ? "Nœud ${sim.nodes.length + 1}" : _newNodeCtrl.text.trim();
    setState(() => sim.addNode(name));
    _newNodeCtrl.clear();
  }

  void _deleteSelected() {
    final addr = sim.selectedAddress;
    if (addr == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ce nœud ?"),
        content: Text("Supprimer ${sim.nodes[addr]?.name} ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => sim.removeNode(addr));
            },
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );
  }

  void _resetSelected() {
    final addr = sim.selectedAddress;
    if (addr == null) return;
    setState(() => sim.resetNode(addr));
  }

  void _resetAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Réinitialiser TOUT ?"),
        content: const Text("Tous les nœuds et le journal seront effacés."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _stopAuto();
              setState(() {
                sim.nodes.clear();
                sim.globalLog.clear();
                sim.selectedAddress = null;
              });
              sim.log("↺ Réseau entièrement réinitialisé.", 'info');
              _startAuto();
            },
            child: const Text("Réinitialiser", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  SimTx? _lastSend;

  void _doSend(String fromAddr, String toAddr, int amount) {
    if (fromAddr.isEmpty || toAddr.isEmpty || fromAddr == toAddr || amount <= 0) {
      sim.log("⚠️ Sélectionne deux nœuds différents et un montant valide.", 'rej');
      return;
    }
    final node = sim.nodes[fromAddr];
    if (node == null || !node.online) {
      sim.log("⚠️ Nœud source hors ligne", 'rej');
      return;
    }
    final nonce = (node.lastNonce[fromAddr] ?? 0) + 1;
    final tx = SimTx(id: newId('send'), type: 'send', from: fromAddr, to: toAddr, amount: amount, nonce: nonce);
    final r = node.addValidated(tx, sim, log: sim.log);
    sim.metrics.txTotal++;
    _lastSend = tx;
    if (r == 'accepted') {
      sim.metrics.txOk++;
      sim.log("📦 ${node.name} → ${sim.nodes[toAddr]?.name ?? shortAddr(toAddr)} $amount DORO", 'ok');
      sim.broadcastTx(node, tx, chaosOn: chaosOn, lossPct: chaosLoss.round(), latMs: chaosLat.round(), autoClaimEnabled: autoClaim);
      node.autoClaim(tx, sim, autoClaimEnabled: autoClaim, log: sim.log);
    } else {
      sim.metrics.txRej++;
      sim.log("✘ $r : ${node.name} → ${sim.nodes[toAddr]?.name ?? shortAddr(toAddr)} $amount DORO", 'rej');
    }
    setState(() {});
  }

  void _doStressSend(String fromAddr) {
    final node = sim.nodes[fromAddr];
    if (node == null || !node.online) return;
    final targets = sim.nodes.values.where((n) => n.address != fromAddr && n.online).toList();
    if (targets.isEmpty) return;
    for (var i = 0; i < 5; i++) {
      final target = pick(targets);
      final amt = rand(1, 10);
      final nonce = (node.lastNonce[fromAddr] ?? 0) + 1;
      final tx = SimTx(id: newId('send'), type: 'send', from: fromAddr, to: target.address, amount: amt, nonce: nonce);
      final r = node.addValidated(tx, sim, log: sim.log);
      if (r == 'accepted') {
        sim.metrics.txTotal++;
        sim.metrics.txOk++;
        sim.broadcastTx(node, tx, chaosOn: chaosOn, lossPct: chaosLoss.round(), latMs: chaosLat.round(), autoClaimEnabled: autoClaim);
        node.autoClaim(tx, sim, autoClaimEnabled: autoClaim, log: sim.log);
      }
    }
    sim.log("🏋️ Stress : 5 transactions envoyées par ${node.name}", 'info');
    setState(() {});
  }

  // ---- Scénarios guidés ----
  SimNode? _selectedOrWarn() {
    final node = sim.selected;
    if (node == null) sim.log("⚠️ Sélectionne un nœud d'abord", 'rej');
    return node;
  }

  void _scenarioReplay() {
    final node = _selectedOrWarn();
    if (node == null) return;
    final last = _lastSend;
    if (last == null) {
      sim.log("ℹ️ Envoie d'abord un paiement avec le nœud sélectionné, puis relance.", 'pend');
      return;
    }
    final replay = SimTx(id: newId('replay'), type: 'send', from: last.from, to: last.to, amount: last.amount, nonce: last.nonce);
    final r = node.addValidated(replay, sim, log: sim.log);
    if (r == 'accepted') sim.metrics.txOk++; else sim.metrics.txRej++;
    sim.metrics.txTotal++;
    sim.log("↻ Rejeu (même nonce ${last.nonce}) : $r", r == 'accepted' ? 'ok' : (r.startsWith('rejected') ? 'rej' : 'pend'));
    setState(() {});
  }

  void _scenarioOverspend() {
    final node = _selectedOrWarn();
    if (node == null || !node.online) return;
    final targets = sim.nodes.values.where((n) => n.address != node.address && n.online).toList();
    if (targets.isEmpty) {
      sim.log("⚠️ Pas de cible disponible", 'rej');
      return;
    }
    final target = pick(targets);
    final tooMuch = node.balanceOf(node.address) + 999999;
    final nonce = (node.lastNonce[node.address] ?? 0) + 1;
    final tx = SimTx(id: newId('overspend'), type: 'send', from: node.address, to: target.address, amount: tooMuch, nonce: nonce);
    final r = node.addValidated(tx, sim, log: sim.log);
    sim.metrics.txTotal++;
    if (r == 'accepted') sim.metrics.txOk++; else sim.metrics.txRej++;
    sim.log("💸 Sur-dépense ($tooMuch DORO, solde=${node.balanceOf(node.address)}) : $r", r.startsWith('rejected') ? 'rej' : 'ok');
    setState(() {});
  }

  void _scenarioDoubleGenesis() {
    final node = _selectedOrWarn();
    if (node == null) return;
    final tx = SimTx(id: newId('genesis2'), type: 'send', from: mintAddress, to: node.address, amount: 50000000000, nonce: 0);
    final r = node.addValidated(tx, sim, log: sim.log);
    if (r == 'accepted') sim.metrics.txOk++; else sim.metrics.txRej++;
    sim.metrics.txTotal++;
    sim.log("🌱 2ᵉ genesis par ${node.name} : $r", r.startsWith('rejected') ? 'rej' : 'ok');
    setState(() {});
  }

  void _scenarioLateSend() {
    final node = _selectedOrWarn();
    if (node == null || !node.online) return;
    final targets = sim.nodes.values.where((n) => n.address != node.address && n.online).toList();
    if (targets.isEmpty) {
      sim.log("⚠️ Pas de cible", 'rej');
      return;
    }
    final target = pick(targets);
    final amt = rand(5, 20);
    final futureSendId = newId('send-future');
    final nonce = (node.lastNonce[node.address] ?? 0) + 1;
    final orphanReceive = SimTx(
      id: newId('receive-orphan'),
      type: 'receive',
      from: target.address,
      to: target.address,
      amount: amt,
      nonce: (node.lastNonce[target.address] ?? 0) + 1,
      linkedSendId: futureSendId,
    );
    sim.log("🧪 Receive orphelin injecté AVANT son send ($futureSendId)...", 'pend');
    final r1 = node.addValidated(orphanReceive, sim, log: sim.log);
    sim.log("   Receive → $r1", r1.startsWith('rejected') ? 'rej' : 'pend');
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!node.online) return;
      sim.log("🧪 ...1.5s plus tard le send correspondant arrive :", 'pend');
      final lateSend = SimTx(id: futureSendId, type: 'send', from: node.address, to: target.address, amount: amt, nonce: nonce);
      final r2 = node.addValidated(lateSend, sim, log: sim.log);
      sim.metrics.txTotal++;
      if (r2 == 'accepted') {
        sim.metrics.txOk++;
        sim.log("   Send → $r2 (receive en attente débloqué automatiquement)", 'ok');
        sim.broadcastTx(node, lateSend, chaosOn: chaosOn, lossPct: chaosLoss.round(), latMs: chaosLat.round(), autoClaimEnabled: autoClaim);
        if (autoClaim) node.autoClaim(lateSend, sim, autoClaimEnabled: autoClaim, log: sim.log);
      } else {
        sim.metrics.txRej++;
        sim.log("   Send → $r2", 'rej');
      }
      setState(() {});
    });
    setState(() {});
  }

  void _scenarioDoubleClaim() {
    final node = _selectedOrWarn();
    if (node == null) return;
    final last = _lastSend;
    if (last == null) {
      sim.log("ℹ️ Envoie d'abord un paiement avec le nœud sélectionné.", 'pend');
      return;
    }
    final nonce = (node.lastNonce[last.to] ?? 0) + 1;
    final rx1 = SimTx(id: newId('rx1'), type: 'receive', from: last.to, to: last.to, amount: last.amount, nonce: nonce, linkedSendId: last.id);
    sim.log("🎯 1er receive : ${node.addValidated(rx1, sim, log: sim.log)}", 'ok');
    final rx2 = SimTx(id: newId('rx2'), type: 'receive', from: last.to, to: last.to, amount: last.amount, nonce: nonce + 1, linkedSendId: last.id);
    final r = node.addValidated(rx2, sim, log: sim.log);
    sim.log("🎯 2ᵉ receive (double claim) : $r", r.startsWith('rejected') ? 'rej' : 'ok');
    setState(() {});
  }

  void _postOrder(String side) {
    final addr = sim.selectedAddress;
    final node = addr == null ? null : sim.nodes[addr];
    if (node == null || !node.online) {
      sim.log("⚠️ Nœud hors ligne", 'rej');
      return;
    }
    node.postOrder(side, rand(1, 20), rand(1, 10), sim, log: sim.log);
    setState(() {});
  }

  void _exportReport() {
    final buf = StringBuffer();
    buf.writeln("=== RAPPORT RÉSEAU DORO ===");
    buf.writeln("Date: ${DateTime.now().toIso8601String()}");
    buf.writeln("Nœuds: ${sim.nodes.length}");
    buf.writeln("Transactions totales: ${sim.metrics.txTotal} (OK: ${sim.metrics.txOk}, REJ: ${sim.metrics.txRej})");
    buf.writeln("Messages: ${sim.metrics.msgTotal}");
    buf.writeln("Trades: ${sim.metrics.tradeTotal}");
    buf.writeln();
    buf.writeln("--- Détail par nœud ---");
    for (final node in sim.nodes.values) {
      buf.writeln("${node.name} (${node.online ? 'EN LIGNE' : 'HORS LIGNE'}) | Ledger: ${node.ledger.length} txs | "
          "Balance: ${node.balanceOf(node.address)} | Msgs: ${node.messages.length} | Ordres: ${node.stats.ordersPlaced}");
    }
    buf.writeln();
    buf.writeln("--- Ledger (tous les blocs, vue globale) ---");
    final allTx = <String, SimTx>{};
    for (final node in sim.nodes.values) {
      allTx.addAll(node.ledger);
    }
    for (final tx in allTx.values) {
      buf.writeln("${tx.id} | ${tx.type} | ${shortAddr(tx.from)} → ${shortAddr(tx.to)} | ${tx.amount}");
    }
    buf.writeln("=== FIN DU RAPPORT ===");
    sim.log("📋 Rapport généré (voir dialogue)", 'info');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rapport réseau"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(buf.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer"))],
      ),
    );
  }

  Color _logColor(String cls) {
    switch (cls) {
      case 'ok':
        return const Color(0xFF00D084);
      case 'rej':
        return const Color(0xFFFF4D4D);
      case 'pend':
        return const Color(0xFFF5A623);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🔗 Simulateur Réseau Multi-Nœuds"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Réseau"),
            Tab(text: "Vue détaillée"),
            Tab(text: "Marché & Journal"),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFF5A623).withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              "⚠️ Chaque nœud possède sa propre copie du ledger, ses propres soldes, sa propre file de messages. "
              "Le réseau propage les données par gossip. Active le chaos pour voir les divergences apparaître.",
              style: TextStyle(fontSize: 11, color: Color(0xFFF5A623), fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNetworkTab(),
                _buildDetailTab(),
                _buildMarketTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Onglet 1 : Nœuds & réseau ----------------
  Widget _buildNetworkTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text("Nœuds du réseau", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .5)),
        const SizedBox(height: 8),
        if (sim.nodes.isEmpty) const Center(child: Text("Aucun nœud. Créez-en au moins deux.", style: TextStyle(color: Colors.grey))),
        ...sim.nodes.values.map((node) {
          final isSelected = sim.selectedAddress == node.address;
          return Card(
            color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
            child: ListTile(
              onTap: () => setState(() => sim.selectedAddress = node.address),
              title: Row(
                children: [
                  Expanded(child: Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                  _badge(node.online ? "EN L" : "HORS L", node.online ? Colors.green : Colors.red),
                ],
              ),
              subtitle: Text("${shortAddr(node.address)} · ${node.connectionCount(sim)} connexions", style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${node.balanceOf(node.address)}", style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Color(0xFF00D084))),
                  Text("${node.ledger.length} blocs", style: const TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newNodeCtrl,
                decoration: const InputDecoration(labelText: "Nom du nœud", isDense: true, border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _createNode, child: const Icon(Icons.add)),
          ],
        ),
        const Divider(height: 32),
        const Text("Chaos Engine", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .5)),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Activer le chaos"),
                  value: chaosOn,
                  onChanged: (v) => setState(() {
                    chaosOn = v;
                    _startAuto();
                  }),
                ),
                _sliderRow("Déconnexion", chaosDisc, 0, 20, "%", (v) => setState(() => chaosDisc = v)),
                _sliderRow("Perte messages", chaosLoss, 0, 40, "%", (v) => setState(() => chaosLoss = v)),
                _sliderRow("Latence max", chaosLat, 0, 3000, "ms", (v) => setState(() => chaosLat = v)),
                _sliderRow("Partitions", chaosPart, 0, 15, "%", (v) => setState(() => chaosPart = v)),
              ],
            ),
          ),
        ),
        const Divider(height: 32),
        const Text("Automatisation", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .5)),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text("Chat automatique continu"), value: autoChat, onChanged: (v) => setState(() { autoChat = v; _startAuto(); })),
                SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text("Transactions automatiques"), value: autoTx, onChanged: (v) => setState(() { autoTx = v; _startAuto(); })),
                SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text("Marché OTC automatique"), value: autoMarket, onChanged: (v) => setState(() { autoMarket = v; _startAuto(); })),
                _sliderRow("Vitesse", autoSpeed, 1, 10, "x", (v) => setState(() { autoSpeed = v; _startAuto(); })),
                SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text("Auto-receive (comme WalletKernel)"), value: autoClaim, onChanged: (v) => setState(() => autoClaim = v)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sliderRow(String label, double value, double min, double max, String unit, void Function(double) onChanged) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))),
        Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
        SizedBox(width: 44, child: Text("${value.round()}$unit", style: const TextStyle(fontSize: 11))),
      ],
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
      );

  // ---------------- Onglet 2 : Vue détaillée d'un nœud ----------------
  Widget _buildDetailTab() {
    final sel = sim.selected;
    final fromCtrl = ValueNotifier<String?>(sel?.address);
    final toCtrl = ValueNotifier<String?>(null);
    final amountCtrl = TextEditingController(text: "5");

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: sim.nodes.containsKey(sim.selectedAddress) ? sim.selectedAddress : null,
                decoration: const InputDecoration(labelText: "Vue depuis", isDense: true, border: OutlineInputBorder()),
                items: sim.nodes.values.map((n) => DropdownMenuItem(value: n.address, child: Text("${n.online ? '🟢' : '🔴'} ${n.name}"))).toList(),
                onChanged: (v) => setState(() => sim.selectedAddress = v),
              ),
            ),
            IconButton(onPressed: _resetSelected, tooltip: "Réinitialiser ce nœud", icon: const Icon(Icons.restart_alt)),
            IconButton(onPressed: _deleteSelected, tooltip: "Supprimer", icon: const Icon(Icons.delete_outline, color: Colors.red)),
          ],
        ),
        const SizedBox(height: 8),
        if (sel == null)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: Text("Sélectionne un nœud", style: TextStyle(color: Colors.grey))))
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(sel.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    _badge(sel.online ? "EN LIGNE" : "HORS LIGNE", sel.online ? Colors.green : Colors.red),
                    const Spacer(),
                    Text(shortAddr(sel.address), style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.grey)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, children: [
                    Text("💰 ${sel.balanceOf(sel.address)} DORO", style: const TextStyle(color: Color(0xFF00D084))),
                    Text("🔢 Nonce: ${sel.lastNonce[sel.address] ?? 0}"),
                    Text("📒 Ledger: ${sel.ledger.length} blocs"),
                    Text("🔗 Pairs: ${sel.connectionCount(sim)}"),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => setState(() => sim.toggleNode(sel.address)),
                    child: Text(sel.online ? "🔴 Déconnecter" : "🟢 Connecter"),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 24),
          const Text("Envoyer un paiement", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: sel.address,
                  decoration: const InputDecoration(labelText: "De", isDense: true, border: OutlineInputBorder()),
                  items: sim.nodes.values.where((n) => n.online).map((n) => DropdownMenuItem(value: n.address, child: Text(n.name, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => fromCtrl.value = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: null,
                  decoration: const InputDecoration(labelText: "Vers", isDense: true, border: OutlineInputBorder()),
                  items: sim.nodes.values.where((n) => n.online).map((n) => DropdownMenuItem(value: n.address, child: Text(n.name, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => toCtrl.value = v,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 90, child: TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _doSend(fromCtrl.value ?? sel.address, toCtrl.value ?? '', int.tryParse(amountCtrl.text) ?? 0),
                  child: const Text("Envoyer"),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _doStressSend(fromCtrl.value ?? sel.address), child: const Text("🏋️ Stress")),
            ],
          ),
          const Divider(height: 24),
          Text("Ledger (${sel.ledger.length} blocs)", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (sel.ledger.isEmpty)
            const Text("Aucun bloc.", style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            SizedBox(
              height: 220,
              child: ListView(
                children: sel.ledger.values.toList().reversed.take(50).map((tx) {
                  final kind = sel.isMint(tx.from) ? 'mint' : tx.type;
                  return ListTile(
                    dense: true,
                    leading: _badge(kind, kind == 'mint' ? Colors.amber : (kind == 'send' ? Colors.deepPurple : Colors.green)),
                    title: Text("${sim.nameOf(tx.from)} → ${sim.nameOf(tx.to)}", style: const TextStyle(fontSize: 12)),
                    trailing: Text("${tx.amount}", style: const TextStyle(fontFamily: 'monospace')),
                  );
                }).toList(),
              ),
            ),
          const Divider(height: 24),
          Text("Messagerie (${sel.messages.length})", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (sel.messages.isEmpty)
            const Text("Aucun message.", style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            SizedBox(
              height: 180,
              child: ListView(
                children: sel.messages.reversed.take(30).map((m) => Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6), border: const Border(left: BorderSide(color: Colors.deepPurple, width: 2))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.fromName, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                          Text(m.text, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )).toList(),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------- Onglet 3 : Marché OTC & journal ----------------
  Widget _buildMarketTab() {
    final sel = sim.selected;
    final orders = sel?.knownOrders.values.where((o) => !o.cancelled && o.filled < o.amount).toList() ?? [];
    final trades = sel?.knownTrades ?? [];
    final elapsed = (DateTime.now().millisecondsSinceEpoch - sim.metrics.startTime) / 1000;
    final tps = elapsed > 0 ? (sim.metrics.txTotal / elapsed).toStringAsFixed(1) : '0';
    final mps = elapsed > 0 ? (sim.metrics.msgTotal / elapsed).toStringAsFixed(1) : '0';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text("Marché OTC", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _postOrder('buy'), child: const Text("📈 Acheter"))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => _postOrder('sell'), child: const Text("📉 Vendre"))),
        ]),
        const SizedBox(height: 8),
        if (orders.isEmpty)
          const Text("Aucun ordre.", style: TextStyle(color: Colors.grey, fontSize: 12))
        else
          ...orders.take(20).map((o) => ListTile(
                dense: true,
                leading: _badge(o.side, o.side == 'buy' ? Colors.green : Colors.red),
                title: Text(o.nodeName),
                trailing: Text("${o.amount - o.filled} @ ${o.price}", style: const TextStyle(fontFamily: 'monospace')),
              )),
        Divider(height: 24, color: Theme.of(context).dividerColor),
        Text("Trades (${trades.length})", style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (trades.isEmpty)
          const Text("Aucun trade.", style: TextStyle(color: Colors.grey, fontSize: 12))
        else
          ...trades.reversed.take(15).map((t) => ListTile(
                dense: true,
                title: Text("${t.sellerName} → ${t.buyerName}", style: const TextStyle(fontSize: 12)),
                trailing: Text("${t.amount} @ ${t.price}", style: const TextStyle(fontFamily: 'monospace')),
              )),
        const Divider(height: 24),
        const Text("Scénarios guidés", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton(onPressed: _scenarioReplay, child: const Text("↻ Rejeu")),
          OutlinedButton(onPressed: _scenarioOverspend, child: const Text("💸 Sur-dépense")),
          OutlinedButton(onPressed: _scenarioDoubleGenesis, child: const Text("🌱 2ᵉ genesis")),
          OutlinedButton(onPressed: _scenarioLateSend, child: const Text("⏳ Send tardif")),
          OutlinedButton(onPressed: _scenarioDoubleClaim, child: const Text("🎯 Double claim")),
        ]),
        const Divider(height: 24),
        const Text("Métriques en direct", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 6, children: [
          _metricChip("📦 TPS", tps),
          _metricChip("💬 Msg/s", mps),
          _metricChip("✅ OK", "${sim.metrics.txOk}"),
          _metricChip("❌ REJ", "${sim.metrics.txRej}"),
          _metricChip("🤝 Trades", "${sim.metrics.tradeTotal}"),
          _metricChip("🕒", "${elapsed.floor()}s"),
        ]),
        const Divider(height: 24),
        Row(children: [
          const Expanded(child: Text("Journal réseau", style: TextStyle(fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => setState(() => sim.globalLog.clear()), tooltip: "Effacer", icon: const Icon(Icons.clear_all, size: 20)),
          IconButton(onPressed: _exportReport, tooltip: "Rapport", icon: const Icon(Icons.description_outlined, size: 20)),
          IconButton(onPressed: _resetAll, tooltip: "Reset global", icon: const Icon(Icons.restart_alt, color: Colors.red, size: 20)),
        ]),
        Container(
          height: 260,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
          child: ListView(
            children: sim.globalLog.take(80).map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      children: [
                        TextSpan(text: "${e.time} ", style: const TextStyle(color: Colors.grey)),
                        TextSpan(text: e.text, style: TextStyle(color: _logColor(e.cls))),
                      ],
                    ),
                  ),
                )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _metricChip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
        child: Text("$label: $value", style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
      );
}
