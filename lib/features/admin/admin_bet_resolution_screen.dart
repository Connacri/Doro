// lib/features/admin/admin_bet_resolution_screen.dart
//
// Écran réservé aux admins (accès à gater via AdminOnly côté navigation
// appelante, ex: un item de menu visible seulement si isCurrentUserAdmin).
// Deux sections :
//   1. Trancher un bet ouvert (choisir l'option gagnante) -> RPC
//      resolve_bet, qui calcule le pool parimutuel et marque les mises
//      gagnantes "owed" avec leur payout_amount.
//   2. Régler les paiements dus : pour chaque wager "owed", l'admin
//      envoie manuellement les USDT depuis Binance puis colle le TxID
//      de paiement -> RPC mark_wager_paid.
//
// Ni resolve_bet ni mark_wager_paid ne font confiance au client au-delà
// de l'appel : les deux fonctions Postgres vérifient is_admin() en
// interne (security definer), donc même un client trafiqué ne peut pas
// passer outre.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminBetResolutionScreen extends StatefulWidget {
  const AdminBetResolutionScreen({super.key});

  @override
  State<AdminBetResolutionScreen> createState() => _AdminBetResolutionScreenState();
}

class _AdminBetResolutionScreenState extends State<AdminBetResolutionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _openBets = [];
  List<Map<String, dynamic>> _owedWagers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bets = await _supabase
          .from('bets')
          .select('id,title,option_labels,staking_deadline,voting_deadline')
          .eq('status', 'open')
          .order('staking_deadline');

      final owed = await _supabase
          .from('wagers')
          .select('id,user_public_key,chosen_option,amount_unique,payout_amount,bet_id,bets(title)')
          .eq('payout_status', 'owed')
          .order('created_at');

      if (!mounted) return;
      setState(() {
        _openBets = List<Map<String, dynamic>>.from(bets as List);
        _owedWagers = List<Map<String, dynamic>>.from(owed as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur de chargement : $e";
        _loading = false;
      });
    }
  }

  Future<void> _resolveBet(Map<String, dynamic> bet) async {
    final options = List<String>.from(bet['option_labels'] as List);
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Résultat réel : "${bet['title']}"'),
        children: options
            .map((o) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, o),
                  child: Text(o),
                ))
            .toList(),
      ),
    );
    if (chosen == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer'),
        content: Text(
          'Trancher "${bet['title']}" avec le résultat "$chosen" ?\n\n'
          'Cette action est DÉFINITIVE : le pool sera réparti entre les mises '
          'gagnantes et le pari passera en "settled".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trancher')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _supabase.rpc('resolve_bet', params: {
        'p_bet_id': bet['id'],
        'p_winning_option': chosen,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Pari tranché, payouts calculés.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  Future<void> _markPaid(Map<String, dynamic> wager) async {
    final ctrl = TextEditingController();
    final txId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Coller le TxID du virement de gain'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: 'TxID',
            suffixIcon: IconButton(
              icon: const Icon(Icons.paste),
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) ctrl.text = data!.text!.trim();
              },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Marquer payé'),
          ),
        ],
      ),
    );
    if (txId == null || txId.isEmpty) return;

    try {
      await _supabase.rpc('mark_wager_paid', params: {
        'p_wager_id': wager['id'],
        'p_payout_tx_id': txId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Marqué payé.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Résolution & Payouts'),
        bottom: TabBar(controller: _tabCtrl, tabs: const [
          Tab(text: 'Trancher un pari'),
          Tab(text: 'Payouts dus'),
        ]),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabCtrl,
                  children: [_buildOpenBetsTab(), _buildOwedTab()],
                ),
    );
  }

  Widget _buildOpenBetsTab() {
    if (_openBets.isEmpty) {
      return const Center(child: Text('Aucun pari ouvert à trancher.'));
    }
    return ListView.builder(
      itemCount: _openBets.length,
      itemBuilder: (_, i) {
        final bet = _openBets[i];
        return ListTile(
          title: Text(bet['title'] as String),
          subtitle: Text('Options : ${(bet['option_labels'] as List).join(', ')}'),
          trailing: FilledButton(
            onPressed: () => _resolveBet(bet),
            child: const Text('Trancher'),
          ),
        );
      },
    );
  }

  Widget _buildOwedTab() {
    if (_owedWagers.isEmpty) {
      return const Center(child: Text('Aucun payout en attente.'));
    }
    return ListView.builder(
      itemCount: _owedWagers.length,
      itemBuilder: (_, i) {
        final w = _owedWagers[i];
        final betTitle = (w['bets'] as Map?)?['title'] ?? w['bet_id'];
        return ListTile(
          title: Text('$betTitle → ${w['user_public_key']}'),
          subtitle: Text('Doit recevoir : ${w['payout_amount']} USDT (misé ${w['amount_unique']} sur "${w['chosen_option']}")'),
          trailing: FilledButton(
            onPressed: () => _markPaid(w),
            child: const Text('Marquer payé'),
          ),
        );
      },
    );
  }
}
