extension StringExt on String {
  bool get isEmptyOrNull => trim().isEmpty;

  String truncate(int len) {
    return length > len ? "${substring(0, len)}..." : this;
  }

  /// Parse tolérant : accepte la virgule comme séparateur décimal (usage
  /// courant en français, ex: "10,5") en plus du point. Retourne `null`
  /// au lieu de lancer une exception sur une saisie invalide — à utiliser
  /// partout où un montant est parsé depuis un champ utilisateur, pour
  /// éviter un crash sur "10,5" ou un texte non numérique.
  double? toLocaleDouble() => double.tryParse(trim().replaceAll(',', '.'));
}