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

## Fix A/B: Revert live drawing to A2, keep deferred tighten

**Root cause:** `_refreshRect()` (line ~835) uses `"partial"` + dither on color
HW for every single segment drawn. GLRC16 is a color REAGL waveform that takes
hundreds of milliseconds — firing it at pen-move rate makes drawing unusable.

**Fix:**

- [x] Change `_refreshRect()` to use `"a2"` universally for all live drawing —
  fast binary B&W, works at 120 Hz. Even colored ink draws in grayscale live.
- [x] Keep `_scheduleTighten()` / `_expandTightenRect()` / `_cancelTighten()`
  exactly as-is — after `COLOR_TIGHTEN_DELAY` (2.5s) of pen inactivity, a
  single GLRC16 refresh fires over the accumulated bbox to reveal color.
- [x] Verify pen-up paths (gesture `onDrawStrokeEnd`, raw evdev pen "up", raw
  touch "up") all call `_scheduleTighten()` — they already do.
- [x] Verify pen-down paths cancel any pending tighten — they already do.

**File:** `plugins/fastnote.koplugin/drawingcanvas.lua`
**Function:** `DrawingCanvas:_refreshRect` (~line 835)

---

## Fix C: Surface color picker and pressure in the page menu

**Root cause:** The quick menu (color picker + contact sensitivity) is only
accessible via double-tap gesture, which is not discoverable. The page menu
(hamburger tap in chrome strip) doesn't include these controls.

**Fix:**

- [x] Add ink color row(s) and contact sensitivity to `onMenuTap()`'s
  `ButtonDialogTitle`, so users can access everything from the menu they
  already know about.
- [x] Keep the double-tap shortcut working as-is (it's a power-user shortcut).

**File:** `plugins/fastnote.koplugin/drawingcanvas.lua`
**Function:** `DrawingCanvas:onMenuTap` (~line 422)

---

## Housekeeping

- [x] Create `CLAUDE.md` symlink → `AGENTS.md`
- [x] Update `.agents/notes/waveform-refresh-research.md` if the tighten
  approach changed
- [x] Commit and push
