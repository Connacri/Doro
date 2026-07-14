# Fix RenderFlex Overflow in boot_terminal_screen.dart

The goal is to fix a layout overflow error (0.299 pixels) in the terminal title bar of the boot screen.

## Proposed Changes

### [Boot Feature]

#### [boot_terminal_screen.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro1/lib/features/boot/boot_terminal_screen.dart)

- Wrap the terminal title text in a `Flexible` widget.
- Add `overflow: TextOverflow.ellipsis` to the `Text` widget to handle potential overflows gracefully.

```diff
-                                    Text(
-                                      "doro-core@node:~ boot.sh",
-                                      style: TextStyle(
-                                        color: Colors.white.withValues(alpha: 0.45),
-                                        fontFamily: 'monospace',
-                                        fontSize: 11.5,
-                                        fontWeight: FontWeight.w600,
-                                      ),
-                                    ),
+                                    Flexible(
+                                      child: Text(
+                                        "doro-core@node:~ boot.sh",
+                                        overflow: TextOverflow.ellipsis,
+                                        style: TextStyle(
+                                          color: Colors.white.withValues(alpha: 0.45),
+                                          fontFamily: 'monospace',
+                                          fontSize: 11.5,
+                                          fontWeight: FontWeight.w600,
+                                        ),
+                                      ),
+                                    ),
```

## Verification Plan

### Automated Tests
- None, as this is a UI layout issue that is hard to test with unit tests without a full widget test environment.

### Manual Verification
- I will use `analyze_file` to ensure no syntax errors are introduced.
- Since I cannot run the app and see the UI directly, I will rely on the fact that `Flexible` is the standard solution for `RenderFlex` overflows in `Row`s.
- I will check the code structure to ensure `Flexible` is a direct child of `Row`.
