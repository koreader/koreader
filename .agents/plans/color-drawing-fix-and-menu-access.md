# Plan: Color Drawing Regression Fix + Menu Access

**Status: IN PROGRESS**

---

## Context

After adding per-segment GLRC16 refresh (`"partial"` + dither) for live color
drawing, the drawing experience is broken:

- Drawing is NOT instant — GLRC16 takes ~300-500ms per segment, far too slow
  at ~120 Hz pen polling
- Refresh "chunks" break up lines mid-stroke — the panel can't keep up
- The hamburger menu (quick menu with color picker / pressure controls) is
  behind a double-tap gesture that users can't discover

---

## Fix A/B: Revert live drawing to A2, keep deferred tighten — DONE

- [x] Change `_refreshRect()` to use `"a2"` universally for all live drawing.
- [x] Keep tighten pass for deferred GLRC16 after pen inactivity.
- [x] Verify pen-up/pen-down paths handle tighten timer correctly.

---

## Fix C: Surface color picker and pressure in the page menu — DONE

- [x] Add ink color rows and contact sensitivity to `onMenuTap()`.
- [x] Keep double-tap quick menu as power-user shortcut.

---

## Fix D: Tighten bbox only covers last stroke — DONE

**Root cause:** `_cancelTighten()` clears `_tighten_rect` on pen-down, wiping
the accumulated bbox from previous strokes. Only the final stroke's region gets
the GLRC16 refresh.

**Fix:** Split into `_cancelTightenTimer()` (pen-down: timer only, preserves
rect) and `_cancelTighten()` (full reset: timer + rect). Pen-down calls the
timer-only variant; `_repaintAll`, `loadPage`, `_doClose` call the full reset.

---

## Fix E: Color not appearing on tighten refresh — DONE

**Root cause:** Missing `self.dithered = has_color_hw` on the DrawingCanvas
widget. UIManager checks `widget.dithered` to honor dithering hints from the
refresh stack. Without it, intervening refreshes (e.g. dialog close) can
overwrite the tighten's GLRC16 color with grayscale.

Also added `hw_dithering` and `isColorEnabled` to the init debug log to help
diagnose if those gates are false on the device.

---

## Fix F: Eraser end of stylus draws instead of erasing — HARDENED, NEEDS DEVICE TESTING

**Architecture review:** The eraser detection chain
(`BTN_STYLUS` → `BTN_TOOL_RUBBER` → SM `tool="eraser"` → canvas
`ev.tool == "eraser"`) is architecturally correct. The code correctly handles:
- Elan MT path: `BTN_STYLUS=1` → feeds `BTN_TOOL_RUBBER=1` to SM
- Wacom EMR path: `BTN_TOOL_RUBBER` passes through directly
- SM sets `tool = "eraser"` on `BTN_TOOL_RUBBER=1`
- Canvas checks `ev.tool == "eraser"` on both "down" and "move"

**Hypothesis:** The Kobo Stylus 2 eraser end may not send `BTN_STYLUS=1`.
If the Elan chip doesn't distinguish the eraser tip from the pen tip at the
evdev level, there's no software fix — we'd need to find an alternative signal.

**Diagnostic:** Added `logger.dbg` on pen "down" events showing `ev.tool`,
`eraser_mode`, `eraser_locked`, and `pressure`. User should check KOReader logs
when touching the eraser end to see what `tool` reports.

**Next steps if `tool` reports `"pen"` for the eraser end:**
- Enable `PenDev.raw_log_fn` to capture raw evdev events
- Look for any event that differs between pen tip and eraser tip
- If no distinguishing event exists, consider adding a menu toggle for
  "eraser end" mode, or detecting via pressure range difference

**Update (2026-07, external confirmation):** the hypothesis that the eraser
end might not send `BTN_STYLUS` is **wrong**. pencil.koplugin and
eraser.koplugin (SimonLiu) both confirm on this exact device+pen: the
eraser end reports `ABS_MT_TOOL_TYPE=1` (pen) but sends `BTN_STYLUS`
(code 331) value 1 while touching, value 0 on release — a level signal, not
an edge. The side button sends `BTN_STYLUS2` the same way, and some
units/pens apparently arrive with the two swapped (pencil ships a swap
toggle). So if the eraser end still draws, debug fastnote's *handling*
(level-vs-edge, event ordering vs. pen-down, or a swapped
BTN_STYLUS/BTN_STYLUS2 unit) — the hardware signal exists. See
`.agents/planning/pencil-koplugin-research.md`.

**Resolved (2026-07, Workstream B of
`.agents/plans/live-color-refresh-and-eraser-hardening.md`):** two real gaps
were found and fixed in software, both root-caused from the hypotheses
above rather than requiring a new hardware signal:

