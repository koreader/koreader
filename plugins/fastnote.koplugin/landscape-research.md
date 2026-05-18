# KOReader Drawing/Stylus Plugin Landscape
## Research Notes for fastnote.koplugin — May 2026

All four repos cloned to `sandbox/kittypimms-boop/` for local study.

> **Note on sourcing:** The upstream research brief referenced `MoreFoxBeans/pixelart.koplugin` — this repo does not exist (404). The real pixelart plugin is `matthewashton-k/pixelart.koplugin`, and the README there still points to the old `MoreFoxBeans` org in its install instructions (suggesting the original account was deleted). Covered as `matthewashton-k/pixelart.koplugin` below.

> **Architectural correction:** The brief states we "must" use pencil.koplugin's `input.lua` replacement to get pen events. This is inaccurate — notes.koplugin demonstrates a cleaner approach that achieves the same result without modifying any KOReader core files. Our dev-plan-v2 raw evdev approach is a valid third path.

---

## 1. `mysticknits/pencil.koplugin` ★81 — Book Annotation Layer

**What it is:** Stylus annotation on top of EPUB pages. Not a standalone notebook — it overlays ink on the reading view.
**Cloned to:** `sandbox/kittypimms-boop/pencil.koplugin/`
**Hardware:** Built for Kobo Libra Colour (confirmed by author)
**License:** AGPL-3.0

### Input approach: modified `input.lua` replacement

Ships a patched copy of KOReader's `/frontend/device/input.lua` that injects `BTN_TOOL_PEN` / `BTN_TOOL_RUBBER` events into the gesture pipeline before they reach the gesture detector.

- **Pro:** Events arrive via KOReader's normal routing — no polling loop needed.
- **Con:** Requires shipping a modified core file. Drifts from upstream on KOReader updates. Installation is invasive (copy file into KOReader internals).
- **Not mandatory for our use case.** See notes.koplugin below for a cleaner hook approach.

### Interesting for fastnote

| Pattern | Where | Notes for us |
|---------|-------|-------------|
| **Annotation grouping** | `main.lua` | Time-and-proximity algorithm: if two strokes are within `GROUP_TIME_THRESHOLD_S` seconds and `GROUP_SPATIAL_THRESHOLD` pixels of each other, group them into one logical annotation. Useful for fastnote's future "auto-title by cluster" feature. |
| **Bookmark sync** | `main.lua` | Converts annotation groups to native KOReader bookmark entries (`"Pencil annotation on page X"`), making them appear in the side-panel index and searchable. Not applicable to fastnote (standalone notebook, not book-tied) but the API call pattern is worth knowing if we ever add "link note to book page" feature. |
| **Color picker UI** | `main.lua` | Experimental 10-color overlay UI without crashing the frame canvas. Uses `FrameContainer` + `HorizontalGroup` + `VerticalGroup` composition. Good reference for our Stage 8 color picker. |
| **Pen width picker UI** | `main.lua` | Same pattern as color picker. Our Stage 5 brush width UI can follow this. |
| **Eraser detection** | `main.lua` | `BTN_TOOL_RUBBER` (code 331) sets `eraser_tool_active = true`. Physical eraser flip on Kobo Stylus 2. |
| **busted test suite** | `spec/` | 7 spec files. Our `.busted` config and `spec/` structure are modeled on this. |
| **Undo stack** | `main.lua` | `undo_stack = {}` with simple push/pop. Their undo only stores whole-stroke data — not a diff. Acceptable for Stage 6. |

---

## 2. `prasy-loyola/notes.koplugin` ★49 — Standalone Notebook (Closest to fastnote)

**What it is:** Full-screen freehand notebook plugin — standalone blank canvas, no book dependency. Multi-page. Save as PNG.
**Cloned to:** `sandbox/kittypimms-boop/notes.koplugin/`
**Hardware:** Developed on **Kobo Libra 2 Colour** — directly relevant hardware
**License:** MIT

### Input approach: gesture detector wrapping (no file modification)

The cleanest of the three approaches. From the `inputlistener.lua` comment block:

> "What we do is we swap out the GestureDetector inside the Device.input with a function which feeds the parsed events into our own listener, and we are free to use these events to draw on the buffer."

The actual mechanism:
```lua
-- Save original, wrap it
self.original_feedEvent = Device.input.gesture_detector.feedEvent
Device.input.gesture_detector.feedEvent = function(s, ev)
    self:__feedEvent(ev)                   -- our handler first
    return self.original_feedEvent(s, ev)  -- then original (system gestures still work!)
end
```

Restored on widget close:
```lua
Device.input.gesture_detector.feedEvent = self.original_feedEvent
```

**Key distinction vs the brief's description:** The original `feedEvent` is still called — system gestures (page turns, menus) continue to work normally. This is a non-destructive intercept, not a swap. The brief's description ("swaps the gesture framework entirely, creating a clean sandbox") is misleading.

- **Pro:** No files modified. No drift from upstream. Plugin is self-contained.
- **Con:** Depends on KOReader's internal `gesture_detector.feedEvent` API, which could theoretically change.

