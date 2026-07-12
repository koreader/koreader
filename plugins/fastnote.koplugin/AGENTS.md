# AGENTS.md — fastnote.koplugin

Read this before changing any code in this directory.

**This file is an index, not a reference manual.** It tells you what exists
and where — not how it works or why it was built that way. Every linked file
below is self-contained; open it only when your task touches that topic.
Don't duplicate linked content back into this file when editing it.

**Editing this file or adding to `.agents/`?** Read
`.github/skills/agents-md-authoring/SKILL.md` (repo root) first — it has the
decision tree for where new content goes and the checklist this file is
held to.

---

## What This Plugin Does

`fastnote` is a KOReader plugin for the **Kobo Libra Colour** that provides a
full-screen hand-drawn note-taking canvas: multi-page notebooks, Wacom EMR
pen input with pressure and hardware eraser detection, palm rejection, dark
mode, a 6-color ink palette, undo/redo, and SVG-based page storage.

**Target hardware:** Kobo Libra Colour (`KoboMonza`, MTK SoC, Kaleido 3
color E-ink). Pen: Kobo Stylus 2 (Wacom EMR, pen + eraser tips). Digitizer:
Elan combo chip on `/dev/input/event1` — handles pen **and** capacitive
touch in the same device node via MT protocol.

---

## Where design decisions live

All paths below are relative to the **repo root** (`.agents/` is not inside
this plugin directory):

- **`.agents/planning/fastnote-dev-plan-v2.md`** — canonical design doc:
  storage layout, coordinate translation formula, palm rejection algorithm,
  stage-by-stage build plan, open questions. Read before implementing
  anything non-trivial.
- **`.agents/ADRs/`** — one file per settled architectural decision
  (storage format, dual input path, undo scope, notebook layout, workflow).
  Check before re-opening a question that's already been decided.
- **`.agents/notes/`** — topic references for specific gotcha-prone areas
  of the code (see "Topics" table below).
- **`.agents/plans/`** — chunk-level implementation plans, mostly historical.
- **This plugin's own `.agents/planning/next-stages-plan.md`** — an older
  phase plan; largely superseded, see the status banner at its top.

---

## Workflow

**No pull requests. Commit directly to `master` and push.**
Local `busted spec/` is the test gate (run from this directory).
The macOS CI workflow (`.github/workflows/build.yml`) is manual-trigger only.

---

## Current State

Core drawing, palm rejection, SVG persistence, notebook browser, eraser,
undo/redo, dark mode, and the 6-color palette are all implemented and
passing `busted spec/`. Remaining open item: Stage 13 (optional polish —
thumbnails, PDF export), not started. For the full stage-by-stage status,
see `.agents/planning/fastnote-dev-plan-v2.md`.

**Known hardware quirk:** the Elan combo chip handles pen and touch on the
**same** device node (`event1`), not separate nodes as the original design
doc assumed. If `TouchDev.find()` fails, the canvas still works — palm
rejection is simply disabled.

---

## File Map

```
fastnote.koplugin/
├── _meta.lua                  Plugin metadata — do not add logic here
├── main.lua                   Entry point: config load, canvas open, notebook routing
├── drawingcanvas.lua          Drawing canvas widget — ALL input, rendering, menu, orientation,
│                              chrome strip, and quick-menu color picker (no separate files for these)
├── fastnote.conf.example      Documented user config (finger_draw, rotation_mode, tighten_*, live_color_refresh, eraser_button, live_ink_style)
├── lib/
│   ├── canvas_utils.lua       Pure math: compute_dirty_rect, point_in_zone, pressure_to_width
│   ├── config.lua             Pure Lua config loader, wired via main.lua's canvas-open path
│   ├── input_codes.lua        Shared Linux input event constants (BTN_*/ABS_*, incl. BTN_STYLUS2)
│   ├── eraser_button.lua      Pure translation: BTN_STYLUS/BTN_STYLUS2 event → eraser tool state
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
│   └── library.lua            All notebooks + app-wide state (last-used notebook/page)
├── ui/
│   └── browser.lua            Notebook list widget: list/create/rename/delete
├── spec/                      One *_spec.lua per lib/model file above (busted, no KOReader runtime needed)
└── dev-plan-v2.md             Convenience copy; canonical version in .agents/planning/ (repo root)
```

The `input/` modules use FFI and are not unit-testable — validate on device.
Everything else under `spec/` runs headless.

