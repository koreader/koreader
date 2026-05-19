# fastnote.koplugin — Maintenance Guide

Full-screen pen drawing canvas for KOReader. Built in four phases: gesture-based drawing (A), SVG save (B), raw evdev input with pressure (C), color/shade picker (D).

## Current Status

| Phase | Goal | Status |
|-------|------|--------|
| A | Minimal drawing canvas (gesture-based pan strokes) | 🔲 In progress — `drawingcanvas.lua` is empty |
| B | Save drawing as SVG | 🔲 Not started |
| C | Raw evdev input, pressure-sensitive line width | 🔲 Not started |
| D | Ink color / shade picker overlay | 🔲 Not started |

## Architecture

```
fastnote.koplugin/
├── _meta.lua              ← Plugin metadata (name, fullname, description)
├── main.lua               ← WidgetContainer; registers Dispatcher action + menu entry
├── drawingcanvas.lua      ← InputContainer canvas widget (Phase A–D)
├── strokebuffer.lua       ← In-memory stroke list + SVG serializer (Phase B+)
└── PLAN.md                ← Detailed per-phase implementation plan with code examples
```

`main.lua` is the plugin entry point. It delegates all drawing work to `DrawingCanvas` via `UIManager:show(DrawingCanvas:new{})`. The canvas is a self-contained widget — closing it returns to whatever screen was active before.

## Key KOReader APIs

**Drawing**
- `Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)` — allocate an 8-bit grayscale pixel buffer
- `bb:paintLine(x0, y0, x1, y1, width, color)` — draw a line segment
- `bb:blitFrom(src, dx, dy, sx, sy, w, h)` — blit canvas onto the display buffer (called by `paintTo`)

**Display refresh**
- `UIManager:setDirty(widget, mode, geom)` — schedule a partial screen refresh
  - `"fast"` — low-latency, allows ghosting (use per stroke segment)
  - `"ui"` — light partial refresh (use on pen-up)
  - `"full"` — full refresh, no ghosting (use on canvas open/close)

**Input**
- `InputContainer:registerTouchZones({...})` — register gesture handlers in `init()`
- `ges` events: `"pan"` (carries `ges.pos`, `ges.relative`), `"pan_release"`, `"hold"`
- Raw evdev (Phase C): open `/dev/input/eventX`, poll via `UIManager:scheduleIn`, use `ffi/linux_input_h`

**Screen**
- `require("device").screen:getSize()` → `{w, h}` Geom
- `Screen:getWidth()`, `Screen:getHeight()`

## Development Workflow

KOReader has no unit test runner for UI widgets. Development is test-on-device (or emulator):

```bash
# Build the emulator (from koreader repo root)
./kodev build

# Run emulator
./kodev run

# The plugin loads automatically from plugins/fastnote.koplugin/
# Access via: Menu → More tools → Fast Note
# Or assign to a gesture: Menu → Gesture Manager → Open Fast Note Canvas
```

Iterating without a device: edit files, restart the emulator. `logger.dbg(...)` output goes to stdout.

```lua
local logger = require("logger")
logger.dbg("fastnote: canvas opened, dimen =", self.dimen)
```

## Maintenance Notes

**Phase A checklist** (implement `drawingcanvas.lua`):
- [ ] `init()`: allocate full-screen `BlitBuffer`, fill white, register two touch zones (pan → draw, hold top-left → close)
- [ ] `paintTo(bb, x, y)`: blit canvas buffer onto display
- [ ] `onStroke(ges)`: extract prev/curr point from `ges.pos` and `ges.relative`, call `bb:paintLine`, call `UIManager:setDirty` with `"fast"` and tight bounding rect
- [ ] Wire `main.lua` `onOpenFnoteCanvas` to show `DrawingCanvas:new{}` instead of `InfoMessage`
- [ ] Wire `addToMainMenu` callback to the same canvas open call

**Phase B** — add `strokebuffer.lua` with `penDown/penMove/penUp/toSVG`, add `pan_release` touch zone, add save+close gesture (hold bottom-left), write to `DataStorage:getDataDir() .. "/fastnote/"`.

**Phase C** — add `openPenDevice()`, `startRawLoop()`, `rawTick()`, `processRawEvent()`, `digToScreen()`. Keep `use_raw_input` flag to fall back to gesture path. Full spec in `PLAN.md`.

**Phase D** — add `showColorPicker()` using `ButtonDialog`, hold bottom-right corner to open. On grayscale: `Blitbuffer.gray()` shades. On color eink: `Blitbuffer.colorRGB()`. Detect at runtime with `Screen:isColorEnabled()`. Update `StrokeBuffer` to track per-stroke color in SVG output.

## Integration Points

- **Dispatcher action:** `open_fnote_canvas` → appears in Gesture Manager and Profile actions
- **Main menu:** registered under `"more_tools"` sorting hint
- **DataStorage** (Phase B+): `DataStorage:getDataDir()` for the save path — always resolves correctly across device types
- **`/dev/input/eventX`** (Phase C): find via `/proc/bus/input/devices` — look for `"Wacom"` or `"[Pp]en"` in device name, extract `eventN` from Handlers line

## Gotchas

- `drawingcanvas.lua` must be required from `main.lua` as `require("plugins/fastnote.koplugin/drawingcanvas")` — relative requires don't work in KOReader plugins.
- `InputContainer` touch zones are registered in `init()` via `self:registerTouchZones({...})` — not `onShow`.
- `ges.relative` on a `pan` event is the **delta from the last event**, so the previous point is `ges.pos - ges.relative` (both are `Geom` objects supporting `-`).
- On eink, `setDirty` with `"full"` on every stroke is too slow — always use `"fast"` per segment and `"ui"` on pen-up.
- Phase C raw polling at 120 Hz: `UIManager:scheduleIn(0.008, ...)` re-schedules itself — always guard with `if not self._raw_active then return end` and clean up `pen_fd` in the close handler.
- The digitizer coordinate range (EVIOCGABS) varies by device. Always query at open time; never hardcode `0–4095`.
