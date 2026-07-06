import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: myId,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    myId,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: "Copier mon ID",
                  onPressed: () => _copyId(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}