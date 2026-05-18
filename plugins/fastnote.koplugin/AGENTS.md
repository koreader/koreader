# AGENTS.md — fastnote.koplugin

Read this before changing any code in this directory.
Written for a coding agent or developer coming in cold.

---

## What This Plugin Does

`fastnote` is a KOReader plugin for the **Kobo Libra Colour** that provides a
full-screen hand-drawn note-taking canvas. Features (planned):

- Multi-page notebooks with a notebook browser
- Wacom EMR pen input with pressure-sensitive line width
- Palm rejection via two-device gating (pen + capacitive touch streams)
- Eraser (physical eraser end of the stylus, stroke-level delete)
- Undo / redo
- 6-color palette (Kaleido 3 panel)
- Pages saved as SVG with embedded JSON stroke data (round-trippable)

**Source of truth for design decisions:** [`dev-plan-v2.md`](dev-plan-v2.md)  
Read it before implementing any stage. It contains the open questions, the
storage layout, the coordinate translation formula, and the palm rejection
algorithm in detail.

---

## Current State

**Stage 0 complete.** The plugin skeleton exists and passes all Stage 0
criteria:
- `_meta.lua` — plugin metadata
- `main.lua` — registers Dispatcher action, adds More Tools entry, opens a stub InfoMessage
- `drawingcanvas.lua` — **empty** (Stage 1 starts here)

Stage 1 (gesture-based canvas) has not been started.

---

## File Map

```
fastnote.koplugin/
├── _meta.lua                  Plugin metadata — do not add logic here
├── main.lua                   Entry point: Dispatcher, menu, canvas open
├── drawingcanvas.lua          Drawing canvas widget (Stage 1+)
├── input/
│   ├── pendev.lua             Raw evdev Wacom reader (Stage 2)
│   ├── touchdev.lua           Raw evdev MT capacitive reader (Stage 3)
│   ├── buttondev.lua          Raw evdev page button reader (Stage 8)
│   └── palmreject.lua         Two-device gating logic (Stage 3)
├── model/
│   ├── stroke.lua             Stroke: points, color, width, hitTest, toSVG (Stage 4)
│   ├── strokebuffer.lua       Stroke list, undo stack (Stage 4)
│   ├── page.lua               One page: StrokeBuffer + load/save (Stage 6)
│   ├── notebook.lua           One notebook: page list + metadata (Stage 6)
│   └── library.lua            All notebooks + app-wide state (Stage 6)
├── ui/
│   ├── browser.lua            Notebook list widget (Stage 9)
│   ├── colorpicker.lua        Color palette overlay (Stage 12)
│   └── chrome.lua             Always-visible canvas chrome (Stage 7)
├── svg.lua                    SVG read + write (Stage 4)
├── dev-plan-v2.md             ← canonical design doc
└── PLAN.md                    ← older v1 plan (superseded by dev-plan-v2.md)
```

Files in `input/` do not exist yet (created at their respective stages).
Files in `model/` and `ui/` do not exist yet.

---

## Architecture

```
main.lua (WidgetContainer)
    └── UIManager:show(DrawingCanvas)
            └── drawingcanvas.lua (InputContainer)
                    ├── BlitBuffer (pixel backing, source of truth for display)
                    ├── StrokeBuffer (stroke list, source of truth for data)
                    │       └── each Stroke → paintTo(bb) + toSVG()
                    ├── input/ (raw evdev, Stages 2+)
                    │       ├── pendev.lua    → {type="down/move/up/hover", x, y, pressure}
                    │       ├── touchdev.lua  → MT slot events
                    │       └── palmreject.lua → gates touch through pen-proximity check
                    └── ui/chrome.lua (drawn into the same BlitBuffer)
```

**The BlitBuffer is a display cache — it can be rebuilt at any time by replaying
the StrokeBuffer.** Never treat BlitBuffer as the source of truth for stroke data.

---

## Development Loop

### In the SDL emulator (most work happens here)

