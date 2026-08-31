# CBE 1.6.1 source / platform compatibility

## Disc identity

CBE requires the user's own Pokemon Colosseum (USA) disc content: `GC6E01`, disc 0, revision 0. The original filename and extension are not part of CBE's identity check.

After the launcher admits the private source, CBE validates:

- GameCube disc ID `GC6E01` and magic `0xC2339F3D`;
- revision 0;
- FST offset/size, root span, directory spans, names and every file extent;
- a Colosseum-sized source inventory;
- `FSYS` magic for `people_archive.fsys`, `fight_common.fsys`, `M1_water_colo.fsys`, `D2_crater_colo.fsys`, `T1_ancient_colo.fsys`, and `D4_casino_colo.fsys`.

The audio archives are deliberately **not** part of visual source validity.

## Directly normalized representations

CBE's logical-media bridge directly understands:

- raw GameCube ISO/GCM bytes (any filename extension after launcher admission);
- full-size scrubbed raw images whose removed sectors remain logical zeroes;
- safely trailing-trimmed raw media only when the FST proves no referenced file was cut;
- Dolphin block-sparse GameCube CISO;
- the same readable raw/CISO payload behind a common small 512-byte or 0x8000-byte wrapper/header.

Other compressed/archive formats such as RVZ/GCZ/7z are not falsely treated as raw media. They work only when the launcher/platform first exposes or normalizes them into a readable representation above. This prevents a filename extension from being mistaken for validated disc content.

## Launcher generations

The 1.6.1 manifest carries both compatibility paths:

1. Legacy admission hashes:
   - canonical raw USA ISO: `e3f389dc5662b9f941769e370195ec90`
   - tested supplied CISO: `a2d58d82c6b76b42653dcd25c8966de7`
2. Representation-aware metadata:
   - `gcn_ciso: true`
   - `allow_scrubbed: true`
   - `disc_id: GC6E01`
   - `disc_revision: 0`

Older Gen1Recomp launchers that only understand MD5 still require one of the declared physical hashes before CBE can execute. Representation-aware launcher builds can structurally admit alternate valid GameCube representations and then CBE performs its own content validation. This pre-mod admission gate is launcher-owned; CBE cannot bypass it safely from inside the sandbox.

## Platform behavior

Native `mod.imports` range reads are the preferred path on Windows, Linux, macOS, Android and iOS. They avoid materializing a 665 MiB CISO / 1.46 GiB raw image in one Lua string. The legacy full-buffer adapter remains only for old hosts without the range API.

The bundled Amuse renderer is Windows-only. On every other platform, or whenever generated audio is missing/corrupt, audio is optional and fails open:

- visual runtime stays ready;
- original game music/sounds remain available;
- complete generated Colosseum theme pairs register independently;
- incomplete/corrupt themes are skipped;
- random mode only chooses complete themes;
- capture replaces the stock caught cue only when the generated Colosseum cue successfully loads.
