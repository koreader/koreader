# ADR-003: Dual input path — raw evdev on device, gesture fallback in emulator

**Status:** Accepted  
**Date:** 2026-05 (Stage 2)

## Context

Pen input on Kobo requires reading raw `struct input_event` from
`/dev/input/eventX` to get pressure data and proper BTN_TOOL_RUBBER (eraser)
detection. KOReader's gesture layer does not expose these.

However, the SDL emulator used for development has no `/dev/input` and no
Wacom digitizer — it can only deliver pan/tap gesture events via mouse.

## Decision

Gate all raw evdev code behind `use_raw_input = Device:isKobo()`.

- **Device path** (`use_raw_input = true`): `PenDev` opens the digitizer fd,
  polls at ~120 Hz via `UIManager:scheduleIn`, feeds a `PenStateMachine`,
  and calls canvas handlers directly.
- **Emulator path** (`use_raw_input = false`): `ges_events.DrawStroke` /
  `DrawStrokeEnd` KOReader pan gesture handlers draw with fixed line width,
  no pressure. `ges_events` are always registered; handlers return early on
  device unless `finger_draw = true`.

Both paths must keep working at all times. Adding device-only features must
never break the emulator path.

## Consequences

- **Most development happens in the emulator** — widget layout, BlitBuffer,
  file I/O, menus all work without hardware.
- **Input stages require on-device testing** — `PenDev`, `TouchDev`,
  palm rejection, button input cannot be unit-tested.
- **`finger_draw` config flag** lets users enable touch drawing on device,
  which also exercises the gesture path end-to-end on real hardware.
- The gesture path's fixed line width is a known limitation; pressure is only
  available via the raw evdev path.
