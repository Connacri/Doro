// lib/features/prediction/create_prediction_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/prediction/prediction_event.dart';
import '../../shared/theme/colors.dart';
import '../wallet/wallet_provider.dart';
import 'prediction_market_provider.dart';

class CreatePredictionScreen extends StatefulWidget {
  final PredictionEvent? editEvent;

  const CreatePredictionScreen({super.key, this.editEvent});

  @override
  State<CreatePredictionScreen> createState() => _CreatePredictionScreenState();
}

class _CreatePredictionScreenState extends State<CreatePredictionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionCtrl = TextEditingController();
  final _oracleAddressCtrl = TextEditingController();
  final _oraclePublicKeyCtrl = TextEditingController();

  final List<int> _durations = [1, 3, 7, 14, 30];
  int _selectedDays = 3;
  bool _isLoading = false;

  bool get _isEdit => widget.editEvent != null;

  @override
  void initState() {
    super.initState();
    final provider = context.read<PredictionMarketProvider>();
    final walletProvider = context.read<WalletProvider>();

    if (_isEdit) {
      final e = widget.editEvent!;
      _questionCtrl.text = e.question;
      _oracleAddressCtrl.text = e.oracleAddress;
      _oraclePublicKeyCtrl.text = e.oraclePublicKey;
      final remainingMs = e.closesAt - DateTime.now().millisecondsSinceEpoch;
      final remainingDays = remainingMs > 0 ? (remainingMs / 86400000).round().clamp(1, 30) : 1;
      _selectedDays = _durations.contains(remainingDays) ? remainingDays : 1;
    } else {
      if (walletProvider.wallets.isNotEmpty) {
        final wallet = walletProvider.wallets.last;
        _oracleAddressCtrl.text = wallet.address;
        _oraclePublicKeyCtrl.text = wallet.publicKey;
      } else {
        _oracleAddressCtrl.text = provider.node.nodeId;
        _oraclePublicKeyCtrl.text = provider.node.identity.publicKeyHex;
      }
    }
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _oracleAddressCtrl.dispose();
    _oraclePublicKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final provider = context.read<PredictionMarketProvider>();

    if (_isEdit) {
      final closesAt = DateTime.now().millisecondsSinceEpoch + Duration(days: _selectedDays).inMilliseconds;
      final updated = await provider.updateEvent(
        event: widget.editEvent!,
        question: _questionCtrl.text.trim(),
        oracleAddress: _oracleAddressCtrl.text.trim(),
        oraclePublicKey: _oraclePublicKeyCtrl.text.trim(),
        closesAt: closesAt,
      );
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (updated != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Marché mis à jour !")),
        );
        Navigator.pop(context, updated);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Échec : ${provider.lastError ?? 'Erreur inconnue'}")),
        );
      }
    } else {
      final duration = Duration(days: _selectedDays);
      final event = await provider.createEvent(
        question: _questionCtrl.text.trim(),
        opensFor: duration,
        oracleAddress: _oracleAddressCtrl.text.trim(),
        oraclePublicKey: _oraclePublicKeyCtrl.text.trim(),
      );
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (event != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Marché prédictif créé et publié !")),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Échec : ${provider.lastError ?? 'Erreur inconnue'}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(_isEdit ? "Modifier le Marché" : "Nouveau Marché", style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _questionCtrl,
                      style: const TextStyle(color: AppColors.text),
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: "Question du marché",
                        hintText: "ex: L'humanité marchera-t-elle sur Mars d'ici fin 2026 ?",
                        labelStyle: const TextStyle(color: AppColors.muted),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? "Requis" : null,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "Durée du marché (Clôture)",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.text),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _durations.map((days) {
                        final isSelected = _selectedDays == days;
                        return ChoiceChip(
                          label: Text("$days ${days == 1 ? 'jour' : 'jours'}"),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          onSelected: (selected) {
                            if (selected) setState(() => _selectedDays = days);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      "Oracle (Arbitrage)",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.text),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "L'oracle est la seule adresse autorisée à signer la réponse réelle (OUI ou NON) pour débloquer les gains.",
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _oracleAddressCtrl,
                      style: const TextStyle(color: AppColors.text),
                      decoration: InputDecoration(
                        labelText: "Adresse de l'Oracle (Arbitre)",
                        labelStyle: const TextStyle(color: AppColors.muted),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? "Requis" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _oraclePublicKeyCtrl,
                      style: const TextStyle(color: AppColors.text),
                      decoration: InputDecoration(
                        labelText: "Clé publique de l'Oracle (Hex)",
                        labelStyle: const TextStyle(color: AppColors.muted),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? "Requis" : null,
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _submit,
                      child: Text(_isEdit ? "Enregistrer" : "Créer le Marché", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