1. **Tool-latch bug (`lib/pen_statemachine.lua`).** `feed_key` for
   `BTN_TOOL_RUBBER` value 0 cleared proximity but left `tool = "eraser"`
   latched. On the Wacom-direct path, a subsequent `BTN_TOUCH` with no
   fresh `BTN_TOOL_PEN 1` in between would emit `"down"` with
   `tool = "eraser"` still set — a phantom eraser stroke. Fixed: rubber
   leaving proximity now resets `tool = "pen"`. Regression specs in
   `spec/pen_statemachine_spec.lua` ("tool-latch reset" describe block).
2. **The swapped-unit case had no software handling at all.** Added
   `BTN_STYLUS2` (`0x14c`) to `lib/input_codes.lua` and a new pure
   `lib/eraser_button.lua` module that decides, given a raw
   `BTN_STYLUS`/`BTN_STYLUS2` event and the new `eraser_button` config key
   (`"stylus"` default | `"stylus2"`), whether to feed the state machine
   `BTN_TOOL_RUBBER`/`BTN_TOOL_PEN` or just log the side button. Wired
   through `lib/config.lua` → `main.lua` → `DrawingCanvas` →
   `input/pendev.lua` (`PenDev.open(path, eraser_button)`). Documented in
   `fastnote.conf.example`, including the user-facing symptom ("eraser end
   draws instead of erasing → try `eraser_button = \"stylus2\"`").

**What remains device-only:** whether the Kobo Stylus 2 eraser tip on this
specific unit sends `BTN_STYLUS` or `BTN_STYLUS2` cannot be determined in
CI/emulator (no `/dev/input` here). Per the post-merge device checklist:
test the eraser end on hardware; if it still draws, set
`eraser_button = "stylus2"` in `fastnote.conf` and retest; capture the
debug log (`logger.dbg` now names the exact code via
`codes.name_of(ec)`) either way and record the result here.

**Update (2026-07, eraser-debugging round, Workstream W2): hardened again
— order-independent latch, still needs device confirmation.** New
on-device evidence (real hardware, latest code at the time): the eraser
end still drew instead of erasing with the `eraser_button = "stylus"`
default, and holding the stylus side button while drawing with the pen tip
widened the line (pressure appeared to rise) without erasing or changing
tools. Code review found a real intra-frame ordering race in
`input/pendev.lua`'s poll loop: when `BTN_STYLUS`/`BTN_STYLUS2` arrived
*before* `ABS_MT_TOOL_TYPE=1` (pen) in a frame — or `ABS_MT_TOOL_TYPE=1`
was sticky-re-emitted in a later frame while the eraser tip was still
down — the old code's `BTN_TOOL_RUBBER` feed on `BTN_STYLUS=1` got
silently overwritten by the `ABS_MT_TOOL_TYPE` branch's unconditional
`BTN_TOOL_PEN` feed, flipping the tool back to pen. Fixed by making the
eraser state an order-independent **level latch**: `lib/eraser_button.lua`
gained two pure functions, `M.update_held(held, action)` (updates the
latch only on the authoritative `"rubber_on"`/`"pen_restore"` actions,
leaving `"side_button"`/`"unknown"` untouched) and
`M.mt_tool_for_pen_slot(held, mt_tool_value)` (what `pendev.lua`'s
`ABS_MT_TOOL_TYPE == MT_TOOL_PEN` branch should feed the state machine:
`BTN_TOOL_RUBBER` while held, `BTN_TOOL_PEN` otherwise). `pendev.lua` now
tracks a per-instance `_eraser_held` (initialized `false` in `open()`),
updated from every `BTN_STYLUS`/`BTN_STYLUS2` decode and consulted by the
`ABS_MT_TOOL_TYPE == MT_TOOL_PEN` branch before feeding a tool code.
Deliberately *not* cleared on `ABS_MT_TRACKING_ID = -1` — `BTN_STYLUS` is
treated as the authoritative level signal for the latch, independent of
MT slot/tracking-id lifecycle. 11 new specs in
`spec/eraser_button_spec.lua` cover the latch and the MT-tool mapping;
`busted spec/` is green. This is still a **software hardening**, not a
confirmed fix — it closes a real bug but doesn't by itself prove the
eraser end will erase on this unit (that depends on which raw code the
unit's eraser tip actually sends, per the `eraser_button` config key).
**Next step:** run `.agents/plans/eraser-capture-runbook.md` on-device —
Step 1 is the cheap `eraser_button = "stylus2"` retest; Step 2 is a raw
debug-log capture (also settles the "wider line while holding the side
button" observation, which is very likely a pressure-reporting artifact
tied to the same button rather than a plugin bug, since line width derives
only from `ABS_PRESSURE` via `pressure_to_width`). Record the outcome
here once run.

---

## Housekeeping

- [x] Create `CLAUDE.md` symlink → `AGENTS.md`
- [x] Update `.agents/notes/waveform-refresh-research.md`
- [x] Commit and push
