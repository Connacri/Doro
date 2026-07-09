# Doro — Migration Messenger P2P → Supabase

## Ce qui a déjà été fait (via MCP, en live sur ton projet Supabase)

- **Projet Supabase** : `Doro's Project` — ref `rwzsnlfuqmfxouhfbeoi` (eu-west-1).
- **Migration appliquée** : `supabase/migrations/0001_doro_messenger_schema.sql`
  → tables `profiles`, `friend_requests`, `friendships`, `messages`, RLS complète, trigger d'acceptation d'ami, publication Realtime.
- **Edge function déployée** : `bind-identity` (v1, `verify_jwt=true`)
  → seul point de contact avec `service_role`, jamais exposé au client.

Rien de tout ça n'a touché ton dépôt GitHub — les fichiers ci-dessous sont à committer toi-même.

## Où va chaque secret

| Secret | Où il vit | Pourquoi |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Dans l'app Flutter (`--dart-define` ou fichier de config committé) | Ce sont des clés **publiques par design**, protégées par RLS, pas par le secret |
| `SUPABASE_SERVICE_ROLE_KEY` | **Nulle part dans ton repo.** Injectée automatiquement par Supabase dans le runtime des edge functions | Bypass RLS = accès admin total. Ne doit jamais atteindre un client (app, CI, artefact buildé) |
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_REF` | Secrets GitHub Actions (`Settings > Secrets and variables > Actions`) | Permettent à la CLI Supabase de déployer migrations/functions en CI — droits différents de service_role, révocables indépendamment |

## Câblage Flutter restant à faire

1. **pubspec.yaml** — ajouter :
   ```yaml
   dependencies:
     supabase_flutter: ^2.8.0
   ```
   Tu peux garder `flutter_webrtc` si le P2P sert encore ailleurs (gossip DAG, sync wallet) — seul le messenger en dépendait ici.

2. **Bootstrap** (là où `WebRTCNetworkEngine` et `MessengerKernel` sont actuellement instanciés, probablement `lib/core/bootstrap/`) :
   ```dart
   await Supabase.initialize(
     url: const String.fromEnvironment('SUPABASE_URL'),
     anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
   );

   final identity = SupabaseIdentityService(Supabase.instance.client, CryptoService());
   await identity.ensureBound(
     address: wallet.address,          // "0x<pubkeyHex>"
     publicKeyHex: wallet.publicKey,
   );

   final messenger = SupabaseMessengerKernel(
     nodeId: wallet.publicKey,
     supabase: Supabase.instance.client,
     db: objectBoxStore,
   );
   ```

3. **`ChatProvider`** (`lib/features/chat/chat_provider.dart`) : il consomme aujourd'hui `P2PNode node`. Remplace le type par `SupabaseMessengerKernel` (l'API `messages`/`friendEvents`/`sendPrivateChat`/etc. est volontairement identique). Les deux seuls appels à adapter :
   - `node.sendToPeer(...)` direct (s'il y en a en dehors du kernel) → passer par `messenger.sendPrivateChat(...)`.
   - Ajoute un appel à `messenger.syncHistoryWith(peerId)` à l'ouverture d'un chat (`chat_screen.dart`) pour rattraper l'historique serveur.

4. **`amis_screen.dart`** : aucune logique à changer si tu passais déjà par `MessengerKernel.sendFriendRequest/accept/decline/cancel` — l'implémentation change, pas la surface.

5. Supprimer `FriendRequestStore` (SharedPreferences) — les demandes vivent maintenant côté serveur dans `friend_requests`, avec Realtime, donc plus besoin de ce stockage local transitoire.

## Fichiers de ce zip

```
lib/core/supabase/supabase_identity_service.dart      # session anonyme + liaison pubkey
lib/core/supabase/profile_service.dart                 # CRUD avatar/cover + suppression de compte
lib/core/supabase/presence_service.dart                 # en ligne/hors ligne + "en train d'écrire"
lib/core/kernels/messenger/supabase_messenger_kernel.dart  # remplace MessengerKernel
lib/features/chat/widgets/chat_animations.dart          # bulles animées, coches, typing indicator
supabase/migrations/0001_doro_messenger_schema.sql      # schéma messenger + RLS (déjà appliqué)
supabase/migrations/0002_profile_media_deletion_chat_features.sql  # avatar/cover/suppression/unsend (déjà appliqué)
supabase/functions/bind-identity/index.ts                # edge function (déjà déployée)
.github/workflows/deploy-supabase.yml                     # CI migrations + functions
```

## Profil : avatar, photo de couverture (façon Facebook)

- Deux buckets Storage privés : `avatars` et `covers`, chemin `<public_key>/avatar.jpg` / `<public_key>/cover.jpg`.
- RLS storage : tout le monde authentifié peut **voir** (comme un réseau social), mais seul le propriétaire (`(storage.foldername(name))[1] = current_pubkey()`) peut écrire/modifier/supprimer son propre dossier.
- `ProfileService` fait le CRUD complet : `uploadAvatar`/`deleteAvatar`, `uploadCover`/`deleteCover`, `updateDisplayName`. Les URLs sont signées (7 jours) car les buckets sont privés — pas d'URL publique permanente qui traînerait dans des caches/logs.

## Suppression de compte façon Facebook (30 jours de grâce)

1. `ProfileService.requestAccountDeletion()` → appelle le RPC `request_account_deletion`, programme `deleted_at = now() + 30 jours`. Affiche côté UI : *"Ton compte sera supprimé le {date}. Reconnecte-toi avant cette date pour annuler."*
2. À chaque login, `ProfileService.deletionStatus()` renvoie l'état — si `isPendingDeletion`, affiche le bandeau de rappel + bouton "Annuler la suppression" → `cancelAccountDeletion()`.
3. Chaque nuit à 03h00 UTC, un **job `pg_cron`** (`doro-purge-deleted-accounts`, déjà actif sur ton projet) appelle `purge_deleted_accounts()` qui, pour chaque compte dont la date est passée :
   - supprime les fichiers dans les buckets `avatars`/`covers` pour ce `public_key` ;
   - supprime la ligne `auth.users` correspondante, ce qui cascade automatiquement (FK `on delete cascade`) sur `profiles`, `messages`, `friend_requests`, `friendships`, `message_deletions`.
   
   Tout ça tourne en SQL pur côté serveur (pg_cron + `security definer`) — **pas d'edge function ni de secret supplémentaire nécessaires** pour cette partie.

## Chat : online/offline, accusés de lecture, historique, unsend

- **Présence en ligne/hors-ligne + "en train d'écrire"** : `PresenceService`, basé sur Supabase Realtime Presence/Broadcast — aucun schéma DB requis, c'est éphémère. Branche `OnlineDot` sur `presenceService.isOnline(peerPubkey)` et `TypingIndicator` sur `presenceService.typingEvents`.
- **Accusés "délivré"/"lu"** : déjà dans `SupabaseMessengerKernel` (colonnes `status`/`delivered_at`/`read_at`), affichés avec `MessageStatusTicks` (transition animée grise → bleue, comme WhatsApp).
- **Vider une conversation ("pour moi" uniquement, comme WhatsApp)** : `SupabaseMessengerKernel.clearConversationForMeOnServer(peerKey)` → RPC `clear_conversation_for_me`, enregistre des lignes dans `message_deletions` (par utilisateur) sans toucher aux messages de l'autre pair, et vide le cache local.
- **Annuler l'envoi d'un message ("unsend", comme WhatsApp/Telegram)** : `SupabaseMessengerKernel.unsendMessage(messageId)` → RPC `delete_message_for_everyone`, fenêtre de 2h après l'envoi (modifiable dans la migration), vide le `body` côté serveur et diffuse en Realtime — l'autre pair voit `DeletedMessageBubble` ("Message supprimé") au lieu du texte.
- **Lecture des conversations** : `syncHistoryWith` lit maintenant la vue `visible_messages` (respecte à la fois l'unsend et le "supprimer pour moi"), donc l'historique rechargé après une coupure réseau reste cohérent avec ce que l'utilisateur a supprimé localement.
- **Animations** : `chat_animations.dart` fournit `AnimatedMessageBubble` (entrée slide+fade des nouveaux messages), `MessageStatusTicks` (coches animées), `TypingIndicator` (3 points façon Messenger), `OnlineDot` (pastille verte avec fondu).



## Sécurité — pourquoi ce design tient la route

- Un attaquant qui extrait l'APK récupère `anon key` + `url` : c'est prévu, RLS empêche tout accès hors des règles ci-dessus (lire/écrire ses propres messages, être ami avant d'envoyer, etc.).
- Usurper une pubkey est impossible sans la clé privée Ed25519 correspondante (challenge signé, vérifié côté serveur avec `crypto.subtle.verify`, fenêtre de rejeu de 5 min).
- `messages_insert_if_friends` empêche d'envoyer un message à quelqu'un qui n'a pas accepté la demande — impossible à contourner depuis le client, c'est en base.
- Le contenu de `body` n'est **pas chiffré end-to-end** dans cette version (contrairement au P2P où seuls les deux pairs voyaient le message) : Supabase (toi, l'opérateur) peut le lire en base. Si tu veux conserver le end-to-end que le P2P donnait gratuitement, il faut chiffrer `body` côté client avant insert (ex. X25519 dérivé de vos clés Ed25519 + XChaCha20-Poly1305) — dis-moi si tu veux que je l'ajoute, c'est un chantier à part.
