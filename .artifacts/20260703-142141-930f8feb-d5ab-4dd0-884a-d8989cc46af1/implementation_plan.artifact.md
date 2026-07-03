# Implementation Plan - Fix Widget Test and Verify NodeIdentity

The goal is to resolve the failing `widget_test.dart` and ensure the new `NodeIdentity` utility is correctly tested.

## Proposed Changes

### Storage Layer
Handle the absence of native ObjectBox libraries in test environments.

#### [store.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/core/storage/objectbox/store.dart)
- Make `_store` nullable.
- Update `init()` to handle potential failures or skip in tests (already handled by nullable state).
- Ensure `close()` is null-safe.

#### [wallet_repository.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/core/storage/repositories/wallet_repository.dart)
- Make `Box` acquisition lazy to avoid early dependency on an initialized `Store`.

---

### Tests
Update existing tests and add new ones for verified functionality.

#### [widget_test.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/test/widget_test.dart)
- Remove `db.init()` call which fails on host machines without native libraries.
- Clean up unused temporary directory logic.

#### [NEW] [node_identity_test.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/test/node_identity_test.dart)
- Implement tests for `NodeIdentity` using `MethodChannel` mocking for `FlutterSecureStorage`.
- Verify persistence and consistency of generated IDs.

## Verification Plan

### Automated Tests
- Run `flutter test` to ensure all tests (including the fixed and new ones) pass.
- Specific command: `flutter test`

### Manual Verification
- None required as automated tests cover the rendering and logic paths.
