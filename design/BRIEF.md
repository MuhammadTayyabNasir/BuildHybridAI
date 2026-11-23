# Bill Saathi — design brief

[Figma design file](https://www.figma.com/design/ZHPxS99XHdrXaOhp5x8XUl) · Original vector mark: [saathi-mark.svg](brand/saathi-mark.svg) · [Asset prompts](ASSET_PROMPTS.md)

## Product promise

Help a person find the correct payment reference on a **fictional electricity bill**, enter it in a **simulated** payment flow, understand a mistake, and confirm only after reviewing the details. The assistant explains and points; it never enters or submits a payment for the user. English and Urdu are the first two languages; Urdu copy still needs review by a fluent speaker. The Figma file covers the experience; on-device model routing still needs testing on a supported phone before promising an offline AI mode.

## Audience and design assumptions

Start with adults who pay household bills in Pakistan, including first-time digital payers, older adults, and people who switch between English and Urdu. The interface should not assume a single level of literacy, vision, hand precision, or banking familiarity. Validate terminology, Urdu wording, reading order, and illustration tone with intended users before implementation. The mascot is a small supportive guide, never a substitute for instructions.

## Primary flow in Figma

| Screen | User decision | Key content and state |
|---|---|---|
| 01 Home | Start a practice bill payment | Clearly marked demo, language switch, concise purpose |
| 02 Add bill | Choose or scan a synthetic bill | Camera/gallery paths and a no-camera sample path |
| 03 Reference | Find and enter the reference | Bill labels are legible; reference and meter numbers are visually distinct |
| 04 Assistant | Get one contextual hint | Highlight the relevant bill label and form field; short text plus optional audio |
| 05 Review | Check every value | Biller, reference, amount, and explicit simulation status |
| 06 Complete | See the result | Practice completion, no claim of money movement |

The present Figma file is a first-pass flow. The Flutter prototype now implements the six primary screens, reference errors, a built-in guide fallback, Urdu RTL, and system dark mode. Add polished generated artwork after it arrives; keep labels and controls editable in Figma. Before the demo, finish the Figma variants for blank/invalid/valid reference, AI unavailable/loading, large text, and dark mode. Camera permission and upload states belong to the later image-import slice. Each state keeps a static help path.

## Visual direction from the supplied references

The five banking images and six short motion clips supplied on 23 November 2026 are mood references, not assets to place in the product. They show three useful patterns: a generous white canvas around a single focal object, expressive but controlled card imagery, and confident hierarchy with large amounts and short labels. The green-card and wallet clips also show how a simple object can enter, rotate, and settle without turning every screen into an animation.

- **Home:** Give the original Saathi mascot or a fictional bill card one clear hero position, with ample quiet space and one dominant action. Use the existing deep teal and mint identity, with a small warm highlight if needed. Keep all headlines and controls as editable text and vectors.
- **Bill selection:** A layered fictional bill can borrow the depth and gentle tilt of the card references. Keep the provider name, payment reference, and meter number legible; avoid realistic bank card details, payment-network marks, and third-party logos.
- **Reference and assistant:** Use the restrained white surfaces and strong type hierarchy from the cleaner dashboard references. The reference value and its matching bill label carry the emphasis. The mascot supports a short hint; decorative 3D shapes never sit behind numbers or error text.
- **Review and completion:** Use a calm summary card and one explicit confirmation action. Completion may have a brief, reduced-motion-aware reveal, but must continue to say that no payment was sent.
- **Motion:** Limit the hero entrance to a short settle and use small state transitions for selection, loading, and success. Provide a static equivalent when reduced motion is requested. Avoid autoplay loops, flashing, parallax during reading, and saturated neon or red/orange backgrounds on task screens.

Build these as reusable Flutter/Figma parts: `SaathiHero`, `FictionalBillCard`, `ReferenceCallout`, `AmountDisplay`, `GuidancePanel`, and `PracticeResult`. Keep artwork, SVG mark, copy, values, and interaction layers separate. The supplied clips are useful for timing and composition, not for reproducing their brands or card designs.

## Layout and reusable parts

- Use a 390 × 844 mobile base, safe areas, a 16 px outer gutter, and an 8 px spacing rhythm. Adapt at 320 px and 600 px widths; use a centered content pane on tablet/desktop.
- Build a shared app bar, language switch, bill preview, identifier callout, reference input, hint card, primary/secondary buttons, progress indicator, summary row, and result panel. Define component variants for states and both languages. Avoid rasterizing text or controls into artwork.
- Brand: deep teal `#103D44`, secondary teal `#126873`, mint `#B9E7D4`, ivory `#F8F6EF`, ink `#17343A`, muted ink `#52656A`, error `#A8333A`, warning `#8A5814`. Treat these as semantic tokens, not direct widget colors. The mark is an original SVG; keep mascot illustrations separate from the functional logo.
- Reserve hero artwork for Home and a small mascot beside contextual help. Screens 03–05 should remain document and action focused. Use a plain placeholder until a transparent, consistent mascot set exists.

## Accessibility and localization acceptance

- Aim for WCAG 2.2 AA: 4.5:1 contrast for normal text and 3:1 for large text and meaningful control boundaries. Verify actual rendered colors in light and dark themes.
- Give each action a visible text label and a distinct shape or icon. Never identify a value or error by color alone. Error text names the issue and next action; highlight both the bill label and matching field.
- Minimum 48 × 48 dp touch targets, visible keyboard focus, logical screen reader order, semantic labels for bill callouts and mascot silence, and controls that work without audio or motion.
- Support system text scale up to at least 200% without clipping or hidden actions. At small widths, let cards and buttons grow vertically. Keep the amount and reference selectable and readable.
- Provide right-to-left Urdu layouts, Urdu numerals only if testing shows they help, and explicit language labels in each language. Do not reverse the order of reference digits. A fluent Urdu reviewer should approve all hints and recordings.
- Reduce decorative animation when reduced motion is requested. Never flash. Avoid small low-contrast cyan text or blue-on-cyan pairings that are hard to distinguish for some users with color vision differences.

## Current implementation constraints

The Flutter Dart AI Logic package provides cloud calls. Android on-device inference is implemented through a native Kotlin bridge using Firebase AI Logic `ONLY_ON_DEVICE`; the Android build passes, but a supported-device test is still needed before any on-device claim. Use the synthetic bill and local fixtures for the first build. Store no real bank credentials or payment data. The [data map](../docs/ARCHITECTURE.md) records the current persistence choices.
