# CBE 1.8.0 Android / AYN Thor storage diagnostics test

This build is based directly on the repackaged 1.8.0 runtime and intentionally does not bump the generated-runtime extractor/cache contract.

Diagnostics added:
- `mod.cache` nested write/read/info/delete probe.
- bounded `mod.imports` header read probe and normalized source metadata.
- exact capture extractor error propagation instead of the generic `native capture source cache incomplete`.
- path-aware cache write errors.
- `build/android_storage_diagnostic.txt` with platform, cache/import bridge, source container, probe results, failed stage, and final error.
- `build/capture_source.txt` preserves capture archive/model failures where possible.

For an affected AYN Thor user, the most useful return data is either the full `build/android_storage_diagnostic.txt` + `build/capture_source.txt`, or a screenshot of the failure gate if cache permissions prevent those files from being written.
