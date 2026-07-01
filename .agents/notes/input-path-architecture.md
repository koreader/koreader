# Input path architecture

Applies to: `plugins/fastnote.koplugin/drawingcanvas.lua`, `input/pendev.lua`, `input/touchdev.lua`

See also: ADR-003 (dual-path decision), `lib/pen_statemachine.lua`

---

## Two mutually exclusive paths, selected by `use_raw_input = Device:isKobo()`

| Path | When active | Entry point | Notes |
|------|------------|-------------|-------|
| **Gesture layer** | emulator (`use_raw_input = false`) | `onDrawStroke` / `onDrawStrokeEnd` | Receives KOReader gesture objects, fixed line width, no pressure |
| **Raw evdev** | Kobo device (`use_raw_input = true`) | `_pollPen` / `_pollTouch` | Reads `/dev/input/eventX` via FFI, pressure-sensitive |

Both paths must keep working at all times. Adding a device-only feature must
never break the emulator path — most development happens in the emulator.

## Which flags are honored on which path

| Flag | Gesture path | Raw evdev path |
|------|--------------|-----------------|
| `finger_draw` | Guard at top of `onDrawStroke` | `_pollTouch` filter: `if filtered and self.finger_draw` |
| `_eraser_locked` (menu toggle) | Yes | Yes |
| Hardware eraser (`ev.tool == "eraser"`) | N/A — no tool concept in gesture events | Raw-path only |

## Hardware eraser detection

The Elan combo chip on `/dev/input/event1` does **not** emit
`BTN_TOOL_PEN`/`BTN_TOOL_RUBBER` via `EV_KEY` — those bits aren't in its
capabilities. `pendev.lua` reads `ABS_MT_TOOL_TYPE` per MT slot
(0=finger, 1=pen, 2=eraser) and synthesizes `BTN_TOOL_PEN`/`BTN_TOOL_RUBBER`
into `pen_statemachine`, which sets `sm.tool = "eraser"`.

`_pollPen` checks `ev.tool == "eraser"` on both "down" and "move" (not just
"down") so a mid-stroke tool flip — user flips the stylus while the pen is
still touching — activates eraser mode immediately.

**Landmine already hit once:** tool-type synthesis must fire **once per
contact start** (`BTN_TOUCH` going 1 for a new slot), never re-fed on every
`EV_SYN`. `ABS_MT_TOOL_TYPE` can be sticky across contacts on the Elan chip;
re-synthesizing every sync frame left the state machine stuck in eraser mode
after the eraser tip lifted. See `.agents/planning/next-stages-plan.md`
("What We Learned From the Failed Attempt") for the full incident.
