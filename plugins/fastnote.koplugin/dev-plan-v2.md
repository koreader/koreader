# fastnote.koplugin — Development Plan (v2)

A KOReader plugin for the **Kobo Libra Colour** that provides full-screen
hand-drawn note-taking with multi-page notebooks, palm rejection, eraser, undo,
and color ink. Drawings are saved as round-trippable SVG.

This is a rewrite of the v1 plan. The architecture is the same in spirit
(BlitBuffer-backed canvas, raw evdev for pen input, stroke list as the
source of truth) but the feature set is much larger and the work is
re-sequenced into smaller, individually verifiable stages so it can be handed
off to a coding agent stage-by-stage.

> **Implementation drift note:** this plan describes app-wide state
> (`last_notebook_uuid`, `last_page_index`) as living in a standalone
> `state.lua` file. As implemented, that state lives inside
> `model/library.lua` instead — no separate file was created. The rest of
> this plan (storage layout, coordinate translation, stage sequencing) was
> implemented as described. This note isn't propagated line-by-line below;
> treat every `state.lua` reference in this document as `model/library.lua`.

---

## Landscape: Existing Alternatives

Before building, surveyed the KOReader plugin ecosystem (May 2026). Repos
cloned to `sandbox/kittypimms-boop/` for reference.

| Repo | What it does | Relevance to fastnote |
|------|-------------|----------------------|
| [`pencil.koplugin`](https://github.com/mysticknits/pencil.koplugin) (mysticknits, 81★) | Stylus drawing **on top of EPUB pages** — annotations overlaid on the book. Pen + eraser + highlighter + color picker + undo. Active (4 days ago). | **Most relevant.** Same hardware, same input stack. Fundamentally different use case: annotating books vs blank notebooks. Good reference for: input.lua approach, eraser detection, busted testing patterns. |
| [`eraser.koplugin`](https://github.com/SimonLiu423/eraser.koplugin) (SimonLiu423, 3★) | Eraser button detection for deleting highlights. Based on Kobo's `BTN_TOOL_RUBBER` event mapping in `device/kobo/device.lua`. | Eraser end detection technique — pencil.koplugin adopted this approach. |

**Conclusion:** fastnote is in a different niche (standalone blank-canvas notebook vs epub annotation), so we're not reinventing the wheel in the bad sense. Both projects can coexist. Borrowing opportunities:
- pencil.koplugin's `spec/` structure as the busted test template
- Their `BTN_TOOL_RUBBER` eraser detection (confirms Stage 2 design)
- Their `logger.dbg()` pattern for emulator debugging

**Key architectural difference:** pencil.koplugin replaces `/frontend/device/input.lua` to inject pen events into KOReader's gesture pipeline. fastnote uses raw evdev directly via `pendev.lua`. Our approach is more self-contained and doesn't require shipping a patched KOReader core file — but it needs the dual-path (gesture fallback for emulator).

---

## Development methodology

- **TDD:** Write a failing spec before implementing any pure-function module. For KOReader-coupled code (canvas, UIManager), develop in the emulator, verify manually via the Stage definition-of-done.
- **Documentation as code:** `AGENTS.md` and this file are the specs. Keep them updated as stages complete and decisions are made. The test file is the executable form of the spec.
- **SDD:** Each Stage section below is the specification. Coding agents start from the definition-of-done and work backward to understand what to build.
- **Test framework:** [busted](https://lunarmodules.github.io/busted/) — same framework used by pencil.koplugin and KOReader itself. Pure-module tests live in `spec/`. Run with `busted` from the plugin root directory.
- **Logging:** `local logger = require("logger")` + `logger.dbg("FastNote tag:", value)` for all debug output. Tags (e.g., `FastNote canvas:`) allow `grep` filtering in emulator stdout or on-device `koreader.log`.

---

## Target hardware: Kobo Libra Colour

The Libra Colour has three input devices that all sit on i2c, each exposed
through its own kernel driver and its own `/dev/input/eventX` node:

| Device              | Provides                                          | Used for                            |
|---------------------|---------------------------------------------------|-------------------------------------|
| Wacom EMR digitizer | `ABS_X`, `ABS_Y`, `ABS_PRESSURE`, `BTN_TOOL_PEN`, `BTN_TOOL_RUBBER`, `BTN_TOUCH` | Pen strokes, pressure, eraser end |
| Capacitive multi-touch | MT slot protocol, `ABS_MT_POSITION_X/Y`, `ABS_MT_TOUCH_MAJOR`, `ABS_MT_TRACKING_ID` | Finger UI, palm detection |
| Power/page buttons  | `EV_KEY` events                                   | Page flip, sleep button             |

These devices are independent. The pen digitizer keeps reporting even when
fingers/palm are on the screen. Palm rejection is therefore something we
implement in userspace by gating one stream against the other — not something
the device does for us. Section "Palm rejection" below has details.

The Kaleido 3 panel renders color through a color filter array over a
grayscale e-ink substrate. KOReader exposes this via `Screen:isColorEnabled()`
and `Blitbuffer.TYPE_BBRGB32`. Color resolution is ~1/3 the native panel
resolution because of the CFA — fine print or fine lines drawn in saturated
color will look fringy. Black ink uses the full panel resolution.

---

## High-level UX

```
                  ┌────────────────────┐
                  │ KOReader (book,    │
                  │  file browser, …)  │
                  └─────────┬──────────┘
            swipe gesture / menu entry
                            ▼
            ┌───────────────────────────────┐
            │ Notebook (the drawing canvas) │  ← lands here if there's a
            │                               │    "last open notebook"
            │  [exit] [browser] [tools]     │
            │                               │
            │   ╭ strokes you've drawn ╮    │
            │                               │
            │   ◀ page n / N ▶              │  hw buttons flip pages
            └────────┬──────────────────────┘
                     │ back gesture
                     ▼
            ┌───────────────────────────────┐
            │ Notebook browser              │
            │                               │
            │  + New notebook               │
            │  • Meeting notes (12 pages)   │
            │  • Sketchbook (3 pages)       │
            │  • Lab journal (47 pages)     │
            │                               │
            │  long-press: rename / delete  │
            └────────┬──────────────────────┘
                     │ back gesture / corner tap
                     ▼
            ┌───────────────────────────────┐
            │ Out of plugin, back in        │
            │ KOReader where you were       │
            └───────────────────────────────┘
```

Entry behaviour:
- First-ever launch → notebook browser, "create your first notebook" prompt
- Subsequent launches → straight to the last notebook on its last page

Exit behaviour:
- Tap an obvious always-visible top-corner widget → goes up one level
  (notebook → browser, browser → out of plugin)
- Plugin always closes cleanly via `UIManager:close(self)` — no special
  teardown for KOReader is needed

---

## Storage layout

```
<koreader_data>/fastnote/
├── state.lua                          ← last_notebook, last_page
└── notebooks/
    ├── <notebook-uuid>/
    │   ├── notebook.lua               ← name, created_at, page order
    │   ├── page_001.svg
    │   ├── page_002.svg
    │   └── …
    └── <notebook-uuid>/
        └── …
```

Notebook directories are named by UUID, not by user-visible name, so renaming
is a metadata-only edit and the directory never has to move. The
user-visible name lives in `notebook.lua`.

`state.lua` and `notebook.lua` are plain Lua tables written with
`util.dumpTable` (already in KOReader). They are small enough that JSON
isn't worth bringing in.

`page_NNN.svg` is the page file. The SVG **is** the source of truth — there
is no separate native format. We embed our stroke data inside a `<metadata>`
block in a `fastnote:` namespace so the file:

1. Renders identically in any browser / Inkscape / iOS preview
2. Reopens losslessly inside the plugin, with full per-stroke editability

```xml
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:fastnote="https://github.com/<you>/fastnote"
     width="1264" height="1680" viewBox="0 0 1264 1680">
  <rect width="100%" height="100%" fill="white"/>
  <polyline points="100,200 105,202 …" stroke="#000000" stroke-width="2"
            fill="none" stroke-linecap="round" stroke-linejoin="round"/>
  <!-- … more polylines, one per stroke … -->
  <metadata>
    <fastnote:strokes>
      [
        {"c":"#000000","w":2,"p":[[100,200,512],[105,202,540], …]},
        …
      ]
    </fastnote:strokes>
  </metadata>
</svg>
```

The `metadata` content is JSON inside an XML element, intentionally — much
simpler to parse from Lua than navigating real XML. On load, we pattern-match
out the `<fastnote:strokes>…</fastnote:strokes>` block and JSON-decode the
contents. If that block is missing or malformed (someone hand-edited the
SVG), we fall back to "view-only": render the SVG polylines once into the
BlitBuffer, set a "read-only-from-svg" flag, and continue.

> **OPEN QUESTION 1: Storage format**
> I'm proposing one file per page (SVG with embedded JSON stroke data).
> Alternative is two files per page (e.g. `page_001.svg` + `page_001.dat`).
> Two-file is slightly simpler to code but means more chances for the files
> to get out of sync. Confirm or reject.

---

## Architecture and files

```
plugins/fastnote.koplugin/
├── _meta.lua                  Plugin metadata
├── main.lua                   Plugin entry point, registers Dispatcher action
├── canvas.lua                 The drawing widget (BlitBuffer, paintLine)
├── input/
│   ├── pendev.lua             Raw evdev pen reader (Wacom node)
│   ├── touchdev.lua           Raw evdev touch reader (MT capacitive node)
│   ├── buttondev.lua          Raw evdev key reader (page buttons)
│   └── palmreject.lua         Gating logic: combines pen + touch streams
├── model/
│   ├── stroke.lua             Stroke object: points, color, width, hit-test
│   ├── strokebuffer.lua       List of strokes, undo stack, snapshot/restore
│   ├── page.lua               One page: stroke buffer + load/save helpers
│   ├── notebook.lua           One notebook: ordered list of pages
│   └── library.lua            All notebooks, plus app-wide state
├── ui/
│   ├── browser.lua            Notebook list widget
│   ├── colorpicker.lua        Color palette overlay
│   └── chrome.lua             Always-visible canvas chrome (exit, page #)
└── svg.lua                    SVG read + write (text-level, not real XML)
```

This is more files than the v1 plan, but each is small and most are pure data
manipulation that can be unit-tested in the KOReader emulator on a Linux
desktop without any hardware.

---

## Build & test loop

KOReader has an **SDL emulator** that runs on Linux/macOS. It's how the rest
of KOReader is developed. It can do everything *except* talk to real evdev
devices — so for `pendev.lua` / `touchdev.lua` / `buttondev.lua`, we need
the actual device.

Recommended loop:

1. Most code (canvas math, stroke model, SVG read/write, notebook
   management, browser UI) → develop and iterate in the emulator
2. The three `input/*.lua` modules → develop on device with `evtest` and KOReader's
   on-device log (`koreader.log` next to the binary) for diagnosis
3. The palm rejection module is a pure function of two event streams —
   develop it with **recorded** evdev streams (capture once with `evtest
   --grab`, then replay against `palmreject.lua` in unit tests)

KOReader's plugin reload doesn't require a full restart on most code
changes: rerun the trigger gesture / menu action and the new code is picked
up. Crash logs go to `<onboard>/.adds/koreader/crash.log` on Kobo and to
stdout in the emulator.

---

## Stages

Each stage ends in an observable, testable state. Stages are sized so a
coding agent can complete one in a session without ambiguity. "Definition of
done" is the agent's stopping condition.

### Stage 0 — Plugin skeleton

**Files:** `_meta.lua`, `main.lua` (stub), `canvas.lua` (empty widget)

**Tasks:**
- `_meta.lua` returns plugin metadata.
- `main.lua` extends `WidgetContainer`, registers Dispatcher action
  `open_fastnote`, adds entry to More Tools menu, opens an empty
  `WidgetContainer` subclass (no drawing yet) on activation.
- The empty widget responds to a tap-anywhere "close" handler so we can get
  out of it.

**Definition of done:**
- Plugin appears in More Tools menu **and** under Gesture Manager
- Activating it shows a blank screen
- Tapping closes it and returns to where you were
- No crash log on open/close
- Works in the SDL emulator

---

### Stage 1 — Gesture-based drawing canvas

This is the v1 Phase A, kept as a working fallback. Even after we add raw
evdev (Stage 2), keeping a `use_raw_input = false` codepath that uses
KOReader's `GestureDetector` is valuable for emulator development (the
emulator has no evdev pen).

**Files modified:** `canvas.lua`

**Tasks:**
- In `canvas:init`: allocate full-screen BlitBuffer
  (`TYPE_BBRGB32` if `Screen:isColorEnabled()` else `TYPE_BB8`), fill white.
- Register touch zone `canvas_pan` over the full screen, `ges = "pan"`.
- Implement `onStroke(ges)`: `paintLine` from
  `(pos.x - relative.x, pos.y - relative.y)` to `(pos.x, pos.y)`.
- `setDirty` rectangle with margin = line_width + 1, mode `"fast"`.
- Register touch zone for `pan_release` for stroke termination.
- Add an exit zone in top-left 60×60 px on `tap` (not `hold` — taps are
  more obvious; hold is for the palm gesture in v1).

**Definition of done:**
- Scribbling with mouse in emulator (or finger on device) draws black lines
- Each stroke ends visually crisp (full refresh on `pan_release`)
- Top-left corner tap exits the plugin

---

### Stage 2 — Raw evdev pen input

This replaces gesture-based drawing on device. It also gives us pressure
sensitivity and hover detection, both of which gesture-based input throws
away.

**Files added:** `input/pendev.lua`
**Files modified:** `canvas.lua` (branch on `use_raw_input`)

**Tasks in `pendev.lua`:**

- `PenDev.find()` parses `/proc/bus/input/devices`, looking for a record
  whose `N: Name=` contains `Wacom`. Returns the `/dev/input/eventX` path.
- `PenDev.open(path)` opens with `O_RDONLY | O_NONBLOCK`, queries
  `EVIOCGABS` for `ABS_X`, `ABS_Y`, `ABS_PRESSURE` to learn the digitizer's
  raw range. Falls back to 0..4095 / 0..1024 if ioctl fails.
- `PenDev:poll(cb)` reads as many `struct input_event` records as are
  available, decodes them, and emits high-level events to `cb`:
  - `{type="down", x, y, pressure, tool="pen"|"eraser"}`
  - `{type="move", x, y, pressure}`
  - `{type="up"}`
  - `{type="hover", x, y}` (BTN_TOOL_PEN=1, BTN_TOUCH=0) — optional, can be
    used later for cursor preview
- `PenDev:close()`

Use `ffi/linux_input_h` (already in KOReader). The state machine:

```
EV_KEY, BTN_TOOL_PEN, 1     →  tool = pen, in_proximity = true
EV_KEY, BTN_TOOL_RUBBER, 1  →  tool = eraser, in_proximity = true
EV_KEY, BTN_TOUCH, 1        →  pen_down = true, emit "down" with latched x,y,p
EV_KEY, BTN_TOUCH, 0        →  pen_down = false, emit "up"
EV_KEY, BTN_TOOL_*, 0       →  in_proximity = false, emit "up" if still down
EV_ABS, ABS_X|Y|PRESSURE    →  latch into raw_x/y/p
EV_SYN, SYN_REPORT          →  if pen_down: emit "move"
                               else if in_proximity: emit "hover"
```

**Tasks in `canvas.lua`:**

- On `init`, if `use_raw_input`: open pen device, start poll loop scheduled
  via `UIManager:scheduleIn(0.008, …)` (~120 Hz).
- Translate raw pen coords → screen coords, respecting
  `Screen:getRotationMode()`. Code for this in section "Coordinate
  translation" below.
- Pressure → width: `width = floor(1 + (p_normalized ^ 1.5) * 7)`.
- On `close`: stop polling, close fd.

**Definition of done:**
- Pen draws on device with the canvas open
- Pressure visibly changes line width over the stroke
- Pen hovering near (but not touching) the screen does **not** draw
- `use_raw_input = false` still works in the emulator
- Closing the canvas while pen is in proximity doesn't leak the fd

---

### Stage 3 — Palm rejection (two-device gating)

The pen and touch digitizers are independent. With Stage 2 alone, you can
draw with the pen, but **fingers and palm still draw too** (via Stage 1's
gesture path that we kept as fallback). Worse: when you write naturally with
your palm resting on the screen, the palm's gesture-pan events will scribble
all over your work.

**Files added:** `input/touchdev.lua`, `input/palmreject.lua`
**Files modified:** `canvas.lua`

**Tasks in `touchdev.lua`:**
- Same shape as `pendev.lua` but parses the **multi-touch protocol B**
  (MT slots). Emits per-slot events with `tracking_id`, `x`, `y`,
  `touch_major` (contact area).
- Find by looking for the touchscreen device in `/proc/bus/input/devices`
  (it has `EV=b` with `ABS_MT_POSITION_X` in its `ABS=` mask, typically
  named something like `cy8mrln` or `fts_ts` on Kobo — check on your unit).

**Tasks in `palmreject.lua`:**

```
state:
  pen_in_proximity = false        -- updated by pendev events
  active_slots = {}               -- tracking_id → { x, y, touch_major, rejected }

on pen "down" / "hover" / "move": set pen_in_proximity = true
on pen "up":                      keep pen_in_proximity = true for
                                  TOUCH_BLACKOUT_MS (e.g. 250 ms) after pen lift,
                                  then clear it

on touch slot down:
  if pen_in_proximity: mark slot rejected
  elif touch_major > PALM_AREA_THRESHOLD: mark slot rejected
  else: forward to UI / drawing
on touch slot move: forward only if not rejected
on touch slot up: drop slot
```

`TOUCH_BLACKOUT_MS` covers the gap where the pen lifts off briefly during a
stroke (writing a "t" cross). `PALM_AREA_THRESHOLD` needs calibration on
your hand — log `touch_major` for both finger taps and palm-resting events
and pick a threshold between them.

**Tasks in `canvas.lua`:**
- Wire touch events through `palmreject` before they reach the gesture
  fallback path or any UI chrome handler.

**Definition of done:**
- Pen draws normally
- Resting palm on the screen does nothing
- Finger taps on chrome (exit button, etc.) still work when pen isn't near
- During a finger UI interaction, picking up the pen mid-air doesn't crash

> **OPEN QUESTION 2: Should fingers be able to draw?**
> Two reasonable defaults:
> - "Pen only" — fingers never draw, they only tap UI. Predictable. (My
>   recommendation.)
> - "Pen and finger both draw, palm rejected by area" — natural for sketching
>   without the pen handy. Riskier (you might draw with a knuckle by accident).
> Pick one as the default; the other can be a setting later.

---

### Stage 4 — Stroke model and SVG save

So far we've been painting directly into the BlitBuffer with no record of
what we drew. We need a stroke list to support undo, eraser, persistence,
and re-rendering after rotation or color change.

**Files added:** `model/stroke.lua`, `model/strokebuffer.lua`, `svg.lua`
**Files modified:** `canvas.lua`

**Tasks in `stroke.lua`:**
```
Stroke = {
  color = "#000000",
  width = 2,            -- nominal width (for SVG); per-point width derived from pressure
  points = { {x, y, p}, … },
}
function Stroke:hitTest(x, y, radius) → bool      -- "does any segment come within `radius` of (x,y)?"
function Stroke:bbox() → x, y, w, h
function Stroke:paintTo(bb)                       -- replay this stroke to a BlitBuffer
function Stroke:toSVG() → string                  -- one <polyline> element
```

**Tasks in `strokebuffer.lua`:**
```
StrokeBuffer = { strokes = {…}, current = nil, undone = {…} }
function StrokeBuffer:penDown(x, y, p, color, width)
function StrokeBuffer:penMove(x, y, p)
function StrokeBuffer:penUp()                     -- commits current to strokes
function StrokeBuffer:undo()                      -- pops strokes → undone
function StrokeBuffer:redo()                      -- pops undone → strokes
function StrokeBuffer:eraseAt(x, y, radius)       -- removes strokes whose hitTest matches
function StrokeBuffer:repaintTo(bb)               -- repaints all strokes (used after undo/erase)
```

**Tasks in `svg.lua`:**
```
svg.write(strokebuffer, width, height) → string   -- SVG text with <metadata> JSON block
svg.read(text) → strokebuffer | nil, err          -- recovers strokes via the <metadata> block
                                                   -- if the metadata is missing, returns a
                                                   -- read-only strokebuffer with strokes
                                                   -- parsed from <polyline> elements
```

JSON in/out can use `rapidjson` (KOReader bundles it) or `dkjson` (pure Lua,
also bundled).

**Tasks in `canvas.lua`:**
- Replace direct `bb:paintLine` calls with: `strokebuffer:penMove(…)` then
  paint the new segment. Source of truth lives in the StrokeBuffer; the
  BlitBuffer is treated as a cache.
- Add a "save" trigger (we'll wire it into chrome in Stage 7; for now bind
  it to a temporary hold-zone) that writes the SVG out to a fixed test
  path.

**Definition of done:**
- A drawing session produces a valid SVG file
- Opening that SVG in a desktop browser shows the strokes exactly as drawn
- The SVG contains a `<metadata>` block with the stroke JSON inside
- `svg.read(svg.write(buffer))` round-trips strokes losslessly

---

### Stage 5 — SVG load and continue editing

**Files modified:** `canvas.lua`

**Tasks:**
- `canvas:loadPage(path)`: read the file, `svg.read` it into a StrokeBuffer,
  store it on the canvas, call `strokebuffer:repaintTo(bb)` to populate the
  visual.
- On exit, if there are unsaved changes, write back to the same path.

**Definition of done:**
- Save a drawing, close the canvas, reopen the same SVG → see the drawing,
  continue adding strokes
- The same SVG opened in a browser still renders correctly after edit

---

### Stage 6 — Notebook model

We now have working pages. Next we promote them into notebooks.

**Files added:** `model/page.lua`, `model/notebook.lua`, `model/library.lua`

**Tasks in `page.lua`:**
- Wraps a StrokeBuffer + path. `load`, `save`, `isDirty`.

**Tasks in `notebook.lua`:**
- Wraps a directory with a `notebook.lua` metadata file and a list of pages.
- `Notebook.create(name)` → makes new UUID dir + metadata + page_001.svg
- `Notebook.load(uuid)` → reads metadata, lists pages
- `notebook:addPage()`, `notebook:deletePage(idx)`, `notebook:rename(newname)`
- `notebook:save()` flushes metadata

**Tasks in `library.lua`:**
- Lists all notebooks under `<koreader_data>/fastnote/notebooks/`.
- Loads/saves `state.lua` with `last_notebook_uuid`, `last_page_index`.

**Tasks in `canvas.lua`:**
- Now operates on a `Page` and knows its parent `Notebook`.
- Adds `nextPage` / `prevPage` methods that swap the current StrokeBuffer.

**Definition of done:**
- Programmatically: create a notebook, add pages, save, exit, reopen → all
  pages restored
- `state.lua` is read on plugin open and points the canvas at the right page

---

### Stage 7 — Always-visible chrome and exit gestures

**Files added:** `ui/chrome.lua`
**Files modified:** `canvas.lua`

**Tasks:**
- Render chrome directly into the BlitBuffer (it's faster than overlaying
  another widget): a small "✕" or "⌂" in the top-left, a page indicator
  `n/N` centred at the top, a tools icon top-right.
- Chrome stays at full opacity over white background, but strokes underneath
  it would still be in the SVG and visible if they wandered there. Reserve
  a strip at the top (say 56 px) as a "no-stroke" zone — taps in it go to
  chrome handlers, pen events in it are ignored.
- Wire palm-rejected touch events to chrome handlers.
- Tap top-left chrome → if in a notebook, go to browser; if in browser, exit
  plugin.

**Definition of done:**
- Exit button is always visible and tappable, never confused for a drawing
  gesture
- Top strip rejects pen strokes (no accidental scribbles under the chrome)

> **OPEN QUESTION 3: Top-strip height and visual style**
> 56 px is a guess. On a 1264×1680 panel that's ~3.3% of the height. Too
> tall and it eats drawing area; too short and it's hard to tap accurately
> with a finger. Want a different number, or want me to leave it
> configurable in settings?

---

### Stage 8 — Hardware page buttons

**Files added:** `input/buttondev.lua`
**Files modified:** `canvas.lua`

**Tasks in `buttondev.lua`:**
- Find the device emitting `EV_KEY` events for the page buttons. On the
  Libra Colour these typically come through as `KEY_PAGEUP` / `KEY_PAGEDOWN`
  on a device whose name contains `gpio-keys` or similar. KOReader's
  `device/kobo/device.lua` has the canonical mapping for the Libra
  Colour — reuse it rather than re-discovering.
- Emit `{type="prev"}` / `{type="next"}` callbacks.

**Tasks in `canvas.lua`:**
- On "next": `notebook:nextPage()` if there is one; if at the last page,
  create a new blank page (see open question below). Save current page
  first if dirty.
- On "prev": `notebook:prevPage()` if there is one; if at the first page,
  do nothing (the back gesture is for leaving the notebook).
- Animate the page change with a single full refresh.

**Definition of done:**
- Page-forward button moves you forward through the notebook
- Page-back moves you back
- At the last page, page-forward extends the notebook by one
- Strokes are saved before the page swap (no lost work)

> **OPEN QUESTION 4: Auto-create-on-forward, or explicit "new page" button?**
> Auto-create is convenient (Goodnotes etc. behave this way). Explicit is
> safer (you can't accidentally fill a notebook with blanks by mashing the
> button). I'm proposing auto-create. Confirm or override.

---

### Stage 9 — Notebook browser

**Files added:** `ui/browser.lua`
**Files modified:** `main.lua` (wire entry routing), `canvas.lua`

**Tasks:**
- Browser is a vertical list of notebooks: name, page count, last modified
  (mtime of newest page).
- Top of the list: "+ New notebook" entry.
- Tap a notebook → open canvas on its last edited page.
- Long-press a notebook → action menu: rename / duplicate / delete.
- The browser is a normal KOReader widget (uses `Menu` or a custom
  `VerticalGroup`) — no raw evdev needed, it lives entirely on the gesture
  layer.

**Tasks in `main.lua`:**
- Routing on plugin activation:
  - Library has zero notebooks → open browser (with "create your first"
    hint)
  - `state.lua` has a `last_notebook_uuid` and it still exists → open
    canvas on that notebook + `last_page_index`
  - Otherwise → open browser

**Definition of done:**
- Browser lists notebooks, can create / rename / delete
- Opening a notebook lands on its last edited page
- Deleting the last-opened notebook gracefully falls back to the browser
  next launch

---

### Stage 10 — Eraser

We have `BTN_TOOL_RUBBER` events from Stage 2 already. The user is the one
deciding when to erase — by flipping the Stylus 2 around — so the canvas
just needs to react to "current tool = eraser."

**Files modified:** `canvas.lua`, `model/strokebuffer.lua`

**Approach:** stroke-level erase. While `tool == "eraser"`, every "move"
event calls `strokebuffer:eraseAt(x, y, ERASER_RADIUS)`, which removes any
stroke whose `hitTest` succeeds within that radius. After each removal,
trigger a partial repaint of the affected bbox.

The alternative — pixel-level erase (paint white over the BlitBuffer) — is
visually nicer but breaks the SVG-as-truth invariant. Stroke erase is
predictable, undoable, and roundtrips cleanly through SVG.

**Definition of done:**
- Flipping the pen and dragging deletes strokes under the eraser
- Repaint is correct (no smearing, no half-erased strokes)
- `BTN_TOOL_PEN` flipping back resumes drawing without restart

> **OPEN QUESTION 5: Eraser radius**
> 20 px? 40 px? Tied to display PPI (300 on the Libra Colour). I'll pick
> 24 px as a default unless you have a preference.

---

### Stage 11 — Undo / redo

**Files modified:** `model/strokebuffer.lua`, `ui/chrome.lua`

**Tasks:**
- StrokeBuffer already has `strokes` and `undone` lists from Stage 4.
- `undo()` moves last element of `strokes` to `undone`, repaints.
- `redo()` reverses.
- Erase events should also be undoable: capture the erased strokes as a
  "deletion" entry in the undo stack rather than just discarding them.
- Add two small chrome icons (or a single icon with a long-press for redo).

**Definition of done:**
- Drawing then undo restores prior state
- Erase then undo restores erased strokes
- Page change clears the undo stack (per-page undo, not cross-page) — call
  this out as a deliberate scope choice

---

### Stage 12 — Color picker

The Libra Colour can actually render color, so this is a real feature, not
a degenerate "shades of gray" picker.

**Files added:** `ui/colorpicker.lua`
**Files modified:** `canvas.lua`, `model/stroke.lua` (already has color)

**Tasks:**
- Palette: 6 colors (black, dark gray, red, blue, green, yellow). 6 is
  enough for handwritten notes; more is clutter.
- Trigger: tap the "tools" chrome icon → palette overlay appears as a
  small `ButtonDialog`.
- Selected color persists until changed; not per-stroke selected from a
  UI per stroke.
- Color is recorded per stroke in the StrokeBuffer (Stage 4 already left
  room for this).
- SVG output already supports per-stroke color from Stage 4; verify.

**Definition of done:**
- Color picker visibly opens and closes
- Changing color affects new strokes only
- Saved SVG has the right `stroke="…"` values per polyline
- Yellow on white is still legible (test on the actual Kaleido panel — it
  may not be; might need to swap to a darker yellow)

---

### Stage 13 (optional) — Polish

Anything worth doing only after the above is solid:
- Page thumbnails in the browser
- Search across notebooks (later, much later, since we have no text)
- Export entire notebook as multi-page PDF (use SVG → PDF via embedded
  Cairo or a pure-Lua converter — KOReader doesn't ship one, this is
  real work)
- Cloud sync (rsync to a Syncthing folder is the dumb-and-works route)

---

## Palm rejection in depth

Since you specifically asked about the i2c / embedded path, here's what's
actually going on under the covers and why the plan above doesn't go below
evdev.

**The hardware layout.** The Libra Colour has at least three i2c slave
devices relevant to input:

```
       i2c bus
         │
   ┌─────┼─────┬──────────────┐
   ▼     ▼     ▼              ▼
  Wacom  CTP   PMU/charger…   GPIO expander (page buttons)
  (W9013 (FT5x06 or
   class) similar)
```

Each is owned by a kernel driver. Each driver creates an evdev node. From
userspace you see:

```
/dev/input/event0  → Wacom pen
/dev/input/event1  → capacitive multi-touch
/dev/input/event2  → gpio-keys (page buttons, power)
```

(Numbering varies — discover via `/proc/bus/input/devices`.)

**What "palm rejection at the i2c level" would mean.** Three different
things, escalating in invasiveness:

1. **Cross-device gating in userspace** (the plan above). You read both pen
   and touch evdev streams. When the pen reports `BTN_TOOL_PEN=1`, you
   discard touch events. This is "two i2c devices" only in the sense that
   the two devices reach you through separate evdev nodes; you're not
   touching i2c directly. **This is what real palm rejection looks like on
   Linux tablets.** Wayland compositors and X.Org input drivers all do
   exactly this.

2. **Capacitive contact-shape analysis.** The capacitive controller exposes
   `ABS_MT_TOUCH_MAJOR` (the major axis of the contact ellipse) and on
   some chips `ABS_MT_WIDTH_MAJOR` (the sensor footprint, which is wider
   than the actual contact for a palm flattening across the array). You
   can refuse to forward any contact whose area exceeds a threshold, even
   when the pen is not in proximity. This catches the "I rested my palm
   without the pen near the screen" case. Still all userspace, just
   richer use of the existing evdev data.

3. **Talking to i2c-dev directly, bypassing the kernel driver.** You'd
   `i2cdetect` the bus, find the capacitive controller's address, unbind
   the kernel driver (`echo … > /sys/bus/i2c/drivers/<drv>/unbind`), then
   read raw register frames from `/dev/i2c-N`. You'd need to reimplement
   protocol decoding for whichever specific chip the Libra ships
   (likely FocalTech FT-series; would need to scope on the device).

   **You can do this. You shouldn't.** It buys you nothing functional —
   the controller doesn't expose richer data over raw i2c than it does
   through the kernel driver's evdev. It does break the rest of KOReader
   (no more touch UI). It's the "looking under the floorboards to see if
   they're really there" version of an embedded project.

**The interesting embedded work that IS available** if you want to flex the
muscle:

- Predictive stroke smoothing (one-Euro filter, Kalman). The Wacom report
  rate is ~133 Hz, the panel refresh is much slower, perceived latency is
  ~80–150 ms. Smoothing past the latest point reduces apparent lag without
  cheating much.
- Skip the UIManager tick scheduler for paint. Read evdev in a tight loop
  on its own coroutine, paint to the BB directly, only setDirty on
  pen-up/timer. This is "what would I do if I had no UI framework."
- Direct framebuffer writes (write the pen's local region directly to
  `/dev/fb0`, bypassing KOReader's blit pipeline). Risky — the panel
  controller wants specific waveform commands for partial refresh — but
  it's where the latency lives.

If you want to fold any of that in, it'd slot in around Stage 2 (smoothing
filter) or as Stage 14+ (latency hacking). My recommendation: get the
plugin working end-to-end first, *then* tune. Premature latency
optimization tends to produce neither.

> **OPEN QUESTION 6: Embedded depth**
> Do you want me to plan in a "Stage 14 — latency tuning / one-euro filter"
> as a first-class part of the project, or leave it as a side quest you can
> attempt once everything works?

---

## Coordinate translation (with rotation)

The Wacom digitizer reports raw integer coordinates. The screen reports
pixel dimensions. We need a mapping that respects the current screen
rotation. Pseudocode:

```lua
local function digToScreen(rx, ry, pendev, screen)
    local rmin_x, rmax_x = pendev.x_min, pendev.x_max
    local rmin_y, rmax_y = pendev.y_min, pendev.y_max
    local sw, sh = screen:getWidth(), screen:getHeight()
    local rot = screen:getRotationMode()   -- 0,1,2,3

    -- Normalize to 0..1 against the device's natural axes
    local nx = (rx - rmin_x) / (rmax_x - rmin_x)
    local ny = (ry - rmin_y) / (rmax_y - rmin_y)

    -- Then rotate
    if     rot == 0 then           return nx*sw, ny*sh
    elseif rot == 1 then           return (1-ny)*sw, nx*sh
    elseif rot == 2 then           return (1-nx)*sw, (1-ny)*sh
    elseif rot == 3 then           return ny*sw, (1-nx)*sh
    end
end
```

Calibrate on first use: ask the user to tap the four screen corners with
the pen. Store the raw coordinates of the taps in `state.lua`. Use them to
override the EVIOCGABS range and to detect axis flips (some Wacom panels
report Y in the opposite sense from the screen).

> **OPEN QUESTION 7: Corner-calibration UX**
> Show a one-time first-launch wizard ("tap the four corners in order")? Or
> trust EVIOCGABS and only fall back to a wizard if the user complains in
> a settings menu? I'd default to trust + fallback. Confirm.

---

## Open questions, gathered

1. **Storage format** — SVG-with-embedded-JSON (one file) vs SVG+separate-data (two files). Recommendation: one file.
2. **Finger drawing** — pen-only or "fingers draw too." Recommendation: pen only.
3. **Chrome strip height** — 56 px guess. Configurable?
4. **End-of-notebook page-forward** — auto-create new page, or stop? Recommendation: auto-create.
5. **Eraser radius** — 24 px default; preference?
6. **Embedded depth** — schedule a "latency tuning" stage in the main plan, or leave it as a side quest?
7. **Calibration UX** — trust EVIOCGABS, or first-launch four-corner wizard?

---

## Things deliberately not in this plan

Calling these out because someone will ask:

- **Text recognition (OCR on handwriting).** Out of scope; not feasible on
  device CPU. Plausible as an export-time step on desktop.
- **Real-time collaboration / sync.** Could be added later by syncing
  `<koreader_data>/fastnote/` via Syncthing or similar.
- **PDF / book annotation overlay.** Different problem (lives over KOReader's
  ReaderView). Could be a separate plugin reusing this one's stroke model.
- **Selection / lasso / move-strokes-around.** Possible but adds a real
  amount of UI work. Not in v1.
- **Layers.** No.

---

## Suggested execution order for a coding agent

The stages are sized so each fits inside a single agent session. The hard
dependencies are:

```
0 → 1 → 2 → 4 → 5 → 6 → 9 (browser can work on a single notebook by stage 6)
        ↓        ↓
        3        7 → 8       (chrome and buttons after pages persist)
                 ↓
                 10 → 11 → 12 → 13
```

Stages 3 and 7 don't strictly depend on each other; either can come first.
Stages 10–12 can be done in any order once 7 is done.