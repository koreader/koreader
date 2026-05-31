# Tech debt / deferred cleanup

Small items noticed during review that weren't worth fixing mid-chunk.
Address opportunistically when touching the relevant file.

---

## lib/config.lua — not wired into production code

`lib/config.lua` loads a `fastnote.conf` file and merges it with defaults.
It has a passing spec (`spec/config_spec.lua`) and a corresponding
`fastnote.conf.example` in the plugin root — clearly intended infrastructure.

**What's missing:** nobody calls `Config.load()`. The natural place is
`main.lua:onOpenFnoteCanvas()`, which should load the config file from
`DataStorage:getDataDir() .. "/fastnote.conf"` and pass relevant keys
(e.g. `finger_draw`, `rotation_mode`) into `DrawingCanvas:new{}` as
init params.

Until then the defaults in `Config.DEFAULTS` are the effective config
and the file is silently ignored.

---

## model/page.lua — superseded, never used

`model/page.lua` is a `Page` class wrapping a StrokeBuffer + SVG path,
with `load()`, `save()`, and `isDirty()`. It has a passing spec
(`spec/page_spec.lua`).

The canvas does all page I/O directly (via `lib/svg` in `loadPage()` /
`_autoSave()`), so `Page` is never instantiated anywhere outside its
spec. It's an early-design artefact that got bypassed.

**Options:** delete it and its spec (simplest), or adopt it as the
official page abstraction and refactor canvas to use it. Deleting is
probably right unless there's a future stage that would benefit from the
encapsulation.

---

## StrokeBuffer:isDirty() — misleading name

`StrokeBuffer:isDirty()` returns `#self.strokes > 0` (i.e. "has any
committed strokes"), not "has unsaved changes". The canvas uses its own
`_page_dirty` boolean for the unsaved-changes concept.

The name implies unsaved-changes semantics (like `Page:isDirty()` which
correctly tracks `_saved_n`). Should be renamed to `hasStrokes()` to
avoid confusion. Update `spec/strokebuffer_spec.lua` when doing so.
