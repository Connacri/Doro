# Fix QR Scan Connection and Real-time Messaging (Revised)

The user reported issues with QR scanning and message delivery. **Auto-connection will be maintained** as it is essential for the decentralized database (DAG/Consensus).

## Proposed Changes

### P2P Core & Network

#### [peer_connection.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/core/p2p/peer_connection.dart)
- Ensure `isOpen` is accurately tracked and public.

#### [webrtc_engine.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/core/p2p/webrtc_engine.dart)
- Add `bool isChannelOpen(String peerId)` to check if the data channel is ready for sending.

### Messenger & Reliability

#### [messenger_kernel.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/core/kernels/messenger/messenger_kernel.dart)
- Implement a **Message Queue**. If `p2p.sendToPeer` fails because the channel is not yet open, the message will be stored in a queue.
- Listen to `p2p.onChannelOpen` and automatically flush the queue for that specific peer.
- This ensures no messages (including invitations) are lost during WebRTC negotiation.

### Chat & UX

#### [chat_provider.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/features/chat/chat_provider.dart)
- Add an `updateWallet(WalletProvider? wallet)` method to allow updating the reference without recreating the entire provider state.
- Ensure `addContact` handles cases where the peer is already connected but an invitation hasn't been sent.

#### [network_screen.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/features/network/network_screen.dart)
- Update `_addPeer` to call `ChatProvider.addContact`. This ensures that scanning a QR code triggers a contact invitation at the application layer, even if the P2P connection already exists.

#### [app.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/app.dart)
- Fix the `ChatProvider` instantiation in `MultiProvider` to use the `update` pattern that preserves state:
  ```dart
  update: (_, wallet, chat) => chat!..updateWallet(wallet),
  ```

## Verification Plan

### Automated Tests
- `flutter test` to ensure core logic integrity.

### Manual Verification
1. **QR Scan & Invitation**:
    - Scan a peer's QR code.
    - Verify that the recipient IMMEDIATELY receives a "👋 Vous a ajouté comme ami" message in their chat list, even if they were already auto-connected at the network level.
2. **Reliability (Queueing)**:
    - Send a message immediately after a new peer joins (while the data channel might still be opening).
    - Verify that the message is eventually delivered once the channel is ready, instead of being dropped.
3. **State Persistence**:
    - Trigger a wallet update and verify that `ChatProvider` preserves its history and pending states.
4. **Auto-connect Verification**:
    - Verify that peers still connect automatically to ensure the decentralized DB continues to function.
