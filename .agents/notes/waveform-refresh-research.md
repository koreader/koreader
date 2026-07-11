# Waveform Refresh & Colour Behaviour — KoboMonza (Kobo Libra Colour)

Research notes from the fastnote.koplugin drawing investigation.  
Device: **Kobo Libra Colour** (codename KoboMonza, MTK SoC, Kaleido 3 panel).  
Framebuffer: **BBRGB32** (32bpp), initialised in `drawingcanvas.lua:init()`.

---

## Device waveform map (KoboMonza / MTK path, confirmed from squashfs)

Source: `squashfs-root/usr/lib/koreader/ffi/framebuffer_mxcfb.lua` lines 1021–1035.

| KOReader abstract name | HWTCON constant | Description |
|---|---|---|
| `waveform_a2` | `HWTCON_WAVEFORM_MODE_A2` | 1-bit ultra-fast, very prone to ghosting |
| `waveform_fast` | `HWTCON_WAVEFORM_MODE_DU` | Direct Update (2-level), fast |
| `waveform_ui` | `HWTCON_WAVEFORM_MODE_AUTO` | Hardware auto-selects |
| `waveform_partial` = `waveform_reagl` | `HWTCON_WAVEFORM_MODE_GLR16` | REAGL (ghosting reduction) |
| `waveform_full` | `HWTCON_WAVEFORM_MODE_GC16` | GC16, high-quality, flashing |
| `waveform_color` | `HWTCON_WAVEFORM_MODE_GCC16` | Kaleido full-colour |
| `waveform_color_reagl` | `HWTCON_WAVEFORM_MODE_GLRC16` | Kaleido colour REAGL |

**⚠️ WARNING: these mappings are per-device.**  On some NXP Kobos,
`waveform_fast = WAVEFORM_MODE_DU` too, but on at least one device class
`waveform_fast = WAVEFORM_MODE_GC16` (line 1110).  Never assume
cross-device portability for `waveform_fast`.

---

## Kaleido waveform promotion logic (mxc_update, ~line 363)

When `dither=true AND hasKaleidoWfm AND isColorEnabled`:

| Input waveform | Promoted to | Note |
|---|---|---|
| `waveform_partial` (= GLR16, REAGL) | `waveform_color_reagl` = GLRC16 | Kaleido REAGL |
| `waveform_full` (= GC16) | `waveform_color` = GCC16 | Kaleido full |
| `waveform_ui` (= AUTO), `waveform_fast` (= DU), others | **no promotion** | Intentional per code comment |

`_isKaleidoWaveFormMode()` returns true only for GCC16 and GLRC16.  
CFA processing flag (`HWTCON_FLAG_CFA_EINK_G2`) is added **only** when
the post-promotion waveform is a Kaleido mode.

So: `"partial" + dither=true` → **GLRC16** (not GCC16).  GCC16 is only
reached via `"full" + dither=true` (full-screen flash path).

---

## THE CRITICAL BUG: DU ("fast") at 32bpp on KoboMonza

In `refresh_kobo_mtk` (~line 720) there is a **commented-out** block:

```lua
--[[
-- Disable CFA processing on A2/DU
-- NOTE: Well, that leads to... interesting... results when used @ 32bpp...
--       The driver seems to have trouble choosing the right working buffer,
--       so you get to see a lot of weird crap ;).
if waveform_mode == HWTCON_WAVEFORM_MODE_A2
or waveform_mode == HWTCON_WAVEFORM_MODE_DU then
    fb.update_data.flags = bor(fb.update_data.flags, C.HWTCON_FLAG_CFA_SKIP)
end
--]]
```

This was an attempt to fix DU at 32bpp by skipping CFA — it was abandoned
because `HWTCON_FLAG_CFA_SKIP` "leads to interesting results when used @ 32bpp"
(i.e. it also broke things).  The block was left as documentation.

