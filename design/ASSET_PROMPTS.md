# Asset prompts for Bill Saathi

Send **separate image files**, not a collage or a screenshot of the Figma frames. Do not include text, logos, bank branding, account numbers, or a background in mascot renders. Transparent PNG/WebP at 2048 × 2048 or larger is ideal. Preserve the same character proportions, materials, and colors in every state. We will place them as replaceable images in Figma and Flutter; UI text and controls stay editable.

## Character reference and master prompt

The attached cyan robot is a *mood reference*: warm, approachable, rounded, and gently futuristic. Create an original character distinct in silhouette, face, ears, chest mark, and proportions. Use this prompt for each pose:

> An original friendly household bill guide named Saathi, designed for a trusted Pakistani utility-payment teaching app. A small soft-ivory pebble-shaped robot with a wide rounded-square head and short tapered body, subtle mint seams, a dark deep-teal oval faceplate, two simple warm-white expressive eyes, and a tiny mint leaf-shaped chest light. No antennae, no side fins, no glowing blue mouth, no waving stock-robot silhouette. Make the character kind, capable, calm, and adult-friendly rather than childish. Premium 3D illustration with tactile matte ceramic texture, restrained mint reflections, soft studio lighting, clean readable silhouette, subtle grounded shadow. Deep teal #103D44, mint #B9E7D4, ivory #F8F6EF. Centered full body, generous transparent padding, orthographic three-quarter view, consistent proportions and lighting across the series. Transparent background, no typography, no logos, no watermark, no extra objects, no cropped hands. Avoid human skin cues, bank insignia, currency symbols, or facial features that encode a specific ethnicity.

Use the master prompt plus **one** of these state instructions per export:

1. `saathi-welcome`: open palm toward the app's main action, soft smile in the eyes, confident neutral stance. Hero use; face toward the viewer.
2. `saathi-point-left`: one hand points down-left to a bill label; other hand relaxed, attentive eyes. Keep the pointing hand entirely visible.
3. `saathi-point-right`: mirror the intent, **render separately** so the character's chest emblem and lighting remain coherent; for Urdu layouts we may need the opposite direction.
4. `saathi-thinking`: one hand near the chin, curious eyes, no question-mark prop. For processing and help states.
5. `saathi-encourage`: gentle small approval gesture, reassuring expression, no confetti. For a corrected reference.
6. `saathi-complete`: modest celebration with both hands slightly raised, no money or transaction claim. For the practice completion screen.

Export each with transparent alpha and consistent canvas and scale. Include a neutral 1024 × 1024 front view if possible for a future small avatar. Deliver source project files if available. The character must stay identifiable at a 72 dp display size; simplify facial detail if needed.

## Optional Home scene (separate asset)

> Saathi from the character master prompt stands beside a large abstract paper bill with no readable text or numbers, pointing to a highlighted blank reference strip. Editorial 3D scene, warm ivory background, teal and mint accents, soft shadows, spacious composition with empty left or right side for editable UI copy. Wide 16:9, no text, logos, brand marks, currency, hands, phone mockup, bank card, or real document. Export at 2400 × 1350. Keep the bill fictional and visually generic.

## Synthetic bill sample (editable document preferred)

Create the bill in Figma as vectors and editable text, then export a high-resolution PNG only for AI/vision testing. Do not use a real bill. The demo needs deliberately different labels so the error is understandable:

> A clean fictional Pakistani electricity bill for a pretend provider, "Northlight Power Demo". Large explicit header "SAMPLE — NO PAYMENT DUE" and a diagonal low-opacity "DEMO ONLY" watermark. Clearly separated fields: "Payment Reference" with fictional 14-digit value `00001234004302`; "Meter Number" with fictional value `MTR-00008196`; "Amount Due" `PKR 4,280`; "Due Date" `30 Nov 2026`. Keep all labels and digits in editable vector text, high contrast, no QR code or barcode that can be paid, no real provider insignia or account details. Paper white, deep teal headings, thin neutral rules, enough whitespace to circle the reference label without covering digits. 4:5 portrait, 2000 × 2500 export for testing.

## Brand and icons

The functional logo is the original [SVG mark](brand/saathi-mark.svg). Keep it as SVG in the app and component in Figma. Use a licensed vector icon set for camera, image import, sound, back, help, and success; document its license. Do not ask an image generator to draw interface icons or any wordmark. Typeset "Bill Saathi" with a licensed font and keep the text separate from the symbol.

## Asset review checklist

- Compare the six mascot outputs side by side for faceplate, eyes, chest mark, materials, dimensions, and light direction.
- Check transparent edges on light and dark backgrounds; avoid a cyan halo.
- At 72 dp and 120 dp, the eyes and gesture must remain recognizable. Add alt/semantics for functional poses; mark decorative appearances as decorative.
- Confirm that the sample bill has no live payment code or real account details and that every digit is legible after export.
