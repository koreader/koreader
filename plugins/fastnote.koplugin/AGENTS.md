# AGENTS.md — fastnote.koplugin

Read this before changing any code in this directory.
Written for a coding agent or developer coming in cold.

---

## What This Plugin Does

`fastnote` is a KOReader plugin for the **Kobo Libra Colour** that provides a
full-screen hand-drawn note-taking canvas. Features (planned):

- Multi-page notebooks with a notebook browser
- Wacom EMR pen input with pressure-sensitive line width
- Palm rejection via two-device gating (pen + capacitive touch streams)
- Eraser (physical eraser end of the stylus, stroke-level delete)
- Undo / redo
- 6-color palette (Kaleido 3 panel)
- Pages saved as SVG with embedded JSON stroke data (round-trippable)

**Source of truth for design decisions:** [`dev-plan-v2.md`](dev-plan-v2.md)  
Read it before implementing any stage. It contains the open questions, the
storage layout, the coordinate translation formula, and the palm rejection
algorithm in detail.

---

## Current State

**Stages 0, 1, 2 complete** (64/64 tests passing). HEAD: `b3d344f87`.

Completed work beyond the numbered stages:
- Config system (`lib/config.lua`) with `finger_draw` toggle and `rotation_mode`
- Hamburger menu button (bottom-right) with portrait/landscape rotation + keep/close
- Orientation lock — canvas locks rotation on open; re-locks on system rotation events

**Stage 3 (palm rejection) and Stage 4 (stroke model + SVG) are next.**  
Executor-ready plan: `helper-user/tmp/plans/plan-stage3-stage4-20260518.md`  
Execute Stage 4 first (fully testable without device), then Stage 3.

---

## File Map

```
fastnote.koplugin/
├── _meta.lua                  Plugin metadata — do not add logic here
├── main.lua                   Entry point: config load, Dispatcher, canvas open
├── drawingcanvas.lua          Drawing canvas widget — all input, rendering, menu, orientation
├── fastnote.conf.example      Documented user config (finger_draw, rotation_mode)
├── lib/
│   ├── canvas_utils.lua       Pure math: compute_dirty_rect, point_in_zone, pressure_to_width
│   ├── config.lua             Pure Lua config loader (loadfile + pcall + merge)
│   ├── pen_statemachine.lua   Wacom evdev state machine → high-level pen events
│   ├── dkjson.lua             [Stage 4] Bundled JSON codec (MIT, copied from KOReader common/)
│   ├── stroke.lua             [Stage 4] Stroke object: points, hitTest, bbox, paintTo, toJSON
│   ├── strokebuffer.lua       [Stage 4] Stroke list, undo/redo stack, eraseAt, repaintTo
│   ├── svg.lua                [Stage 4] svg.write() + svg.read() with <metadata> JSON block
│   └── palmreject.lua         [Stage 3] Proximity-gated palm rejection state machine
├── input/
│   ├── pendev.lua             FFI: finds Wacom, opens fd, polls events → pen_statemachine
│   ├── touchdev.lua           [Stage 3] FFI: MT protocol B reader for capacitive touch
│   └── buttondev.lua          [Stage 8] FFI: hardware page button reader
├── model/
│   ├── page.lua               [Stage 6] One page: StrokeBuffer + load/save path
│   ├── notebook.lua           [Stage 6] One notebook: ordered page list + metadata
│   └── library.lua            [Stage 6] All notebooks + app-wide state
├── ui/
│   ├── browser.lua            [Stage 9] Notebook list widget
│   ├── colorpicker.lua        [Stage 12] Color palette overlay
│   └── chrome.lua             [Stage 7] Always-visible canvas chrome (exit, page indicator)
├── spec/
│   ├── canvas_utils_spec.lua  20 tests ✅
│   ├── config_spec.lua        14 tests ✅
│   ├── pen_statemachine_spec.lua  30 tests ✅
│   ├── palmreject_spec.lua    [Stage 3] to be created
│   ├── stroke_spec.lua        [Stage 4] to be created
│   ├── strokebuffer_spec.lua  [Stage 4] to be created
│   └── svg_spec.lua           [Stage 4] to be created
├── dev-plan-v2.md             ← canonical design doc (read before implementing any stage)
├── landscape-research.md      ← analysis of 4 reference plugins
└── PLAN.md                    ← superseded by dev-plan-v2.md (ignore)
```

Files marked `[Stage N]` do not exist yet; `model/` and `ui/` dirs do not exist yet.

---

## Architecture

```
main.lua
    └── UIManager:show(DrawingCanvas)
            └── drawingcanvas.lua (InputContainer)
                    ├── BlitBuffer (display cache — rebuilt by replaying StrokeBuffer)
                    ├── StrokeBuffer [Stage 4] (source of truth for stroke data)
                    │       └── each Stroke → paintTo(bb) + toJSON() + toSVGPolyline()
                    ├── input/ (raw evdev, Stages 2+)
                    │       ├── pendev.lua    → pen_statemachine → {down/move/up/hover}
                    │       ├── touchdev.lua  [Stage 3] → MT slot events
                    │       └── lib/palmreject.lua [Stage 3] → filters touch through pen-proximity gate
                    └── ui/chrome.lua [Stage 7] (drawn into the same BlitBuffer)
```

**The BlitBuffer is a display cache** — it can be rebuilt at any time by replaying the StrokeBuffer.
After Stage 4, never treat BlitBuffer as the source of truth for stroke data.

