# PMA — Packing & Monitoring App

**Pitch.** On a snack-factory floor, quality checks are still written on paper
or typed into forms by operators wearing gloves, between machines, often with
no signal. PMA lets them say the reading in the language they think in —
Urdu, Roman Urdu or English — and saves it only after reading it back. Gemini
Nano on the phone understands them offline; cloud Gemini takes over on phones
without Nano and for the long reports managers read at the office.

## Who it is for

- **Operators / QC staff** on the line: record temperature, humidity and
  packing checks hands-free; ask "aaj main ne kitni entries ki?" or "koi entry
  miss to nahi hui?" before the shift ends.
- **Managers / admins**: define sections, thresholds and the reading
  schedule; read summaries and dashboards; get alerted when checks are missed
  or values go red (later slice).

## Design rules

1. **The model never writes data.** It only extracts intent and slots into a
   strict JSON schema. The app validates section, range and thresholds
   deterministically and executes.
2. **Confirm before save.** Every reading is read back by voice and shown on a
   card; "haan / okay / theek hai" saves, "nahi" cancels, "nahi 48 karo"
   corrects and re-confirms. Fast mode skips the question for normal values
   but never for red or out-of-range values, settings changes, deletes or
   low-confidence parses. Undo is always available.
3. **Show where the answer came from.** Every answer carries an
   *On-device*, *Cloud* or *Rules* badge.
4. **Offline first.** Readings land in SQLite and sync to Firestore later;
   counts and missed-entry checks run on local data.
5. **Synthetic data only** in development and demos.

## Where each inference belongs

| Task | Where | Why |
|---|---|---|
| Understand a spoken/typed command | On-device Nano (`PREFER_ON_DEVICE`), cloud fallback, rules when offline without Nano | Short, private, must work without signal |
| Short daily summary for an operator | On-device | Small context, instant |
| Monthly analysis, dashboards, explanations | Cloud (`ONLY_IN_CLOUD`) | Long context, charts |
| Photo of a paper form | On-device OCR + Nano | Single page, private |
| Bulk scanned PDFs | Cloud Gemini with per-page retry | Many pages, multimodal |

## Demo under three minutes

| Time | What the judge sees |
|---|---|
| 0:00–0:20 | The problem: a paper sheet and an operator with full hands. |
| 0:20–1:10 | Airplane mode on a Nano phone: "Peri Peri section ki humidity 45 dal do" → read-back in Urdu → "nahi 48 karo" → "haan" → saved, *On-device* badge. |
| 1:10–1:40 | "Aaj meri koi entry miss to nahi hui?" → the missing sections, from local data. |
| 1:40–2:10 | Same command on a phone without Nano → *Cloud* badge; offline without Nano → *Rules*. |
| 2:10–2:50 | Manager view: dashboard and spoken summary from cloud Gemini (later slice). |

## Slices

1. Rename, Firebase + App Check, hybrid bridge, voice assistant with confirm
   flow, counts and missed entries. *(done)*
2. UI redesign; cloud analytics dashboard with spoken explanation.
3. Automations and manager alerts (FCM, Cloud Functions).
4. Photo and bulk-PDF extraction of paper forms with a review grid.
5. Chrome web build; iOS with Apple Foundation Models.