**Consequence for fastnote:** Using `"fast"` (DU) for live pen drawing on a
BBRGB32 32bpp canvas causes invisible or corrupted strokes in **light mode**
(black on white).  Dark mode (white on black) appeared to work, possibly
because that pixel transition direction is coincidentally tolerable, or
because the visible end result after pen-up AUTO refresh masked the live-draw
issue.

**The fix (commit 8fe9ddee8):** Use `"partial"` (GLR16/REAGL) for live drawing
when `_has_color_hw = true`.  Non-colour devices (BB8, 8bpp) keep `"fast"` —
DU is not affected by the 32bpp Kaleido CFA issue on those.

---

## What was tried / ruled out

### Hypothesis: alpha=0 causing invisible strokes
Investigated `blitbuffer.lua` C source and `colorFromString`.  
`colorFromString("#000000")` returns `ColorRGB32(0, 0, 0, 0xFF)` — alpha IS
set to 0xFF (opaque).  `paintRect` via `getColor8().a` gives value=0 (black),
which fills BBRGB32 pixels as `0xFF000000` (black, alpha=0xFF).  
**Ruled out.**

### Hypothesis: wrong colour type / missing colourFromString
Traced `_strokeColor()` path — it calls `colorFromString()` which is defined
in the squashfs blitbuffer.lua at line 2602 and works correctly.  
**Ruled out.**

### Hypothesis: GCC16 needed for live drawing
Tried `"partial" + dither=true` (→ GLRC16) and considered GCC16 (→ "full" +
dither).  GCC16 requires a full-screen refresh — inappropriate for per-stroke
partial updates.  GLRC16 via `_repaintAll()` works for full repaints.  
**Not the right tool for live drawing.**

### Hypothesis: double-tap detection causing spurious refreshes
Removed double-tap detection entirely (commit 3e83fc1af).  This fixed an
unrelated nuisance but did not affect stroke visibility.

### Hypothesis: screen flash from unconditional pen-up setDirty
Fixed by gating pen-up `setDirty` on `had_stroke` (commit a804663ab).
Also removed `self.dithered` flag that was applying GCC16 on pen-up.
Fixed the flash issue; strokes still invisible in light mode live drawing.

---

## UIManager flash promotion: the "automatic refresh interrupts my line" cause

`frontend/ui/uimanager.lua` (~line 513): **any `"partial"` refresh submitted
through `UIManager:setDirty` counts toward promotion to a full flashing
refresh after `FULL_REFRESH_COUNT` refreshes — default 6** (user-settable;
separate night-mode setting). Live drawing emits many refreshes per second,
so per-segment `"partial"` hits the promotion almost instantly: the screen
flashes mid-stroke and drawing is locked out during the flash.

`"ui"`, `"fast"`, and `"a2"` do **not** count toward the promotion.
Direct `Screen:refreshUI/refreshFast/...` calls bypass UIManager entirely —
no queues, no widget repaint, no promotion counter — which is how
pencil.koplugin sustains throttled live color refreshes (see
`.agents/planning/pencil-koplugin-research.md`).

Consequence for this plugin: per-segment `"partial"` was doubly wrong —
too slow (GLRC16 latency, above) *and* flash-promoted. One-shot uses of
`"partial"` (+dither) for `_repaintAll`/tighten remain correct.

---

## The color gate chain and the 8bpp trap (verified from source, 2026-07)

Everything below is read directly from this repo's KOReader sources — not
inferred. If ANY link in this chain is off, **no plugin code can ever
produce color**, and every symptom looks like "the waveform isn't working."

1. **`Screen:isColorEnabled()`** (`frontend/device/generic/device.lua`
   ~line 216): returns the `color_rendering` user setting if set, else
   defaults to `isColorScreen()` (true on Libra Colour). So color is ON by
   default — false only if the user ever toggled *top menu → gear →
   Screen → Color rendering* off.
