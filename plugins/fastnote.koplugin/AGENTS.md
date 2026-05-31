# AGENTS.md — fastnote.koplugin

Read this before changing any code in this directory.
Written for a coding agent or developer coming in cold.

---

## What This Plugin Does

`fastnote` is a KOReader plugin for the **Kobo Libra Colour** that provides a
full-screen hand-drawn note-taking canvas. Features (planned/implemented):

- Multi-page notebooks with a notebook browser
- Wacom EMR pen input with pressure-sensitive line width
- Palm rejection via two-device gating (pen + capacitive touch streams)
- Eraser (physical eraser end of the stylus, stroke-level delete) — hardware detection via `ABS_MT_TOOL_TYPE`
- Undo / redo
- Dark mode
- 6-color ink palette (Kaleido 3 panel) — infrastructure in place, Phase A
- Pages saved as SVG with embedded JSON stroke data (round-trippable)

**Target hardware:**
- Device: **Kobo Libra Colour** (model `KoboMonza`, MTK SoC, Kaleido 3 colour E-ink)
- Pen: **Kobo Stylus 2** — Wacom EMR protocol, has pen tip and eraser tip
- Digitizer: Elan combo chip on `/dev/input/event1`; handles pen and capacitive
  touch in the same node. Uses MT protocol with `ABS_MT_TOOL_TYPE` (0=finger,
  1=pen tip, 2=eraser tip). Does **not** emit `BTN_TOOL_PEN`/`BTN_TOOL_RUBBER`
  via EV_KEY — those must be synthesised from `ABS_MT_TOOL_TYPE` on contact start.

**Source of truth for design decisions:** `.agents/planning/fastnote-dev-plan-v2.md`  
Read it before implementing any stage. It contains the open questions, the
storage layout, the coordinate translation formula, and the palm rejection
algorithm in detail.

**Architecture Decision Records:** `.agents/ADRs/`  
Key non-obvious design choices (storage format, input path, undo scope, etc.)
are documented there. Check before re-opening settled questions.

---

## Workflow

**No pull requests. Commit directly to `master` and push.**  
Use descriptive commit messages — the commit log is the record of what changed and why.

The macOS CI workflow (`.github/workflows/build.yml`) is disabled for auto-triggers.
Local `busted spec/` is the test gate (208 tests, ~0.5s).

---

## Current State

**Stages 0–12 partially complete** (208/208 busted tests passing).

Stage 12 progress:
- ✅ Input event debug logger (`lib/eventlog.lua`, `PenDev.raw_log_fn`, hamburger toggle)
- ✅ Color model (`lib/color.lua`): 6-color PALETTE with light/dark variants, `Color.resolve`, `Color.is_achromatic`
- ✅ `StrokeBuffer:repaintTo` accepts a per-stroke `function(hex) → BlitBuffer color` (backward-compatible)
- ✅ Deferred colour develop refresh: `_scheduleDevelop` / `_developColor`, `utils.union_rect`
- ⏳ Eraser diagnosis: blocked on device SSH access (see Part 2 in plan)
- ⏳ Device validation of develop refresh and colour palette on-device

**Stages 6, 8, 9** code is complete but needs on-device validation:
- Stage 6: notebooks should appear at `<datadir>/fastnote/notebooks/<uuid>/`
- Stage 8: RPgFwd/RPgBack hardware buttons should turn pages
- Stage 9: notebook browser list/create/rename/delete

Completed work:
- Config system (`lib/config.lua`) with `finger_draw` toggle and `rotation_mode`
- Chrome strip: exit button (left), page indicator (center), hamburger menu (right)
- Hamburger menu: rotation toggle, eraser toggle, dark mode, finger draw, save, clear page, close
- Orientation lock — canvas locks rotation on open; re-locks on system rotation events
- Stroke model (`lib/stroke.lua`, `lib/strokebuffer.lua`) — source of truth for all drawing
- SVG persistence (`lib/svg.lua`) — `svg.write`/`svg.read` with lossless `<metadata>` JSON round-trip
- Palm rejection (`lib/palmreject.lua`) — pen-proximity gate + area threshold, injectable clock
- Capacitive touch input (`input/touchdev.lua`) — MT protocol B, non-blocking poll
- `drawingcanvas.lua`: StrokeBuffer integration, `_digToScreen` rotation-aware coordinate translation,
  finger-draw toggle, SVG save, eraser mode (stroke-level), dark mode (inverts all stroke colors),
  clear page (with confirm dialog), undo/redo, hardware page-button callbacks
