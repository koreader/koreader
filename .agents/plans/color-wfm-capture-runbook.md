# Color WFM capture runbook (maintainer; on-device only)

**Status: RESOLVED (2026-07) — captured `WFM: 10` (`HWTCON_WAVEFORM_MODE_GCC16`).**
KOReader's software layer genuinely requested a real Kaleido color update
at the moment of refresh. The software chain is proven correct end to end;
the remaining gap is downstream of KOReader (kernel driver / EPDC firmware
/ physical panel) and is not fixable from this plugin or KOReader itself.
See the conclusion in `.agents/plans/grayscale-ink-and-eraser-handoff.md`.
The steps below are kept for reference / in case this needs re-running
after a firmware update or on another unit.

---

Companion to the Color self-test
(`DrawingCanvas:_runColorSelfTest`, `plugins/fastnote.koplugin/drawingcanvas.lua`).
This file cannot be executed from CI/emulator (no real EPDC/kernel driver
there); it's written so a maintainer with the physical Kobo Libra Colour can
run it copy-pasteably, in the style of `.agents/plans/eraser-capture-runbook.md`.

**Background**: the self-test now shows the bars (a prior round fixed the UI
bug where the InfoMessage covered them — see
`.agents/plans/grayscale-ink-and-eraser-handoff.md`), but they render as
distinguishable grayscale shades, never actual color, even though every
plugin-level gate (`has_color_hw`, `is_color_enabled`, `has_kaleido_wfm`,
`hw_dithering`, `screen_bb_type=5`, `bb8_trap=false`) reads true. This round
traced the full software call chain against the `base/` submodule (cloned
fresh this round — see the dated section in
`.agents/notes/waveform-refresh-research.md`) and found it structurally
correct all the way to the ioctl boundary. The one thing static reading
cannot settle is what waveform mode is actually requested at the moment the
self-test's refresh fires — that requires a runtime log line. This runbook
captures it.

---

## Step 1 — enable debug logging, THEN RESTART KOREADER

1. Open the hamburger/tools menu (wrench icon) → **More tools** →
   **Developer options**.
2. Enable **"Enable debug logging"**.
3. Enable **"Enable verbose debug logging"** (only selectable once debug
   logging is on).
4. **Fully close and reopen KOReader now, before doing anything else.**
   This step is not optional — see the gotcha below.

Both toggles are in `frontend/apps/filemanager/filemanagermenu.lua`
(`self.menu_items.developer_options`). `fb.debug` — the line we're chasing
— is `logger.dbg`.

**Gotcha (confirmed 2026-07, cost a whole capture attempt without it):**
`logger.dbg` is not a live flag check -- `frontend/logger.lua`'s
`Logger:setLevel` REASSIGNS the `logger.dbg` field to either the real
logging function or a no-op, and defaults to the no-op at boot. The Kobo
screen object captures `debug = logger.dbg` exactly once, at boot
(`frontend/device/kobo/device.lua`, `self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg, ...}`)
-- a snapshot of whatever `logger.dbg` was AT THAT MOMENT, not a live
reference. Toggling the two menu items above reassigns the *global*
`logger.dbg` going forward, but the screen object's already-captured copy
still points at the stale no-op, so `mxc_update`'s debug line can never
fire in that running session, no matter how long you wait or how many
times you re-run the self-test. Only a restart re-runs `Device:init()`
after the setting is already persisted (`reader.lua` line 73:
`if G_reader_settings:isTrue("debug") then dbg:turnOn() end`, which runs
before the screen object is constructed), so the capture happens with the
real function this time.

This does NOT affect any of the OTHER debug lines you'll see in crash.log
(`_refresh: Enqueued ...`, `triggering refresh {...}`, this plugin's own
breadcrumbs, etc.) -- those all call `logger.dbg(...)` directly each time,
doing a fresh lookup, so they reflect the toggle immediately without a
restart. It's specifically `fb.debug`'s one-time captured copy that needs
the restart.

---

## Step 2 — confirm "Disable CFA post-processing" is OFF (default)

Same **Developer options** submenu, further down: **"Disable CFA
post-processing"**. It should be unchecked (the default).

This is a rule-out step, not the likely cause: even if it were on, the
CFA flag would be stomped from `HWTCON_FLAG_CFA_EINK_G2` (saturation boost)
to `0`/`HWTCON_FLAG_CFA_EINK_G1` — documented in
`base/ffi-cdecl/include/mtk-kobo.h` (~line 67) as "Standard behavior (e.g.,
same results as no flags)". That's reduced saturation, not an absence of
color. Don't overweight this — just rule it out while you're in the menu.

