# MoveFX source audit — 1.6.1

The runtime alias roster was checked directly against the supplied GC6E01 CISO file-system table. Every Gen-I/II move ID from 1 through 251 now has an exact `wzx_<stem>_<phase>.fsys` source family candidate. No archive is accepted merely because an alias exists: runtime still probes the user's imported disc.

The Waza members were then parsed for typed payload presence. 249/251 families contain a non-empty Type-2 HSD model or Type-3 GPT1 particle payload. The two without one are Mirror Move (`oumugaesi`) and Conversion (`texture`), whose retail sequences are copy/controller-led. Type-4 entries are retained in raw WZX caches and remain explicitly opaque.

Regression targets:
- Wing Attack (17): `tsubasa`; source typed visual is in **damage**, 107,476-byte GPT1.
- Psybeam (60): `psyche`; typed GPT1 in attack + damage.
- Psychic (94): `psycho`; typed GPT1 in attack + damage + sp1.
- Swords Dance (14): corrected to `turuginomai`; no longer allowed to match the Vine Whip `tsuru` bank.
- Rest (156): corrected to `nemuru`; no longer allowed to match Sleep Powder `nemuri`.

1.6.1 runtime ownership note: when one of these retail Waza timelines exists, it is the sole phase scheduler. Whole-role GPT1 staging is retained only for legacy caches with no Waza timeline; it is never layered beside the retail entry graph.
