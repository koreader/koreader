# ADR-004: Synthesize BTN_TOUCH from ABS_MT_PRESSURE to suppress hover writes

**Status:** Accepted  
**Date:** 2026-05 (Stage 2 on-device fix)

## Context

The Kobo Libra Colour uses an Elan combo chip (event1) that handles both EMR
pen and capacitive touch on a single device node. The chip sends `EV_KEY
BTN_TOUCH=1` when the pen enters ~10 mm proximity — not at physical contact.
This caused the canvas to begin drawing strokes while the pen was hovering.

A canvas-level pressure guard (`MIN_PEN_PRESSURE = 50`) was tried first but
was insufficient: the state machine receives `BTN_TOUCH` before pressure
context is available per-event.

## Decision

Suppress `EV_KEY BTN_TOUCH` entirely in `pendev.lua` when the device is
identified as an MT pen chip, and synthesize contact/release from
`ABS_MT_PRESSURE` per SYN_REPORT frame instead.

Specifically, in `pendev.lua`:
- Set `_has_mt_pen = true` when `ABS_MT_TOOL_TYPE == 1` (pen slot) is seen
- Drop all subsequent `EV_KEY BTN_TOUCH` events
- On each `EV_SYN SYN_REPORT`: if pressure ≥ `PRESSURE_CONTACT_THRESHOLD (20)`,
  synthesize `BTN_TOUCH=1` to the state machine; if pressure < threshold and
  pen was down, synthesize `BTN_TOUCH=0`

## Consequences

- **Hover writes eliminated:** the pen must physically touch the screen
  (pressure ≥ 20 raw units) before a stroke begins.
- **Eraser hover also eliminated:** same path, same fix.
- **Threshold is a constant** (`PRESSURE_CONTACT_THRESHOLD = 20`). On-device
  observation showed hover pressure ~0–5, light contact ~50–200. 20 is
  conservative. If false negatives appear (light touches not registering),
  lower it; if hover still writes, raise it.
- **`_has_mt_pen` gate** means non-Elan Wacom devices (standard BTN_TOUCH via
  EV_KEY) are unaffected — the gate is only armed when MT pen tool-type is seen.
- The canvas retains `MIN_PEN_PRESSURE = 50` as a secondary guard.
