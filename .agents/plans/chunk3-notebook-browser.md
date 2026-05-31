# Chunk 3: Notebook browser (Stage 9)

**Branch:** master  
**Status:** ✅ Complete

---

## Goal

Replace "open last notebook on launch" with a proper browser screen.
- List view: notebook name + page count, sorted by last-edited (default)
- Create / rename / delete notebooks
- Opens at launch when >1 notebook exists; also reachable from canvas menu
- Thumbnail stub: `Notebook:getThumbnailPath()` → path (not yet generated)

---

## Design decisions

**Where it lives:**  
`ui/browser.lua` — a full-screen `InputContainer` widget, shown by `main.lua`
instead of jumping straight to `DrawingCanvas`.

**Trigger logic in main.lua:**
```
lib has 0 notebooks → create "My Notebook" → open canvas directly (first launch)
lib has 1 notebook  → open canvas directly (skip browser)
lib has 2+ notebooks → show browser
```
Additionally, a "Notebooks" button in the canvas hamburger menu always opens
the browser (saves current page first).

**Browser list item:** `[Notebook name]  [n pages]  [last edited date]`  
Tap → open notebook at last-used page.  
Long-press → context menu: Rename / Delete.

**Sort:**  
Default: last_edited descending (most recently touched first).  
Toggle button to switch to alphabetical. State persisted per-session only
(not to state.lua — not important enough).

**Rename:**  
`InputDialog` with pre-filled name; on confirm → `nb:rename(name)`.

**Delete:**  
`ButtonDialogTitle` confirm dialog (same pattern as clear-page).  
"Delete" button on the LEFT (per user's stated preference).

**Thumbnail stub:**  
`Notebook:getThumbnailPath()` returns `nb.dir .. "/thumb.png"`.  
File may not exist — caller should check. Stage 13 fills it in.

---

## Tasks

### ui/browser.lua
- [x] Module with `show(lib, on_open_notebook)` and `close()` API
- [x] `_build_items()`: "New notebook" first, sort toggle second, notebooks below
- [x] Each row: name + page count + last-edited date; tap → open; long-press → context menu
- [x] `_context_menu(nb)`: Rename (InputDialog) / Delete (confirm, Delete on left)
- [x] Sort toggle (last edited ↔ A→Z); session-only state
- [x] Calls `on_open_notebook(nb)` and closes menu on tap

### model/notebook.lua
- [x] Add `last_edited` field (unix timestamp, set on create, persisted via `save()`)
- [x] `getThumbnailPath()` stub: `nb.dir .. "/thumb.png"`

### model/library.lua  
- [x] `_sortOrder()`: sorts `_order` by `nb.last_edited` desc
- [x] Called after `_scan()` and after `createNotebook()`

### main.lua
- [x] Routing: 0 → create + canvas; 1 → canvas; 2+ → browser
- [x] Refactored into `_openCanvas()` and `_showBrowser()` helpers
- [x] `on_save_callback` updates `nb.last_edited` + persists
- [x] `on_show_browser` callback wired: closes canvas → shows browser

### drawingcanvas.lua
- [x] `on_show_browser = nil` field
- [x] "Notebooks" button in hamburger Row 5 (closes canvas, fires `on_show_browser`)

---

## Notes / open questions

- `last_edited` must be written to `notebook.lua` metadata on every save.
  The `on_save_callback` already fires after each auto-save — update there.
- `InputDialog` for rename: `require("ui/widget/inputdialog")` — standard KOReader widget.
- Scrollable list: Use `Menu` widget (KOReader's built-in list with scroll) or
  build with `ScrollableContainer` + `VerticalGroup`. The `Menu` widget is simpler
  but less customizable. Prefer `Menu` for the first version.
- `Menu` widget API: `Menu:new{ title, items=[{text, callback}], ...}`.
  Long-press support: `Menu` items support `hold_callback` alongside `callback`.

## Files to create/modify
- **Create:** `plugins/fastnote.koplugin/ui/browser.lua`
- **Modify:** `plugins/fastnote.koplugin/model/notebook.lua` (last_edited, thumbnail stub)
- **Modify:** `plugins/fastnote.koplugin/model/library.lua` (sort by last_edited)
- **Modify:** `plugins/fastnote.koplugin/main.lua` (routing, Notebooks menu item)
- **Modify:** `plugins/fastnote.koplugin/drawingcanvas.lua` (Notebooks menu item)
- **Possibly modify:** `plugins/fastnote.koplugin/spec/notebook_spec.lua` (last_edited tests)
- **Possibly modify:** `plugins/fastnote.koplugin/spec/library_spec.lua` (sort tests)

## Test checklist (busted)
- [x] `notebook_spec`: `last_edited` set on create, persists after explicit update + save
- [x] `notebook_spec`: `getThumbnailPath()` returns correct path
- [x] `library_spec`: sort by last_edited descending (rescan test)

## Test checklist (on device)
- [ ] Single notebook → goes straight to canvas (no browser flash)
- [ ] Multiple notebooks → browser shown with correct list
- [ ] Tap notebook → opens at last page
- [ ] New notebook → creates + opens
- [ ] Rename → updates name in list
- [ ] Delete (confirm, Delete button LEFT) → removed from list
- [ ] Sort toggle works
- [ ] "Notebooks" from canvas menu saves and returns to browser
