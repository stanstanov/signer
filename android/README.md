# Signer for Android

Kotlin / Jetpack Compose clone of the iOS Signer app (`lt.turron.signer`).

## Open in Android Studio

1. Open the `android` folder (not the repo root).
2. Sync Gradle.
3. Run on a device or emulator (API 26+).

From the command line:

```sh
cd android
./gradlew assembleDebug
```

## Features

Same flow as iOS: open PDF → draw a signature → tap the page to place it → drag / zoom / delete → share the signed PDF.

- Signature colors: black, gray, blue, navy, red, green, plus a custom hue
- Multiple signatures toggle in Settings
- Locales: English, Russian, Lithuanian, Spanish, German, French, Polish
