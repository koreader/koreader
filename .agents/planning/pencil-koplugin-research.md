# Research: pencil.koplugin vs. fastnote — live color drawing & eraser on Kobo Libra Colour

**Status: REFERENCE (research writeup, 2026-07)**

Source reviewed: https://github.com/mysticknits/pencil.koplugin (main branch,
head `f4e58b3` at review time). Cross-checked against this repo's
`frontend/ui/uimanager.lua` and the findings already recorded in
`.agents/notes/waveform-refresh-research.md`.

Question this answers: pencil.koplugin has working "draw in color" and
"eraser end" support for the Kobo Stylus 2 on the Libra Colour — how does it
do it, and why did fastnote's earlier attempts at fast color live-drawing
fail?

---

## What pencil.koplugin is

An annotation plugin (draw on top of ebook pages) — not a notebook app like
fastnote. Two-part install:

1. **A replacement for KOReader core `frontend/device/input.lua`** (~1,800
   lines). This is the load-bearing piece: it adds a dedicated pen slot
   (`main_finger_slot + 4`), stylus tool-type tracking, and a
   `registerStylusCallback()` hook that routes stylus MT slots to the plugin
   *before* gesture detection (returning true "dominates" the event away
   from gestures).
2. **The plugin itself** (`pencil.koplugin/main.lua`, ~4,200 lines) which
   registers that callback and paints strokes directly into the framebuffer.

fastnote reads `/dev/input/event1` itself via FFI (`input/pendev.lua`) and
never patches core — a deliberate difference (see ADR-003). pencil's
approach requires shipping a forked core file that must track upstream
KOReader; fastnote's does not.

---

## How pencil does live drawing (the part that "just works" in color)

Raw-input path, per point (`Pencil:addRawPoint`, main.lua ~633):

1. Paint the segment **directly into `Screen.bb`** (`paintRectRGB32` /
   line-segment painter) with the stroke's RGB32 color.
2. Accumulate a dirty rect across points.
3. At most every **16 ms** (`refresh_interval_ms`, ~60 fps cap), call
   **`Screen:refreshUI(x, y, w, h)`** on the accumulated rect and clear it.
   Code comment: "Use UI refresh mode for proper color rendering on color
   e-ink."
4. On pen-up: schedule a **delayed cleanup refresh 600 ms** after the last
   stroke — `UIManager:setDirty(view, "fast")` over the whole view;
   cancelled and rescheduled if another stroke starts first.

The two tricks that make this fast AND uninterrupted:

- **`Screen:refreshUI(...)` is a direct framebuffer refresh, not
  `UIManager:setDirty`.** It bypasses UIManager's paint/refresh queues
  entirely: no widget repaint, no queue latency, and critically **no
  participation in UIManager's flash-promotion counter** (see next
  section). The refresh fires inline inside the input callback.
- **`"ui"` maps to `HWTCON_WAVEFORM_MODE_AUTO` on KoboMonza** — the driver
  picks the waveform per update. Unlike A2 (1-bit) or DU (2-level, broken
  at 32bpp on this device), AUTO renders the RGB content, so colored ink is
  visible while drawing. Note the Kaleido promotion path (dither → GCC16 /
  GLRC16) never applies to `"ui"`, and direct `Screen:refresh*` calls carry
  no dither flag — so live color via AUTO is *probably* not CFA-processed,
  i.e. likely less saturated than a GLRC16 pass. Their 600 ms `"fast"`
  cleanup doesn't add color fidelity either. Acceptable for margin
  annotations; fastnote's tighten pass exists precisely to restore full
  color, so the two designs are not in conflict.

