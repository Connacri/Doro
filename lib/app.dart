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

import 'core/wallet/wallet_core.dart';
import 'core/storage/repositories/wallet_repository.dart';
import 'core/p2p/p2p_node.dart';
import 'core/bootstrap/bootstrap_service.dart';
import 'core/utils/logger.dart';

class VolteApp extends StatefulWidget {
  const VolteApp({super.key});

  @override
  State<VolteApp> createState() => _VolteAppState();
}

class _VolteAppState extends State<VolteApp> {
  late final P2PNode _node;
  late final WalletCore _walletCore;
  late final WalletRepository _walletRepo;

  @override
  void initState() {
    super.initState();
    _node = P2PNode("volte-${DateTime.now().millisecondsSinceEpoch}");
    _walletCore = WalletCore();
    _walletRepo = WalletRepository();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    try {
      final seeds = BootstrapService.getSeeds();
      if (seeds.isNotEmpty) {
        await _node.start(signalingUrl: seeds.first);
      }
    } catch (e) {
      Logger.error("Bootstrap failed: $e");
    }
  }

  @override
  void dispose() {
    _node.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => WalletProvider(_walletCore, _walletRepo, node: _node),
        ),
        ChangeNotifierProvider(create: (_) => ChatProvider(_node)),
        ChangeNotifierProvider(create: (_) => LedgerProvider(_node)),
        ChangeNotifierProvider(create: (_) => NetworkProvider(_node)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "Volte",
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