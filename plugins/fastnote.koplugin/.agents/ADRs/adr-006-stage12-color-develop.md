# ADR-006 — Stage 12: Colour Model, Deferred Develop Refresh, Input Event Logger

**Date:** 2026-05-31  
**Status:** Accepted  
**Context:** fastnote.koplugin Stage 12 (colour picker, Kaleido 3 develop refresh, eraser diagnosis logger)

---

## 1. Context

The plugin targets the Kobo Libra Colour (Kaleido 3 panel). Kaleido panels have two refresh waveforms:

- **A2** — fast greyscale, used for real-time drawing.
- **partial + allow_color=true** — slower Kaleido colour waveform, "develops" strokes into full colour.

Drawing in real-time with colour waveforms is too slow (~200 ms). Drawing A2 then developing is the standard Kaleido pattern (similar to how the stock Kobo notes app works). Three independent design questions arose.

---

## 2. Decisions

### 2A — Colour palette storage: light-mode canonical hex

**Decision:** Store strokes with the *light-mode* hex colour as the canonical value (`Stroke.color`). Dark mode is a display-only transform.

**Alternatives considered:**

| Option | Problem |
|--------|---------|
| Store display hex (changes with mode) | Repaint requires knowing the mode at save time; round-trip through SVG loses intent |
| Store palette index | Couples stroke data to a specific palette version; breaks if palette is customised |
| Store light hex (chosen) | Canonical, palette-version-stable, display transform is always reversible |

**Consequences:** `Color.resolve(stored_hex, dark_mode)` is called at paint time, never at write time. SVG round-trip is lossless (hex survives). Palette can be updated without migrating existing pages.

---

### 2B — Deferred develop refresh: post-stroke idle timer

**Decision:** Arm a `DEFAULT_DEVELOP_DELAY` (5 s) UIManager timer after each pen-up. When it fires, issue `UIManager:setDirty(self, function() return "partial", rect, true end)` over the accumulated dirty region.

**Alternatives considered:**

| Option | Problem |
|--------|---------|
| Develop immediately on pen-up | Colour waveform mid-stroke causes visible lag and out-of-order A2/colour flicker |
| Develop on every segment | Unacceptable latency; defeats the purpose of A2 fast-draw |
| Develop on idle-save (30 s) | Too long; user expects colour within a few seconds of lifting pen |
| 5 s idle timer after pen-up (chosen) | Matches user expectation: draw → lift → wait briefly → colour appears |

**Consequences:** `_dirty_since_develop` accumulates `utils.union_rect` merges per segment; cleared on develop. Pen-down cancels any pending develop timer to avoid colour flicker mid-stroke. Feature is gated by `_has_color_hw` and `_develop_enabled` — no-op on emulator and monochrome devices.

---

### 2C — Input event logger: module-level singleton vs. per-instance

**Decision:** `PenDev.raw_log_fn` is a module-level field on `input/pendev.lua` (singleton). `DrawingCanvas._toggleInputLog()` assigns/clears it.

**Alternatives considered:**

| Option | Problem |
|--------|---------|
| Per-instance closure passed to PenDev | `PenDev` is a singleton; multiple canvas instances sharing one device would be unusual and complex |
| Module-level singleton (chosen) | Simple; `PenDev` is already a module singleton; only one canvas is active at a time |
| Separate sidecar process / `evtest` | Cannot be toggled from the running plugin; requires SSH session |

**Consequences:** `PenDev.raw_log_fn` must be cleared in `onCloseWidget` and when the toggle disables logging — otherwise a stale closure holds a reference to a closed `EventLog`. This is documented as a cleanup contract and enforced in `onCloseWidget`.

---

## 3. Related Files

| File | Role |
|------|------|
| `lib/color.lua` | Palette definition, `Color.resolve`, `Color.is_achromatic` |
| `lib/eventlog.lua` | Line-buffered append log, 2 MB rotation |
| `lib/canvas_utils.lua` | `union_rect` for dirty-region accumulation |
| `lib/strokebuffer.lua` | `repaintTo(bb, color_fn)` extended to accept resolver fn |
| `drawingcanvas.lua` | `_scheduleDevelop`, `_developColor`, `_toggleInputLog` |
| `input/pendev.lua` | `PenDev.raw_log_fn` hook |

---

## 4. Eraser Detection — Hardware Finding (Part 2 Complete)

**Device log analysis result (KoboMonza, Elan combo chip):**

`ABS_MT_TOOL_TYPE=2` is **never emitted**. The chip always reports `TOOL_TYPE=1` (pen) for both pen tip and eraser tip, making the `MT_TOOL_ERASER` branch in the original pendev.lua unreachable dead code.

**Actual eraser signal:** `EV_KEY BTN_STYLUS (0x14B)`:
- Value=1 fires when eraser tip contacts screen
- Value=0 fires when eraser tip lifts

**Fix implemented:** In `pendev.lua` EV_KEY handler, BTN_STYLUS is intercepted before reaching `sm:feed_key()` and translated to BTN_TOOL_RUBBER=1 (eraser on) or BTN_TOOL_PEN=1 (pen restored). The BTN_STYLUS=1 override fires after ABS_MT_TOOL_TYPE=1 has already fed BTN_TOOL_PEN=1 to the SM in the same frame — the override correctly wins because EV_KEY events follow EV_ABS events within a sync frame.

**Unknown code 236 (0xEC = KEY_COFFEE):** A vendor-specific Elan code that fires a 0→1 toggle at eraser lift. Not used in the fix (BTN_STYLUS is sufficient and unambiguous).

---

## 5. Deferred / Out of Scope

- **`develop_delay` user config wiring:** `lib/config.lua` declares `develop_delay` and `develop_enabled` defaults. `drawingcanvas.lua` uses hardcoded constants (`DEFAULT_DEVELOP_DELAY`, `_develop_enabled = true`). Full config wiring deferred to Stage 13 or a follow-up.
