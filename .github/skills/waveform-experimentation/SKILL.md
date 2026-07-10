---
name: waveform-experimentation
description: Provides the on-device test procedure for changing E-ink refresh or waveform behavior in fastnote.koplugin — where to make the change, the failure-mode test matrix (invisible strokes, mid-stroke flash, chunking, missing color, premature tighten), and how to record results. Use when changing waveform modes, setDirty or Screen:refresh* calls, the tighten pass, refresh throttling, or live-drawing latency and feel on the Kobo Libra Colour.
---

# Waveform experimentation — on-device test workflow

This is the **process** for trying a refresh/waveform change without
re-tripping a known landmine. The standing rules (which modes are unsafe
and why) are in `.github/instructions/eink-refresh.instructions.md`, which
applies automatically when `drawingcanvas.lua` is in play; the full research
record is `.agents/notes/waveform-refresh-research.md` (repo root). This
skill assumes both.

The SDL emulator has **no waveform modes** — none of this can be validated
off-device. Plan for hardware in the loop before starting.

---

## Step 1: locate the change

All refresh decisions live in `drawingcanvas.lua`:

- `_refreshRect` — per-segment live refresh (the hot path)
- `_drawSegment` — paints the segment, computes the dirty rect
- `_repaintAll` — full-quality repaint (page load, undo, orientation)
- `_scheduleTighten` / `_cancelTightenTimer` / `_cancelTighten` /
  `_expandTightenRect` / `COLOR_TIGHTEN_DELAY` — deferred color pass

Before editing, note the current mode table in
`waveform-refresh-research.md` § "Current fastnote waveform decisions" —
that section is the design of record you'll update afterward.

## Step 2: deploy to the device

1. Copy the plugin directory onto the Kobo:
   `<onboard>/.adds/koreader/plugins/fastnote.koplugin/`
2. Restart KOReader (exit fully; a sleep/wake is not a restart).
3. Crash log if it doesn't come back: `<onboard>/.adds/koreader/crash.log`.
4. For input-level questions, `evtest` on `/dev/input/event1` (pen and
   touch share this node).

## Step 3: run the failure-mode matrix

Every line below is a failure that actually happened. Run all of them even
if the change "obviously" only affects one — waveform, throttling, and
tighten interact.

- [ ] **Light mode, black ink, one slow straight line** — stroke visible
      while drawing? (Catches the DU-at-32bpp invisible-stroke bug.)
- [ ] **Continuous fast scribble for 10+ seconds** — no full-screen flash
      mid-drawing (flash promotion), no chunked/laggy segments, pen never
      locked out.
- [ ] **Color ink stroke, then hold still past the tighten delay** — note
      what color looks like live (gray is expected under A2), and that true
      color appears after the delay without further input.
- [ ] **Write a multi-stroke word at normal handwriting cadence** — the
      tighten pass must NOT fire between strokes; after finishing, one
      tighten covers ALL strokes written since the last full repaint (bbox
      accumulates across strokes).
- [ ] **Dark mode, one line** — visible while drawing (the pixel-transition
      direction differs; DU historically "worked" here while broken in
      light mode, so dark-mode success proves nothing about light mode).
- [ ] **Eraser pass + undo + `_repaintAll`** (e.g. page change and back) —
      no ghosting left behind, full repaint quality unchanged.
- [ ] **Open and close a dialog mid-session** — subsequent tighten still
      shows color (catches a lost `self.dithered` / dither-gate regression).

If color stops appearing on the tighten: check the three gates listed in
the instructions file before suspecting the waveform change.

## Step 4: record the result

Per the documentation-as-code skill, the doc update rides with the change:

- Design changed and shipped → update the mode table in
  `waveform-refresh-research.md` § "Current fastnote waveform decisions".
- Tried and rejected → add it to that note's "What was tried / ruled out"
  with the observed failure, so the next agent doesn't re-run the dead end.
- External claim tested (forum post, another plugin's technique) → add a
  row to the note's fact-check table with the verdict.