**For fastnote:** This is a middle path between pencil.koplugin's invasive replacement and our raw evdev approach. Worth keeping in mind if the raw evdev path causes problems in the emulator. But our `use_raw_input` dual-path already handles the emulator case cleanly.

### Interesting for fastnote

| Pattern | File | Notes for us |
|---------|------|-------------|
| **`alphablitFrom` for transparent page overlay** | `widget.lua` | Pages use `TYPE_BBRGB32` with `TRANSPARENT_ALPHA` background. In `paintTo()`, they call `bb:alphablitFrom(page._bb, x, y, ...)` so the background shows through. Our approach (opaque white canvas, blitFrom) is simpler but this pattern is useful if we add template backgrounds. |
| **Tight dirty rect with brush padding** | `widget.lua` | `minX/minY/maxX/maxY` tracking per move event, then `Geom:new({x=minX, y=minY, w=maxX-minX, h=maxY-minY}):offsetBy(self.dimen.x, self.dimen.y)` then `±brushSize` padding on all sides. This is the exact pattern our `canvas_utils.compute_dirty_rect()` should implement. |
| **Bidirectional interpolation** | `widget.lua` `interPolate()` | Fills x-major and y-major segments separately to avoid diagonal gaps. More robust than lerp-based approach for fast strokes. |
| **Template backgrounds** | `widget.lua` | Load a PNG as a template, `alphablitFrom` it in `paintTo()` before drawing strokes. Cached in a `TEMPLATES` table (path → BlitBuffer). Could be our future "graph paper / ruled lines" background feature. |
| **PNG persistence** | `widget.lua` | `_bb:writePNG(filePath)` for save, `RenderImage:renderImageFile(filename, false, w, h)` for load. Their format is page-N.png + `.notes_meta.lua` sidecar for template metadata. We use SVG instead (better for stroke editing) but the PNG approach is simpler for a prototype. |
| **`KOBO_STYLUS_ERASER` via `eventAdjustmentHook`** | `inputlistener.lua` | Lower-level hook at `Device.input.eventAdjustmentHook` detects `code == mtCodes.KOBO_STYLUS_ERASER` (key code 331) and calls `Device.input:setCurrentMtSlotChecked("subtool", ToolSubType.ERASER)`. This sets a `subtool` field on the current MT slot that their gesture interceptor reads. A third way to detect the eraser tip — finer-grained than raw BTN_TOOL_RUBBER. |
| **Page model** | `widget.lua` | `pages = {}` array, each entry is `{_bb = BlitBuffer, templatePath = string}`. `currentPage` integer index. `newPage()`, `nextPage()`, `prevPage()`, `clearPage()`. Minimal but complete. Our Stage 3 multi-page model can be structurally similar. |
| **Finger input toggle** | `widget.lua` | `fingerInputEnabled` flag — when true, finger touch also draws (useful for devices without stylus). Their `ToolType.FINGER` check in `touchEventListener` gates it. Potential future preference for fastnote. |

### What they DON'T have (fastnote advantages)

