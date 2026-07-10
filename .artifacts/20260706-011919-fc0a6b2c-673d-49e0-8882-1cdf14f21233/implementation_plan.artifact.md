# Fix Missing Supabase Configuration

The application fails to initialize Supabase features (Chat and Profile) because the required environment variables `SUPABASE_URL` and `SUPABASE_ANON_KEY` are not provided during local execution. While these are correctly set in the CI pipeline using GitHub Secrets, they must be manually passed to `flutter run` or `flutter build` during local development.

## User Review Required

> [!IMPORTANT]
> You will need to retrieve your **Anon Key** from your Supabase Dashboard (`Project Settings > API`).
> The URL for your project seems to be `https://rwzsnlfuqmfxouhfbeoi.supabase.co` based on the migration notes.

## Proposed Changes

### Configuration Automation

I will provide a `.vscode/launch.json` file to automate passing these flags when debugging from VS Code. I will also update the `README.md` to document the correct run command.

#### [NEW] [launch.json](file:///C:/Users/gzers/AndroidStudioProjects/Doro/.vscode/launch.json)

- Create a launch configuration that includes the `--dart-define` arguments.

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Doro (Debug)",
      "request": "launch",
      "type": "dart",
      "toolArgs": [
        "--dart-define",
        "SUPABASE_URL=https://rwzsnlfuqmfxouhfbeoi.supabase.co",
        "--dart-define",
        "SUPABASE_ANON_KEY=YOUR_ANON_KEY_HERE"
      ]
    }
  ]
}
```

#### [README.md](file:///C:/Users/gzers/AndroidStudioProjects/Doro/README.md)

- Update the "Installation & Build" section to include the required flags.

```diff
 ### 2. Application Flutter (Android/Windows)
 ```bash
 # Prérequis
 flutter --version  # 3.44.0+

 # Dépendances
 flutter pub get

 # Lancement en dev
-flutter run
+flutter run \
+  --dart-define=SUPABASE_URL=https://rwzsnlfuqmfxouhfbeoi.supabase.co \
+  --dart-define=SUPABASE_ANON_KEY=<TA_CLE_ANON>

 # Build signé
-flutter build apk --release
+flutter build apk --release \
+  --dart-define=SUPABASE_URL=https://rwzsnlfuqmfxouhfbeoi.supabase.co \
+  --dart-define=SUPABASE_ANON_KEY=<TA_CLE_ANON>
 ```
```

---

### Code Improvements (Optional but Recommended)

#### [supabase_config.dart](file:///C:/Users/gzers/AndroidStudioProjects/Doro/lib/core/supabase/supabase_config.dart)

- I can add the URL as a default since it's already public in the migration notes, making it easier for the user as they would only need to provide the `ANON_KEY`.

```dart
static const String url = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://rwzsnlfuqmfxouhfbeoi.supabase.co');
```

## Verification Plan

### Manual Verification
1. Open `.vscode/launch.json` (if created) and replace `YOUR_ANON_KEY_HERE` with the actual key.
2. Run the app using the "Doro (Debug)" configuration.
3. Verify in the `boot log` screen that the `[ERROR] Configuration Supabase manquante` message is gone and replaced by `[INFO] Connexion à Supabase...`.
4. Run `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` from the terminal and verify the same.
