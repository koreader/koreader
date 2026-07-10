---
applyTo: "plugins/fastnote.koplugin/drawingcanvas.lua"
paths:
  - "plugins/fastnote.koplugin/drawingcanvas.lua"
description: "E-ink refresh and waveform rules for the drawing canvas on Kobo Libra Colour — which modes are safe for live drawing and which cause invisible strokes, mid-stroke flashes, or missing color."
---

# E-ink refresh conventions (drawing canvas, Kobo Libra Colour)

Hard rules for any code that paints strokes or requests screen refreshes.
Each was learned from a real on-device failure — the history and evidence
live in `.agents/notes/waveform-refresh-research.md` (repo root). For the
procedure to test a refresh/waveform change on device, use
`.github/skills/waveform-experimentation/SKILL.md`.

---

## Never use `"partial"` per segment during live drawing

UIManager promotes *any* `"partial"` refresh to a full flashing refresh
after `FULL_REFRESH_COUNT` refreshes (default 6, `frontend/ui/uimanager.lua`
~line 513). At drawing rates that means a screen flash within the first
stroke, locking out the pen mid-line. `"partial"` (+dither) is correct only
for one-shot full-quality repaints: `_repaintAll` and the tighten pass.
`"ui"`, `"fast"`, and `"a2"` do not count toward the promotion.

## Never use `"fast"` (DU) on color hardware at 32bpp

On KoboMonza, DU at 32bpp hits a driver CFA working-buffer bug: strokes are
invisible or corrupted in light mode. Non-color (8bpp) devices are fine
with `"fast"`. Per-device waveform mappings differ — never assume a mode
name means the same thing on another Kobo.

## `"a2"` is 1-bit black/white — grayscale live ink is by design

Color ink rendering as gray during active drawing is expected, not a bug.
True color arrives via the deferred tighten pass (GLRC16). Do not "fix"
gray live ink by switching the live waveform to a color mode — the color
modes are hundreds of ms per update and unusable at pen polling rates.

## Kaleido color is reached only by dither promotion

`"partial"`+dither → GLRC16; `"full"`+dither → GCC16. Nothing else
produces a color-processed (CFA) update. The promotion additionally
requires `self.dithered = true` on the widget (set when color hw present),
`Screen.hw_dithering`, and `Screen:isColorEnabled()` — if color stops
appearing on the tighten pass, check those three gates first.

## Direct `Screen:refresh*` calls bypass UIManager entirely

`Screen:refreshUI/refreshFast/...` hit the framebuffer directly: no paint
queue, no widget repaint, no flash-promotion counter. That makes them the
sanctioned escape hatch for high-frequency live refreshes (the technique
pencil.koplugin uses for live color — see
`.agents/planning/pencil-koplugin-research.md`). Anything painted this way
must still be recorded in StrokeBuffer — the framebuffer is never the
source of truth (ADR-002).

## The tighten delay is device-tuned — don't lower it casually

`COLOR_TIGHTEN_DELAY` was tuned on hardware: shorter delays fire the GLRC16
pass between the strokes of normal handwriting, locking out the pen
mid-word. Any change to it needs the multi-stroke writing test in the
waveform-experimentation skill's matrix.
