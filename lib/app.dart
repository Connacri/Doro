import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/wallet/wallet_provider.dart';
import 'features/wallet/wallet_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/chat_provider.dart';
import 'features/ledger/ledger_provider.dart';
import 'features/ledger/ledger_screen.dart';
import 'features/network/network_provider.dart';
import 'features/network/network_screen.dart';

import 'core/storage/repositories/wallet_repository.dart';
import 'core/p2p/p2p_node.dart';
import 'core/bootstrap/bootstrap_service.dart';
import 'core/utils/logger.dart';
import 'core/utils/node_identity.dart';
class DoroApp extends StatefulWidget {
  const DoroApp({super.key});

  @override
  State<DoroApp> createState() => _DoroAppState();
}

class _DoroAppState extends State<DoroApp> {
  P2PNode? _node;
  late final WalletRepository _walletRepo;

  @override
  void initState() {
    super.initState();
    _walletRepo = WalletRepository();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _initNode();
    }
  }

  Future<void> _initNode() async {
    final nodeId = await NodeIdentity.getOrCreate();
    final node = P2PNode(nodeId);
    _node = node;
    if (!mounted) return;
    setState(() {});
    try {
      final seeds = BootstrapService.getSeeds();
      if (seeds.isNotEmpty) {
        await node.start(signalingUrl: seeds.first);
      }
    } catch (e) {
      Logger.error("Bootstrap failed: $e");
    }
  }

  @override
  void dispose() {
    _node?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = _node;
    if (node == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => WalletProvider(node.wallet, _walletRepo, node: node),
        ),
        ChangeNotifierProvider(create: (_) => ChatProvider(node)),
        ChangeNotifierProvider(create: (_) => LedgerProvider(node)),
        ChangeNotifierProvider(create: (_) => NetworkProvider(node)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "Doro",
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF6C5CE7),
          useMaterial3: true,
        ),
        home: const Root(),
      ),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkProvider>();
    final online = net.peers.length;

    return Scaffold(
      body: IndexedStack(index: index, children: const [
        WalletScreen(),
        ChatScreen(),
        LedgerScreen(),
        NetworkScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.wallet), label: "Wallet"),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: online > 0,
              label: Text("$online"),
              child: const Icon(Icons.chat),
            ),
            label: "Chat",
          ),
          const NavigationDestination(icon: Icon(Icons.book), label: "Ledger"),
          NavigationDestination(
            icon: Icon(
              Icons.wifi,
              color: net.isConnected ? Colors.green : Colors.grey,
            ),
            label: "Network",
          ),
        ],
      ),
    );
  }
}
