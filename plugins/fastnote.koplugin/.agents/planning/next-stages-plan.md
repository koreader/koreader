# fastnote.koplugin — Next Stages Implementation Plan

**Written:** 2026-05-27  
**Branch at time of writing:** `master` @ `b48d58e91`  
**Goal:** One piece at a time. Each phase has its own commit. No bundling.

---

## What We Learned From the Failed Attempt

Branch `broken-eraser-investigation` (HEAD: `24f27d593`) has five commits
that broke drawing. The root causes are documented here so we don't repeat them.

### Bug 1: `undo()` in the double-tap handler (fe240e069)

The double-tap detection window (350 ms) is too wide relative to normal
handwriting pace. Nearly every second pen-down triggered a false double-tap,
which:
- Called `self._stroke_buf:undo()` — silently deleted the just-drawn stroke
- Called `self:_repaintAll()` — caused a GL16 screen flash
- Opened the quick menu — intercepted subsequent touch events

**From the user's perspective:** "the pen doesn't draw." Every stroke was
immediately erased and the menu appeared on top.

**Rule going forward:** The quick menu opens on double-tap, but the callback
must NEVER call `undo()`. Undo is a separate user action (long-press, button,
or explicit undo button in the menu). It must never be a side-effect of menu
open.

### Bug 2: BTN_TOOL_RUBBER synthesis on every EV_SYN (fe240e069)

`pendev.lua` was modified to synthesise `BTN_TOOL_PEN` / `BTN_TOOL_RUBBER`
from `ABS_MT_TOOL_TYPE` on every EV_SYN event. The Elan chip sends
`ABS_MT_TOOL_TYPE` per contact slot; after the eraser tip lifts, the slot's
`tool` value can be sticky (stays at 2 = eraser). The synthesis kept firing
`BTN_TOOL_RUBBER` → the pen state machine stayed in eraser mode → pen drew
nothing.

**Rule going forward:** Tool-type synthesis must only fire on **contact start**
(when BTN_TOUCH goes 1 for a new slot), not on every EV_SYN. The state machine
should not be re-fed a tool-change event mid-stroke.

### Commits fe240e069 → 24f27d593 (all four follow-on "fixes")

None resolved the underlying issues because they addressed symptoms (nil guard
on `pd.tool`, partial EV_SYN gating) rather than the root causes above. They
are preserved in `broken-eraser-investigation` for reference.

---

## Phase A: Color Ink  ← START HERE

**Status:** Infrastructure is in master. Drawing always renders black. Palette
selection has no visible effect on device.

### What's already there (b48d58e91)

- `PALETTE` — 6-color table with hex strings
- `_current_color` — tracks selected ink color
- `_showQuickMenu()` — sets `_current_color = entry.hex` on selection
- `_strokeColor()` — calls `Blitbuffer.colorFromString(_current_color)` for
  live drawing
- `penDown(x, y, w, color)` — stores hex in `Stroke.color`
- `Stroke:paintTo(bb, override)` — calls `colorFromString(self.color)` when no
  override
- Buffer init uses `TYPE_BBRGB32` when `Screen:isColorEnabled()` is true

### Diagnosed root cause

`Screen:isColorEnabled()` is a **user-configurable toggle** — it reads
`G_reader_settings:isTrue("color_rendering")`. If that setting is off (or not
set), it returns false and the canvas allocates a **BB8 (grayscale)** buffer.
All ColorRGB32 values drawn into a BB8 buffer are quantised to luminance — red
`#cc2222` → ~47/255 (dark grey), blue `#2244cc` → ~42/255 (dark grey). Both
look black on E-ink.

`Screen:isColorScreen()` and `Device:hasKaleidoWfm()` are **hardware
properties** (not user settings). KoboMonza has both. Using these for the
buffer-type decision makes color work regardless of KOReader's global color
toggle.

### The fix (single commit)

**File:** `drawingcanvas.lua`, `init()` function (~line 172).

Change:
```lua
-- BEFORE
local bb_type = Screen:isColorEnabled()
                and Blitbuffer.TYPE_BBRGB32
                or  Blitbuffer.TYPE_BB8
```
To:
```lua
-- AFTER
-- Use BBRGB32 when the hardware has a color E-ink panel (Kaleido 3 / hasKaleidoWfm).
-- Screen:isColorEnabled() is a user toggle and can be off even on a colour device;
-- we need the hardware query to guarantee the buffer can hold colour pixels.
local has_color_hw = Device.hasKaleidoWfm and Device:hasKaleidoWfm()
                     or Screen:isColorScreen()
local bb_type = has_color_hw
                and Blitbuffer.TYPE_BBRGB32
                or  Blitbuffer.TYPE_BB8
```

