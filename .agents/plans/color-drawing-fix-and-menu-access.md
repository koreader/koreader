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

## Fix F: Eraser end of stylus draws instead of erasing — NEEDS DEVICE TESTING

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

---

## Housekeeping

- [x] Create `CLAUDE.md` symlink → `AGENTS.md`
- [x] Update `.agents/notes/waveform-refresh-research.md`
- [x] Commit and push