2. **The startup 8bpp trap** (`platform/kobo/koreader.sh`,
   `ko_do_fbdepth()`): on color panels, if `color_rendering = false` in
   `settings.reader.lua`, the launcher runs `fbdepth -d 8` — the
   framebuffer becomes **8bpp grayscale with CFA processing skipped
   entirely**. Every blit is converted to gray at paint time;
   no waveform choice can bring color back. Otherwise it enforces 32bpp.
   `crash.log` states which branch ran: "Switching fb bitdepth to
   8bpp (to disable CFA)" vs "...to 32bpp".
3. **`Device:hasKaleidoWfm`** (`frontend/device/kobo/device.lua` ~line
   799): `yes` only when `hasColorScreen() and isMTK()` — true on
   KoboMonza. **`canHWDither`** (~line 795): `yes` on Mk7/MTK.
4. Kaleido promotion (GLRC16/GCC16 + CFA flag) then additionally requires
   `dither=true` on the refresh and `Screen.hw_dithering` (see the
   promotion table above).

**Diagnostic implication:** "line refreshes but only ever gets more
visible, never colored" — check gates 1–2 *first* (a device-side settings
question), before touching waveform code. A one-tap check: KOReader's own
UI shows color accents (e.g. colored book covers in the file browser) only
when the chain is intact.

---

## Correction (2026-07): A2 renders colored ink as sparse 1-bit dither, not "grayscale"

Earlier revisions of this note said color ink "renders as grayscale"
under A2 live drawing. That's imprecise in a way that matters: A2 is
**1-bit** — each pixel is thresholded to pure black or pure white. A
colored (or gray) line becomes a **sparse dither pattern**, and the
lighter the ink color's luminance, the fewer black pixels survive — on
device this reads as a **very faint, dotted line** in light mode. Dark
mode looks solid because ink is forced to white on black (maximum
contrast, no thresholding loss). Reported on hardware 2026-07; consistent
with A2's definition. The tighten pass (or any GLR16/GLRC16 refresh over
the region) re-renders the region at full depth, which is why the line
"becomes more visible" afterward.

Design consequence: if solid live ink is wanted under A2, the *display
buffer* copy of the live stroke must be painted near-black (true color
stays in StrokeBuffer; the tighten repaints true color before its
refresh). See `.agents/plans/color-pipeline-diagnosis-and-fix.md`.

---

## Fact-check: "Implementing Real-Time Color Stylus Drawing" paper (2026-07)

An externally produced guide reviewed during the color investigation.
Verdicts against this repo's sources and observed device behavior:

