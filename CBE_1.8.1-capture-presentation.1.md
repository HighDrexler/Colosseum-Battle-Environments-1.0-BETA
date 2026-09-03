# CBE 1.8.1 capture presentation pass

This test build focuses only on wild-capture presentation. It keeps engine catch odds, shake result data, inventory, Pokédex state, and nickname logic authoritative while CBE owns the visible 3D choreography.

## Changes
- Result-neutral camera path: an already-resolved successful catch cannot transition to the exit/result camera until CBE finishes the same capture sequence used by a failed throw.
- Throw motion: source-hand attachment through release, linear horizontal projectile travel with a ballistic vertical arc, compact target recoil, gravity-driven drop, and one damped settle.
- Camera: stable sideline tracking during flight rather than projectile-mounted tracking.
- Successful-catch visibility: the caught enemy remains suppressed after the ball cinematic finishes and through post-catch Pokédex/nickname prompts. Native sprite fallback uses the same suppression latch.
- Existing retail capture assets from extractor revision 15 remain valid; no source-cache rebuild is required solely for this presentation patch.
