// lib/app.dart
import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/home/home_screen.dart';
import 'features/wallet/wallet_provider.dart';
import 'features/wallet/wallet_screen.dart';
import 'features/chat/chats_screen.dart';
import 'features/chat/chat_provider.dart';
import 'features/ledger/ledger_provider.dart';
import 'features/network/network_provider.dart';
import 'core/storage/objectbox/store.dart';
import 'core/storage/repositories/wallet_repository.dart';
import 'core/p2p/p2p_node.dart';
import 'core/bootstrap/bootstrap_service.dart';
import 'core/utils/logger.dart';
import 'core/utils/node_identity.dart';
import 'core/supabase/supabase_bootstrap.dart';
import 'features/market/market_provider.dart';
import 'features/profile/profile_provider.dart';
import 'features/profile/profile_screen.dart';
import 'features/boot/boot_terminal_screen.dart';
import 'features/bet/bet_provider.dart';
import 'features/bet/bets_list_screen.dart';

/// Point d'entrée de l'app. IMPORTANT : le rendu de l'UI ne dépend QUE
/// de `_node` (le P2PNode — wallet/DAG/marché/réseau), qui s'initialise
/// localement sans réseau. La messagerie/le profil Supabase
/// s'initialisent en tâche de fond via [SupabaseBootstrap] et ne
/// bloquent jamais l'affichage : une config manquante ou un réseau en
/// échec dégrade uniquement les onglets Discussions/Profil (avec un
/// bouton "Réessayer"), jamais le reste de l'app.
class DoroApp extends StatefulWidget {
  final ObjectBoxStore db;
  const DoroApp({super.key, required this.db});
  @override
  State<DoroApp> createState() => _DoroAppState();
}

class _DoroAppState extends State<DoroApp> with WidgetsBindingObserver {
  P2PNode? _node;
  SupabaseBootstrap? _supabaseBootstrap;
  bool _bootDone = false;
  late final WalletRepository _walletRepo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _walletRepo = WalletRepository(widget.db);
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _initNode();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _node?.stop();
    _supabaseBootstrap?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final node = _node;
    if (node == null) return;
    if (state == AppLifecycleState.resumed) {
      Logger.info("App resumed — checking signaling connection");
      node.reconnectSignaling();
      // Si Supabase avait échoué (réseau coupé pendant la pause), on
      // retente silencieusement au retour au premier plan.
      final bootstrap = _supabaseBootstrap;
      if (bootstrap != null && !bootstrap.isReady) {
        bootstrap.retry();
      }
    } else if (state == AppLifecycleState.paused) {
      Logger.info("App paused — keeping node alive in background");
    }
  }

  Future<void> _initNode() async {
    final identity = await NodeIdentity.getOrCreate();
    final node = P2PNode(identity, widget.db);

    // Le P2PNode (wallet/DAG/marché/réseau) est prêt et suffisant pour
    // afficher l'app — on ne l'attend JAMAIS après Supabase.
    _node = node;
    _supabaseBootstrap = SupabaseBootstrap(identity: identity, db: widget.db);
    Logger.info("Cœur local prêt (wallet, DAG, marché) — affichage de l'app.");
    if (!mounted) return;
    setState(() {});

    // Messagerie/profil Supabase : lancés en tâche de fond, sans
    // bloquer le rendu. `SupabaseBootstrap` notifie ChatProvider/
    // ProfileProvider dès qu'ils deviennent disponibles.
    unawaited(_supabaseBootstrap!.start());

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
    final bootstrap = _supabaseBootstrap;

    // Tant que le cœur local (P2PNode) n'est pas prêt, ou tant que
    // l'utilisateur n'a pas confirmé/laissé filer le délai auto sur
    // l'écran terminal, on affiche le journal de démarrage en direct —
    // jamais un simple spinner muet.
    if (node == null || bootstrap == null || !_bootDone) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: BootTerminalScreen(
          ready: node != null && bootstrap != null,
          onContinue: () => setState(() => _bootDone = true),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bootstrap),
        ChangeNotifierProvider(create: (_) => WalletProvider(node.wallet, _walletRepo, node: node)),
        ChangeNotifierProxyProvider<WalletProvider, ChatProvider>(
          create: (_) => ChatProvider(bootstrap),
          update: (_, wallet, chat) => chat!..walletProvider = wallet,
        ),
        ChangeNotifierProvider(create: (_) => LedgerProvider(node)),
        ChangeNotifierProvider(create: (_) => NetworkProvider(node)),

        ChangeNotifierProxyProvider<WalletProvider, MarketProvider>(
          create: (_) => MarketProvider(node),
          update: (_, wallet, market) => market!..walletProvider = wallet,
        ),
        ChangeNotifierProvider(create: (_) => ProfileProvider(bootstrap, node.nodeId)),
        ChangeNotifierProxyProvider<WalletProvider, BetProvider>(
          create: (_) => BetProvider(node),
          update: (_, wallet, bet) {
            bet!.node.betKernel.walletSend = ({required to, required amount}) =>
                wallet.send(from: node.nodeId, to: to, amount: amount);
            return bet;
          },
        ),
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
    final pendingRequests = chat.available ? chat.receivedRequests.length : 0;

    return Scaffold(
      body: IndexedStack(index: index, children: const [
        HomeScreen(),
        WalletScreen(),
        BetsListScreen(),
        ChatsScreen(),
        ProfileScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home), label: "Home"),
          const NavigationDestination(icon: Icon(Icons.wallet), label: "Wallet"),
          const NavigationDestination(icon: Icon(Icons.emoji_events), label: "Paris"),
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
