# Bill Saathi architecture and data map

## Current vertical slice

1. Flutter renders six editable screens using reusable cards, buttons, bill rows, SVG brand assets, light/dark themes, and English/Urdu directionality.
2. A fictional bill fixture lives in app code. `ReferenceValidator` checks the entered number locally and deterministically. The AI cannot decide whether the payment form proceeds.
3. The built-in guide is available offline. On Android, an explicit English help request attempts Firebase AI Logic `ONLY_ON_DEVICE` through a Kotlin platform channel. On supported hardware with an available model, that response is labeled on-device; otherwise the built-in guide remains.
4. An explicit cloud help request uses `firebase_ai` with App Check and `gemini-3.8-flash`. The outbound prompt is constructed only from `HelpTopic` and `AppLanguage` enums. It contains no bill image, payment reference, meter number, arbitrary user text, or account data. A rejected or failed response falls back to the built-in guide.
5. Review and completion are simulations. Nothing calls a banking or payment API.

## Storage decision

| Data | Current location | Retention |
|---|---|---|
| Synthetic bill fixture | Bundled app code | App lifetime |
| Entered reference | Flutter text controller in memory | Cleared after completion; never uploaded |
| AI help topic/language | App memory, then fixed public Gemini prompt on explicit request | No app-side persistence |
| Generated explanation | App memory | Lost on app close |
| Real bill image | Not accepted in this build | None |
| User profile/authentication | Not collected | None |

Firestore, Data Connect, Cloud Storage, Realtime Database, Functions, Genkit, and RAG are not needed for this first demonstration. Adding a real bill-image path later requires local OCR and a deliberate retention design. The intended default is temporary on-device processing with no server upload.

## Verification gates before hackathon claims

- Compile Android bridge and run it on a [supported on-device model](https://firebase.google.com/docs/ai-logic/hybrid/android/get-started) phone; inspect the inference source and offline traffic.
- Register App Check debug tokens for local development; use production attestation for any public release.
- Verify a real cloud call succeeds and inspect its outbound request fields. The current unit test checks prompt construction, not network traffic.
- Test the flow with intended users, including Urdu speakers and people who use large text or screen readers. Have a fluent speaker review all Urdu copy.
- Build image import/OCR only after a fictional test document and local privacy path are working.
