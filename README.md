<p align="center">
  <img src="https://img.shields.io/github/v/release/Connacri/Volte?style=for-the-badge&label=Version&color=6C5CE7" alt="Version">
  <img src="https://img.shields.io/github/actions/workflow/status/Connacri/Volte/volte-ci.yml?style=for-the-badge&label=CI&color=00D084" alt="CI">
  <img src="https://img.shields.io/badge/Flutter-3.44+-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License">
</p>

<h1 align="center">⚡ Volte</h1>
<p align="center"><strong>Réseau décentralisé P2P — Communications, portefeuille et registre distribué.</strong></p>

<p align="center">
  Volte est un réseau peer-to-peer 100&nbsp;% décentralisé : aucun serveur central ne détient vos
  données, vos fonds ou vos messages. Chiffrement Ed25519, consensus BFT, gossip protocol,
  registre DAG et messagerie instantanée — le tout connecté directement entre appareils via WebRTC.
</p>

<p align="center">
  <a href="#-fonctionnalités">Fonctionnalités</a> •
  <a href="#-téléchargement">Téléchargement</a> •
  <a href="#-tutoriel-dutilisation">Tutoriel</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#-build-local">Build</a>
</p>

---

## ✨ Fonctionnalités

| Module | Description |
|--------|-------------|
| 🌐 **P2P** | Connexion directe entre pairs via WebRTC, avec serveur de signalisation pour l'établissement initial |
| 🆔 **Identité persistante** | Un ID stable par appareil (généré une seule fois, jamais régénéré) — partageable par QR code ou copie |
| 📷 **Ajout de pairs** | Scan de QR code ou collage d'ID pour ajouter un contact, sans annuaire central |
| 🔐 **Chiffrement** | Signatures Ed25519 (cryptographie réelle, pas de placeholder) |
| 🗣️ **Gossip** | Protocole de diffusion avec déduplication et contrôle TTL |
| 📋 **DAG Ledger** | Registre distribué en DAG avec détection de double-dépense |
| ✅ **Consensus** | BFT avec vote pondéré et score de réputation |
| 💰 **Wallet** | Portefeuille natif (NovaCoin) — le solde de départ n'existe que sur *votre* appareil, jamais dupliqué chez vos pairs |
| 💬 **Chat** | Messagerie instantanée P2P, diffusée directement à vos pairs connectés |
| 🔄 **Sync** | Synchronisation d'état avec horloge vectorielle |

> **Sur le solde des wallets** : chaque wallet démarre à zéro. Le seul solde de départ est celui
> que *vous* recevez localement à la création de *votre* wallet. Le solde d'un pair n'augmente
> jamais automatiquement — uniquement lorsqu'une transaction lui est réellement envoyée et reçue
> via le réseau.

## 📸 Aperçu

<p align="center">
  <img src="assets/screenshots/wallet.png" width="200" alt="Wallet">
  <img src="assets/screenshots/network.png" width="200" alt="Réseau — Mon ID">
  <img src="assets/screenshots/chat.png" width="200" alt="Chat">
  <img src="assets/screenshots/ledger.png" width="200" alt="Ledger">
</p>

<p align="center"><sub>Placez vos captures d'écran dans <code>docs/screenshots/</code> pour qu'elles s'affichent ici.</sub></p>

## 🚀 Téléchargement

<table>
  <tr>
    <td align="center">
      <a href="https://github.com/Connacri/Volte/releases/latest">
        <img src="https://img.shields.io/badge/Android-APK-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android APK"><br>
        <strong>volte-android-universal.apk</strong>
      </a>
    </td>
    <td align="center">
      <a href="https://github.com/Connacri/Volte/releases/latest">
        <img src="https://img.shields.io/badge/Windows-Portable-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows"><br>
        <strong>volte-windows.zip</strong>
      </a>
    </td>
  </tr>
</table>

> Les builds sont générés automatiquement par GitHub Actions à chaque push sur `main`.

---

## 📖 Tutoriel d'utilisation

Pour tester Volte dans de bonnes conditions, utilisez **deux instances de l'application**
(deux téléphones, ou un téléphone et un PC/émulateur). Tout se passe en 5 étapes.

### 1. Premier lancement

À l'ouverture, l'app génère automatiquement votre **identité de node** — un identifiant unique et
**stable** (il ne change plus au redémarrage). Cet ID est la seule chose dont vos amis ont besoin
pour vous ajouter.

### 2. Se connecter au réseau

- Ouvrez l'onglet **Réseau** 🛜.
- Le badge en haut passe au vert dès que vous êtes connecté au serveur de signalisation
  (nécessaire uniquement pour la mise en relation initiale — les échanges eux-mêmes restent
  toujours en direct entre appareils via WebRTC).

### 3. Ajouter un pair — QR code ou ID

Dans l'onglet **Réseau**, deux façons de mettre deux appareils en relation :

