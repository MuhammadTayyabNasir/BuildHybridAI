# PMA — Packing & Monitoring App

PMA is a voice-first logbook for snack-factory floor staff. Operators speak or
type in Urdu, Roman Urdu or English — *"Peri Peri section ki humidity 45 dal
do"*, *"aaj main ne kitni entries ki?"*, *"aaj meri koi entry miss to nahi
hui?"* — and PMA records temperature/humidity readings, answers questions about
their own entries, and opens the right sheet. It is built for the
#BuildHybridAI 2026 hackathon on Firebase AI Logic hybrid inference.

## How it uses Firebase AI Logic hybrid inference

The factory floor is often offline, so understanding the operator has to work
on the phone:

| Situation | What answers | Badge |
|---|---|---|
| Android phone with Gemini Nano | On-device Gemini Nano through Firebase AI Logic (`InferenceMode.PREFER_ON_DEVICE`) | **On-device** |
| No Nano on the phone, network available | Cloud Gemini (`gemini-3.8-flash`) through the same call | **Cloud** |
| No Nano and no network | Deterministic rules parser (Urdu / Roman Urdu number words, keywords) | **Rules** |

The model only turns words into a strict JSON intent (`count_entries`,
`find_missing_entries`, `add_th_reading`, `add_packing_entry`, `open_screen`,
`unknown`) using a response schema. The app then validates it deterministically
— known section, physically possible range, green/yellow/red thresholds — and
reads it back by voice and on screen. It saves only after *"haan / okay / theek
hai"*; *"nahi"* cancels and *"nahi 48 karo"* corrects and re-confirms. Each
answer shows which engine produced it.

Flutter's `firebase_ai` package has no hybrid mode, so the Android Firebase AI
Logic SDK (`firebase-ai` 18.2.0 + `firebase-ai-ondevice`) runs in
[`MainActivity.kt`](flutter_app/android/app/src/main/kotlin/app/pma/monitor/MainActivity.kt)
behind a MethodChannel, and reports the SDK's `inferenceSource` back to Dart.
App Check protects every call (debug provider in debug builds, Play Integrity
in release).

## What works today (slice 1)

- **PMA assistant** (dashboard → *Ask PMA*): mic + text box, Urdu (ur-PK) and
  English speech-to-text and text-to-speech, source badge on every answer
- Temperature / humidity readings by voice with read-back, confirm, cancel,
  correct, red-value warnings, **fast mode** (by voice or setting; red values,
  settings changes, deletes and low-confidence parses still ask) and **undo**
- *How many entries did I make* and *did I miss any entry* answered from local
  storage, against an admin-defined schedule (default: temperature + humidity
  once per morning and night shift per section)
- *"Peri Peri ki sheet kholo"* opens that section's sheet
- Audit fields on every assistant reading: who, when, source, confirmed by
- Everything is local-first (SQLite) and syncs to Firestore when online

Planned next: analyst summaries (short on-device, long in the cloud), cloud
dashboards with spoken explanations, automations with alerts to the manager,
photo and PDF extraction of paper forms, a redesigned UI, and Chrome web.

## Run it

```bash
cd flutter_app
flutter pub get
flutter run        # Android device or emulator (API 26+)
```

On-device inference needs a phone that supports Gemini Nano through Firebase
AI Logic; other phones use the cloud model. Register the App Check debug token
printed in logcat in the Firebase console before trying AI in a debug build.
Firebase setup notes: [flutter_app/SETUP.md](flutter_app/SETUP.md). All demo
data is synthetic (Settings → test data).

## Pre-existing work

PMA is built on the author's own Flutter packing/process monitoring app,
written before the submission period (before Nov 11, 2026) and never deployed
publicly. It is imported unchanged in commit
"Import pre-existing packing monitor app as baseline (built before Nov 11)",
minus API keys, product photos and a third-party logo.

**Already existed:** login and roles, sections and machines, packing entry
forms and Excel-style sheets, temperature/humidity forms with admin
thresholds, offline SQLite storage with Firestore sync, Excel report export,
and analytics screens.

**Built during #BuildHybridAI (after Nov 11):** the rename to PMA and neutral
assets; the move to the hackathon Firebase project with App Check; the Kotlin
Firebase AI Logic hybrid bridge (on-device Nano / cloud fallback with source
reporting and a JSON response schema); the Urdu / Roman Urdu / English intent
pipeline with a deterministic rules fallback; the voice assistant with
confirm-before-save, corrections, fast mode, undo and audit fields; missed-entry
schedules; and everything listed under *Planned next* as it lands. `git log`
on this branch shows each step.

## Project resources

- [Idea, audience and demo plan](IDEA.md)
- [Official hackathon and technical sources](guides/README.md)
- [Third-party resources and attribution](THIRD_PARTY_NOTICES.md)

## License

Original project material is available under the [MIT License](LICENSE).
Included third-party material retains its own license and attribution.
