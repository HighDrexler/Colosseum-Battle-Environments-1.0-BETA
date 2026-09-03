# CBE 1.7.18-gen1-viewport-hotfix.1 validation

- Based directly on 1.7.17-arena-camera-fidelity.1.
- Gen 1-only final compositor patch; Gen 2 path unchanged.
- World surface resolution and Android depth-buffer policy unchanged.
- Final Gen 1 CBE surface is scaled to the live `Renderer.frameRects()` playfield.
- Renderer draw hook is scoped to the exact CBE `worldOverride` canvas and restored immediately after `endFrame`.
- Error paths restore `love.graphics.draw` before rethrowing.