**Also update the debug log** on the same line to log `has_color_hw` instead
of (only) `Screen:isColorEnabled()` so on-device confirmation is easy.

> **Note on `_reinitAtRotation`:** The same buffer-type logic is repeated there.
> Apply the same `has_color_hw` fix so rotation doesn't revert to BB8.

### Test plan

1. **Busted:** No change to the testable units — `stroke.lua`, `strokebuffer.lua`,
   `canvas_utils.lua` have no path through `Screen:isColorEnabled`. Existing
   tests still pass.
2. **On device:** Open fastnote, open quick menu (double-tap), select Red. Draw a
   line. It should appear red. Select Blue, draw. Should appear blue. Rotate
   device, draw — color should persist through rotation.
3. **Confirm log:** Check KOReader log for
   `FastNote canvas: init … has_color_hw= true` (or equivalent).

### Commit message

```
fix(color): use hardware colour capability for buffer type, not user toggle

Screen:isColorEnabled() reads G_reader_settings and can be off on a Kaleido 3
device. Use Device:hasKaleidoWfm()/isColorScreen() instead — these are hardware
properties. Fixes ink colour selection having no visible effect on device.
```

---

## Phase B: Eraser (physical eraser tip)

**Status:** Deferred until Phase A is confirmed working on device.

### What we know from the failed attempt

The Elan combo digitizer on `/dev/input/event1` does **not** send
`BTN_TOOL_PEN` (0x140) or `BTN_TOOL_RUBBER` (0x141) via EV_KEY. Those bits
are not in the device's capabilities. The pen state machine (`pen_statemachine.lua`)
watches for EV_KEY events on those codes to switch tool mode — so without
synthesis, the eraser tip never triggers eraser mode (it behaves as pen).

The synthesis approach in `broken-eraser-investigation` is correct in concept
but wrong in timing:

**What went wrong:** Synthesis fired on every EV_SYN, re-feeding the state
machine with tool-change events mid-stroke. After eraser use,
`_mt_slots[slot].tool` could be sticky at 2 (eraser), keeping the SM in eraser
mode indefinitely.

### Safer synthesis approach

Only emit the synthetic BTN_TOOL_PEN / BTN_TOOL_RUBBER event **once per
contact**, at the moment of contact start (BTN_TOUCH = 1 for a new slot).

**File:** `input/pendev.lua`

Sketch of the approach:
```lua
-- In the EV_KEY / BTN_TOUCH handler, after updating _mt_contact_active:
if value == 1 then
    -- New contact starting — read the tool type from the current MT slot
    -- and synthesise the appropriate BTN_TOOL event NOW, not in EV_SYN.
    local slot_tool = self._mt_slots[self._active_slot] and
                      self._mt_slots[self._active_slot].tool or 1
    local synth_code = (slot_tool == 2)
                       and C.BTN_TOOL_RUBBER  -- 0x141
                       or  C.BTN_TOOL_PEN     -- 0x140
    self._pen_sm:feed({ type = C.EV_KEY, code = synth_code, value = 1 })
end
```

**Key invariant:** Never re-synthesise inside EV_SYN. ABS_MT_TOOL_TYPE is
updated in the slot data, but the state machine is only told about a tool
change when BTN_TOUCH fires for a new contact.

### Eraser reset on lift

When BTN_TOUCH = 0 (pen lift), synthesise BTN_TOOL_PEN = 0 and
BTN_TOOL_RUBBER = 0 to reset the SM cleanly:
```lua
if value == 0 then
    self._pen_sm:feed({ type = C.EV_KEY, code = C.BTN_TOOL_RUBBER, value = 0 })
    self._pen_sm:feed({ type = C.EV_KEY, code = C.BTN_TOOL_PEN,    value = 0 })
end
```

### Test plan

1. **Busted:** Add spec for `pendev.lua` MT contact tool synthesis. Verify that:
   - Pen contact → SM sees BTN_TOOL_PEN=1 exactly once
   - Eraser contact → SM sees BTN_TOOL_RUBBER=1 exactly once
   - Neither event is re-fired during the same contact's EV_SYN sequence
