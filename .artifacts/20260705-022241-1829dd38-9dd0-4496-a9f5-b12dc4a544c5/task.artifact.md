# Task: Fix QR Scan Connection and Real-time Messaging

- [x] Research existing QR scan and connection logic
- [/] Fix connection and real-time issues
	- [ ] Disable auto-connect to random peers in `P2PNode`
	- [ ] Implement message queueing in `ChatProvider` for pending connections
	- [ ] Fix `ChatProvider` recreation in `App`
	- [ ] Update `NetworkScreen` to send invitations on scan
	- [ ] Add `isChannelOpen` checks in WebRTC layer
- [ ] Verify fixes with manual testing and simulations
- [ ] Finalize walkthrough
