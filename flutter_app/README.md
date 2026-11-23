# Bill Saathi Flutter demo

A practice electricity-bill flow with a fictional bill. No real payment, bank connection, user account, database, or bill upload is involved in this build.

## Run

```powershell
flutter pub get
flutter run -d chrome
```

The practice flow and built-in hints work without Firebase or a network connection. Android and web Firebase client options are generated in `lib/firebase_options.dart` for project `buildhybridai-e2cc2`. AI Logic is enabled for the Android app. A cloud explanation appears only after Firebase and App Check initialize successfully; requests contain a fixed public help topic and language code, never the bill image or entered reference.

## AI routes

- **Built-in guide:** Always available offline. This is deterministic text; Urdu copy still needs review by a fluent speaker.
- **On-device Android:** The native Firebase AI Logic bridge uses `ONLY_ON_DEVICE` for one-turn English help. This is experimental and needs Android API 26+ and a supported device. On first request it checks model availability and starts a download if supported; a failed or unavailable model falls back to the built-in guide. Urdu on-device generation is not claimed because Firebase has not validated it.
- **Gemini cloud:** An explicit button requests a short explanation through Firebase AI Logic with App Check. The model defaults to `gemini-3.8-flash`; `--dart-define=GEMINI_MODEL=...` overrides it. Empty replies, replies over 360 characters, and replies containing long digit sequences fall back to the built-in guide. Semantic safety of model output has not been verified.

For web release builds, supply an App Check reCAPTCHA Enterprise site key with `--dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=...`; without it, cloud help stays disabled. Debug builds use Firebase App Check debug providers. Register generated debug tokens in the Firebase console before trying cloud help. Never commit a debug token.

## Verification

```powershell
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

The Android build also needs accepted Android SDK licenses and Gradle dependencies. A physical supported phone is required to verify true on-device inference and model routing.

## Next implementation slice

Import a fictional bill image and run local OCR on Android/iOS, then verify the extracted reference before entering it. Keep the image and extracted digits in memory; do not send them to Gemini cloud, Firestore, Storage, analytics, or logs. Add dedicated model download progress UI before demoing on-device inference. Replace the vector mascot placeholder with reviewed final artwork and get Urdu copy reviewed by a fluent speaker.
