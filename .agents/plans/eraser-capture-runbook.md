# Eraser capture runbook (maintainer; on-device only)

**Status: NEEDS DEVICE TESTING** — companion to Fix F in
`.agents/plans/color-drawing-fix-and-menu-access.md`. This file cannot be
executed from CI/emulator (no `/dev/input` there); it's written so a
maintainer with the physical Kobo Libra Colour + Kobo Stylus 2 can run it
copy-pasteably, in the style of Phase D of
`.agents/plans/color-pipeline-diagnosis-and-fix.md`.

**Prerequisite**: the order-independent eraser latch (Workstream A of this
eraser-debugging round — see `lib/eraser_button.lua`'s `update_held` /
`mt_tool_for_pen_slot` and `input/pendev.lua`'s `_eraser_held`) must be
deployed to the device first. `busted spec/` passing locally doesn't prove
the on-device behavior; only the steps below do.

---

## Step 1 — cheapest test: try the other button code

The eraser end and the side button are wired to `BTN_STYLUS` /
`BTN_STYLUS2` and can ship swapped on some units/pens. Before capturing any
logs, just try the other mapping:

1. On the device, edit (or create)
   `/mnt/onboard/.adds/koreader/settings/fastnote.conf`:

   ```lua
   return {
       eraser_button = "stylus2",
   }
   ```

2. Restart KOReader.
3. Open a notebook, draw with the pen tip, then draw with the eraser end.

**If the eraser end now erases: done.** Record the outcome (which
`eraser_button` value the unit needs) in the Fix F section of
`.agents/plans/color-drawing-fix-and-menu-access.md` and stop here — no
further capture needed.

If it still draws instead of erasing, continue to Step 2.

---

## Step 2 — capture ground truth with the debug input log

1. Enable logging, either:
   - hamburger menu inside the canvas → **"Debug log: on"**, or
   - set `debug_input_log = true` in `fastnote.conf` and restart KOReader.

   (If neither the menu toggle nor the config key appears to change
   anything — i.e. `fastnote/input.log` never gets created — the toggle
   may not be wired into this build yet; paste that finding back into this
   file instead of guessing further, since it blocks every step below.)

2. Over SSH, tail the log live while you perform the captures in step 3:

   ```bash
   tail -F /mnt/onboard/.adds/koreader/fastnote/input.log
   ```

3. Perform three separate, clearly-separated captures (pause a couple of
   seconds between them so the log is easy to split by eye):

   a. **A normal pen stroke** — touch down with the pen tip, draw a short
      line, lift.

   b. **An eraser-end stroke** — touch down with the eraser end, draw a
      short stroke, lift.

   c. **A pen stroke while holding the side button** — hold the button on
      the barrel, touch down with the pen tip, draw a short stroke, lift,
      then release the button.

4. Save the full tailed output (copy from the terminal, or redirect the
   `tail` command to a file) — the next step reads it line by line.

---

## What to look for

Log format (see `lib/eventlog.lua`):

```
<timestamp>  <level>  <ev_type>  <code_name>  <value>
```

Example expected lines for a **normal pen stroke**:

```
1748736100  RAW  EV_ABS  ABS_MT_TOOL_TYPE  1
1748736100  RAW  EV_ABS  ABS_MT_PRESSURE   340
1748736100  DEC  down    tool=pen          x=512 y=880 p=340
```

Example expected lines for an **eraser-end stroke**, if the hardware and
software are both behaving:

```
1748736123  RAW  EV_ABS  ABS_MT_TOOL_TYPE  1
1748736123  RAW  EV_KEY  BTN_STYLUS        1
1748736123  DEC  down    tool=eraser       x=512 y=880 p=310
```

Check specifically:

- **Does `BTN_STYLUS` or `BTN_STYLUS2` appear at all** when the eraser end
  contacts the screen? Which one, and at what value (1 on contact, 0 on
  lift)?
- **What order does it appear in relative to `ABS_MT_TOOL_TYPE`** within
  the same timestamp/frame — before, after, or does `ABS_MT_TOOL_TYPE=1`
  (pen) get re-sent in a *later* frame while the button code is still
  held at 1?
- **`ABS_PRESSURE` (or `ABS_MT_PRESSURE`) values while the side button is
  held** during capture (c), compared to a normal stroke (a) at similar
  contact force. This settles the "holding the side button widens the
  line" mystery from the on-device report — line width in this plugin
  derives *only* from pressure via `pressure_to_width`
  (`lib/canvas_utils.lua`); nothing else can widen a line. If pressure
  numbers are genuinely higher with the button held, that's the digitizer
  reporting differently, not a plugin bug.

---

## Decision tree

- **`BTN_STYLUS`/`BTN_STYLUS2` codes are swapped from the default**
  (eraser end sends the code NOT selected by `eraser_button`) →
  keep/confirm `eraser_button = "stylus2"` (or `"stylus"` if this unit
  turns out to need the opposite of what Step 1 tried). Record the
  resolution in Fix F.

- **No `BTN_STYLUS`/`BTN_STYLUS2` event at all on eraser contact** (only
  `ABS_MT_TOOL_TYPE=1` and pressure/position, same as a normal pen touch)
  → this unit's eraser tip doesn't use the signal this plugin expects.
  Paste the captured log for capture (b) back into this file (or a new
  note) for the next agent — a different signal (e.g. a pressure-range
  heuristic, or a different MT tool-type value) will need investigating.

- **Pressure jump confirmed with the side button held** (capture (c) shows
  materially higher `ABS_PRESSURE`/`ABS_MT_PRESSURE` than capture (a) at
  similar contact force, with no tool-type or button-code change) →
  hardware/driver reporting artifact, not a plugin bug. Document the
  observed numbers here and in
  `.agents/notes/input-path-architecture.md`; no code change needed.

Record whichever branch applies, with the actual captured log excerpts, in
this file and in the Fix F section of
`.agents/plans/color-drawing-fix-and-menu-access.md` once resolved.
