# Provider adapters

`generate_sound.py` owns the stable request, output, receipt, and prompt contract. A provider is one file in `scripts/providers/<name>.py` that exports `generate(request) -> tuple[bytes, dict]`.

`request` contains `name`, `text`, `duration`, `influence`, `loop`, and `output`. Return raw audio bytes plus public receipt data; never include a key, authorization header, or a provider response that may contain secrets.

Provider-specific parameters may be added to the receipt, but do not alter shared request fields or output-path behaviour. Another hosted provider or local model can therefore be added as an adapter while the palette, review workflow, and generated files stay interchangeable.

Each adapter must document its required environment variable in `setup/references/secrets.md`, reject a missing secret without printing it, and return audio the target runtime can play.