- Stage 5 SVG round-trip: `loadPage(path)`, auto-save on close, `on_save_callback`
- Stage 6 notebook model: `model/library.lua`, `model/notebook.lua`, `model/page.lua`;
  `main.lua` routes open to last-used notebook/page via `state.lua`
- Stage 8 page navigation: `on_page_forward`/`on_page_back` callbacks, `_autoSave` before page turn
- Stage 10 eraser: stroke-level `eraseAt(x, y, radius)` in StrokeBuffer + canvas menu toggle
- Stage 11 undo/redo: push/pop stack in StrokeBuffer
- On-device fixes: Elan combo chip MT protocol, coordinate axis mapping (`_dig_rot_base`),
  gyroscope auto-rotation lock, hover-writes-on-screen fix (pressure-based BTN_TOUCH synthesis),
  gesture straight-line bug fix (ges.start_pos boundary detection)

### Known hardware notes (Kobo Libra Colour / KoboMonza)
- The Elan combo chip on event1 handles **both** pen and touch in the same device node
  (MT protocol: ABS_MT_TOOL_TYPE 1=pen, 0=finger). The separate "capacitive touch" device
  described in dev-plan-v2.md may not exist as a separate node. If `TouchDev.find()` fails,
  the canvas still works — palm rejection is simply disabled.

---

## File Map

```
fastnote.koplugin/
├── _meta.lua                  Plugin metadata — do not add logic here
├── main.lua                   Entry point: config load, Dispatcher, canvas open, notebook routing
├── drawingcanvas.lua          Drawing canvas widget — all input, rendering, menu, orientation
├── fastnote.conf.example      Documented user config (finger_draw, rotation_mode)
├── lib/
│   ├── canvas_utils.lua       Pure math: compute_dirty_rect, point_in_zone, pressure_to_width
│   ├── config.lua             Pure Lua config loader (loadfile + pcall + merge)
│   ├── pen_statemachine.lua   Wacom evdev state machine → high-level pen events
│   ├── json.lua               Pure Lua JSON encoder/decoder (no KOReader deps; busted-testable)
│   ├── stroke.lua             Stroke object: points, hitTest, bbox, paintTo, toTable/fromTable
│   ├── strokebuffer.lua       Stroke list, undo/redo stack, eraseAt, repaintTo, serialization
│   ├── svg.lua                svg.write() + svg.read() with <metadata> JSON block
│   └── palmreject.lua         Proximity-gated palm rejection state machine
├── input/
│   ├── pendev.lua             FFI: finds Wacom/Elan, opens fd, polls events → pen_statemachine
│   └── touchdev.lua           FFI: MT protocol B reader for capacitive touch
├── model/
│   ├── notebook.lua           One notebook: ordered page list + metadata
│   └── library.lua            All notebooks + app-wide state
├── ui/
│   ├── browser.lua            Notebook list widget (Stage 9)
│   ├── colorpicker.lua        [Stage 12] Color palette overlay
│   └── chrome.lua             [Stage 7†] Always-visible canvas chrome
├── spec/
│   ├── canvas_utils_spec.lua
│   ├── color_spec.lua
│   ├── config_spec.lua
│   ├── eventlog_spec.lua
│   ├── library_spec.lua
│   ├── notebook_spec.lua
│   ├── palmreject_spec.lua
│   ├── pen_statemachine_spec.lua
│   ├── stroke_spec.lua
│   ├── strokebuffer_spec.lua
│   └── svg_spec.lua
└── dev-plan-v2.md             ← kept here for convenience; canonical copy in .agents/planning/
```

`[Stage N]` = file does not exist yet.  
`†` = chrome and button logic is integrated into `drawingcanvas.lua` rather than standalone files.

---

## Architecture

```
main.lua
    └── UIManager:show(DrawingCanvas)
            └── drawingcanvas.lua (InputContainer)
                    ├── BlitBuffer (display cache — rebuilt by replaying StrokeBuffer)
                    ├── StrokeBuffer (source of truth for stroke data)
                    │       └── each Stroke → paintTo(bb) + toTable() + SVG polyline
                    ├── input/ (raw evdev, Stages 2+)
                    │       ├── pendev.lua    → pen_statemachine → {down/move/up/hover}
                    │       └── touchdev.lua  → MT slot events
                    └── lib/palmreject.lua → filters touch through pen-proximity gate
```

**The BlitBuffer is a display cache** — it can be rebuilt at any time by replaying the StrokeBuffer.
Never treat BlitBuffer as the source of truth for stroke data. (See ADR-002.)