- No undo/redo
- No SVG/vector output (PNG only — can't re-edit strokes)
- No palm rejection
- No pressure sensitivity

---

## 3. `SimonLiu423/eraser.koplugin` ★3 — Eraser Button → Text Highlight Wipe

**What it is:** Minimal utility. When the physical eraser button on the Kobo Stylus is held, tapping on a text highlight deletes it.
**Cloned to:** `sandbox/kittypimms-boop/eraser.koplugin/`
**Hardware:** Kobo with Kobo Stylus (any)
**License:** (no license file)

### Interesting for fastnote

| Pattern | Notes for us |
|---------|-------------|
| **BTN_TOOL_RUBBER detection in device.lua** | Shows which key code to watch for (`BTN_TOOL_RUBBER = 331` in KOReader's device table). Confirms our eraser event approach. pencil.koplugin and notes.koplugin use the same code. |
| **Absolute position intersection test** | When eraser is active, tests the pen position against the bounding boxes of existing text highlights to determine which one to delete. The bounding box test logic is usable for fastnote's future "erase stroke" hit-test (Stage 6). |

This repo is minimal — two files, ~150 lines total. Useful as confirmation of the eraser detection pattern but no deeper architecture to borrow.

---

## 4. `matthewashton-k/pixelart.koplugin` ★3 — Pixel Art Editor

**What it is:** Full pixel art editor — small canvases (default 64×64), zoom + pan, grid, full drawing tool suite.
**Cloned to:** `sandbox/kittypimms-boop/pixelart.koplugin/`
**Hardware:** Tested on Kindle (not Kobo); should work on any KOReader device
**License:** AGPL-3.0

> **On attribution:** This repo's README still points to `MoreFoxBeans/pixelart.koplugin` in install instructions. The MoreFoxBeans account no longer exists on GitHub — matthewashton-k appears to be a fork that outlived the original.

### Interesting for fastnote

| Pattern | File | Notes for us |
|---------|------|-------------|
| **Bresenham line algorithm** | `canvas.lua` `paintLine()` | Classic Bresenham using `err/dx/dy`. Uses `bb:setPixel()` for 1px or `bb:paintCircle()` for wider. Clean, portable, no dependencies. Lift directly for Stage 2 pressure-to-width line rendering. |
| **Lerp-based pencil interpolation** | `canvas.lua` `dragPencil()` | Iterates `for i = 0, 1, 1/dist(px,py,x,y) do` with `lerp()` to fill sub-pixel gaps between events. Simpler than bidirectional interpolation but slightly less gap-proof. |
| **Preview buffer pattern** | `canvas.lua` | For multi-step tools (line, rect, circle): `_preview` is a copy of `_image`. During drag, draw to `_preview`; on release, commit to `_image`. Prevents "ghost strokes" mid-draw. **Useful for fastnote's future straight-line tool.** |
| **Zoom + coordinate transform** | `canvas.lua` `tx()/ty()` | `tx(screen_x) = floor((screen_x - dim.x - view_x) / zoom)`. Inverse is `canvas_x * zoom + dim.x + view_x`. Clean example of separating canvas coordinates from screen coordinates. |
| **`_bb` as lazy display cache** | `canvas.lua` | `_bb` holds the rendered display buffer. Set to `nil` on canvas change; regenerated on next `paintTo()`. `_update()` just nils `_bb` and calls `_refresh()`. Our Stage 1 canvas should follow this lazy-regeneration pattern. |
| **Flood fill (4-dir and 8-dir)** | `canvas.lua` `floodFill()/fill()` | Recursive BFS using `bb:getPixel(x,y).a` for color comparison. **⚠️ CRITICAL WARNING:** This is a recursive implementation. On a pixel-art canvas (64×64 = 4096 pixels max) it's fine. On a full-screen fastnote canvas (1264×1680 = ~2.1M pixels), this WILL stack overflow LuaJIT's call stack. For fastnote's future fill tool, use an **iterative queue-based BFS** instead. |
| **`scheduleIn` polling for touch state** | `canvas.lua` | `UIManager:scheduleIn(0.1, drag_callback)` + `Device.input:getCurrentMtSlotData("x")` to poll continuously while touch is held. Same polling pattern as our dev-plan-v2 `pendev.lua` approach. Confirms this is a valid KOReader idiom. |
| **Canvas resize with content preservation** | `canvas.lua` `resizeCanvas()` | Allocates a temp buffer, blits old content, creates new canvas, blits back. The `blitFrom()` + `free()` + `nil` discipline is correct. |
| **`_bb:writePNG(bgr)` with BGR flag** | `canvas.lua` `saveImage()` | `Device:hasBGRFrameBuffer()` check before writing PNG. Some KOReader devices use BGR channel order. If fastnote ever exports PNG, remember this flag. |

---

## Summary: What to Borrow for fastnote

### High priority

| What | From | Stage |
|------|------|-------|
| Tight dirty rect calculation (minX/Y + brushSize padding) | notes.koplugin `widget.lua` | Stage 1 |
| `_bb` lazy display cache (`nil` on change, regenerate in `paintTo`) | pixelart `canvas.lua` | Stage 1 |
| Bresenham line for draw calls | pixelart `canvas.lua` `paintLine()` | Stage 2 |
| Bidirectional interpolation for smooth strokes | notes.koplugin `widget.lua` `interPolate()` | Stage 2 |
| `BTN_TOOL_RUBBER` code 331 for eraser end detection | all three | Stage 2 |
| Preview buffer pattern for future straight-line tool | pixelart `canvas.lua` | Stage 5+ |
| Color picker UI composition pattern | pencil.koplugin | Stage 8 |
| `alphablitFrom` + template background | notes.koplugin | Future |

### Decisions confirmed by research

| Decision | Evidence |
|----------|---------|
| Raw evdev is a valid approach (not mandatory to use input.lua) | notes.koplugin shows gesture_detector wrap works without any file modification |
| `scheduleIn` polling is a KOReader idiom | pencil.koplugin and pixelart both use it |
| busted is the right test framework | pencil.koplugin has 7 spec files; KOReader core uses it |
| `TYPE_BBRGB32` for color device, `TYPE_BB8` for grayscale | notes.koplugin and pixelart both handle this |
| Recursive flood fill is unsafe at full-screen scale | pixelart uses it; their canvas is max 64×64; use iterative BFS for Stage 10+ |

### Open question resolved

OQ2 (pen-only vs finger-draw by default): notes.koplugin has `fingerInputEnabled` toggle (off by default). pencil.koplugin is pen-only. Fastnote: pen-only by default, optional finger mode deferred to Stage 9.

---

## Repos on disk

```
sandbox/kittypimms-boop/
├── pencil.koplugin/    # mysticknits, 81★ — book annotation
├── notes.koplugin/     # prasy-loyola, 49★ — standalone notebook ← most similar to us
├── eraser.koplugin/    # SimonLiu423, 3★  — eraser button utility
└── pixelart.koplugin/  # matthewashton-k, 3★ — pixel art editor (algorithms)
```