| Claim | Verdict | Notes |
|---|---|---|
| Kaleido 3 = mono film + CFA, 300/150 PPI; MTK EPDC | ✅ Correct | Matches known hardware. |
| Two-phase render: fast live pass + high-fidelity pass on pen-up | ✅ Correct | This is exactly the A2-live + tighten design (and the stock app's behavior). |
| A2 is 1-bit mono, unusable for color | ✅ Correct | Matches this note. |
| BlitBuffer must be 32-bit for color | ✅ Correct, incomplete | Necessary but not sufficient — `Screen.bb` itself is 8bpp if the color_rendering/8bpp trap is sprung; the plugin's own BB type can't fix that. |
| A hardware "FastGLR" pen waveform draws **in color** during the live phase | ❌ Unsupported | No such mode exists in the KoboMonza hwtcon map (see table at top). The fast modes are DU/A2, both mono. No online source for "FastGLR" on this hardware was found. |
| Use `"fast"` for the live phase | ❌ Wrong for this device | `"fast"` = DU, broken at 32bpp on KoboMonza (invisible strokes — see THE CRITICAL BUG above). |
| Use abstract modes, tight bboxes, avoid full-screen flashes | ✅ Correct | Standard practice; matches this plugin. |
| Pen-up pass: `"ui"` or `"partial"` | ⚠️ Partial | `"partial"`+dither (→ GLRC16) is the color-correct choice on this device; plain `"ui"` never gets CFA processing. |

### Throttled direct Screen:refreshUI for live color (pencil.koplugin technique)
Paint into the framebuffer, accumulate a dirty rect, and fire a direct
`Screen:refreshUI(rect)` (AUTO waveform) at most every 16–33 ms, bypassing
UIManager. pencil.koplugin ships this and users report working live color
drawing on this exact device+pen. Would show (probably muted) color during
the stroke while keeping the GLRC16 tighten for final fidelity. Details,
caveats, and the comparison: `.agents/planning/pencil-koplugin-research.md`.
**Implemented behind `live_color_refresh` (default off), pending device
validation.** `drawingcanvas.lua`: `_useLiveColorRefresh`,
`_liveColorRefresh`, `_flushLiveRefresh`; throttle interval
`LIVE_REFRESH_INTERVAL` (0.033 s ≈ 30 fps). Only takes the new path when
color hardware AND the raw evdev pen path are both active — mono hardware
and the gesture/emulator path are unaffected regardless of the flag. Flag
is also toggleable live from the hamburger menu ("Live color ink
(experimental)"), session-only. Run the on-device test matrix in
`.github/skills/waveform-experimentation/SKILL.md` (flag off for
regression, flag on for the new path) before considering a default flip.

### ~~Deferred colour refresh timer~~ — IMPLEMENTED (see below)
Originally proposed as: use an idle timer (like `_scheduleIdleSave`) to fire
a GLRC16 refresh after the user stops drawing. Shipped as the "tighten pass"
— see "Current design" below. Delay tuned to 2.5s (not 0.5s) based on
observed hardware behaviour: on-device testing showed that anything faster
risked firing mid-multi-stroke-sequence, which briefly locks out drawing
during the refresh and breaks the user's ability to keep writing.

### GCC16 on full repaint instead of GLRC16
`_repaintAll()` currently uses `"partial" + dither=true` → GLRC16.  Using
`"full" + dither=true` → GCC16 would give the highest colour accuracy at the
cost of a flash.  Reasonable to offer as an optional "refresh now" gesture.
**Not implemented.**

### ~~waveform_a2 for live drawing~~ — NOW THE APPROACH
`HWTCON_WAVEFORM_MODE_A2` is 1-bit, even faster than DU.  Initially assumed
it would share DU's 32bpp CFA issues, but on-device testing showed A2
works correctly at 32bpp on KoboMonza — strokes are visible and fast.
Color ink renders as sparse 1-bit dither during live drawing (see the
2026-07 correction section — light colors read as faint/dotted); the
deferred tighten pass (GLRC16) reveals true color after pen inactivity.
**Now the default for all live drawing.**

### HWTCON_FLAG_CFA_SKIP for DU/A2
The commented-out code in `refresh_kobo_mtk` shows this was attempted
upstream and abandoned ("interesting results when used @ 32bpp").  
We cannot set this flag without patching KOReader core.  **Not viable.**

### async per-stroke GLRC16 refresh
Fire a GLRC16 partial update per completed stroke (pen-up), not per point.
This is essentially what pen-up `"ui"` (AUTO) already does.  Could be made
explicit with `"partial" + dither=true` for guaranteed GLRC16.  **Low
priority; pen-up "ui" already works.**

---

## Fact-check: online info (May 2026)

Claim source described device as "Kobo Clara Colour" — ours is
**Kobo Libra Colour** (KoboMonza).  Both use Kaleido 3 + MTK, so most
waveform behaviour generalises, but device-specific mappings may differ.

| Claim | Verdict | Notes |
|---|---|---|
| `waveform_fast` and `waveform_a2` are the same / fallback for each other | ❌ Wrong | On KoboMonza both are set simultaneously: `waveform_fast=DU`, `waveform_a2=A2`. Separate constants, not fallbacks. |
| `waveform_fast` maps to DU/Direct Update | ✅ Correct | Confirmed at line 1022. |
| Force `waveform_fast` for smooth live drawing | ❌ Wrong for our device | DU at 32bpp on KoboMonza is broken (CFA working-buffer issue). Using DU causes invisible strokes in light mode. |
| `waveform_partial` = REAGL, clears ghosting without full flash | ✅ Correct | GLR16 = REAGL on KoboMonza. |
| `waveform_color` = GCC16, full 4096-colour, heavy flash | ✅ Broadly correct | GCC16 is Kaleido full; it is used for full-page repaints, not live drawing. Not inherently "flashing" in the GC16 sense but it is a full-quality slow mode. |
| `_isKaleidoWaveFormMode` checks `waveform_color` and `waveform_color_reagl` | ✅ Correct | Confirmed at lines 114-115. |
| RGB888 @ 32bpp + `waveform_fast` → dithered muted colour lines visible | ❌ Inaccurate for our device | Actual result: strokes are **invisible** (not visible-but-dithered). Driver fails to produce any output, not an output-with-dithering. |
| Async timer to defer full colour refresh | ✅ Valid technique | Implemented as the "tighten pass" — GLRC16 fires 2.5s after last pen-up. |
| `"partial" + dither=true` → GCC16 | ❌ Wrong | REAGL waveform + dither → **GLRC16** (Kaleido REAGL). GCC16 is only reached via `"full"` + dither (confirmed in mxc_update promotion table). |

---

## Current fastnote waveform decisions (A2 live + deferred tighten)

The design: all live drawing uses A2 (1-bit B&W, fastest possible) regardless
of ink color. Color ink renders as sparse 1-bit dither during active writing
(faint/dotted for light colors — see the 2026-07 correction section) — the user
sees instant, uninterrupted strokes. After 2.5s of pen inactivity, a single
targeted GLRC16 refresh fires over the accumulated stroke bounding box to
reveal true color. This matches the stock Kobo notebook app's observed
behaviour.

The earlier approach (GLRC16 per live segment) was too slow — GLRC16 takes
~300-500ms per update, causing visible "chunking" that broke up lines
mid-stroke and made drawing unusable.

| Operation | Waveform | Colour HW (KoboMonza) | Non-colour HW |
|---|---|---|---|
| Full repaint (`_repaintAll`) | `"partial"` + dither=true | → GLRC16 | → GLR16 |
| Live pen/touch segment (`_drawSegment` → `_refreshRect`) | `"a2"` (fast B&W) | → A2 (color ink shown as 1-bit dither) | → A2 |
| Pen-up / touch-up | — | schedules the tighten timer | `"a2"` |
| Tighten pass (fires `COLOR_TIGHTEN_DELAY` = 2.5s after last pen-up, cancelled on next pen-down) | `"partial"` + dither=true, targeted to accumulated stroke bbox | → GLRC16 (reveals true color) | N/A — mono HW never schedules a tighten |

Implementation: `drawingcanvas.lua` — `_scheduleTighten`,
`_cancelTightenTimer` (pen-down: cancels timer only, preserves rect),
`_cancelTighten` (full reset: cancels timer AND clears rect),
`_expandTightenRect`, `COLOR_TIGHTEN_DELAY`.

Critical detail: pen-down calls `_cancelTightenTimer()` (timer only), so
the bbox accumulates across multiple strokes in a writing session. The
rect is only cleared when: (a) the tighten fires, (b) `_repaintAll`, (c)
`loadPage`, or (d) `_doClose` — these do full-quality refreshes that make
the tighten redundant.

The widget sets `self.dithered = has_color_hw` so UIManager knows to honor
dithering hints from the refresh stack. Without this, intervening
widget-dirty refreshes can overwrite the tighten's GLRC16 color with
grayscale. The dither→GLRC16 promotion also requires `Screen.hw_dithering`
(true by default on MTK Kobo) and `Screen:isColorEnabled()` (true by
default on color screens).
