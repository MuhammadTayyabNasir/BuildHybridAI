# PMA architecture

PMA is one Flutter app (Android, Chrome web, iOS later) over local-first
storage that syncs to Firestore. Every AI feature only *understands or
explains*; the app itself validates and saves.

```
 operator voice / text ──► AssistantService (lib/assistant)
                             │  1. rules parser (offline, instant)
                             │  2. hybrid model when the rules are unsure
                             │       Android: Kotlin bridge → Firebase AI Logic
                             │                Gemini Nano (PREFER_ON_DEVICE)
                             │                or cloud Gemini (ONLY_IN_CLOUD)
                             │       Chrome:  built-in Prompt API → cloud Gemini
                             │  3. deterministic checks: section, range,
                             │     green/yellow/red limits
                             │  4. read-back → "haan" → save (fast mode skips
                             │     only all-green, fully stated entries)
                             ▼
                    LocalStorage (SQLite / browser) ──► Firestore (sync)

 Gemini Live (online) ──► one function tool `pma(command)` ──► AssistantService
 Insights ──► aggregated, name-free numbers ──► cloud Gemini ──► JSON spec
            ──► whitelisted widgets (KPIs, charts) + spoken explanation
 Paper forms ──► photo: ML Kit OCR → Nano / cloud; PDF: cloud Gemini per page
            ──► ditto fill ──► review grid ──► packing entries
 Automations ──► on-phone rule engine ──► alerts (local) ──► Firestore
            ──► Cloud Functions (functions/, Blaze) ──► FCM to managers
```

| Area | Code |
|---|---|
| Hybrid bridge | `flutter_app/android/app/src/main/kotlin/app/pma/monitor/MainActivity.kt`, `lib/assistant/hybrid_ai*.dart`, `chrome_hybrid_ai.dart`, `cloud_hybrid_ai.dart` |
| Assistant logic | `lib/assistant/assistant_service.dart`, `rules_parser.dart`, `packing_voice.dart` |
| Gemini Live | `lib/assistant/live/` |
| Insights | `lib/analytics/`, `lib/screens/analytics/insights_screen.dart` |
| Paper forms | `lib/extraction/`, `lib/screens/extraction/` |
| Automations | `lib/automations/`, `functions/` |
| Design system and mascot | `lib/ui/pma_ui.dart`, `lib/ui/dabba_mascot.dart` |
| Demo mode | `lib/services/demo_data.dart` |
| UI check | `flutter_app/tools/playwright/screens.mjs` |

Security: App Check on every Firebase AI Logic call (debug provider in debug
builds, Play Integrity / reCAPTCHA Enterprise in release); Firestore rules
allow signed-in users only; the cloud never receives free text with names for
insights; demo mode is local-only and isolated from real data.
