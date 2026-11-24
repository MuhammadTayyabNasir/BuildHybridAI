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

## What works today

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

- **Insights** tab: cloud Gemini (`ONLY_IN_CLOUD`) builds a dashboard from
  aggregated, name-free numbers as a small JSON spec (KPIs, line/bar charts,
  actions, spoken explanation). The app validates it against a whitelist,
  renders it with its own charts and reads the explanation aloud in Urdu or
  English. A one-line summary runs on-device; with no model the phone builds
  the same dashboard deterministically.
- New look: gradient hero with big numbers and trend pills, *Today* view of
  what is still missing this shift, and a floating pill navigation bar.

- **Batch dictation**: *"batch shuru karo"*, up to 20 readings, *"bas"*, one
  read-back, fix by item number.
- **Automations** (Today → Automations): daily reminders, shift-end
  missed-reading checks and condition alerts (above / below a value or the red
  limit). Rules run on the phone every minute, offline too, through a
  deterministic engine; Gemini can only *suggest* rules, which stay paused until
  an admin approves them. Manager alerts queue offline and go to Firestore;
  Cloud Functions in [`functions/`](functions/README.md) push them over FCM and
  run a server-side shift-end check (needs the Blaze plan).
- **Paper forms** (Today → Scan paper forms): photo → on-device ML Kit OCR →
  Gemini Nano structures the rows (cloud vision as fallback); bulk scanned PDF
  → cloud Gemini page by page with retry and resume. Ditto marks are filled
  from the row above, and every row is reviewed in an editable grid before it
  becomes a packing entry.
- **Chrome web build**: browser storage instead of SQLite, and Chrome's
  built-in Gemini Nano (Prompt API) on-device with cloud Gemini fallback.

| Platform | On-device model | Fallback |
|---|---|---|
| Android | Gemini Nano via Firebase AI Logic (Kotlin bridge) | Cloud Gemini, then rules |
| Chrome | Built-in Gemini Nano (Prompt API) | Cloud Gemini via Firebase AI Logic, then rules |
| iOS (planned on a Mac) | — (Apple Foundation Models not bridged yet) | Cloud Gemini, then rules |

Planned next: voice packing entries and restyling the older screens.

## Run it

```bash
cd flutter_app
flutter pub get
flutter run        # Android device or emulator (API 26+)
flutter run -d chrome   # web
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
schedules; insights dashboards; batch dictation; automations and Cloud
Functions; paper-form extraction; and the Chrome web build. `git log`
on this branch shows each step.

## Project resources

- [Idea, audience and demo plan](IDEA.md)
- [Official hackathon and technical sources](guides/README.md)
- [Third-party resources and attribution](THIRD_PARTY_NOTICES.md)

## License

Original project material is available under the [MIT License](LICENSE).
Included third-party material retains its own license and attribution.
