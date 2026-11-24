# PMA asset prompts (for Gemini image / animation generation)

The app already ships the PMA logo (`flutter_app/assets/images/pma_logo.png`,
`pma_mark.png`, animated `pma_logo_anim.gif`) and draws the mascot **Dabba**
in code (`lib/ui/dabba_mascot.dart`), so nothing below is required for the app
to work. These assets make the video, store listing and empty states richer.

**Shared style for every prompt** (paste at the end of each):
> Flat vector illustration with soft gradients, warm orange palette (#FFA24C,
> #FF6A3D, #E8431F) with charcoal (#2B2A30) outlines and mint-teal accents
> (#7CF5D6), clean white or very light warm background (#F6F3F1), friendly and
> modern, no text, no brand logos, centered subject with generous padding.

Save files into `flutter_app/assets/images/` with the given file names; PNG
with transparent background unless noted.

## 1. Dabba, the mascot (matches the code-drawn one)

Dabba is a small cardboard-box robot: an orange box body with two lid flaps
on top like ears, a charcoal face screen with two rounded mint-teal eyes and a
small smile, a thin antenna with a glowing orange bulb, short charcoal arms
with orange round hands, two small charcoal feet, faint white circuit lines on
the right side of the box (like the PMA logo).

| File | Prompt |
| --- | --- |
| `dabba_hello.png` (1024²) | Dabba waving one hand, lid flaps slightly open, cheerful smile. |
| `dabba_listening.png` | Dabba leaning forward, lid flaps raised like perked-up ears, antenna glowing brightly, curved sound-wave lines entering from the left. |
| `dabba_thinking.png` | Dabba looking up, one hand on its chin, three small orange dots circling the antenna. |
| `dabba_speaking.png` | Dabba with mouth open mid-word, sound-wave arcs coming out to the right. |
| `dabba_happy.png` | Dabba jumping with both arms up, eyes as happy arcs, small orange sparkles around. |
| `dabba_worried.png` | Dabba tinted slightly red, eyebrows tilted, holding a clipboard showing a red bar. |
| `dabba_sleeping.png` | Dabba sitting, eyes closed, small "z" floating up, no wifi symbol nearby (offline). |
| `dabba_clipboard.png` | Dabba holding a clipboard with a green check mark (empty "all done" state). |

**Animated loops** (ask Gemini/Veo for a 2-second seamless loop, 512², GIF or WebM):
- `dabba_idle.gif` – gentle up-down bob and one blink.
- `dabba_talk.gif` – mouth opening/closing with sound waves.
- `dabba_listen.gif` – lid flaps lifting and antenna pulsing.

## 2. Empty states (800×600)

| File | Prompt |
| --- | --- |
| `empty_entries.png` | Dabba next to an empty conveyor belt with one snack pouch, looking curious. |
| `empty_alerts.png` | Dabba relaxing on a stack of boxes, a calm green bell icon above (no alerts). |
| `empty_offline.png` | Dabba holding an umbrella under a small grey cloud, a phone in its other hand still glowing (works offline). |
| `empty_scan.png` | Dabba holding up a paper form toward a phone camera, a scan line across the paper. |

## 3. Onboarding / video slides (1920×1080, background allowed)

1. **"Speak it"** – factory floor operator in a hairnet speaking to a phone; Dabba on screen with sound waves; snack pouches on a conveyor behind. Warm, bright, realistic-flat.
2. **"Check it"** – a large phone showing a reading card with green/yellow/red pills; Dabba pointing at the red pill.
3. **"Works offline"** – phone with an on-device chip glowing inside (Gemini Nano idea), a crossed-out wifi cloud above, Dabba giving a thumbs up.
4. **"Office analytics"** – laptop with orange area charts and KPI tiles, a supervisor and Dabba looking at it together, cloud icon above.
5. **"Paper to data"** – stack of handwritten packing sheets turning into neat table rows on a tablet.

## 4. Store / Devpost screenshots frames (1290×2796)

> A premium phone mockup on a soft warm gradient background (#FFF1E6 to
> #FFE0CC), the phone tilted 8 degrees, a large bold headline area left empty
> at the top for text, subtle shadow. (Put the real app screenshot into the
> phone afterwards.)

## 5. Thumbnail for the YouTube demo (1280×720)

> Dabba the cardboard-box robot shouting happily into a phone, the phone
> showing an orange chart, big empty space on the left for the title
> "Speak it. Check it. Save it.", bright warm orange gradient background,
> high contrast, YouTube thumbnail style.
