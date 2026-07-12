// lib/features/bet/create_bet_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/theme/colors.dart';
import 'bet_provider.dart';

class CreateBetScreen extends StatefulWidget {
  const CreateBetScreen({super.key});

  @override
  State<CreateBetScreen> createState() => _CreateBetScreenState();
}

class _CreateBetScreenState extends State<CreateBetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _minStakeCtrl = TextEditingController();

  final List<TextEditingController> _optionCtrls = [
    TextEditingController(text: "Oui"),
    TextEditingController(text: "Non"),
  ];

  DateTime? _stakingDeadline;
  DateTime? _votingDeadline;
  bool _isLoading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _categoryCtrl.dispose();
    _minStakeCtrl.dispose();
    for (final ctrl in _optionCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionCtrls.length >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Maximum 8 options par pari.")),
      );
      return;
    }
    setState(() {
      _optionCtrls.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Au moins 2 options sont requises.")),
      );
      return;
    }
    setState(() {
      final ctrl = _optionCtrls.removeAt(index);
      ctrl.dispose();
    });
  }

  Future<DateTime?> _pickDateTime(BuildContext context, {required DateTime initialDate, String? helpText}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(minutes: 5)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: helpText,
    );
    if (date == null) return null;
    if (!context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      helpText: helpText,
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return "Non définie";
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_stakingDeadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez choisir la deadline de mise.")),
      );
      return;
    }
    if (_votingDeadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez choisir la deadline de vote.")),
      );
      return;
    }
    if (!_votingDeadline!.isAfter(_stakingDeadline!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La deadline de vote doit être après la deadline de mise.")),
      );
      return;
    }

    final options = _optionCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Au moins 2 options non vides sont requises.")),
      );
      return;
    }

    final minStakeDoro = double.tryParse(_minStakeCtrl.text.trim());
    if (minStakeDoro == null || minStakeDoro <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mise minimale invalide.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    final provider = context.read<BetProvider>();
    final minStake = BigInt.from(minStakeDoro * 1e18);

    final bet = await provider.createBet(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: _categoryCtrl.text.trim().isEmpty ? "Général" : _categoryCtrl.text.trim(),
      optionLabels: options,
      stakingDeadline: _stakingDeadline!,
      votingDeadline: _votingDeadline!,
      minStake: minStake,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (bet != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pari créé et publié sur le réseau !")),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur de création : ${provider.lastError ?? 'Échec'}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text("Créer un Pari", style: TextStyle(fontWeight: FontWeight.bold)),
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
                      controller: _titleCtrl,
                      style: const TextStyle(color: AppColors.text),
                      decoration: InputDecoration(
                        labelText: "Titre du pari",
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
                      controller: _descCtrl,
                      style: const TextStyle(color: AppColors.text),
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: "Description / Détails",
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
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _categoryCtrl,
                            style: const TextStyle(color: AppColors.text),
                            decoration: InputDecoration(
                              labelText: "Catégorie",
                              hintText: "ex: Sport, Tech",
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
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _minStakeCtrl,
                            style: const TextStyle(color: AppColors.text),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: "Mise min (DORO)",
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
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return "Requis";
                              final d = double.tryParse(val);
                              if (d == null || d <= 0) return "Supérieur à 0";
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "Option de réponses",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.text),
                    ),
                    const SizedBox(height: 8),
                    ..._optionCtrls.asMap().entries.map((entry) {
                      final i = entry.key;
                      final ctrl = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: ctrl,
                                style: const TextStyle(color: AppColors.text),
                                decoration: InputDecoration(
                                  labelText: "Option ${i + 1}",
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
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error),
                              onPressed: () => _removeOption(i),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: _addOption,
                      icon: const Icon(Icons.add, color: AppColors.primary),
                      label: const Text("Ajouter une option", style: TextStyle(color: AppColors.primary)),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "Deadlines (Dates limites)",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.text),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      tileColor: AppColors.surface,
                      title: const Text("Fin des mises (Staking Deadline)", style: TextStyle(fontSize: 14, color: AppColors.muted)),
                      subtitle: Text(
                        _formatDateTime(_stakingDeadline),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.text),
                      ),
                      trailing: const Icon(Icons.calendar_month, color: AppColors.primary),
                      onTap: () async {
                        final dt = await _pickDateTime(context, initialDate: DateTime.now().add(const Duration(hours: 1)), helpText: "Fin des mises");
                        if (dt != null) {
                          setState(() => _stakingDeadline = dt);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      tileColor: AppColors.surface,
                      title: const Text("Fin des votes (Voting Deadline)", style: TextStyle(fontSize: 14, color: AppColors.muted)),
                      subtitle: Text(
                        _formatDateTime(_votingDeadline),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.text),
                      ),
                      trailing: const Icon(Icons.calendar_month, color: AppColors.primary),
                      onTap: () async {
                        final start = _stakingDeadline ?? DateTime.now();
                        final dt = await _pickDateTime(context, initialDate: start.add(const Duration(hours: 1)), helpText: "Fin des votes");
                        if (dt != null) {
                          setState(() => _votingDeadline = dt);
                        }
                      },
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _submit,
                      child: const Text("Publier le Pari", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
