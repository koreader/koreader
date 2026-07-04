# Arrow Key Page Turning — KOReader macOS Build

## Goal

Make all four arrow keys (Up, Down, Left, Right) turn pages in KOReader on the macOS SDL build. Keep scroll/pan functionality accessible via Shift+arrow.

## Approach

Always-on mapping with Shift-modifier fallback for scroll.

## Mapping

| Key | Paging (PDF) | Rolling (EPUB page mode) | Rolling (scroll mode) |
|-----|-------------|--------------------------|----------------------|
| Left | Prev page | Prev view | Prev view |
| Right | Next page | Next view | Next view |
| Up | Prev page | Prev view | Prev view |
| Down | Next page | Next view | Next view |
| Shift+Up | Pos scroll up | Pan up | Pan up |
| Shift+Down | Pos scroll down | Pan down | Pan down |
| PageUp / F6 | Prev page | Prev view | Prev view |
| PageDown / F7 | Next page | Next view | Next view |

## Rationale

- Left/Right already turn pages on macOS SDL (mapped in `hasKeys` branch)
- Up/Down are currently position scroll (paging) or pan (rolling) — not page turn
- Shift-modifier preserves scroll/pan access without losing the key for page turning
- No new settings needed; follows KOReader's existing modifier key pattern

## Changes

### 1. `frontend/apps/reader/modules/readerpaging.lua`

**Lines 69-73** — Add `"Up"`/`"Down"` to the page-turn key events in the `hasKeys` branch. Move position-scroll to Shift-modifier keys.

```lua
self.key_events.GotoNextPage = { { { "RPgFwd", "LPgFwd", "Down", not Device:hasFewKeys() and next_key } }, event = "GotoViewRel", args = 1 }
self.key_events.GotoPrevPage = { { { "RPgBack", "LPgBack", "Up", not Device:hasFewKeys() and prev_key } }, event = "GotoViewRel", args = -1 }
self.key_events.GotoNextPos = { { "Shift", "Down" }, event = "GotoPosRel", args = 1 }
self.key_events.GotoPrevPos = { { "Shift", "Up" }, event = "GotoPosRel", args = -1 }
```

### 2. `frontend/apps/reader/modules/readerrolling.lua`

**Lines 135-141** — Add `"Up"`/`"Down"` to page-turn events in the `hasDPad` branch. Move panning to Shift-modifier.

```lua
elseif Device:hasDPad() then
    self.key_events.MoveUp = { { "Shift", "Up" }, event = "Panning", args = {0, -1} }
    self.key_events.MoveDown = { { "Shift", "Down" }, event = "Panning", args = {0,  1} }
end
if (Device:hasDPad() and not Device:useDPadAsActionKeys()) or (Device:hasKeys() and not Device:useDPadAsActionKeys()) then
    self.key_events.GotoNextView = { { { "RPgFwd", "LPgFwd", "Down", next_key } }, event = "GotoViewRel", args = 1 }
    self.key_events.GotoPrevView = { { { "RPgBack", "LPgBack", "Up", prev_key } }, event = "GotoViewRel", args = -1 }
end
```

## Files NOT modified

- `event_map_sdl2.lua` — Up/Down already mapped (lines 74-78)
- `input.lua` — Already tracks Shift modifier (line 773-780) and includes Up/Down in repeat list (line 788-789)
- `key.lua` — `Key:match()` natively handles `{ "Shift", "Down" }` pairs (lines 59-91)
- `physical_buttons.lua` — No new setting needed

## Verification

1. `./kodev build`
2. `./kodev run`
3. Test in both EPUB and PDF documents:
   - Right → next page, Left → prev page
   - Down → next page, Up → prev page
   - Shift+Down → scroll down, Shift+Up → scroll up
   - PageUp/PageDown, F6/F7 unchanged
