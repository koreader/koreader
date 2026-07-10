# Tech debt / deferred cleanup

Small items noticed during review that weren't worth fixing mid-chunk.
Address opportunistically when touching the relevant file.

---

## Resolved

- **`model/page.lua`** — deleted along with `spec/page_spec.lua`. Confirmed
  orphaned (never required outside its own spec); canvas does all page I/O
  directly via `lib/svg`.
- **`StrokeBuffer:isDirty()`** — renamed to `hasStrokes()`. The old name
  implied unsaved-changes semantics; the canvas's own `_page_dirty` boolean
  is the actual unsaved-changes tracker.
- **`lib/config.lua` — not wired into production code.** Fixed:
  `main.lua:_openCanvas()` now calls `Config.load(DataStorage:getDataDir()
  .. "/settings/fastnote.conf")` and passes `finger_draw`, `rotation_mode`
  (as `init_rotation_mode`), `tighten_delay`, `tighten_enabled`, and
  `live_color_refresh` into `DrawingCanvas:new{}`. Along the way: the
  `develop_delay`/`develop_enabled` keys (never wired; the implementation
  calls this the "tighten" pass) were renamed to `tighten_delay` /
  `tighten_enabled` to match, and the config merge's `and/or` ternary was
  replaced with an explicit `if` (it silently discarded an explicit
  `false` for any key whose default is `true`). See
  `spec/config_spec.lua` and `fastnote.conf.example`.