```bash
cd /path/to/koreader
./kodev run
```

The emulator supports: widget rendering, BlitBuffer, file I/O, tap/pan gestures (via mouse).

It does NOT support: `/dev/input/eventX`, `EVIOCGABS`, E-Ink waveform modes, `Screen:isColorEnabled()` returning true.

**`use_raw_input` flag:** `drawingcanvas.lua` gates all evdev code behind
`Device:isKobo()` (or an explicit config flag). When false, the gesture fallback
path (`onTouch` / `onPan`) allows the canvas to work in the emulator. This
fallback path must be kept working even after Stages 2+.

### On device (for input stages)

- `input/pendev.lua`, `input/touchdev.lua`, `input/buttondev.lua` require real hardware
- Use `evtest` to inspect events before writing code: `evtest /dev/input/event0`
- Capture a palm rejection test stream: `evtest --grab /dev/input/event1 > palm_session.bin`
- Crash logs: `<onboard>/.adds/koreader/crash.log`
- Plugin reload: re-trigger the activation gesture (no full KOReader restart needed)

---

## Stage Checklist

Each stage has a "Definition of done" in `dev-plan-v2.md`. Do not close a stage
until all criteria pass. The stages in execution order:

```
0 ✅ → 1 → 2 → 4 → 5 → 6 → 9
              ↓        ↓
              3        7 → 8
                       ↓
                       10 → 11 → 12 → 13
```

Current position: **Stage 1 is next.**

---

## Coding Conventions

- **Lua dialect:** LuaJIT / Lua 5.1. See `.github/instructions/lua.instructions.md` for the full rules.
- **KOReader patterns:** See `.github/skills/koreader-plugin/SKILL.md` for widget hierarchy, BlitBuffer usage, raw evdev, coordinate translation, setDirty modes, and SVG persistence.
- **`local` everything.** Global leaks in a long-running KOReader process are hard to debug.
- **GC discipline in hot paths.** The pen poll loop runs at ~120 Hz. Do not allocate new tables per poll tick — use persistent scratch tables (see `lua.instructions.md` → Tables).
- **Error handling:** Wrap file I/O and JSON decode in `pcall`. A corrupt page file should degrade gracefully, not crash the plugin.

---

## Open Questions (from dev-plan-v2.md)

These need answers before the relevant stage is implemented. Do not guess —
surface these to the user when the stage is reached.

| # | Stage | Question | Recommendation |
|---|-------|----------|----------------|
| 1 | 4 | One SVG file per page, or SVG + separate data file? | One file |
| 2 | 3 | Fingers draw too, or pen-only? | Pen only |
| 3 | 7 | Chrome strip height — 56 px? Configurable? | 56 px, maybe configurable |
| 4 | 8 | Auto-create page on end-of-notebook page-forward? | Auto-create |
| 5 | 10 | Eraser radius — 24 px default? | 24 px |
| 6 | — | Include a "Stage 14 — latency tuning" stage? | Side quest |
| 7 | 2 | Trust EVIOCGABS range, or show first-launch corner calibration wizard? | Trust + fallback wizard in settings |

---

## Key Technical Notes

### Coordinate translation
Raw Wacom coordinates must be mapped to screen pixels. The formula is in
`dev-plan-v2.md` → "Coordinate translation." Respect `Screen:getRotationMode()`.

### SVG round-trip
`svg.read(svg.write(buffer))` must be lossless. The `<metadata>` block contains
the JSON stroke data. If the block is absent (file hand-edited externally),
fall back to a view-only mode by parsing `<polyline>` elements and setting a
`read_only` flag — never crash.

### Chrome zone
The top 56 px of the canvas is reserved for UI chrome (exit button, page
indicator, tools icon). Pen strokes in this zone are ignored. All touch events
in this zone go to chrome handlers, not to drawing.

### Undo stack scope
Undo is per-page. Crossing a page boundary clears the undo stack. This is a
deliberate scope choice — document it in comments if anyone asks.
