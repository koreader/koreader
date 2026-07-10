# Plan: config wiring + live-color refresh experiment + eraser hardening

**Status: IN PROGRESS (handoff plan — written for delegated execution)**

Two independent workstreams derived from the pencil.koplugin review
(`.agents/planning/pencil-koplugin-research.md`). Execute A before B —
both touch `fastnote.conf.example` and `main.lua`.

---

## Required reading before touching code

1. `plugins/fastnote.koplugin/AGENTS.md` — repo entry point, invariants.
2. `.github/instructions/lua.instructions.md` — Lua rules (the `_` vs `__`
   gettext rule and the `and/or` pitfall both matter in this plan).
3. `.github/instructions/eink-refresh.instructions.md` — refresh-mode rules;
   Workstream A lives entirely inside these constraints.
4. `.agents/notes/waveform-refresh-research.md` — current waveform design.
5. `.github/skills/test-driven-development/SKILL.md` — spec-first applies to
   all `lib/` changes here; `input/` FFI and widget glue are device-only.
6. `.agents/planning/pencil-koplugin-research.md` — where these fixes come
   from.

## Ground rules for the executing agent

- Work on the current branch. **Do not push. Do not create PRs.** The
  supervising session reviews, commits, and pushes.
- Test gate: `cd plugins/fastnote.koplugin && busted spec/` — must end
  **0 failures / 0 errors**, and every new behavior in `lib/` needs a spec.
- The SDL emulator/container cannot validate E-ink refresh behavior. Any
  refresh-path change must be **flag-gated, default OFF**, so shipping it
  untested on device is safe.
- Documentation rides with the code change
  (`.github/skills/documentation-as-code/SKILL.md`): update
  `fastnote.conf.example`, the waveform note's design table (only if the
  *default* design changes — a default-off flag is a "future ideas" status
  update, not a design change), this plan's checkboxes, and
  `.agents/notes/tech-debt.md` when the config item is resolved.

---

## Workstream A — config wiring + flag-gated live-color refresh

### A1. Wire `lib/config.lua` into `main.lua` (resolves tech-debt item)

`lib/config.lua` is written and spec-tested but nothing calls it — see
`.agents/notes/tech-debt.md`. Do what that note says: in `main.lua`'s
canvas-open path, `Config.load(DataStorage:getDataDir() .. "/settings/fastnote.conf")`
and pass the keys into `DrawingCanvas:new{}` as init params (`finger_draw`,
`rotation_mode` already exist as widget fields).

While in there, fix two latent problems (spec-first for both):

- **The `and/or` merge bug** (`lib/config.lua` line ~69):
  `out[k] = (cfg[k] ~= nil) and cfg[k] or v` returns the *default* when the
  user explicitly sets a key to `false` (e.g. `tighten_enabled = false`
  would silently become `true`). Replace with an explicit `if`. Add a spec
  case: explicit `false` in the file must survive the merge.
- **Stale key names:** `Config.DEFAULTS` has `develop_delay = 5` /
  `develop_enabled` from an older design; the implementation calls this the
  *tighten* pass and hardcodes `COLOR_TIGHTEN_DELAY = 2.5` in
  `drawingcanvas.lua`. These keys were never wired, so rename freely:
  `tighten_delay` (default 2.5 — match the device-tuned constant, and note
  the tuning warning from the eink-refresh instructions) and
  `tighten_enabled`. Wire them: canvas uses the config value instead of the
  hardcoded constant. Update `spec/config_spec.lua` and
  `fastnote.conf.example` (document all newly wired keys).

### A2. Flag-gated experimental live-color refresh (`live_color_refresh`)

