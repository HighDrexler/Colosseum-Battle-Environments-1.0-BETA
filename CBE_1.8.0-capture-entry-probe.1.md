# CBE 1.8.0 capture-entry probe test

The AYN Thor diagnostic proved native `mod.cache` and bounded `mod.imports` both pass. The observed failure is therefore in capture-ball source selection rather than Android storage.

This test removes the previous 3-24 KiB hard gate. Parsed Waza type-2/model entries are now enumerated without an upper size limit, soft-ranked by proximity to the historical ~7 KiB observation, and accepted only when the embedded payload decodes as an HSD model.

Diagnostics:
- `build/capture_timeline_entries.txt`: every parsed entry for every capture archive reached.
- `build/capture_source.txt`: candidate order, identifier, byte size, and HSD decode result.
- `build/android_storage_diagnostic.txt`: retained storage/import probe.

Extractor revision is 14 to force a clean generated-runtime rebuild for the changed extraction contract.