| Méthode | Comment faire |
|---------|----------------|
| 📷 **Scanner un QR** | Appuyez sur *"Scanner un QR"*, autorisez la caméra, et cadrez le QR code affiché sur l'écran **Réseau** de votre ami (carte *"Mon ID"*) |
| 📋 **Coller l'ID** | Votre ami vous envoie son ID par un autre canal (SMS, autre messagerie…) ; collez-le dans le champ *"Coller l'ID du pair"* puis appuyez sur *"Ajouter"* |

Dans les deux cas, vous pouvez aussi partager **votre propre ID** de la même façon : la carte
*"Mon ID"* affiche votre QR code personnel et un bouton pour le copier directement.

Une fois la connexion établie, le pair apparaît dans la liste *"Pairs connectés"*, avec un accès
direct au chat en un tap.

### 4. Créer un wallet et envoyer des fonds

- Ouvrez l'onglet **Wallet** 💰.
- Appuyez sur **"Créer un wallet"** — une adresse unique est générée, et *votre* solde de départ
  est crédité **uniquement sur votre appareil**.
- Pour envoyer des fonds : récupérez l'adresse de votre ami (visible dans son propre onglet
  Wallet), collez-la dans **"Recipient address"**, indiquez le montant, puis **"Send"**.
- La transaction est diffusée sur le réseau P2P. Le solde du destinataire n'augmente que lorsque
  la transaction lui parvient réellement — pas avant, pas ailleurs.

### 5. Chat et registre

- Onglet **Chat** 💬 : dès qu'un pair est connecté (bandeau vert), tapez et envoyez — les messages
  sont diffusés en direct via WebRTC, sans passer par un serveur.
- Onglet **Ledger** 📋 : historique complet de toutes les transactions vues par votre node,
  classées par ordre d'arrivée dans le DAG.

---

## 🔐 Sauvegarde et récupération des wallets

### Principe

Chaque wallet Volte est protégé par une **seed** (clé privée) Ed25519 de **64 caractères hexadécimaux**.
C'est la seule et unique clé qui permet de dépenser les fonds de ce wallet et de le restaurer
sur un autre appareil. Pas de mot de passe, pas de serveur central — **qui possède la seed possède
le wallet**.

### Sauvegarder sa seed (à faire immédiatement après la création)

1. Ouvrez l'onglet **Wallet** 💰.
2. Appuyez sur **"Créer un wallet"**.
3. Une boîte de dialogue s'affiche immédiatement avec votre **seed hex**.
4. **Avant de fermer la boîte** :
   - ✅ **Notez la seed sur un papier** — 64 caractères, à copier sans erreur.
   - ✅ **Conservez ce papier dans un endroit sûr** (coffre, tiroir fermé à clé).
   - ✅ (Optionnel) **Gravez-la sur un support métallique** pour une protection contre le feu /
     l'eau.
5. Vous pouvez aussi utiliser le bouton **"Copier la seed"** pour la coller dans un gestionnaire
   de mots de passe chiffré (KeePass, Bitwarden, etc.).
6. Confirmez en appuyant sur **"J'ai sauvegardé ma seed"**.

> ⚠️ **La seed n'est affichée qu'une seule fois**, juste après la création du wallet. Volte ne
> la stocke que dans le Keystore sécurisé de votre appareil (Android Keystore / iOS Keychain) —
> elle n'est ni envoyée sur un serveur, ni stockée en clair dans les préférences. Si vous la
> perdez, personne ne pourra jamais récupérer vos fonds.

### Règles de sécurité

| Règle | Pourquoi |
|-------|----------|
| ❌ **Ne partage JAMAIS ta seed** | Quiconque a la seed peut dépenser TOUS les fonds du wallet |
| ❌ **Ne la stocke pas dans le cloud** (Google Drive, iCloud, Dropbox) | Un compte compromis = fonds volés |
| ❌ **Ne fais pas de capture d'écran** | Les screenshots peuvent être lus par des malwares ou synchronisés |
| ✅ **Note-la sur un papier en deux exemplaires** | Lieux différents = sécurité maximale |
| ✅ **Stocke-la dans un gestionnaire de mots de passe chiffré** | Bitwarden, KeePass, 1Password — jamais dans le presse-papiers longtemps |
| ✅ **Vérifie que tu as bien recopié les 64 caractères** | Une seule erreur de copie rend la récupération impossible |

### Récupérer ses fonds sur un nouvel appareil

Si vous perdez votre téléphone ou PC, ou si vous voulez accéder à vos fonds depuis un autre
appareil :

1. **Installez Volte** sur le nouvel appareil.
2. Ouvrez l'onglet **Wallet** 💰.
3. Appuyez sur l'icône **🔑 (clé)** dans la barre d'action.
4. Collez votre **seed hex** (64 caractères) dans le champ.
   > La chaîne doit ressembler à : `a1b2c3d4e5f67890a1b2c3d4e5f67890a1b2c3d4e5f67890a1b2c3d4e5f67890`
5. Appuyez sur **"Importer"**.
6. Si la seed est valide, votre wallet apparaît immédiatement avec :
   - Son **solde** (celui qui était sur votre ancien appareil).
   - Son **nonce** (le compteur de transactions, pour continuer à envoyer des fonds).