**Dual-path invariant:** `use_raw_input = Device:isKobo()`. Emulator always uses the gesture
layer (`onDrawStroke`/`onDrawStrokeEnd`). Device always uses raw evdev poll loop (`_pollPen`).
Both paths must keep working. Do not break the emulator path when adding device features.
(See ADR-003.)

---

## Development Loop

### In the SDL emulator (most work happens here)

```bash
cd /path/to/koreader
./kodev run
```

The emulator supports: widget rendering, BlitBuffer, file I/O, tap/pan gestures (via mouse).

It does NOT support: `/dev/input/eventX`, `EVIOCGABS`, E-Ink waveform modes.
`Screen:isColorEnabled()` returns false in the emulator — this is now bypassed;
colour buffer selection uses `Device:hasKaleidoWfm()` / `Screen:isColorScreen()`
instead (both return false in SDL, so BB8 is used in the emulator as expected).

### Running unit tests

```bash
cd plugins/fastnote.koplugin
busted spec/
```

All spec files under `spec/` are pure Lua — no KOReader runtime needed.
The `lib/` and `model/` modules have no KOReader/FFI dependencies.
The `input/` modules do (they use FFI) and are not unit-testable; test them on device.

### On device

- Use `evtest` to inspect events: `evtest /dev/input/event0`
- Crash logs: `<onboard>/.adds/koreader/crash.log`
- Notebook data: `<onboard>/.adds/koreader/fastnote/notebooks/<uuid>/`
- Plugin reload: re-trigger the activation gesture (no full KOReader restart needed)

---

## Stage Checklist

```
0 ✅ → 1 ✅ → 2 ✅ → 4 ✅ → 5 ✅ → 6* → 9*
                ↓                    ↓
                3 ✅                  7 ✅ → 8*
                                     ↓
                                     10 ✅ → 11 ✅ → 12▶ → 13
```

`*` Code complete; needs on-device validation.  
`▶` In progress — logger + color + develop done; eraser fix blocked on device.

### Remaining stages

| Stage | What | Status |
|-------|------|--------|
| 6 | Notebook model (`model/*.lua`, `main.lua` routing) | code done, needs device test |
| 8 | Hardware page buttons — prev/next page | code done, needs device test |
| 9 | Notebook browser UI — list/create/rename/delete | code done, needs device test |
| 12 | Color picker + deferred develop refresh | logger/color/develop done; eraser fix pending device |
| 13 | Optional polish — thumbnails, PDF export | not started |

---

## Coding Conventions

