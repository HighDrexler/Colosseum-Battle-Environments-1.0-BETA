# CBE 1.7.13-movefx-generalization.1

## Purpose

Generalize the Waza type-3 generator fix discovered while reproducing Flame Wheel so it applies to every move rather than one move or one GPT1-bank layout.

## Runtime rule

A typed Waza particle entry selects one authored generator root. It does **not** define the complete set of generator templates that root may reference during execution. CBE therefore loads every executable generator in the same WZX phase as a dormant dependency template, auto-starts exactly one selected root, and lets GPT1 spawn opcodes activate dependencies on demand.

Reference resolution now prefers a sibling in the current bank, then the current GPT payload, then a REF that is unique across the complete phase. This supports nested and cross-bank generator graphs while avoiding ambiguous global ordinal lookups.

The ownership gate remains conservative: source particle ownership requires extracted texture data and an executable source root. Missing/unusable source data continues to fail open to the native visual path.

## Cache/performance

No source-cache schema bump is required. Extractor revision 16 already preserves the complete generator-program set for all 251 move aliases. This change is runtime dependency resolution only, so users do not need to rebuild the large MoveFX cache. Dormant templates are Lua metadata/bytecode and do not imply all particle meshes or audio sources are uploaded to the GPU/audio backend.

## Preserved fixes

The 1.7.12 Windows trainer compact-renderer/fallback behavior and trainer-aware native fallback are retained unchanged.
