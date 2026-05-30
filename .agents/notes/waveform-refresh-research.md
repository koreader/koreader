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

## Paths not yet tried / future ideas

### Deferred colour refresh timer
Use an idle timer (like `_scheduleIdleSave`) to fire a GLRC16 full repaint
~0.5s after the user stops drawing.  Live drawing uses GLR16 (fast, mono);
idle timer fires GLRC16 for full colour fidelity.  Potentially better colour
saturation for non-black palette colours.  **Not implemented — deferred.**

### GCC16 on full repaint instead of GLRC16
`_repaintAll()` currently uses `"partial" + dither=true` → GLRC16.  Using
`"full" + dither=true` → GCC16 would give the highest colour accuracy at the
cost of a flash.  Reasonable to offer as an optional "refresh now" gesture.
**Not implemented.**

### waveform_a2 for live drawing
`HWTCON_WAVEFORM_MODE_A2` is 1-bit, even faster than DU.  Would share the
same 32bpp CFA issues as DU and likely be worse.  **Not worth trying.**

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
| Async timer to defer full colour refresh | ✅ Valid technique | Not implemented yet; deferred. |
| `"partial" + dither=true` → GCC16 | ❌ Wrong | REAGL waveform + dither → **GLRC16** (Kaleido REAGL). GCC16 is only reached via `"full"` + dither (confirmed in mxc_update promotion table). |

---

## Current fastnote waveform decisions (as of 8fe9ddee8)

| Operation | Waveform | Colour HW (KoboMonza) | Non-colour HW |
|---|---|---|---|
| Full repaint (`_repaintAll`) | `"partial"` + dither=true | → GLRC16 | → GLR16 |
| Live pen drawing | `"partial"` | → GLR16 | `"fast"` = DU |
| Live touch drawing | `"partial"` | → GLR16 | `"fast"` = DU |
| Pen-up | `"ui"` | → AUTO | → AUTO |
