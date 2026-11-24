# PMA Cloud Functions

Two functions back the PMA automations (they need the Firebase **Blaze** plan):

| Function | Trigger | What it does |
| --- | --- | --- |
| `pushAlert` | `alerts/{id}` created | Sends the alert to the FCM topic `managers` (phones of signed-in admins/managers). |
| `shiftEndCheck` | every 30 minutes (Asia/Karachi) | For each active shift-end rule that just became due, checks `temp_humidity` for missed scheduled readings and writes an alert (which `pushAlert` then pushes). Uses the same alert document id as the app, so a phone and the function never push the same alert twice. |

Rules come from `global_settings/automations` (mirrored from the app whenever an admin edits automations); without that document the default morning (19:30) and night (07:30) checks are used.

## Deploy (not done automatically)

1. Upgrade project `buildhybridai-e2cc2` to Blaze in the Firebase console.
2. Install the CLI and log in: `npm i -g firebase-tools`, `firebase login`.
3. From the repo root: `cd functions && npm install && npm test`.
4. If Firestore is not in a US location, create `functions/.env` with `FUNCTION_REGION=<region next to the database>` (e.g. `asia-south1`).
5. `firebase deploy --only functions,firestore:rules --project buildhybridai-e2cc2`.
6. On the manager's Android phone, sign in as an admin in PMA and allow notifications; the app subscribes to the `managers` topic.
7. Test: add a red reading (e.g. humidity 70) — the phone writes an alert and the manager phone gets a push.
