# Third-party notices

## Firebase agent skills

The Firebase skill directories in `.agents/skills` were downloaded from [firebase/agent-skills](https://github.com/firebase/agent-skills/tree/99954a30898bb5ddc8152ee10e124dc3b4106bf7) at revision `99954a30898bb5ddc8152ee10e124dc3b4106bf7`.

They are distributed under Apache-2.0. The license is included at [.agents/skills/Firebase-LICENSE](.agents/skills/Firebase-LICENSE). Copyright notices in the source files remain applicable.

## ECC

The selected ECC skill directories and `docs/examples/product-capability-template.md` were copied from the user-supplied `ECC-main.zip`, whose documented upstream is [affaan-m/ECC](https://github.com/affaan-m/ECC).

ECC is copyright 2026 Affaan Mustafa and distributed under the MIT License, included at [.agents/skills/ECC-LICENSE](.agents/skills/ECC-LICENSE). The [installation manifest](.agents/skills/ECC-install.json) records the archive checksum and selected skill names.

## Official documentation

The guide index links to Devpost, Firebase, Google and Chrome documentation. Offline text copies are retained locally for research and excluded from Git.

## Syncfusion

Excel export with charts and PDF page splitting use Syncfusion Flutter
packages (`syncfusion_flutter_xlsio`, `syncfusion_officechart`,
`syncfusion_flutter_pdf`, `syncfusion_flutter_core`). They are **not open
source**; they are used under the Syncfusion Community License. Everything else
in PMA is open source.

## Pre-existing work

The packing-monitor app in `flutter_app/` was written by the author before the
hackathon (baseline commit `133150f`) and was never used commercially. All AI,
voice, insights, automations, paper-form, web, mascot and redesign work was
built during the submission period; see the README's "Pre-existing work"
section.
