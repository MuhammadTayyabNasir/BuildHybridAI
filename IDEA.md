# Bill Saathi

**Working pitch.** Bill Saathi helps a first-time electricity-bill payer find the payment reference on their bill and reach the review screen themselves. They can get help in English or Urdu while the bill, account details and entered digits stay on their device.

### One moment to build around

Show a fictional electricity bill beside a simulated payment form. The user copies the meter number into the payment-reference field. A generic “Invalid reference” leaves two questions unanswered. Which number does the form want, and where can I find it on this bill? The coach points to the reference label on the bill, highlights the corresponding form field, and gives one short instruction. The user corrects the entry, checks the preview and confirms the simulation themselves.

The audience hypothesis is that some people who can read a bill still need a second person to interpret an unfamiliar banking form. Interview a few intended users about the last time this happened. Use their wording and ask which labels they confused. Work from synthetic examples throughout.

IESCO's consumer manual defines the reference number as an identifier assigned to a consumer. Use the manual to ground the fictional bill's vocabulary. The interviews will establish whether choosing the wrong identifier is a meaningful problem for the people testing the prototype. [IESCO consumer service manual, section 6.4](https://www.iesco.com.pk/storage/Consumer-Service-Manual-January2021-with-clarification.pdf)

### Where each inference belongs

| Situation | Behavior to demonstrate |
|---|---|
| Help with a private question | The Flutter client should select a permitted hint from the current field and error, check the target locally, and show a speaker-reviewed Urdu translation with optional bundled audio. Test any proposed on-device model path on the actual target device before labeling this as local AI. |
| A clearer explanation in Urdu | The user asks for more detail. A cloud Gemini text call receives a fixed topic, screen, error and language, such as `payment_reference_help / bill_payment / meter_number_entered / ur`. Use a reviewed public glossary. Show the actual request fields in the demo. The payload builder accepts only enumerated values. |
| A demo device lacks a supported local model | Offer predefined help topics and a reviewed static hint. Label the source of the hint. A public topic may use a cloud model only through an allowlisted payload and with a visible network status. |

The app compares identifiers, checks the mock bill, and controls the review button deterministically. The model can explain or highlight. The bill image, form values, arbitrary user text and audio have no path into cloud requests or telemetry. Voice in the first release means replayable spoken instructions with captions. Open-microphone conversation, additional languages, WebRTC, human-agent sessions and real banking connections can wait.

### A demo under three minutes

| Time | What the judge sees |
|---|---|
| 0:00–0:25 | The payer chooses the wrong number. Show both labels on the synthetic bill and the form's error. |
| 0:25–1:10 | With networking disabled, show the permitted local hint, the matching highlight, and the reviewed Urdu cue. If a verified on-device model is available on the chosen Flutter target, show its behavior separately. |
| 1:10–1:50 | Reconnect and ask for the distinction in simpler Urdu. Show the actual cloud request beside its answer with English subtitles. |
| 1:50–2:25 | The user edits the field, reaches review and confirms the simulation. Show the static fallback on a device without the local model. |
| 2:25–2:50 | Report observed usability results and show the hosted demo link. |

### Evidence before extending scope

- First technical check: confirm Firebase AI Logic's Flutter support for the intended device targets, then complete a verified local inference call if supported and a cloud call built from an allowed topic with App Check enabled. Verify network traffic and routing, including model-unavailable and offline cases. Label a static hint as static. If Flutter cannot meet the hackathon's on-device inference requirement, choose a supported platform or local model route before building the demo around that claim.
- Try the flow with three to five intended users, including an Urdu speaker. Give each two equivalent synthetic bills, alternating which version has coaching first. Count independent completions and wrong-field retries. Ask them to point to the right identifier on a fresh bill without the hint. Report raw counts and the small sample size.
- Use ECC's `skills/accessibility` as a review reference for keyboard focus, accessible labels and announcing the current hint. Use `skills/eval-harness` for paraphrase, fallback and privacy regression cases. The attached archive has an MIT license. Preserve applicable notices and disclose any incorporated pre-existing work in the submission.

### Build inputs

Start with the [Flutter screen design](design/BRIEF.md), a synthetic bill with fictional labels and numbers, a public glossary for the demo provider, a Firebase project with AI Logic and App Check, and a judge-accessible demo. Use local fixtures for the banking screens. Recruit a fluent Urdu speaker to review or record cues. Prepare a public GitHub or GitLab repository and a public YouTube upload for submission. The platform and local inference claims remain conditional on a successful technical proof on the actual demo device.

[Official contest and technical references](guides/README.md)
