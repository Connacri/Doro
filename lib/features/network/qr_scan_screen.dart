import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

/// Écran plein cadre qui scanne un QR code et fait un `Navigator.pop`
/// avec la valeur décodée (l'ID du pair) dès qu'un code valide est lu.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _controller;
  bool _handled = false;
  bool _flashOn = false;

  // Pour corriger les problèmes de rechargement à chaud (Hot Reload) sur Android.
  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _controller?.pauseCamera();
    }
    _controller?.resumeCamera();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scanner l'ID d'un pair"),
        actions: [
          IconButton(
            icon: Icon(_flashOn ? Icons.flash_off : Icons.flash_on),
            onPressed: () async {
              if (_controller != null) {
                await _controller!.toggleFlash();
                final flashStatus = await _controller!.getFlashStatus();
                if (mounted) {
                  setState(() {
                    _flashOn = flashStatus ?? false;
                  });
                }
              }
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          QRView(
            key: qrKey,
            onQRViewCreated: _onQRViewCreated,
            overlay: QrScannerOverlayShape(
              borderColor: Colors.white,
              borderRadius: 16,
              borderLength: 30,
              borderWidth: 2,
              cutOutSize: 240,
            ),
            onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
          ),
          const Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Text(
              "Cadre le QR code du pair à ajouter",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    setState(() {
      _controller = controller;
    });
    controller.scannedDataStream.listen((scanData) {
      if (_handled) return;
      final code = scanData.code;
      if (code == null || code.trim().isEmpty) return;

      _handled = true;
      Navigator.of(context).pop(code.trim());
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController ctrl, bool p) {
    if (!p) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Impossible d'accéder à la caméra.\n"
            "Vérifie les permissions dans les paramètres.",
          ),
        ),
      );
    }
  }
}