**Dual-path invariant:** `use_raw_input = Device:isKobo()`. Emulator always uses the gesture
layer (`onDrawStroke`/`onDrawStrokeEnd`). Device always uses raw evdev poll loop (`_pollPen`).
Both paths must keep working. Do not break the emulator path when adding device features.

---

## Development Loop

### In the SDL emulator (most work happens here)

```bash
cd /path/to/koreader
./kodev run
```

The emulator supports: widget rendering, BlitBuffer, file I/O, tap/pan gestures (via mouse).

It does NOT support: `/dev/input/eventX`, `EVIOCGABS`, E-Ink waveform modes, `Screen:isColorEnabled()` returning true.

**`use_raw_input` flag:** `drawingcanvas.lua` gates all evdev code behind
`Device:isKobo()` (or an explicit config flag). When false, the gesture fallback
path (`onTouch` / `onPan`) allows the canvas to work in the emulator. This
fallback path must be kept working even after Stages 2+.

### On device (for input stages)

- `input/pendev.lua`, `input/touchdev.lua`, `input/buttondev.lua` require real hardware
- Use `evtest` to inspect events before writing code: `evtest /dev/input/event0`
- Capture a palm rejection test stream: `evtest --grab /dev/input/event1 > palm_session.bin`
- Crash logs: `<onboard>/.adds/koreader/crash.log`
- Plugin reload: re-trigger the activation gesture (no full KOReader restart needed)

---

## Stage Checklist

Each stage has a "Definition of done" in `dev-plan-v2.md`. Do not close a stage
until all criteria pass. The stages in execution order:

```
0 ✅ → 1 ✅ → 2 ✅ → 4 → 5 → 6 → 9
                ↓         ↓
                3          7 → 8
                           ↓
                           10 → 11 → 12 → 13
```

Current position: **Stage 4 is next** (then Stage 3 — see plan doc).

---

## Coding Conventions

- **Lua dialect:** LuaJIT / Lua 5.1. See `.github/instructions/lua.instructions.md` for the full rules.
- **KOReader patterns:** See `.github/skills/koreader-plugin/SKILL.md` for widget hierarchy, BlitBuffer usage, raw evdev, coordinate translation, setDirty modes, and SVG persistence.
- **`local` everything.** Global leaks in a long-running KOReader process are hard to debug.
- **GC discipline in hot paths.** The pen poll loop runs at ~120 Hz. Do not allocate new tables per poll tick — use persistent scratch tables (see `lua.instructions.md` → Tables).
- **Error handling:** Wrap file I/O and JSON decode in `pcall`. A corrupt page file should degrade gracefully, not crash the plugin.

---

## Open Questions (from dev-plan-v2.md)

These need answers before the relevant stage is implemented. Do not guess —
surface these to the user when the stage is reached.

| # | Stage | Question | Status |
|---|-------|----------|--------|
| 1 | 4 | One SVG file per page, or SVG + separate data file? | **Resolved: one file** ✅ |
| 2 | 3 | Fingers draw too, or pen-only? | **Resolved: pen-only default; `finger_draw = true` in config enables finger drawing** ✅ |
| 3 | 7 | Chrome strip height — 56 px? Configurable? | 56 px, maybe configurable |
| 4 | 8 | Auto-create page on end-of-notebook page-forward? | Auto-create |
| 5 | 10 | Eraser radius — 24 px default? | 24 px |
| 6 | — | Include a "Stage 14 — latency tuning" stage? | Side quest |
| 7 | 2 | Trust EVIOCGABS range, or show first-launch corner calibration wizard? | Trust + fallback wizard in settings |

---

## Key Technical Notes

### Coordinate translation
Raw Wacom coordinates must be mapped to screen pixels. The formula is in
`dev-plan-v2.md` → "Coordinate translation." Respect `Screen:getRotationMode()`.

### SVG round-trip
`svg.read(svg.write(buffer))` must be lossless. The `<metadata>` block contains
the JSON stroke data. If the block is absent (file hand-edited externally),
fall back to a view-only mode by parsing `<polyline>` elements and setting a
`read_only` flag — never crash.

### Chrome zone
The top 56 px of the canvas is reserved for UI chrome (exit button, page
indicator, tools icon). Pen strokes in this zone are ignored. All touch events
in this zone go to chrome handlers, not to drawing.

### Undo stack scope
Undo is per-page. Crossing a page boundary clears the undo stack. This is a
deliberate scope choice — document it in comments if anyone asks.

### Orientation lock
`drawingcanvas.lua` stores `self._rotation_mode` (the locked mode). On
`onSetRotationMode(event)`, if the incoming mode differs from `self._rotation_mode`, the
canvas calls `self:_reinitAtRotation(self._rotation_mode)` to re-lock. That re-lock call
emits `SetRotationMode(self._rotation_mode)` again — but the handler's `new_mode ~=
self._rotation_mode` check is false for the second call, so there is no loop. No extra guard
is needed.

### self.dimen mutation — IN-PLACE only
GestureRange objects inside `self.ges_events` (DrawStroke, DrawStrokeEnd) hold a direct
reference to the `self.dimen` table created at init. **Never assign a new table** to
`self.dimen` — mutate its fields in-place:
```lua
self.dimen.x = 0; self.dimen.y = 0
self.dimen.w = new_w; self.dimen.h = new_h
```
Only the `MenuTap` zone (which stores its own independent Geom) needs an explicit update
via `_updateGestureZones()` after a rotation.
