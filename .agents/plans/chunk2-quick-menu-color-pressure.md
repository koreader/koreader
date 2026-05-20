# Chunk 2: Quick-access overlay, color picker, contact sensitivity

**Branch:** master  
**Status:** 🔄 In progress

---

## Goal

Double-tapping the canvas opens a compact overlay with:
- 6-color ink palette (Kaleido 3 colors)
- Contact sensitivity control (pressure floor, opens SpinWidget)

Colors require upgrading the drawing buffer from BB8 (grayscale) to BBRGB32
(color) so ink actually renders in the chosen color on the Kaleido 3 panel.

---

## Discovered APIs (KOReader)

| API | Source |
|-----|--------|
| `Blitbuffer.colorFromString("#rrggbb")` | `readerhighlight.lua:66` |
| `Blitbuffer.ColorRGB32(r, g, b, 0xFF)` | `readerview.lua:693` |
| `Blitbuffer.TYPE_BBRGB32` | `renderimage.lua:111`, `textboxwidget.lua:854` |
| `Screen:isColorEnabled() and TYPE_BBRGB32 or TYPE_BB8` | `textboxwidget.lua:854` |
| `SpinWidget{ value, value_min, value_max, value_step, default_value, callback }` | `spinwidget.lua` |

---

## Tasks

### 1. Buffer upgrade: BB8 → BBRGB32 on color devices
- [x] `drawingcanvas.lua init()`: `Screen:isColorEnabled() and TYPE_BBRGB32 or TYPE_BB8`
- [x] `drawingcanvas.lua _reinitAtRotation()`: same
- [x] `lib/stroke.lua paintTo()`: `Blitbuffer.colorFromString(self.color)` replaces binary B/W logic (color_override still takes priority for dark mode)
- [x] `drawingcanvas.lua _strokeColor()`: returns `colorFromString(_current_color)` in light mode, `COLOR_WHITE` in dark
- [x] `drawingcanvas.lua _repaintAll()`: pass `COLOR_WHITE` override only in dark mode; nil in light (uses stored color)

### 2. Color palette constants
- [x] 6-color `PALETTE` table in drawingcanvas.lua:
  Black `#000000`, Red `#cc2222`, Blue `#2244cc`, Green `#22aa44`, Orange `#cc7700`, Purple `#8822bb`
- [x] New strokes use `self._current_color` (hex string, default `#000000`)

### 3. Double-tap gesture zone
- [x] Register `QuickDoubleTap` in `ges_events` over drawing area (below chrome)
- [x] `onQuickDoubleTap()` → `_showQuickMenu()`

### 4. Quick menu overlay (`_showQuickMenu`)
- [x] `ButtonDialogTitle` with title "Ink & Pressure"
- [x] Row 1: Black / Red / Blue (checkmark on current)
- [x] Row 2: Green / Orange / Purple (checkmark on current)  
- [x] Row 3: [Contact Sensitivity…] → opens SpinWidget
- [x] Color selection: sets `_current_color`, calls `on_color_change`

### 5. Contact sensitivity SpinWidget
- [x] Range 0–512, step 25, default 200; shows current value
- [x] `callback`: sets `self._pressure_floor`, calls `on_pressure_change`

### 6. State persistence
- [x] `main.lua`: pass `current_color` and `pressure_floor` from state to canvas
- [x] `on_color_change` callback writes `state.current_color`
- [x] `on_pressure_change` callback writes `state.pressure_floor`

---

## Notes / discoveries

- `Blitbuffer.colorFromString` returns nil on bad input — fall back to `COLOR_BLACK`
- `_bgColor()` returns `COLOR_WHITE`/`COLOR_BLACK`; these are valid fill colors on both BB8 and BBRGB32
- Dark mode override: pass `Blitbuffer.COLOR_WHITE` to `repaintTo`; in light mode pass `nil` (use stored colors)
- Stage 12 note for colors in dark mode: currently all strokes flip to white in dark mode regardless of ink color. A proper per-stroke inversion (invert each stored color) is a Stage 12 concern.
- The quick menu closes on outside tap because `ButtonDialogTitle` propagates unhandled touch events to the underlying widget stack

---

## Files changed
- `lib/stroke.lua`
- `drawingcanvas.lua`
- `main.lua`

---

## Test checklist (on device)
- [ ] Color strokes render in correct color on Kaleido 3
- [ ] Grayscale device falls back to BB8 (no color corruption)
- [ ] Dark mode still inverts correctly with colored strokes (all → white)
- [ ] Double-tap opens quick menu; tap outside dismisses it
- [ ] Color selection persists across page turns and restart
- [ ] Sensitivity setting persists; affects minimum stroke width immediately
- [ ] 183 busted tests still pass (no regressions in lib/)