Gesture-fallback path (when the raw hook isn't active): pencil paints with
**no refresh at all during the stroke**, relying on e-ink ghost pixels for
feedback, then the 600 ms delayed refresh cleans up (main.lua ~2418).

---

## Why fastnote's "speedy color drawing" attempts failed — now fully explained

Symptoms observed during fastnote development, mapped to root causes:

| Symptom | Root cause |
|---|---|
| Color "simply not working" with `"a2"` | A2 is a 1-bit black/white waveform *by hardware definition*. Color content cannot render in it, ever — this is physics, not a bug. The stock Kobo notebook app has the same constraint and does the same thing fastnote now does: mono live ink, deferred color pass. |
| Invisible strokes with `"fast"` (DU) in light mode | KoboMonza driver bug at 32bpp — CFA working-buffer issue, documented upstream as a commented-out workaround. See `waveform-refresh-research.md` § "THE CRITICAL BUG". |
| Per-segment `"partial"`(+dither → GLRC16) chunked and lagged | GLRC16 takes ~300–500 ms per update; pen polls at ~120 Hz. |
| **"Automatic refresh" interrupting a line after a moment of drawing** | **UIManager flash promotion.** Per `frontend/ui/uimanager.lua` (~line 513): *any* `"partial"` refresh submitted through `UIManager:setDirty` counts toward promotion to a full flashing refresh after `FULL_REFRESH_COUNT` refreshes — **default 6**. Drawing emits many partial refreshes per second, so the promotion fires almost immediately, flashing the screen mid-stroke and locking out drawing. This is why "some alternative waveforms" couldn't survive a straight line. `"ui"`, `"fast"`, and `"a2"` do not count toward promotion; direct `Screen:refresh*` calls bypass the counter entirely. |

So there was never a single failure — each waveform failed for a different,
now-identified reason, and the interruption was UIManager policy rather
than the waveform itself.

---

## How pencil does the eraser (confirms fastnote's Fix F design)

From pencil's patched `input.lua` (~744) and `eraser.koplugin` (SimonLiu),
which it credits:

- The Kobo Stylus 2 **eraser end reports `ABS_MT_TOOL_TYPE = 1` (PEN)** —
  the Elan chip does *not* report tool type 2 for it.
- But while the eraser end touches the screen, the device **sends
  `BTN_STYLUS` (code 331, value 1)**; release sends value 0. pencil tracks
  this as `kobo_eraser_active` (level-triggered) and overrides the slot's
  tool to ERASER while it's held.
- The **side button sends `BTN_STYLUS2`** the same way — pencil maps it to
  a highlighter tool, with a menu toggle to swap the two mappings (they
  note some units/pens apparently arrive reversed).

Implication for fastnote: the Fix F detection chain
(`BTN_STYLUS` → synthesize `BTN_TOOL_RUBBER` → state machine
`tool="eraser"`) is built on a **real, externally confirmed signal**. If
the eraser end still draws on device, the bug is in fastnote's handling
(e.g. edge-vs-level handling of BTN_STYLUS, or event ordering relative to
pen-down), not a missing hardware signal. The swap toggle in pencil is also
a hint: check whether the unit reports eraser as `BTN_STYLUS2` instead.

Eraser behavior on match: pencil deletes whole strokes whose points fall
within the eraser radius (same model as fastnote's `eraseAt`), repaints
view + overlay into `Screen.bb`, and refreshes with a direct full-screen
`Screen:refreshUI`/`refreshFast`.

---

## What fastnote could adopt (candidate experiments, in order of promise)

1. **Throttled direct-refresh live drawing** — replace the per-segment
   `UIManager:setDirty(self, "a2", rect)` with a direct
   `Screen:refreshUI(rect)` (AUTO) capped at one refresh per 16–33 ms over
   an accumulated dirty rect. Expected result: colored ink visible (if
   muted) *during* the stroke, no flash promotion, lower latency (no
   UIManager queue round-trip). Keep the GLRC16 tighten pass for full color
   fidelity. Risk: AUTO's latency on this panel is unverified for
   stroke-following; A2 may still feel snappier — needs the on-device test
   matrix (see the `waveform-experimentation` skill).
2. **A2 live + direct refresh** — keep A2 but issue it via
   `Screen:refreshA2`-equivalent direct call with the same 16 ms batching,
   for latency alone. Smaller change, no color benefit.
3. **BTN_STYLUS2 side-button feature** — the side button is a usable input
   (pencil uses it for highlight/tool-toggle). Free hardware affordance for
   a future fastnote tool switch.
4. **Not worth adopting: the core input.lua patch.** fastnote's FFI raw
   reader already delivers lower-level access without forking core.

Anything from this list that gets implemented should update
`.agents/notes/waveform-refresh-research.md` (the design-of-record note)
per the documentation-as-code skill; this file stays a historical snapshot
of the review.