2. **On device:** Draw with pen tip (should draw). Switch to eraser tip, stroke
   over a drawn line (should erase). Switch back to pen tip (should draw again
   without being stuck in eraser mode). Repeat 3 contacts alternating.

### Commit message

```
fix(eraser): synthesise BTN_TOOL_RUBBER on contact start, not every EV_SYN

The Elan combo chip does not emit BTN_TOOL_PEN/RUBBER via EV_KEY.
Previous attempt synthesised on every EV_SYN — if ABS_MT_TOOL_TYPE was
sticky across contacts, the state machine stayed stuck in eraser mode.

New approach: synthesise exactly once per contact, in the BTN_TOUCH=1
handler, using the slot's ABS_MT_TOOL_TYPE at that moment. Reset both
codes on BTN_TOUCH=0 (lift). This prevents mid-stroke tool-type drift.
```

---

## Phase C: Notebook Browser (Stage 9)

**Status:** `ui/browser.lua` exists as a stub. Deferred until Phase A and B
are confirmed on device.

### Scope

A full-screen widget that appears when fastnote opens with no last-used
notebook (or user navigates "home"). Shows:
- List of existing notebooks (name, page count, last-edited date)
- "New Notebook" button → creates UUID notebook, opens to page 1
- Tap existing → opens to last-used page

### Files involved

| File | Change |
|------|--------|
| `ui/browser.lua` | Implement the browser widget |
| `main.lua` | Route to browser when no last-used notebook; handle `on_close` from browser |
| `model/library.lua` | `list()` method (already exists?) — confirm |
| `spec/browser_spec.lua` | New test file |

### Known constraints

- KOReader's widget toolkit (`Menu`, `ButtonDialog`) can be used; no need for
  raw painting.
- The browser doesn't need to touch `drawingcanvas.lua` at all.
- Orientation: browser opens in portrait; canvas can open in whatever rotation
  the notebook was saved with.

### Plan sketch (to be expanded into a phase plan when we reach it)

1. Implement `Library:list()` → returns `{ {uuid, name, page_count, last_edited}, ... }` sorted by `last_edited` descending
2. Build `browser.lua` as a `Menu`-based widget (KOReader `Menu` widget handles scrolling list natively)
3. Wire `main.lua`: if `state.last_notebook_uuid` is nil → open browser; if browser returns a uuid → open that notebook; if browser is closed → exit plugin
4. "New Notebook" creates a notebook via `Library:create()`, adds it, opens it
5. Tests: library list ordering, empty state (no notebooks), create + list roundtrip

### Commit message (when we get here)

```
feat(browser): Stage 9 notebook browser — list, create, open

Replaces direct-to-canvas startup when no last-used notebook exists.
Shows all notebooks sorted by last-edited; supports create-new and
open-existing. Routes through main.lua state machine.
```

---

## Deferred: Double-Tap for Quick Menu

The double-tap → open menu feature **works** in master (`b48d58e91`) and
should be left as-is. The complexity is in the false-positive rejection — we
need to know when a second tap is genuinely a "double" and not just rapid
writing. Ideas for if/when we revisit:

- **Time gate only (current):** 350 ms window. Too wide. Drawing pace of 3
  strokes/second will trigger false positives.
- **Spatial gate:** Both taps must land within N pixels of each other. Rapid
  writing moves the pen; a deliberate double-tap usually stays in the same
  spot.
- **Combined gate:** Time < 350 ms AND spatial < 30 px.
- **Hold approach:** Single long-press (500 ms no-move) opens menu. Avoids the
  "two fast taps" problem entirely.

**Do not implement any of these until Phases A and B are stable.** Opening
the double-tap rabbit-hole while color and eraser are untested adds risk with
no benefit.

---

## Implementation Rules (applies to all phases)

1. **One phase per PR / commit set.** Do not bundle Phase A and B changes.
2. **Write or update tests before implementing.** Even if the test can only
   be busted-unit-level (no device), write it first.
3. **Log the thing you're about to change.** Add a debug log at the decision
   point (e.g. `logger.dbg("FastNote: has_color_hw=", has_color_hw)`) so
   on-device verification is fast.
4. **Confirm on device before starting the next phase.** Don't chain untested
   changes.
5. **Update AGENTS.md** after each phase completes (move item from "in
   progress" to "Completed", update Known Issues).
