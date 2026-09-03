# 1.8.0-capture-source-fix.1 — capture extraction resolution
- Removes the 3-24 KiB capture model gate completely; source byte size is never a validity requirement.
- Decodes every retail type-2 HSD candidate and ranks actual ball-like geometry plus recurrence across shake/throw/land/miss banks.
- Uses the same decoded retail prop to repair phase banks that do not redundantly embed their own model.
- Falls back to the exact static retail HSD prop if a source animation clip cannot be compiled.
- Capture props are no longer allowed to block the entire generated CBE runtime; the existing deterministic 3D ball fallback is used only if no retail model can be decoded at all.
- Retains detailed source/candidate diagnostics and bumps generated-runtime extractor revision to 15.

