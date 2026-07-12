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
capabilities, and `ABS_MT_TOOL_TYPE` never actually reports `2` (eraser) for
the Kobo Stylus 2's eraser tip on this hardware — it always reports `1`
(pen), even for the eraser end (confirmed externally against
pencil.koplugin / eraser.koplugin on this exact device+pen — see
`.agents/planning/pencil-koplugin-research.md`). The real eraser signal is
`BTN_STYLUS` (or `BTN_STYLUS2` on units/pens that ship with the two
swapped): a **level** signal — 1 while the eraser tip is touching, 0 on
release — decoded by the pure `lib/eraser_button.lua` module against the
`eraser_button` config key (`"stylus"` default | `"stylus2"`).

Because `BTN_STYLUS`/`BTN_STYLUS2` (`EV_KEY`) and `ABS_MT_TOOL_TYPE`
(`EV_ABS`) can arrive in either order within a frame — and
`ABS_MT_TOOL_TYPE=1` can be re-emitted in a later frame while the eraser tip
is still down (sticky reporting) — `pendev.lua` tracks a per-instance
`_eraser_held` **latch**, not a one-shot correction: `eraser_button.lua`'s
`update_held` sets/clears it only from the authoritative `BTN_STYLUS`/
`BTN_STYLUS2` value, and `mt_tool_for_pen_slot` makes the
`ABS_MT_TOOL_TYPE == MT_TOOL_PEN` branch consult that latch (feed
`BTN_TOOL_RUBBER` while held, `BTN_TOOL_PEN` otherwise) instead of
unconditionally feeding `BTN_TOOL_PEN`. This makes the tool decision
order-independent — see `.agents/plans/eraser-capture-runbook.md` for the
on-device capture procedure if the eraser end still misbehaves, and the
"Fix F" section of `.agents/plans/color-drawing-fix-and-menu-access.md` for
history.

If `ABS_MT_TOOL_TYPE` legitimately reports `2` (eraser) on some other
device, `pendev.lua` still handles that directly (feeds `BTN_TOOL_RUBBER`
without consulting the latch) — the latch only matters for the
`MT_TOOL_PEN` case, which is what the Kobo Stylus 2 actually sends for both
tips.

`pen_statemachine.lua` sets `sm.tool = "eraser"` once it receives
`BTN_TOOL_RUBBER`. `_pollPen` checks `ev.tool == "eraser"` on both "down"
and "move" (not just "down") so a mid-stroke tool flip — user flips the
stylus while the pen is still touching — activates eraser mode
immediately.

**Landmine already hit once:** tool-type synthesis must fire **once per
contact start** (`BTN_TOUCH` going 1 for a new slot), never re-fed on every
`EV_SYN`. `ABS_MT_TOOL_TYPE` can be sticky across contacts on the Elan chip;
re-synthesizing every sync frame left the state machine stuck in eraser mode
after the eraser tip lifted. See `.agents/planning/next-stages-plan.md`
("What We Learned From the Failed Attempt") for the full incident.
