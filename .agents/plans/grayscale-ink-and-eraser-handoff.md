# Handoff: plugin-side grayscale ink + eraser-still-draws investigation

**RETRACTED then FIXED (2026-07).** An earlier version of this status
concluded "downstream of KOReader, not a software bug" on the strength of
a captured `WFM: 10` (`HWTCON_WAVEFORM_MODE_GCC16`) log line, reasoning
that a genuinely-requested color waveform mode proved the whole chain
correct. **That conclusion was wrong**, and was falsified within the same
conversation turn: the maintainer reported color renders correctly in
KOReader's own features and in other plugins (pencil.koplugin) on this
exact device. Since the kernel driver and EPDC firmware are shared,
process-wide singletons, a driver/firmware/panel fault could not
selectively fail for one caller while working for others in the same
running KOReader process — the `WFM: 10` finding was real (the promotion
logic genuinely is correct) but didn't rule out a bug further upstream,
in how the pixel data itself gets painted before that refresh ever fires.

**Root cause, found by reading `base/ffi/blitbuffer.lua` directly:**
`BlitBuffer:paintRect(x, y, w, h, value, setter)` — the function this
plugin's `canvas_utils.drawLine` and the color self-test's bar-painting
loop both called — unconditionally downconverts its color argument via
`value:getColor8()` before writing any pixels (lines ~1711, ~1722),
**even into a genuine `TYPE_BBRGB32` buffer**. Different ink hues produce
different luminance values on that conversion, which is exactly why the
self-test's bars appeared as *distinguishable* grayscale shades rather
than a single flat gray — real color info was being discarded at the
paint call itself, every single time, regardless of buffer type, gate
state, or refresh waveform. `BlitBuffer:paintRectRGB32(x, y, w, h, color,
setter)` is the type-aware sibling function that exists specifically to
avoid this: it preserves full color on RGB32/RGB16 buffers and still
degrades correctly to grayscale on BB8/BB8A buffers (`Color8` also
implements `:getColorRGB32()`), so it's a safe, unconditional replacement
regardless of hardware color capability.

