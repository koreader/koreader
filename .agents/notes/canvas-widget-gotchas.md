# DrawingCanvas widget-lifecycle gotchas

Applies to: `plugins/fastnote.koplugin/drawingcanvas.lua`

Three unrelated InputContainer/UIManager landmines that silently break the
canvas if violated. None of these produce a Lua error — they produce subtle
runtime misbehavior (dead gesture zones, rotation loops) that's hard to
trace back to the cause.

---

## `self.dimen` — in-place mutation only

`GestureRange` objects inside `self.ges_events` hold a **direct reference**
to the `self.dimen` table created at `init()`. Assigning a new table to
`self.dimen` (e.g. `self.dimen = Geom:new{...}`) silently detaches all
existing gesture zones from the widget's actual dimensions — taps stop
registering with no error.

**Rule:** always mutate `self.dimen.w` / `self.dimen.h` / etc. in place.
Never reassign `self.dimen` itself after `init()`.

## Orientation lock / re-lock

`drawingcanvas.lua` stores `self._rotation_mode` (the locked mode). On
`onSetRotationMode(event)`, if the incoming mode differs from
`self._rotation_mode`, the canvas calls `Screen:setRotationMode(self._rotation_mode)`
to re-lock — overriding whatever triggered the rotation (e.g. gyroscope).

No loop guard is needed: the re-lock call itself fires a second
`onSetRotationMode` event, but that event's incoming mode now equals
`self._rotation_mode`, so the `if` is false and recursion stops after one
extra hop.

## Gesture zone registration timing

Touch zones (`DrawStroke`/`DrawStrokeEnd`, chrome taps) must be registered
in `init()` — **not** in `onShow`. They are always registered regardless of
`use_raw_input`/`finger_draw`; the handlers themselves check those flags at
runtime and return early. This lets `finger_draw` be toggled live from the
menu without re-registering zones (which would require closing and
reopening the canvas).