---

## Architecture

```
main.lua
    └── UIManager:show(DrawingCanvas)
            └── drawingcanvas.lua (InputContainer)
                    ├── BlitBuffer (display cache — rebuilt by replaying StrokeBuffer)
                    ├── StrokeBuffer (source of truth for stroke data)
                    ├── input/ (raw evdev on device)
                    │       ├── pendev.lua    → pen_statemachine → {down/move/up/hover}
                    │       └── touchdev.lua  → MT slot events
                    └── lib/palmreject.lua → filters touch through pen-proximity gate
```

Two invariants that, if violated, reintroduce fixed bugs:

- **BlitBuffer is a display cache, never the source of truth.** StrokeBuffer
  is authoritative. See ADR-002.
- **`use_raw_input = Device:isKobo()` selects gesture vs. raw-evdev input.**
  Both paths must keep working. See ADR-003 and
  `.agents/notes/input-path-architecture.md`.

---

## Development Loop

```bash
cd /path/to/koreader && ./kodev run        # SDL emulator — most work happens here
cd plugins/fastnote.koplugin && busted spec/   # unit tests, ~2s
```

The emulator has no `/dev/input/eventX`, no `EVIOCGABS`, no E-ink waveform
modes — it renders widgets/BlitBuffer/gestures only. Raw input and refresh
behavior require on-device testing (`evtest` for event inspection; crash
log at `<onboard>/.adds/koreader/crash.log`).

**Before adding or fixing anything in `lib/`, `model/`, or `spec/`:** read
`.github/skills/test-driven-development/SKILL.md` (repo root) — it covers
when to write the spec first in this codebase and when the raw-evdev /
widget code genuinely can't be unit-tested.

---

## Coding Conventions

- **Lua dialect:** LuaJIT / Lua 5.1 — see `.github/instructions/lua.instructions.md`
  (repo root) for the full rules and the bugs each rule prevents.
- Read the Lua instructions file before writing anything — it covers the `_`
  vs `__` gettext gotcha and other rules that have already caused real bugs
  in this codebase.
- **Documentation changes ride with the code change that needs them** — see
  `.github/skills/documentation-as-code/SKILL.md` (repo root) for what moves
  together (doc comments, ADRs, config examples, AGENTS.md's File Map).
- **E-ink refresh / waveform changes:** hard rules in
  `.github/instructions/eink-refresh.instructions.md`; on-device test
  procedure in `.github/skills/waveform-experimentation/SKILL.md` (both
  repo root).

---

## Topics

Deep-dive references for specific areas. Load the one relevant to your task;
skip the rest.

| Topic | What it covers | File (repo root `.agents/`) |
|-------|-----------------|------------------------------|
| Color / dark mode | Canonical hex storage invariant, why dark mode must be display-only | `notes/stroke-color-invariant.md` |
| E-ink refresh / waveforms | Kaleido color waveform modes, A2-live + deferred GLRC16 tighten-pass design | `notes/waveform-refresh-research.md` |
| Input path architecture | Gesture vs. raw-evdev, per-flag scope, hardware eraser detection | `notes/input-path-architecture.md` |
| Canvas widget lifecycle | `self.dimen` mutation rule, orientation re-lock, gesture zone timing | `notes/canvas-widget-gotchas.md` |
| Known tech debt | Deferred cleanup items and their resolutions | `notes/tech-debt.md` |
| Storage format | SVG + embedded JSON metadata | `ADRs/ADR-001-svg-with-embedded-json-metadata.md` |
| Source of truth | StrokeBuffer vs. BlitBuffer | `ADRs/ADR-002-strokebuffer-as-source-of-truth.md` |
| Dual input path | Why raw evdev + gesture fallback both exist | `ADRs/ADR-003-dual-path-raw-evdev-plus-gesture-fallback.md` |
| Hover suppression | Pressure-based BTN_TOUCH synthesis | `ADRs/ADR-004-pressure-based-btn-touch-synthesis.md` |
| Undo scope | Why undo is per-page | `ADRs/ADR-005-per-page-undo-stack.md` |
| Notebook storage layout | UUID directory layout | `ADRs/ADR-006-uuid-directory-layout-for-notebooks.md` |
| Coordinate translation | Rotation-aware raw-to-screen mapping formula | `planning/fastnote-dev-plan-v2.md` → "Coordinate translation" |