The pencil.koplugin technique, adapted (research doc § "What fastnote could
adopt", candidate 1). New config key `live_color_refresh`, **default
`false`**. Only active when `_has_color_hw` and the raw pen path are in use.

Current behavior (`drawingcanvas.lua`): `_drawSegment` (~line 903) paints
into `self._bb` and calls `_refreshRect` (~894), which is
`UIManager:setDirty(self, "a2", rect)` per segment.

When the flag is ON, replace the per-segment path with:

1. Paint the segment into `self._bb` exactly as now (StrokeBuffer and the
   BB cache stay authoritative — ADR-002; the tighten bbox still expands).
2. Blit the dirty rect from `self._bb` to `Screen.bb`
   (`Screen.bb:blitFrom(self._bb, x, y, x, y, w, h)` — canvas is a
   full-screen widget at 0,0; verify offset assumptions against
   `paintTo`).
3. Accumulate the dirty rect into a pending union; at most once per
   `LIVE_REFRESH_INTERVAL` (new file-top constant, 0.033 s ≈ 30 fps — use
   KOReader's `ui/time` for monotonic time like the poll loops do), call
   `Screen:refreshUI(x, y, w, h)` **directly** (bypasses UIManager — this
   is the sanctioned escape hatch, see eink-refresh instructions) and clear
   the pending rect.
4. On pen "up": flush any pending rect with one final direct refresh, then
   proceed with the existing tighten scheduling unchanged.

Constraints:

- Flag OFF ⇒ behavior byte-identical to today (`"a2"` via `_refreshRect`).
  Mono hardware and the gesture/emulator path never take the new branch.
- No per-tick table allocations in the hot path beyond the accumulated-rect
  pattern already used elsewhere (see lua.instructions.md GC section);
  reuse a scratch rect table.
- Rect-union logic: extract a pure `union_rect(a, b)` into
  `lib/canvas_utils.lua` (spec-first), and refactor `_expandTightenRect`
  to use it — that's the third copy of this pattern (tighten rect, pencil
  research, now this), which is the repo's extraction threshold.
- Menu: add a toggle row ("Live color ink (experimental)") alongside the
  existing finger-draw toggle so it can be flipped on device without
  editing the conf file. Session-only toggle is fine (matches finger_draw).

Acceptance (A):

- [ ] `busted spec/` green; new specs for config merge-false, key renames,
      `union_rect`.
- [ ] `fastnote.conf.example` documents `tighten_delay`, `tighten_enabled`,
      `live_color_refresh` in the file's existing comment style.
- [ ] Flag OFF path verified unchanged by reading the diff (no behavior
      change without the flag).
- [ ] tech-debt.md: config item moved to Resolved.
- [ ] waveform-refresh-research.md "future ideas" entry for the throttled
      direct refresh updated to "implemented behind `live_color_refresh`
      (default off), pending device validation".

### A. NOT in scope

- Changing the default live waveform. A2-live stays the default until the
  device test matrix (waveform-experimentation skill) passes on hardware.
- Any `HWTCON`/ioctl-level work, or touching KOReader core.

---

## Workstream B — eraser (Fix F) hardening

Background: `.agents/plans/color-drawing-fix-and-menu-access.md` Fix F, plus
the 2026-07 external confirmation appended there: the Stylus 2 eraser end
sends `BTN_STYLUS` (level signal) while touching; the side button sends
`BTN_STYLUS2`; **some units/pens ship with the two swapped**. fastnote's
chain (`pendev.lua` ~309–330 translates `BTN_STYLUS` → SM
`BTN_TOOL_RUBBER`) is architecturally right but has gaps:

### B1. `pen_statemachine.lua` tool-reset bug (spec-first — pure lib code)

`feed_key` for `BTN_TOOL_RUBBER` value 0 (~line 68–79) clears proximity but
**leaves `tool = "eraser"` latched**. On the Wacom-direct path a subsequent
`BTN_TOUCH` without a fresh `BTN_TOOL_PEN 1` emits `down` with
`tool="eraser"` — phantom eraser. Fix: reset `tool = "pen"` when the rubber
leaves proximity. Specs to add in `spec/pen_statemachine_spec.lua`:

- rubber in → out → touch ⇒ `down` reports `tool = "pen"`.
- mid-contact tool flip (pen down → `BTN_TOOL_RUBBER 1` → move frame) ⇒
  move events report `tool = "eraser"` (this is what the canvas's
  down+move eraser check relies on — don't break it).
- eraser down → up → pen down sequence round-trips correctly.

### B2. `BTN_STYLUS2` support + `eraser_button` config

- Add `M.BTN_STYLUS2 = 0x14c` (and its debug-name entry) to
  `lib/input_codes.lua`.
- New config key `eraser_button` (via the now-wired config): `"stylus"`
  (default, current behavior) or `"stylus2"` for swapped units. `pendev.lua`
  translates the *configured* code to `BTN_TOOL_RUBBER`/`BTN_TOOL_PEN`
  exactly as it does today for `BTN_STYLUS`, and the *other* button is
  ignored for tool state but logged at `logger.dbg` (it's the side button —
  future feature surface, see research doc candidate 3).
- The translation decision ("given code, value, and the configured
  eraser_button, what do we feed the SM?") must live in a **pure function**
  so it's busted-testable — either in `lib/input_codes.lua` or a small new
  `lib/` helper — with `pendev.lua` reduced to calling it. Spec the four
  combinations (stylus/stylus2 × configured/other) plus press and release.
- `fastnote.conf.example`: document `eraser_button` including the
  symptom that tells a user they need it ("eraser end draws instead of
  erasing → try \"stylus2\"").
- Extend the existing pen-down `logger.dbg` diagnostics if needed so a
  device log unambiguously shows which button code fired.

Acceptance (B):

- [ ] `busted spec/` green; new SM and translation specs as above.
- [ ] `pendev.lua` diff is minimal — logic moved to pure lib code, FFI loop
      structure untouched.
- [ ] Fix F section in `color-drawing-fix-and-menu-access.md` updated:
      hypothesis resolved, what shipped, what remains device-only.
- [ ] `fastnote.conf.example` documents `eraser_button`.

### B. NOT in scope

- A highlighter tool or any BTN_STYLUS2-as-feature work (log-only for now).
- Changing eraser semantics (`ERASER_RADIUS`, whole-stroke vs partial).

---

## Post-merge device checklist (for the maintainer — cannot be done in CI)

1. Run the full matrix in `.github/skills/waveform-experimentation/SKILL.md`
   twice: flag off (regression) and `live_color_refresh = true`.
2. Eraser end on the physical Stylus 2: erases immediately, no drawn dot
   first; if it draws, set `eraser_button = "stylus2"` and retest; capture
   the debug log either way and paste results into Fix F.
3. If live color passes the matrix: consider flipping the default and
   updating the waveform note's design table (that's a new decision — ADR
   or note update at that point, not now).
