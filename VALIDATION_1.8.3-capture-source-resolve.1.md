# Validation — 1.8.3 Capture Source Resolve

- All 57 Lua files parsed successfully with `texlua loadfile`.
- `manifest.json` validates as JSON.
- `main.lua` and manifest versions both report `1.8.3-capture-source-resolve.1`.
- Capture index contract bumped from revision 4 to 5.
- Existing generated runtime extractor marker remains revision 15 so migration stays capture-only.
- `captureSourceReady()` requires 12/12 source rows, zero fallback rows, `staticSource=true`, and capture index revision 5.
- No 3–24 KiB model-size gate was reintroduced.
- Candidate resolution remains constrained to the retail WZX family for each ball type and requires successful HSD decode/compile.
