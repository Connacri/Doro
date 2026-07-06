import 'package:objectbox/objectbox.dart';

/// Mon propre profil, une seule ligne (id fixe = 1). Séparé de
/// `WalletEntity`/`ContactEntity` : le profil est une identité sociale
/// (nom, bio, photo), pas un compte financier ni un simple contact.
///
/// `photoPath` pointe vers un fichier LOCAL (répertoire documents de
/// l'app) — jamais uploadée sur un serveur, jamais dans le stockage
/// ObjectBox lui-même (éviter de gonfler la base avec des blobs binaires).
/// Ce qui est diffusé aux autres pairs, c'est une version redimensionnée
/// et compressée en base64 (voir `ProfileKernel`), gardée volontairement
/// petite pour ne pas servir de vecteur de spam réseau.
@Entity()
class ProfileEntity {
  int id = 0;

  String displayName;
  String bio;

  /// Chemin absolu vers le fichier photo local, ou vide si aucune photo.
  String photoPath;

  /// Horodatage de la dernière modification — inclus dans chaque diffusion
  /// réseau pour que les pairs ignorent une version de profil plus
  /// ancienne que celle qu'ils connaissent déjà (évite qu'un vieux message
  /// rejoué écrase un profil à jour).
  int updatedAt;

  ProfileEntity({
    this.id = 0,
    this.displayName = "",
    this.bio = "",
    this.photoPath = "",
    this.updatedAt = 0,
  });
}
