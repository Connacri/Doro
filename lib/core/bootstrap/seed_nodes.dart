class SeedNodes {
  /// Liste ordonnée de serveurs de signaling. SignalingClient bascule
  /// automatiquement sur l'entrée suivante si la connexion échoue.
  ///
  /// Déploiement gratuit possible sur :
  ///   - Render.com  (render.yaml fourni)
  ///   - Railway.app (railway.json)
  ///   - Google Cloud Run (Dockerfile dans signaling_server/)
  ///   - Fly.io
  ///   - Koyeb
  static const List<String> nodes = [
    "wss://volte-dhyr.onrender.com",
    "wss://doro-1.onrender.com",
    "wss://doro-2.onrender.com",
    "wss://doro-3.onrender.com",
  ];

  static List<String> getAll() => nodes;
}
