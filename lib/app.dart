// lib/app.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/home/home_screen.dart';
import 'features/wallet/wallet_provider.dart';
import 'features/wallet/wallet_screen.dart';
import 'features/chat/chats_screen.dart';
import 'features/chat/chat_provider.dart';
import 'features/ledger/ledger_provider.dart';
import 'features/network/network_provider.dart';
import 'core/storage/objectbox/store.dart';
import 'core/storage/repositories/wallet_repository.dart';
import 'core/storage/repositories/profile_repository.dart';
import 'core/p2p/p2p_node.dart';
import 'core/bootstrap/bootstrap_service.dart';
import 'core/utils/logger.dart';
import 'core/utils/node_identity.dart';
import 'core/crypto/signature.dart';
import 'core/supabase/supabase_config.dart';
import 'core/supabase/supabase_identity_service.dart';
import 'core/supabase/presence_service.dart';
import 'core/kernels/messenger/supabase_messenger_kernel.dart';
import 'features/market/market_provider.dart';
import 'features/profile/profile_provider.dart';
import 'features/profile/profile_screen.dart';

class DoroApp extends StatefulWidget {
  final ObjectBoxStore db;
  const DoroApp({super.key, required this.db});
  @override
  State<DoroApp> createState() => _DoroAppState();
}

class _DoroAppState extends State<DoroApp> with WidgetsBindingObserver {
  P2PNode? _node;
  SupabaseMessengerKernel? _messenger;
  PresenceService? _presence;
  late final WalletRepository _walletRepo;
  late final ProfileRepository _profileRepo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _walletRepo = WalletRepository(widget.db);
    _profileRepo = ProfileRepository(widget.db);
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _initNode();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _node?.stop();
    _messenger?.dispose();
    _presence?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final node = _node;
    if (node == null) return;
    if (state == AppLifecycleState.resumed) {
      Logger.info("App resumed — checking signaling connection");
      node.reconnectSignaling();
    } else if (state == AppLifecycleState.paused) {
      Logger.info("App paused — keeping node alive in background");
    }
  }

  Future<void> _initNode() async {
    final identity = await NodeIdentity.getOrCreate();
    final node = P2PNode(identity, widget.db);

    // ---- Messenger : Supabase (identité = nodeId = "0x"+pubkey, comme
    // partout ailleurs dans l'app — cf. AddressGenerator). Le P2PNode
    // reste utilisé pour wallet/ledger/market/network (inchangé).
    if (SupabaseConfig.isConfigured) {
      try {
        await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
        final supabase = Supabase.instance.client;

        final identityService = SupabaseIdentityService(supabase, CryptoService());
        await identityService.ensureBound(
          publicKeyHex: identity.nodeId,
          keyPair: identity.keyPair,
        );

        _messenger = SupabaseMessengerKernel(
          nodeId: identity.nodeId,
          supabase: supabase,
          db: widget.db,
        );
        _presence = PresenceService(supabase, identity.nodeId)..start();
      } catch (e) {
        Logger.error("Supabase messenger init failed: $e");
      }
    } else {
      Logger.error(
        "SUPABASE_URL / SUPABASE_ANON_KEY non configurés (--dart-define) — "
        "la messagerie Supabase est désactivée.",
      );
    }

    _node = node;
    if (!mounted) return;
    setState(() {});
    try {
      final seeds = BootstrapService.getSeeds();
      if (seeds.isNotEmpty) await node.start(signalingUrls: seeds);
    } catch (e) {
      Logger.error("Bootstrap failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = _node;
    final messenger = _messenger;
    final presence = _presence;
    if (node == null || messenger == null || presence == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider(node.wallet, _walletRepo, node: node)),
        ChangeNotifierProxyProvider<WalletProvider, ChatProvider>(
          create: (_) => ChatProvider(messenger, presence),
          update: (_, wallet, chat) => chat!..walletProvider = wallet,
        ),
        ChangeNotifierProvider(create: (_) => LedgerProvider(node)),
        ChangeNotifierProvider(create: (_) => NetworkProvider(node)),

        ChangeNotifierProxyProvider<WalletProvider, MarketProvider>(
          create: (_) => MarketProvider(node),
          update: (_, wallet, market) => market!..walletProvider = wallet,
        ),
        ChangeNotifierProvider(create: (_) => ProfileProvider(_profileRepo, node: node)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "Doro",
        theme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF6C5CE7), useMaterial3: true),
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
    final chat = context.watch<ChatProvider>();
    final pendingRequests = chat.receivedRequests.length;

    return Scaffold(
      body: IndexedStack(index: index, children: const [
        HomeScreen(),
        WalletScreen(),
        ChatsScreen(),
        ProfileScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home), label: "Home"),
          const NavigationDestination(icon: Icon(Icons.wallet), label: "Wallet"),
          NavigationDestination(
            icon: Badge(isLabelVisible: pendingRequests > 0, label: Text("$pendingRequests"), child: const Icon(Icons.chat_bubble_outline)),
            label: "Discussions",
          ),
          NavigationDestination(icon: Icon(Icons.person, color: net.isConnected ? Colors.green : Colors.grey), label: "Profil"),
        ],
      ),
    );
  }
}
