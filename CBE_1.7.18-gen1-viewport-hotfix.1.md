# CBE 1.7.18-gen1-viewport-hotfix.1

Hotfix over 1.7.17 for the remaining Gen 1-only quarter/mini-screen arena presentation.

## Root cause
Gen 1 `Renderer.worldOverride` assumes a physical-window-sized source and draws it at `1 / dpi`. CBE's Android arena renderer deliberately uses a lower logical/capped framebuffer for performance. On high-DPI devices the final Gen 1 blit therefore shrank the completed arena a second time. Gen 2 already explicitly scales the CBE surface and was unaffected.

## Fix
At the Gen 1 `Renderer:endFrame` boundary only, CBE recognizes its own `worldOverride` draw and scales that source canvas to the renderer's live playfield rectangle. The 3D working framebuffer remains capped; no full-resolution depth buffer is introduced. Gen 2 is not modified.
