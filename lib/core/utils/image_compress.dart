// lib/core/utils/image_compress.dart
//
// Redimensionne + recompresse une image avant upload vers Supabase
// Storage — évite d'envoyer des photos brutes de plusieurs Mo (coût
// mémoire, bande passante, quota de stockage). Tourne dans un isolate
// séparé (`compute`) pour ne pas geler l'UI le temps du décodage/
// réencodage, qui peut prendre plusieurs centaines de ms sur une
// grosse photo.
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageCompressSpec {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;
  const ImageCompressSpec({required this.bytes, required this.maxDimension, required this.quality});
}

class ImageCompressor {
  /// Photo de profil : carrée-ish, petite (l'affichage ne dépasse
  /// jamais quelques centaines de pixels même en plein écran).
  static const int avatarMaxDimension = 512;
  static const int avatarQuality = 82;

  /// Bannière de couverture : plus large (façon Facebook), mais reste
  /// raisonnable — inutile de stocker en 4K une image affichée sur
  /// une largeur d'écran mobile/desktop.
  static const int coverMaxDimension = 1280;
  static const int coverQuality = 80;

  static Future<Uint8List> compressAvatar(Uint8List bytes) => compute(
        _compress,
        ImageCompressSpec(bytes: bytes, maxDimension: avatarMaxDimension, quality: avatarQuality),
      );

  static Future<Uint8List> compressCover(Uint8List bytes) => compute(
        _compress,
        ImageCompressSpec(bytes: bytes, maxDimension: coverMaxDimension, quality: coverQuality),
      );

  /// Fonction top-level (requis par `compute`) : décode l'image
  /// (n'importe quel format supporté par `package:image` — JPEG, PNG,
  /// WebP, HEIC selon plateforme...), la redimensionne si elle dépasse
  /// [ImageCompressSpec.maxDimension] sur son plus grand côté (ratio
  /// conservé), corrige l'orientation EXIF, puis réencode en JPEG à
  /// [ImageCompressSpec.quality]. Renvoie les octets d'origine si le
  /// décodage échoue (format non reconnu) plutôt que de faire planter
  /// l'upload.
  static Uint8List _compress(ImageCompressSpec spec) {
    final decoded = img.decodeImage(spec.bytes);
    if (decoded == null) return spec.bytes;

    // `bakeOrientation` applique la rotation EXIF puis la retire — sans
    // ça, une photo prise en portrait sur mobile peut s'afficher
    // couchée une fois le tag EXIF ignoré par un lecteur tiers.
    final oriented = img.bakeOrientation(decoded);

    img.Image resized = oriented;
    final longestSide = oriented.width > oriented.height ? oriented.width : oriented.height;
    if (longestSide > spec.maxDimension) {
      resized = oriented.width >= oriented.height
          ? img.copyResize(oriented, width: spec.maxDimension)
          : img.copyResize(oriented, height: spec.maxDimension);
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: spec.quality));
  }
}
