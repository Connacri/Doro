# Fix QR Scan Connection and Real-time Messaging

The user reported three main issues when scanning QR codes:
1. The recipient receives nothing.
2. The connection sometimes goes to the "wrong user".
3. Messages are not real-time (or lost).

## Proposed Changes

### P2P Core & Network

#### [p2p_node.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/core/p2p/p2p_node.dart)
- Disable auto-connection to every peer in the `peer_list` broadcast by the signaling server. This prevents connecting to random users and ensures privacy.
- Add `isChannelOpen(String peerId)` helper.

#### [webrtc_engine.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/core/p2p/webrtc_engine.dart)
- Add `isChannelOpen(String peerId)` to check if the data channel is actually ready for sending data.

#### [peer_connection.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/core/p2p/peer_connection.dart)
- Ensure `isOpen` is accurately tracked.

### Chat & UX

#### [chat_provider.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/features/chat/chat_provider.dart)
- Implement a message queue for "pending messages". If a user sends a message while the connection is still being established (e.g., right after scanning), the message will be queued and sent automatically as soon as the channel opens.
- Add an `updateWallet` method to allow updating the `WalletProvider` reference without recreating the entire `ChatProvider` state.
- Improve `addContact` to provide better feedback if the signaling server is unreachable.

#### [network_screen.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/features/network/network_screen.dart)
- Update `_addPeer` to call `ChatProvider.addContact`. This ensures that scanning a QR code not only connects the peer but also sends a contact invitation, so the recipient sees a new chat/notification.

#### [app.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/app.dart)
- Fix the `ChatProvider` instantiation in `MultiProvider` to use the `update` pattern that preserves state instead of recreating the provider on every wallet update.

## Verification Plan

### Automated Tests
- I will run existing tests if available, but since this is mostly P2P and UI logic, manual verification is preferred.
- `flutter test` to ensure no regressions in core logic.

### Manual Verification
1. **QR Scan & Invitation**:
    - Scan a peer's QR code.
    - Verify that the sender sees "Demande de connexion envoyée".
    - Verify that the recipient IMMEDIATELY receives a "Vous a ajouté comme ami" message in their chat list.
2. **Privacy / No Auto-connect**:
    - Connect two instances to the same signaling server.
    - Verify that they do NOT connect to each other automatically unless one scans the other.
3. **Real-time Messaging**:
    - Send a message immediately after scanning (while connection is negotiating).
    - Verify that the message is queued and delivered as soon as the channel is open, instead of being dropped.
4. **State Persistence**:
    - Trigger a wallet update (e.g., by changing accounts or receiving a tx) and verify that the chat history and pending invitations are NOT wiped in `ChatProvider`.
