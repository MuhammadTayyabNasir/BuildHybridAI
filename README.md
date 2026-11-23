# BuildHybridAI

A workspace for the #BuildHybridAI 2026 hackathon, exploring a multilingual banking assistant with on-device and cloud inference through Firebase AI Logic.

The project now contains a Flutter practice flow for [Bill Saathi](IDEA.md): users identify a fictional electricity bill's payment reference, correct a meter-number mistake, review the details, and confirm a simulation. Hybrid AI must be validated on a supported Android demo device before submission claims are finalized.

## Project resources

- [Proposed experience and evaluation plan](IDEA.md)
- [Figma screens, design rules, and reusable parts](design/BRIEF.md)
- [Mascot and sample-bill asset prompts](design/ASSET_PROMPTS.md)
- [Flutter app setup, AI routes, and verification](flutter_app/README.md)
- [Official hackathon and technical sources](guides/README.md)
- [Implementation planning template](docs/examples/product-capability-template.md)
- [Third-party resources and attribution](THIRD_PARTY_NOTICES.md)

## Development guidance

The project includes 14 official Firebase agent skills and 12 selected ECC skills under `.agents/skills`. Coding agents can load relevant guidance when working in this repository.

CodeRabbit review settings live in `.coderabbit.yaml`. Automatic reviews require the CodeRabbit GitHub App to have access to this repository.

Use synthetic banking data during development and demos. Verify model routing, outgoing payloads, language quality, and user confirmation behavior as features are implemented.

## License

Original project material is available under the [MIT License](LICENSE). Included third-party material retains its own license and attribution.
