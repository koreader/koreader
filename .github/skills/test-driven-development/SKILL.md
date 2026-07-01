---
name: test-driven-development
description: Use when adding a new function or module to lib/ or model/, fixing a bug in code covered by spec/, or refactoring already-tested code in this repo. Explains when the red-green-refactor cycle applies and when it doesn't (FFI/device-only code under input/, KOReader widget glue in drawingcanvas.lua, exploratory design work), and follows the busted spec/ conventions already used in plugins/fastnote.koplugin/spec/.
---

# Test-driven development — where appropriate

TDD means: when you already know the desired behavior before the
implementation exists, write the test first (red), write the minimal code
to pass it (green), then improve the code with the test as a guardrail
(refactor). It is not "write a test for everything, always" — it's most
valuable exactly where this repo already concentrates its test coverage:
pure Lua logic with no runtime dependency.

---

## This repo's test seam

Whether TDD applies is mostly decided by which directory the code lives in:

| Location | Testable? | Practice |
|----------|-----------|----------|
| `lib/`, `model/` | Yes — pure Lua, no KOReader/FFI deps, runs under `busted` | TDD by default: write the spec first |
| `input/` (`pendev.lua`, `touchdev.lua`) | No — FFI-backed, reads real `/dev/input` device files | Write a short on-device test plan before implementing; verify manually after |
| `drawingcanvas.lua` | Mostly no — depends on KOReader's `UIManager`/`Screen`/`BlitBuffer` runtime, not available under `busted` | Extract pure logic into `lib/` first (see below), TDD the extracted piece; verify the remaining thin glue in the emulator or on-device |

`lib/canvas_utils.lua` exists **because of** this seam: `compute_dirty_rect`,
`pressure_to_width`, and `drawLine` were pulled out of the canvas widget
specifically so they could be unit tested, leaving `drawingcanvas.lua` as
thin, mostly-untestable glue around them. When you're about to add logic to
`drawingcanvas.lua`, ask first whether it's actually pure computation that
belongs in `lib/` instead — if yes, it gets a spec; if no (it's genuinely
tied to `UIManager`/`Screen`/widget state), it doesn't, and that's fine.

---

## Decision: does this change get a test-first treatment?

- **New pure function or module in `lib/` or `model/`?**
  → Yes. Write the `describe`/`it` block first, watch it fail, implement,
  watch it pass.

- **Bug in code covered by an existing `spec/*_spec.lua`?**
  → Yes. Write a failing spec that reproduces the bug *before* touching the
  implementation, confirm it fails for the right reason, then fix until
  green. Real example in this repo: the eraser-flips-mid-stroke bug was
  fixed in `lib/pen_statemachine.lua` alongside two new regression tests in
  `spec/pen_statemachine_spec.lua` — `"'move' event carries the current
  tool ('pen' default)"` and `"'move' tool reflects BTN_TOOL_RUBBER fired
  mid-stroke"` — added in the same commit as the fix, not after.

- **Refactor of already-tested code?**
  → Yes, tests must stay green throughout the refactor. If the code being
  refactored has thin or no coverage, write characterization tests first —
  tests that lock in current behavior (even undocumented behavior) — so the
  refactor has a safety net before you start moving things around.

- **New code in `input/` (FFI, real device files)?**
  → No unit-test-first — there's no harness for `/dev/input` under
  `busted`. Instead, write the on-device test plan (concrete steps +
  expected observation) *before* implementing, same discipline as TDD
  applied to manual verification instead of an automated spec. See the
  "Bug 5 — Eraser detection" test plan in
  `plugins/fastnote.koplugin/.agents/planning/next-stages-plan.md` for the
  shape this takes.

- **New widget/UI glue in `drawingcanvas.lua`?**
  → No unit-test-first for the glue itself. First ask "can this be
  extracted into `lib/` instead?" — if yes, TDD the extracted piece and
  leave the glue as a thin call site. If the logic is genuinely tied to
  `UIManager`/`Screen` state (e.g. scheduling a refresh, allocating a
  BlitBuffer), it isn't testable under `busted`; verify it in the SDL
  emulator (`./kodev run`) or on-device instead. This repo's color-drawing
  refresh work (the `_scheduleTighten`/`_cancelTighten` timer logic) is a
  real example — it's pure `UIManager` scheduling, no unit test possible,
  verified by the on-device behavior it was designed to produce.

- **Exploratory or spike work where the right interface isn't known yet?**
  → No test-first. Spike freely to find the shape of the solution. Once the
  design stabilizes, extract the reusable logic into a `lib/`/`model/`
  module and backfill specs for it before it's considered done — don't
  leave a spike's logic un-tested permanently just because it started as a
  spike.

---

## The loop, using this repo's actual tooling

1. Write the `describe(...)`/`it(...)` block in the relevant
   `spec/<module>_spec.lua` first.
2. Run it (`busted spec/<module>_spec.lua` from the plugin root) and
   confirm it fails **for the reason you expect** — not a typo or a
   `require` error. A test that fails for the wrong reason proves nothing.
3. Write the minimal implementation change to make it pass.
4. Refactor with the test green as a guardrail.
5. Before committing, run the **full** suite (`busted spec/`), not just the
   file you touched — a change in a shared module like
   `lib/canvas_utils.lua` can affect callers exercised by other spec files.

---

## Test structure conventions (match these in new specs)

Based on the existing `spec/*_spec.lua` files:

- One `describe("ModuleName", ...)` per module; nested `describe(...)` per
  method or feature grouping; `-- ── section ── ` comment dividers between
  groups (see `spec/strokebuffer_spec.lua` for the pattern).
- One behavior per `it(...)`; name the *behavior*, not the implementation —
  `"penUp with a single-point stroke discards it"`, not `"test penUp case
  3"`. The name should make sense as a spec even if you never read the
  body.
- No mocking framework in use, and none should be needed for `lib/`/`model/`
  code — pure Lua modules make real dependencies cheap to construct
  directly (`StrokeBuffer.new()`, not a mock).
- `package.path = package.path .. ";fastnote.koplugin/?.lua"` at the top of
  every spec file, then a direct `require` — copy this line, don't
  reinvent the path setup.