> 🔄 Le solde est un montant **local et personnel** — il ne se "télécharge" pas depuis un
> serveur bloqué. Les transactions que vous aviez reçues sont stockées dans votre DAG local.
> Quand vous vous reconnectez au réseau P2P, vos nouveaux pairs vous synchronisent les
> transactions manquantes, et votre solde s'actualise automatiquement.

### Cas du wallet fondateur

Le wallet fondateur (adresse `0x05ef5fa9991402ede9e8339d715469276c908b7d`) est le seul wallet
qui possède un solde de départ non nul (l'allocation génésis de **21 millions NOVA**). Il suit
exactement le même processus de sauvegarde et de récupération que n'importe quel autre wallet :
- Importez la seed hex correspondante via l'icône 🔑.
- Le solde de départ est automatiquement crédité si l'adresse dérivée correspond à l'adresse
  fondatrice et que le solde est encore à zéro.

---

## 📐 Architecture

```
┌──────────────────────────────────────────────┐
│                   Volte App                    │
├──────────────────────────────────────────────┤
│  ┌─────────┐  ┌──────┐  ┌────────┐  ┌─────┐  │
│  │ Wallet  │  │ Chat │  │ Ledger │  │Network│  │
│  └────┬────┘  └──┬───┘  └───┬────┘  └──┬───┘  │
│       └──────────┼──────────┼──────────┘       │
│                  ▼          ▼                   │
│  ┌──────────────────────────────────────────┐  │
│  │              P2PNode                       │  │
│  │  ┌────────┐ ┌──────┐ ┌─────┐ ┌────────┐  │  │
│  │  │Crypto  │ │Gossip│ │ DAG │ │Consensus│  │  │
│  │  │Ed25519 │ │Engine│ │Engine│ │  BFT    │  │  │
│  │  └────────┘ └──────┘ └─────┘ └────────┘  │  │
│  │  ┌────────┐ ┌──────────┐ ┌─────────────┐  │  │
│  │  │WebRTC  │ │  Signal  │ │  SyncEngine  │  │  │
│  │  │ Engine │ │  Client  │ │ (VectorClock)│  │  │
│  │  └────────┘ └──────────┘ └─────────────┘  │  │
│  │  ┌────────────────────────────────────┐    │  │
│  │  │  NodeIdentity (ID persistant local) │    │  │
│  │  └────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

## 🛠️ Build local

```bash
# Prérequis
flutter --version  # 3.44.0+

# Dépendances
flutter pub get

# Lancement en dev
flutter run

# Build signé
flutter build apk --release --build-name=1.0.0 --build-number=1
```

### Serveur de signalisation

```bash
cd signaling_server
npm install
node server.js   # ws://localhost:8080
```

### Permissions requises

| Permission | Usage |
|------------|-------|
| `INTERNET` / `ACCESS_NETWORK_STATE` | Connexion au serveur de signalisation et aux pairs WebRTC |
| `CAMERA` | Scan du QR code d'un pair (optionnelle : `android:required="false"`) |

## 🤖 CI / CD

| Étape | Description |
|-------|-------------|
| `version` | Calcule la version depuis le dernier tag git (incrémente le patch) |
| `quality` | `flutter analyze` + `flutter test` |
| `build-android` | APK (arm64 + universal) + AAB signés |
| `build-windows` | ZIP portable |
| `publish` | Crée le tag git + GitHub Release avec tous les artefacts |

Pour signer les APK en release, ajoutez ces secrets GitHub :

| Secret | Description |
|--------|-------------|
| `ANDROID_KEYSTORE_BASE64` | Keystore encodé en base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Mot de passe du keystore |
| `ANDROID_KEY_PASSWORD` | Mot de passe de la clé |
| `ANDROID_KEY_ALIAS` | Alias de la clé |

> **Sans ces secrets**, le build utilisera la signature de debug (les artefacts ne seront pas
> substituables d'un run à l'autre).

## 🧩 Stack technique

<p align="left">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/WebRTC-333333?style=flat-square&logo=webrtc&logoColor=white" alt="WebRTC">
  <img src="https://img.shields.io/badge/Ed25519-6C5CE7?style=flat-square" alt="Ed25519">
  <img src="https://img.shields.io/badge/Provider-02569B?style=flat-square" alt="Provider">
</p>

## 🗺️ Roadmap

- [ ] Identité cryptographique persistante (clé Ed25519 stockée via `flutter_secure_storage`)
- [ ] Signature effective des transactions
- [ ] Découverte de pairs sans serveur de signalisation (mDNS / bootstrap DHT)
- [ ] Historique de chat persistant hors ligne
- [ ] Support iOS

## 🤝 Contribuer

Les issues et pull requests sont les bienvenues. Avant de proposer un changement important,
ouvrez une issue pour en discuter.

## 📄 License

Distribué sous licence MIT. Voir [LICENSE](LICENSE) pour plus d'informations.

---

<p align="center">
  <sub>Built with ❤️ using Flutter, WebRTC, Ed25519 & DAG Consensus</sub>
</p>
