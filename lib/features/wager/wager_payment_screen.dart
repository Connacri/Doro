// lib/features/wager/wager_payment_screen.dart
//
// Écran affiché après qu'un user a choisi une option + un montant sur un
// bet/prediction :
//   - QR code de l'adresse de dépôt (pretty_qr_code, déjà en dépendance)
//   - Montant EXACT à copier (précision 6 décimales TRC20)
//   - Champ "Coller le hash de transaction" avec bouton Coller
//   - Soumission -> confirm-wager-payment, avec Realtime + retry auto

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/binance_pay_service.dart';

class WagerPaymentScreen extends StatefulWidget {
  final String? betId;
  final String? predictionEventId;
  final String chosenOption;
  final double amount;

  const WagerPaymentScreen({
    super.key,
    this.betId,
    this.predictionEventId,
    required this.chosenOption,
    required this.amount,
  }) : assert(betId != null || predictionEventId != null);

  @override
  State<WagerPaymentScreen> createState() => _WagerPaymentScreenState();
}

enum _ScreenStatus { creating, awaitingPayment, verifying, confirmed, rejected, error }

class _WagerPaymentScreenState extends State<WagerPaymentScreen> {
  late final BinancePayService _payService;
  final _txIdController = TextEditingController();
  StreamSubscription? _realtimeSub;
  StreamSubscription<ConfirmResult>? _pollSub;

  _ScreenStatus _status = _ScreenStatus.creating;
  WagerPaymentInfo? _paymentInfo;
  String? _message;

  @override
  void initState() {
    super.initState();
    _payService = BinancePayService(Supabase.instance.client);
    _createPayment();
  }

  Future<void> _createPayment() async {
    try {
      final info = await _payService.createWagerPayment(
        betId: widget.betId,
        predictionEventId: widget.predictionEventId,
        chosenOption: widget.chosenOption,
        amount: widget.amount,
      );
      if (!mounted) return;
      setState(() {
        _paymentInfo = info;
        _status = _ScreenStatus.awaitingPayment;
      });
      // Realtime : détecte instantanément une confirmation/rejet côté backend,
      // même si l'user ne soumet pas lui-même le txId depuis cet écran
      // (ex: un admin résout un incident manuellement).
      _realtimeSub = _payService.watchWagerStatus(
        wagerId: info.wagerId,
        onChange: (status, rejectReason) {
          if (!mounted) return;
          if (status == 'confirmed') {
            setState(() {
              _status = _ScreenStatus.confirmed;
              _message = "✅ Mise confirmée.";
            });
          } else if (status == 'rejected') {
            setState(() {
              _status = _ScreenStatus.rejected;
              _message = rejectReason ?? "Paiement rejeté.";
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _ScreenStatus.error;
        _message = "Impossible de créer la mise : $e";
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _txIdController.text = data!.text!.trim();
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copié')));
  }

  Future<void> _submitTxId() async {
    final txId = _txIdController.text.trim();
    if (txId.isEmpty || _paymentInfo == null) return;

    setState(() {
      _status = _ScreenStatus.verifying;
      _message = null;
    });

    _pollSub?.cancel();
    _pollSub = _payService
        .pollUntilResolved(wagerId: _paymentInfo!.wagerId, txId: txId)
        .listen((result) {
      if (!mounted) return;
      setState(() {
        _message = result.message;
        switch (result.outcome) {
          case ConfirmOutcome.confirmed:
            _status = _ScreenStatus.confirmed;
            break;
          case ConfirmOutcome.rejected:
          case ConfirmOutcome.error:
            _status = _ScreenStatus.rejected;
            break;
          case ConfirmOutcome.pending:
            _status = _ScreenStatus.verifying; // reste en vérification, retry en cours
            break;
        }
      });
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _pollSub?.cancel();
    _txIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paiement de la mise')),
      body: switch (_status) {
        _ScreenStatus.creating => const Center(child: CircularProgressIndicator()),
        _ScreenStatus.error => _ErrorView(message: _message ?? 'Erreur inconnue', onRetry: _createPayment),
        _ScreenStatus.confirmed => _ConfirmedView(message: _message ?? '✅ Mise confirmée.'),
        _ScreenStatus.rejected => _RejectedView(
            message: _message ?? 'Paiement rejeté.',
            onRetry: () => setState(() => _status = _ScreenStatus.awaitingPayment),
          ),
        _ScreenStatus.awaitingPayment || _ScreenStatus.verifying => _buildPaymentForm(),
      },
    );
  }

  Widget _buildPaymentForm() {
    final info = _paymentInfo!;
    final verifying = _status == _ScreenStatus.verifying;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: PrettyQrView.data(data: info.depositAddress, decoration: const PrettyQrDecoration()),
            ),
          ),
          const SizedBox(height: 20),
          _CopyRow(label: 'Adresse de dépôt (${info.network})', value: info.depositAddress, onCopy: _copy),
          const SizedBox(height: 12),
          _CopyRow(
            label: 'Montant EXACT à envoyer (${info.currency})',
            value: info.amountExact,
            onCopy: _copy,
            emphasize: true,
          ),
          const SizedBox(height: 8),
          Text(
            "⚠️ Envoie le montant EXACT ci-dessus, au centime près (6 décimales). "
            "Un montant différent ne pourra pas être associé automatiquement à ta mise.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
          ),
          const Divider(height: 40),
          Text('Après paiement', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            "Ouvre ton app Binance/wallet → historique des transactions → "
            "\"View on Explorer\" → copie le hash (TxID) → colle-le ci-dessous.",
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _txIdController,
            enabled: !verifying,
            decoration: InputDecoration(
              labelText: 'Hash de transaction (TxID)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Coller',
                onPressed: verifying ? null : _pasteFromClipboard,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_message != null) ...[
            Text(_message!, style: TextStyle(color: verifying ? Colors.blueGrey : Colors.red)),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: verifying || _txIdController.text.trim().isEmpty ? null : _submitTxId,
            child: verifying
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Vérification en cours…'),
                    ],
                  )
                : const Text('Confirmer le paiement'),
          ),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  final Future<void> Function(String value, String label) onCopy;

  const _CopyRow({required this.label, required this.value, required this.onCopy, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                value,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: emphasize ? 20 : 14,
                  fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.copy), onPressed: () => onCopy(value, label)),
          ],
        ),
      ],
    );
  }
}

class _ConfirmedView extends StatelessWidget {
  final String message;
  const _ConfirmedView({required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('OK')),
          ],
        ),
      );
}

class _RejectedView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _RejectedView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
}