**Fix shipped:** both call sites (`lib/canvas_utils.lua`'s `drawLine`,
used by every live stroke segment and every StrokeBuffer repaint/tighten
pass; and `drawingcanvas.lua`'s `_runColorSelfTest` bar-painting loop) now
call `paintRectRGB32` instead of `paintRect`. Chrome-strip calls
(background fill, borders, hamburger icon) were left untouched — they
pass `Blitbuffer.COLOR_BLACK`/`COLOR_WHITE` (already `Color8`, luminance
by design), which is exactly what the generic `paintRect` is for. Spec
coverage added in `spec/canvas_utils_spec.lua` (`drawLine` describe block)
asserting `paintRectRGB32` is called, using a recording fake BlitBuffer,
plus a test confirming a bb exposing only the old `paintRect` errors
loudly rather than silently falling back to the broken behavior.

**Needs one more on-device confirmation:** deploy this commit and re-run
the color self-test — the bars should now show true color, and ink drawn
after the tighten pass should too. If they don't, something else remains;
if they do, this investigation is genuinely closed. The eraser is fixed
(order-independent latch, six event-order scenarios reviewed) and the
debug-log wiring is confirmed end-to-end working.

Loose end (independent of the above): the WFM capture that led to the
retracted conclusion was done on a build that still showed the self-test
dialog overlapping the bar block — the merged-region symptom in that
capture (`63,83` to `1137x1368`, matching the pre-height-cap-fix numbers
exactly) suggests the device was running the commit just before
`63493b0` at capture time. Redeploy the latest branch tip (this fix
included) for a clean test.

---

**Status update (2026-07, earlier this round):** on device, the self-test bars
are now visible (the prior round's UI fix worked) — but they render as
distinguishable grayscale shades (different luminance per color, not flat
gray), never actual color, with every plugin-level gate reading true. The
eraser is now fixed and out of scope for this doc going forward. This
round traced the entire software refresh/promotion chain against real
`base/` submodule source (`koreader-base`, cloned for the first time this
round) and found it structurally correct all the way to the ioctl
boundary — see the new dated section in
`.agents/notes/waveform-refresh-research.md` for the file:line detail. The
remaining open question — hardware/firmware limitation vs. an as-yet-unfound
software bug — is resolved by one on-device log line, captured in the new
runbook `.agents/plans/color-wfm-capture-runbook.md`. Separately, and
independent of that result either way, `.agents/plans/color-wfm-capture-runbook.md`
also flags the "Avoid mandatory black flashes in UI" setting
(`avoid_flashing_ui`, hamburger/gear → Screen → E-ink settings) as worth
checking regardless — if on, it silently downgrades the deferred tighten
pass's `"partial"`+dither refresh to `"ui"` mode, which never reaches the
Kaleido color-promotion logic at all, defeating this plugin's whole
"draw fast then reveal true color" design for that pass specifically.

**Status: CODE ROUND EXECUTED (2026-07) — awaiting on-device results.**
The investigation below was carried out; findings and the code that
shipped for them:

1. **Fact 2 ("no bars at all") is VOID as color evidence.** The self-test
   painted its bars centered in the drawable area — directly under its own
   centered InfoMessage — and the dismiss callback repainted the page
   immediately. The bars were never visible on any run. Fixed: bars now
   paint at the top of the drawable area, persist after dismissal behind a
   keep/restore dialog, and the readout now includes `canvas_bb_type`
   (`self._bb:getType()` — suspect A's missing number), the current ink
   hex, the resolved stroke color, and the bar rect coordinates.
2. **The color chain is statically correct end-to-end** (hex →
   colorFromString → paintRect into BBRGB32 `_bb` → blitFrom into BBRGB32
   Screen.bb → dither-promoted refresh; same combo KOReader core uses for
   colored highlights). No code-visible place where color dies was found —
   the next on-device self-test run is designed to be decisive.
3. **Eraser: real intra-frame ordering race found and fixed.** pendev's
   ABS_MT_TOOL_TYPE=pen branch could overwrite the BTN_STYLUS-driven
   rubber state depending on event order. Now an order-independent level
   latch (`lib/eraser_button.update_held` / `mt_tool_for_pen_slot`,
   spec-covered; reviewed against six event-order scenarios).
4. **debug_input_log was designed (ADR-006) but never wired** — no menu
   toggle, no raw_log_fn assignment, ever. Now fully wired (menu toggle +
   conf key + `<datadir>/fastnote/input.log`), RAW + DEC lines both
   written, rotation failure degrades gracefully.
5. **On-device next steps for the maintainer** are packaged in
   `.agents/plans/eraser-capture-runbook.md` (eraser + side-button
   captures) and step 4 below (run the self-test once, read the numbers).

The original handoff text follows unchanged — its "What comes next"
ordering still applies, with steps 3/4/6 now implemented in code.

You are picking up a long-running color/eraser investigation on
fastnote.koplugin (Kobo Libra Colour). This doc is self-contained: it
tells you what's been done, what the newest device evidence says, what it
rules out, and where to start. Do the Required Reading before touching
anything.

---

## Required reading (in this order)

1. `plugins/fastnote.koplugin/AGENTS.md` — repo entry point, invariants,
   file map. (Repo root `AGENTS.md` just routes here.)
2. `.agents/notes/waveform-refresh-research.md` — the accumulated device
   knowledge: waveform map, DU-at-32bpp bug, UIManager flash promotion,
   **the color gate chain / 8bpp trap**, the A2 1-bit dither correction,
   and two fact-check tables. Treat "hypothesis" entries as hints, not
   truth — this file has had wrong guesses before and says so.
3. `.agents/plans/color-pipeline-diagnosis-and-fix.md` — the previous
   round: root causes (stale master deployment, gate chain, A2 dither),
   Tasks C1 (color self-test) + C2 (solid live ink), review results, and
   the Phase D device checklist this handoff's evidence came from.
4. `.agents/plans/live-color-refresh-and-eraser-hardening.md` — the round
   before that: config wiring, `live_color_refresh` direct-refresh
   experiment, eraser `BTN_STYLUS`/`BTN_STYLUS2` hardening.
5. `.agents/plans/color-drawing-fix-and-menu-access.md` — Fix F (eraser)
   history, including the external confirmation of how the Stylus 2
   eraser/side-button signals work.
6. `.agents/planning/pencil-koplugin-research.md` — how a working plugin
   (pencil.koplugin) does live color + eraser on this exact device.
7. `.github/instructions/eink-refresh.instructions.md` +
   `.github/instructions/lua.instructions.md` — hard rules; both encode
   real prior bugs.

Code hot spots: `plugins/fastnote.koplugin/drawingcanvas.lua` (all paint/
refresh/menu/self-test), `lib/canvas_utils.lua` (`live_ink_mode`,
`union_rect`, `drawLine`), `lib/config.lua` + `fastnote.conf.example`
(all flags), `input/pendev.lua` + `lib/eraser_button.lua` +
`lib/pen_statemachine.lua` (eraser chain). Test gate:
`cd plugins/fastnote.koplugin && busted spec/` (243 passing at handoff;
`busted` may need `luarocks install busted --lua-version=5.1`).

**First step before ANY code reading: verify what the device is actually
running.** This investigation was previously derailed by a wrong-base
merge (PR #12 merged into another feature branch, not master — master sat
stale for a full round of fixes). Confirm `master` contains the C1/C2
commits ("color self-test", "solid live ink") and that the deployed
plugin directory matches master.

---

## What has been built and verified so far (all on the branch lineage)

- Config file wiring (`fastnote.conf`), keys: `finger_draw`,
  `rotation_mode`, `tighten_delay`, `tighten_enabled`,
  `live_color_refresh`, `eraser_button`, `live_ink_style`.
- Live drawing default: A2 per-segment refresh + deferred GLRC16
  "tighten" pass over the accumulated stroke bbox ~2.5 s after pen-up.
- `live_color_refresh` (menu: "Live color ink (experimental)"): paints
  segments to `Screen.bb` and fires throttled direct `Screen:refreshUI`
  (~30 fps), bypassing UIManager.
- `live_ink_style = "solid"` (default): live segments painted solid black
  into the display buffer; tighten rebuilds true color from StrokeBuffer
  before its refresh ("draw black, bloom color").
- Color self-test (menu): paints 6 palette + black + white bars into
  `self._bb`, refreshes `"full"`+dither (GCC16), shows every gate value.
- Eraser chain: `BTN_STYLUS`/`BTN_STYLUS2` → `lib/eraser_button.decode`
  (honors `eraser_button` config for swapped units) → state machine
  `tool="eraser"`; tool-latch reset bug fixed; debug logs name the exact
  button code (`codes.name_of`).
- Ruled out earlier: alpha=0, colorFromString *existence*, per-segment
  GLRC16 (too slow + flash promotion), DU (broken at 32bpp), the 8bpp
  trap as a *default* (it requires the user setting to be off).

## The NEW device evidence (2026-07, latest code, on hardware)

Verbatim-level facts from the maintainer's test session:

1. **All self-test gate flags are true**; `screen_bb_type=5`,
   `bb8_trap=false`. Type 5 is `TYPE_BBRGB32` (check
   `ffi/blitbuffer.lua` in the KOReader install to confirm the constant)
   — so **`Screen.bb` really is 32-bit color and every KOReader-level
   gate passes**. The 8bpp trap is ruled out. This is the single most
   important new fact.
2. **The self-test bars are not visible at all** — the InfoMessage
   appears and lists the color names, but no bar pattern can be found on
   the page, not even as gray bars. (Not "bars are gray" — *no bars*.)
3. **No color has ever appeared in any mode**: not live under
   `live_color_refresh`, not after the tighten pass, not in the
   self-test.
4. `live_color_refresh` **feel** is good: slightly slower than A2 but
   acceptable, and the pen-up line-only refresh cadence is exactly what
   the maintainer wants. Keep this UX; fix only the color.
5. **Eraser end still draws.** New clue: **holding the stylus side button
   while drawing makes the line noticeably wider** — as if pressure rose,
   without the maintainer pressing harder.

## What the new evidence implies (deductions, not yet verified)

- Facts 1+3 together relocate the bug: the KOReader pipeline is intact,
  so **the grayscale conversion must happen inside the plugin's own paint
  path** — i.e., the pixels the plugin puts into its buffers are already
  gray/black before any waveform is involved. Prior waveform theories are
  now mostly moot for the "no color" symptom.
- Prime suspect A: **the canvas's own `_bb` BlitBuffer type**. The gate
  snapshot logs `Screen.bb:getType()` but NOT `self._bb:getType()` — a
  known blind spot. If `_bb` is BB8/BB8A, every color paints to gray at
  draw time and every downstream refresh faithfully shows gray. Check
  `drawingcanvas.lua:init()`'s buffer-creation logic (it chooses by
  "hardware capability" — verify what it actually evaluates on device)
  and ADD `_bb:getType()` + the resolved `_current_color` value to the
  gate log/self-test message.
- Prime suspect B: **the color values themselves** —
  `Blitbuffer.colorFromString(hex)` returning nil (silent black fallback)
  or a Color8 conversion somewhere in `_strokeColor()`/`drawLine`. Note
  the self-test uses the same `colorFromString` — but its fallback is
  BLACK bars, which the maintainer also cannot see, so…
- Fact 2 (no bars AT ALL) doesn't fit either suspect alone — black bars
  should be visible on a white page. Something may be preventing the
  self-test's paint or its refresh from reaching the panel (ordering vs
  the InfoMessage's own repaint? region mismatch? bars painted then
  immediately repainted away?). Reproduce the sequence in code:
  `_runColorSelfTest` paints `_bb` → `setDirty(self, "full", rect, true)`
  → `UIManager:show(InfoMessage)` → dismiss → `_repaintAll()`. Consider
  whether the InfoMessage `show` triggers a widget repaint that runs
  BEFORE the queued full refresh and what `paintTo` blits. An easy
  experiment: make the self-test keep the bars until a second menu action
  restores the page, removing the InfoMessage from the timing equation.
- Fact 5 (side button widens the line): if the side button were being
  interpreted as the eraser signal we'd expect mid-stroke *erasing*, not
  widening. Width comes only from `pressure_to_width(ABS_PRESSURE)` —
  so either the Elan chip genuinely reports higher pressure while the
  button is held (hardware artifact), or button events are perturbing the
  state machine's latched pressure. Either way it suggests **neither
  BTN_STYLUS nor BTN_STYLUS2 is currently reaching the eraser path on
  this unit** — which would also explain fact 5's sibling: eraser end
  still draws.

## What comes next (ordered)

1. **Deployment sanity** (5 min): confirm master == deployed code ==
   branch tip (see "First step" above). Everything below assumes it.
2. **Eraser, cheapest test first**: the maintainer should set
   `eraser_button = "stylus2"` in `fastnote.conf` and retest the eraser
   end — the swapped-unit fix is already shipped and this is its exact
   symptom. If that fixes it, done; record it in
   `color-drawing-fix-and-menu-access.md` Fix F.
3. **Eraser, if (2) fails — capture ground truth**: enable the plugin's
   input debug logging (`debug_input_log` config / menu toggle; also
   `PenDev.raw_log_fn`) and/or run `evtest` on `/dev/input/event1`.
   Record: what codes fire for (a) eraser-end contact, (b) side button
   press while drawing (this also nails the width mystery — watch
   ABS_PRESSURE while holding the button). The debug logs already name
   button codes via `codes.name_of`. Adjust `eraser_button.decode` /
   pendev translation to whatever the log actually shows.
4. **Color: extend the diagnostics before theorizing** (small code task):
   add to the gate snapshot + self-test InfoMessage: `self._bb:getType()`,
   `tostring(self:_strokeColor())` / the resolved current color, and the
   painted bar rect coordinates. Redeploy, run self-test once, read the
   numbers. This should decide between suspects A and B in one pass.
5. **Color: fix per what (4) shows.** If `_bb` is not BBRGB32 on device →
   fix the buffer-type selection in `init()` (and log why it mis-chose).
   If colors are nil/gray at paint time → trace
   `PALETTE hex → colorFromString → drawLine/paintRect` on 32bpp.
   If both look right → chase the self-test render-ordering angle
   (fact 2) and instrument `paintTo`.
6. **Self-test hardening** regardless: make bars persist until explicitly
   dismissed (not racing the InfoMessage), and print the bar rect coords
   in the message so "I can't find the bars" is answerable.
7. When root cause is found: update `waveform-refresh-research.md`
   (fact-check table + a correction section if a prior claim was wrong),
   this file's Status, and the Fix F / plan checklists. Documentation
   rides with the fix (documentation-as-code skill).
8. Parked, unrelated: `broken-eraser-investigation` branch holds an
   unmerged undo stroke-grouping feature (0.5 s window) worth porting
   fresh if undo feels too granular; its color/eraser attempts are
   superseded — do not merge that branch.

## Ground rules for the executing agent

- Same as prior plans: work on a branch, no pushes without the
  supervising session/maintainer, `busted spec/` stays green, spec-first
  for `lib/` changes, docs ride along.
- On-device steps (2, 3, and the "read the numbers" half of 4) can only
  be done by the maintainer — package them as short, copy-pasteable
  instructions with expected outputs, like Phase D in
  `color-pipeline-diagnosis-and-fix.md` did.
- Keep the `live_color_refresh` UX exactly as-is (maintainer explicitly
  likes the speed + line-only refresh cadence). Color must come from
  fixing the pixel path, not from changing refresh behavior.
