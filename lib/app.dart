import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/network/network_provider.dart';
import 'features/ledger/ledger_provider.dart';
import 'features/messaging/chat_provider.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NetworkProvider()),
        ChangeNotifierProvider(create: (_) => LedgerProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(
          body: Center(child: Text("Mobile Distributed Network")),
        ),
      ),
    );
  }
}