---

## Step 3 — separately, check "Avoid mandatory black flashes in UI"

This is an **independent** finding, not related to the self-test result
(the self-test uses `"full"`, and this setting only affects `"partial"`
refreshes with a region — exactly what the plugin's deferred tighten pass
uses). Worth ruling out regardless of what Step 5's log line says.

Menu path: hamburger/gear icon (**Settings**) → **Screen** → **E-ink
settings** → **"Avoid mandatory black flashes in UI"**
(`avoid_flashing_ui` setting; `frontend/ui/elements/screen_eink_opt_menu_table.lua`
/ `frontend/ui/elements/avoid_flashing_ui.lua`).

If this is ON: `frontend/ui/uimanager.lua` (~line 1144-1147) silently
downgrades any `"partial"` refresh that has a region to `"ui"` mode before
it ever reaches the Kaleido color-promotion check in `mxc_update`. `"ui"`
maps to `HWTCON_WAVEFORM_MODE_AUTO`, which matches neither
`_isFullWaveFormMode` nor `_isREAGLWaveFormMode` — so the plugin's tighten
pass (`"partial"` + dither, targeted region) would be silently defeated for
color, independent of whatever the self-test's own `"full"` refresh does.

Note the current state either way (ON or OFF) when you report back — if
ON, turn it OFF and retest the tighten pass separately from this runbook's
main diagnostic.

---

## Step 4 — run the Color self-test

Open a notebook → hamburger menu inside the canvas → **Color self-test**.
Note the bar rect readout in the InfoMessage: `Bars painted at x=..., y=...,
w=..., h=...` — you'll need these numbers in Step 5 to find the right log
line.

---

## Step 5 — read crash.log

Over SSH or USB, open the crash log in the KOReader install directory —
on a standard sideload, `/mnt/onboard/.adds/koreader/crash.log`
(`platform/kobo/koreader.sh` appends all of `reader.lua`'s stdout/stderr
there: `./reader.lua "$@" >>crash.log 2>&1`).

Search for this breadcrumb (added this round to
`DrawingCanvas:_runColorSelfTest`, right before the self-test's `setDirty`
call):

```
FastNote canvas: color self-test firing refresh, watch for the next mxc_update WFM line in crash.log
```

The next `mxc_update:` line after that breadcrumb is the one that matters:

```
mxc_update: <w>x<h> region @ (<x>, <y>) with marker <n> (WFM: <wfm> & UPD: <upd>)
```

crash.log will likely have other `mxc_update:` lines from ordinary UI
activity — use the breadcrumb's position, and cross-check the region's
`w`/`h`/`x`/`y` roughly match the self-test's own "Bars painted at
x=...,y=...,w=...,h=..." readout from Step 4, to make sure you've got the
right one.

---

## Step 6 — decision tree

The relevant constants (`base/ffi/mxcfb_kobo_h.lua`):

- `HWTCON_WAVEFORM_MODE_GC16 = 2` — grayscale, un-promoted.
- `HWTCON_WAVEFORM_MODE_GCC16 = 10` — Kaleido color, promoted. This is what
  SHOULD appear if the self-test's own refresh call is working as intended.

**If the line reads `WFM: 10`**: KOReader's software layer genuinely
requested a color update, and the promotion logic is proven correct all
the way to the ioctl boundary (this matches the static trace done this
round — see `.agents/notes/waveform-refresh-research.md`). The remaining
failure is downstream of KOReader — kernel driver, EPDC firmware, or the
physical panel — which is outside this plugin's (or even KOReader's)
control. **Stop chasing a software fix.** Document this conclusion
prominently wherever this investigation's status lives next
(`.agents/plans/grayscale-ink-and-eraser-handoff.md`), and consider
reporting it upstream to koreader-base if you want to pursue it further —
it would affect any KOReader app using color highlights on this device,
not just this plugin.

**If the line reads `WFM: 2` (or anything else)**: the promotion is NOT
happening at actual refresh time despite every plugin-level gate reading
true at self-test-snapshot time. That means there's a real, fixable
software bug in a place this investigation hasn't found yet — the
promotion logic itself was confirmed correct by static reading this round,
so something upstream of `mxc_update` (a stale `dither` flag, a gate that
flips between snapshot-time and refresh-time, a different code path being
hit than the one traced) needs runtime instrumentation to chase further —
e.g., a temporary `logger.dbg` breadcrumb inside the plugin's own
`setDirty` call, or in `UIManager:_refresh`/`_repaint`. Paste the exact log
line back for a fresh investigation pass — this is not a hardware
conclusion.
