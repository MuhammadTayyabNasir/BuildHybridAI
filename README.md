# BuildHybridAI

A workspace for the #BuildHybridAI 2026 hackathon, exploring a multilingual banking assistant with on-device and cloud inference through Firebase AI Logic.

The project is in idea refinement. [Bill Saathi](IDEA.md) is a proposed first demonstration that helps a user identify an electricity bill's payment reference and complete a simulated payment. Platform selection and implementation are pending.

## Project resources

- [Proposed experience and evaluation plan](IDEA.md)
- [Official hackathon and technical sources](guides/README.md)
- [Implementation planning template](docs/examples/product-capability-template.md)
- [Third-party resources and attribution](THIRD_PARTY_NOTICES.md)

## Development guidance

The project includes 14 official Firebase agent skills and 12 selected ECC skills under `.agents/skills`. Coding agents can load relevant guidance when working in this repository.

CodeRabbit review settings live in `.coderabbit.yaml`. Automatic reviews require the CodeRabbit GitHub App to have access to this repository.

Use synthetic banking data during development and demos. Verify model routing, outgoing payloads, language quality, and user confirmation behavior as features are implemented.

## License

Original project material is available under the [MIT License](LICENSE). Included third-party material retains its own license and attribution.

