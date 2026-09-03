# Validation — 1.7.15-waza-runtime-rewrite.1

Performed in the ChatGPT build container; no physical Android/Windows game runtime was available.

- Lua syntax compilation: all 56 `.lua` files loaded successfully with LuaTeX `loadfile`.
- Synthetic Waza parser tests passed for normal, mode-1 (`0x6C`), and mode-2 (`0x68`) common layouts.
- Synthetic parser test verified the corrected linked-entry/timing/attachment fields and type-3 selector / GPT1 offset extraction.
- `MoveFXExtractor._internal.scanSequenceGPT1` exists and loads successfully; the 1.7.14 undefined-helper failure is removed.
- MoveFX extractor revision is 17; Waza parser revision is 4; Waza runtime version is 6; GPT1 VM version is 11.
- Full MoveFX marker requires extractor 17 / Waza 4 / selector-resource-link runtime v2, so stale revision-16 MoveFX banks cannot satisfy the complete-cache gate.
- `manifest.json` parses successfully.
- ZIP integrity is checked after packaging.

Device/runtime validation still required: source-disc extraction, 251-bank rebuild, visible particle rendering, procedural type-4 family fidelity, cross-generation battle timing, and Android/Windows GPU behavior.
