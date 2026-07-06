class SeedNodes {
  /// Liste ordonnée de serveurs de signaling. SignalingClient bascule
  /// automatiquement sur l'entrée suivante si la connexion échoue.
  static const List<String> nodes = [
    "wss://volte-dhyr.onrender.com",
    "wss://doro-1.onrender.com",
  ];

  static List<String> getAll() => nodes;
}
