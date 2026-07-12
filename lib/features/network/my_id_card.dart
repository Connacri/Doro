import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import '../../shared/theme/colors.dart';

/// Carte affichant l'ID du node local en QR code + en texte copiable.
/// C'est ce que l'autre personne scanne (ou que je lui envoie par un
/// autre canal) pour m'ajouter comme pair.
class MyIdCard extends StatelessWidget {
  final String myId;
  final String title;

  const MyIdCard({super.key, required this.myId, this.title = "Mon ID (à partager)"});

  void _copyId(BuildContext context) {
    Clipboard.setData(ClipboardData(text: myId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("ID copié dans le presse-papiers")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: PrettyQrView.data(
                data: myId,
                errorCorrectLevel: QrErrorCorrectLevel.H,
                decoration: const PrettyQrDecoration(
                  shape: PrettyQrSmoothSymbol(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  myId,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.black54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy, size: 20, color: Colors.black54),
                tooltip: "Copier mon ID",
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _copyId(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}