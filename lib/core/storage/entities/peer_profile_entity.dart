import 'package:objectbox/objectbox.dart';

/// Cache local du profil ANNONCÉ par un pair distant (nom, bio, photo).
/// Volontairement séparé de `ContactEntity` : un profil peut être reçu
/// et affiché pour N'IMPORTE QUEL pair connecté, ami ou non — comme
/// l'adresse/nodeId, c'est une information publique par nature, pas
/// réservée à la liste d'amis.
///
/// Rien ici n'est une preuve d'identité au sens fort : n'importe quel
/// pair choisit librement son nom/sa photo affichés, exactement comme un
/// pseudo Discord/Telegram. Seule l'adresse (`peerId`) est vérifiable
/// cryptographiquement (dérivée de sa clé publique) — le nom et la photo
/// sont déclaratifs.
@Entity()
class PeerProfileEntity {
  int id = 0;

  @Index()
  final String peerId;

  String displayName;
  String bio;

  /// Photo reçue, déjà redimensionnée/compressée par l'émetteur, encodée
  /// en base64. Vide si le pair n'a jamais annoncé de photo.
  String photoBase64;

  /// Horodatage annoncé par l'émetteur — sert à ignorer une annonce plus
  /// ancienne reçue en retard (ex: gossip multi-sauts) qui écraserait à
  /// tort une version plus récente déjà connue.
  int updatedAt;

  PeerProfileEntity({
    this.id = 0,
    required this.peerId,
    this.displayName = "",
    this.bio = "",
    this.photoBase64 = "",
    this.updatedAt = 0,
  });
}
