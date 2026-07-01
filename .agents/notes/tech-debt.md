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

## Resolved

- **`model/page.lua`** — deleted along with `spec/page_spec.lua`. Confirmed
  orphaned (never required outside its own spec); canvas does all page I/O
  directly via `lib/svg`.
- **`StrokeBuffer:isDirty()`** — renamed to `hasStrokes()`. The old name
  implied unsaved-changes semantics; the canvas's own `_page_dirty` boolean
  is the actual unsaved-changes tracker.
