# Validation — CBE 1.7.13-movefx-generalization.1

- Lua syntax: all package Lua files parsed with `texluac -p`.
- Manifest JSON parsed successfully.
- Package root contains `main.lua`, `manifest.json`, and `mod.card`.
- Generalized GPT1 synthetic harness passed:
  - selected controller root + same-bank child generator;
  - selected controller root + unique cross-bank child generator;
  - later Waza row selecting a non-original root while keeping exactly one auto-start root;
  - phase-wide dependency template pool retained in all cases;
  - legacy no-entry fallback still starts all authored phase roots.
- MoveFXVM runtime version bumped to 10.
- Extractor revision remains 16 intentionally; no 251-move cache rebuild is forced.
- No ROM/ISO/CISO/GC media included.
- Physical Windows/Android gameplay runtime was not executed in this environment.