- **Lua dialect:** LuaJIT / Lua 5.1. See `.github/instructions/lua.instructions.md` for the full rules.
- **KOReader patterns:** See `.github/skills/koreader-plugin/SKILL.md` for widget hierarchy, BlitBuffer usage, raw evdev, coordinate translation, setDirty modes, and SVG persistence. *(Skill file not yet added — coming from the author's skill library.)*

### Rules that have already caused real bugs — read these first

**`_` is gettext, not a throwaway.** Every KOReader plugin starts with
`local _ = require("gettext")`. Using `_` as a loop variable shadows it and
crashes any `_("string")` call in the same scope:

```lua
-- WRONG — crashes with "attempt to call a number"
for _, item in ipairs(list) do
    label = _("Name")
end

-- RIGHT — use __ (double underscore; .luacheckrc already suppresses warnings for it)
for __, item in ipairs(list) do
    label = _("Name")
end
```

**No cryptic single-letter names.** `t`, `s`, `pd`, `e` have all introduced real bugs
in this codebase. Use full words (`pressure_ratio`, `slot`, `pen_data`, `event`).
See `lua.instructions.md` → "Variable naming" for the acceptable exceptions.

**Extract repeated blocks.** Three copies of the same code need a named helper.
See the `_doEraseAt` / `_drawSegment` / `_refreshRect` helpers in `drawingcanvas.lua`
for recent examples.

**Named constants for magic numbers.** File-top `local UPPER_CASE = value`.
`PEN_POLL_INTERVAL`, `TOUCH_POLL_INTERVAL`, `IDLE_SAVE_DELAY` in `drawingcanvas.lua`
show the pattern.

### General

- **`local` everything.** Global leaks in a long-running KOReader process are hard to debug.
- **GC discipline in hot paths.** The pen poll loop runs at ~120 Hz. Do not allocate new tables per poll tick — use persistent scratch tables (see `lua.instructions.md` → GC pressure).
- **Error handling:** Wrap file I/O and JSON decode in `pcall`. A corrupt page file should degrade gracefully, not crash the plugin.

---

## Open Questions

| # | Stage | Question | Status |
|---|-------|----------|--------|
| 3 | 7 | Chrome strip height — 56 px? Configurable? | 56 px fixed for now |
| 6 | — | Include a "Stage 14 — latency tuning" stage? | Side quest |
| 7 | 2 | Trust EVIOCGABS range, or show first-launch corner calibration wizard? | Trust + fallback wizard in settings |

---

## Key Technical Notes

### Coordinate translation
Raw Wacom coordinates must be mapped to screen pixels. See `.agents/planning/fastnote-dev-plan-v2.md`
→ "Coordinate translation." Respect `Screen:getRotationMode()`.
`drawingcanvas.lua:_digToScreen(rx, ry)` implements all four rotation modes using
normalized coordinates: `nx = (rx - x_min) / (x_max - x_min)`.

### SVG round-trip
`svg.read(svg.write(buffer))` must be lossless. The `<metadata>` block contains
the JSON stroke data. If the block is absent (file hand-edited externally),
fall back to parsing `<polyline>` elements — never crash. (See ADR-001.)

### Hover suppression
The Elan chip fires `EV_KEY BTN_TOUCH=1` at ~10 mm proximity, not contact.
`pendev.lua` intercepts this and synthesizes BTN_TOUCH from `ABS_MT_PRESSURE`
instead. See ADR-004.

### ffi.cdef idempotency
`input/pendev.lua` defines `struct fn_input_absinfo` at module level guarded by
`pcall(ffi.cdef, ...)`. LuaJIT throws on duplicate struct declarations; never
put `ffi.cdef` inside a function that may be called more than once.

### Chrome zone
The top 56 px of the canvas is reserved for UI chrome (exit button, page
indicator, tools icon). Pen strokes in this zone are ignored.

### Input path architecture
Two mutually exclusive code paths exist, selected by `use_raw_input = Device:isKobo()`:

| Path | When active | Entry point | Notes |
|------|------------|-------------|-------|
| **Gesture layer** | `use_raw_input = false` (emulator) | `onDrawStroke` / `onDrawStrokeEnd` | Receives KOReader gesture objects |
| **Raw evdev** | `use_raw_input = true` (Kobo device) | `_pollPen` / `_pollTouch` | Reads `/dev/input/eventX` via FFI |

**Flag scope:** `finger_draw` is checked on **both** paths — gesture-path guard at `onDrawStroke:5` and `_pollTouch` filter on `if filtered and self.finger_draw`. `_eraser_locked` (menu toggle) is honored on both paths. Hardware eraser detection (`ev.tool == "eraser"`) is raw-path only.

**Stroke color invariant (updated Stage 12):** Strokes are always stored with the **light-mode hex** as the canonical `Stroke.color` (e.g. `"#cc2222"`). `penDown` always receives `self._current_color` (hex). Dark mode is a **display-only transform**: `_repaintAll` now passes a `function(stored_hex) → BlitBuffer color` resolver (using `Color.resolve`) to `repaintTo`; stroke data is never mutated. Live strokes use `_strokeColor()` → `Color.resolve(_current_color, _dark_mode)`. See ADR-006.

**Eraser detection (hardware — KoboMonza/Elan combo chip):**
`ABS_MT_TOOL_TYPE=2` is **never emitted** on this device — the Elan chip always reports `TOOL_TYPE=1` (pen) for both pen tip and eraser tip. The eraser is identified via `EV_KEY BTN_STYLUS (0x14B)` instead:
- `BTN_STYLUS=1` fires when the eraser tip contacts the screen
- `BTN_STYLUS=0` fires when the eraser tip lifts

`pendev.lua` intercepts BTN_STYLUS in the EV_KEY handler and translates:
- `BTN_STYLUS=1` → `sm:feed_key(BTN_TOOL_RUBBER, 1, nil)` (overrides the BTN_TOOL_PEN=1 that TOOL_TYPE=1 already fed in the same frame)
- `BTN_STYLUS=0` → `sm:feed_key(BTN_TOOL_PEN, 1, nil)` (restore pen mode for next contact)

Diagnosed via the input event logger (Stage 12c+). See ADR-006.

### Undo stack scope
Undo is per-page. Crossing a page boundary clears the undo stack. See ADR-005.

### Input event debug logger (Stage 12c+)
`lib/eventlog.lua` is a standalone line-buffered append log. `DrawingCanvas:_toggleInputLog()` (hamburger menu row) opens/closes it and wires/clears `PenDev.raw_log_fn` — a module-level hook on `input/pendev.lua` that captures every raw `input_event` before decoding. Decoded events are logged separately inside the `_pollPen` callback.

To diagnose eraser issues on device:
```bash
ssh root@<device-ip> "tail -F /mnt/onboard/.adds/koreader/fastnote/input.log"
```
Then press the eraser tip and look for `RAW EV_KEY BTN_STYLUS 1`. Note: `ABS_MT_TOOL_TYPE=2` is **never emitted** on KoboMonza — see Eraser detection note above.

### E-Ink waveforms (Kobo Libra Colour)

| Waveform | KOReader arg | Speed | Ghosting | Colour? | Use case |
|----------|-------------|-------|----------|---------|----------|
| **A2** | `"a2"` | ~120 ms | High (accumulates) | **No — luminance threshold to B/W only** | Active pen draw, every segment |
| **DU** | `"ui"` or `"partial"` (no flag) | ~260 ms | Low | No | Menu/UI interactions, button taps |
| **GC16** | `"partial", nil, true` (allow\_color) | ~450 ms | Very low | **Yes — full Kaleido CFA colour** | Colour develop refresh after pen idle |
| **Full flash** | `"full"` | ~600 ms | Clears all | No | Page clear, major layout changes |

**A2 visibility constraint:** A2 maps luminance to pure black or white — there is no middle ground. Saturated ink colours have medium luminance and may threshold to the same value as the background:
- **Light mode** (white bg): red `#cc2222` ≈ luma 0.33 → may render as **white on white = invisible**
- **Dark mode** (black bg): same colour would render as black on black = invisible

**Fix applied in `_drawSegment`:** On colour hw, live strokes always draw in the **mode-foreground colour** (black in light mode, white in dark mode) for immediate A2 visibility. True ink colour is restored by `_developColor()` after pen idle.

**Partial+rect Kaleido:** `_developColor` uses `"partial", Geom:new(dirty_rect), true` — GC16 colour refresh scoped to the accumulated dirty region only. No whole-screen flash; only the area you drew in flickers with the colour waveform.

### Color model (Stage 12)
`lib/color.lua` owns the 6-color palette with light/dark Kaleido 3 variants. Key invariant: **stored hex is always the light variant** (canonical on-disk form). Use `Color.resolve(hex, dark_mode)` to get the display color. Dark mode automatically uses brighter variants (e.g. red: `#cc2222` light → `#ff5555` dark) — this is purely a display transform, stored hex is never mutated.

`StrokeBuffer:repaintTo(bb, color_fn)` now accepts a `function(stored_hex) → BlitBuffer color` as the second argument in addition to a flat BlitBuffer color (nil = use stored color). Backward-compatible: all existing callers passing nil or a flat color still work.

### Deferred colour develop refresh (Stage 12)
After each pen-up, `_scheduleDevelop()` arms a `DEFAULT_DEVELOP_DELAY` (5 s) timer — **but only if the current ink colour is chromatic** (`Color.is_achromatic` gate). Drawing black or white ink never schedules a develop; A2 already renders those correctly at full resolution with no GC16 flash.

When the timer fires, `_developColor()`:
1. Rebuilds the full BB: `fill(bgColor)` + `repaintTo(bb, color_fn)` — all strokes rendered in their stored colours
2. Fires `UIManager:setDirty(self, "partial", Geom:new(dirty_rect), true)` — GC16 colour waveform scoped to the accumulated dirty region only

**Important:** develop restores each stroke to *its own stored colour*, not the current ink selection. A previously-drawn black stroke stays black; a previously-drawn red stroke becomes red. The current selection only affects strokes drawn after it was chosen.

`_dirty_since_develop` is a `{x,y,w,h}` accumulator (union_rect per segment) used both as a "did anything get drawn?" guard and as the rect for the GC16 refresh. Cleared after each develop. No-op when `_develop_enabled = false`.

### Orientation lock
`drawingcanvas.lua` stores `self._rotation_mode` (the locked mode). On
`onSetRotationMode(event)`, if the incoming mode differs from `self._rotation_mode`, the
canvas calls `Screen:setRotationMode(self._rotation_mode)` to re-lock. No loop guard
is needed because the second re-lock call sees `new_mode == self._rotation_mode`.

### self.dimen mutation — IN-PLACE only
GestureRange objects inside `self.ges_events` hold a direct reference to the `self.dimen`
table created at init. **Never assign a new table** to `self.dimen` — mutate its fields in-place.

### Gesture zone registration timing
Touch zones must be registered in `init()` — not in `onShow`. The DrawStroke/DrawStrokeEnd
zones are **always registered**; handlers check `self.use_raw_input` and `self.finger_draw`
at runtime. This allows the `finger_draw` toggle to work without re-registering zones.
