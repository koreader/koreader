# Panel Navigation

## Overview

Panel Navigation is a feature for reading comics and manga that enables panel-by-panel navigation. Instead of viewing the entire page, readers can zoom into individual panels and navigate between them in a configurable reading order.

This feature is particularly useful for:
- **Comics/Manga**: Read panel-by-panel in the correct reading direction
- **Small screens**: View panels at a comfortable zoom level on e-ink devices
- **Detailed artwork**: Focus on individual panels without manual zooming

## Architecture

### Modules

The panel navigation feature consists of two main modules:

1. **ReaderPanelNav** (`frontend/apps/reader/modules/readerpanelnav.lua`)
   - Core panel navigation logic
   - Panel detection, processing, and sorting
   - Panel visualization (debug boxes, current panel highlight)
   - Keyboard and touch navigation within ImageViewer

2. **ReaderHighlight** (`frontend/apps/reader/modules/readerhighlight.lua`)
   - Menu integration via `genPanelZoomMenu()`
   - Long-press panel zoom handler (`onPanelZoom`)

### Dependencies

```
ReaderPanelNav
    └── KoptInterface.getAllPanelsFromPage()
            └── KOPTContext.getAllPanelsFromPage()
                    └── Leptonica (pixConnCompBB - connected component analysis)
```

## Panel Detection

Panels are detected using Leptonica's connected component analysis on the rendered page image:

1. **Image Processing** (`base/ffi/koptcontext.lua`):
   - Convert page to grayscale
   - Invert image (to detect dark content on light background)
   - Apply binary threshold (value: 50)
   - Find connected components using `pixConnCompBB` with 8-connectivity

2. **Size Filtering**:
   - Panels must be at least 1/8 of page width AND 1/8 of page height
   - Smaller components are discarded as noise or panel fragments

## Panel Processing Pipeline

After detection, panels go through several processing steps in `ReaderPanelNav`:

### 1. Clip to Page Bounds (`clipPanelsToPage`)
Ensures all panel coordinates are within the page boundaries:
- Panels extending beyond edges are clipped
- Panels completely outside the page are removed

### 2. Merge Overlapping Panels (`mergeOverlappingPanels`)
Combines panels that overlap significantly:
- **Threshold**: 50% of the smaller panel's area
- Iteratively merges until no more overlapping panels remain
- Result: bounding box encompassing both original panels

### 3. Filter Nested Panels (`filterNestedPanels`)
Removes panels completely contained within other panels:
- Keeps only the outermost panel
- Prevents duplicate navigation through the same content

### 4. Sort by Reading Direction (`sortPanelsByReadingDirection`)
Orders panels according to the configured reading direction.

## Reading Directions

Eight reading directions are supported:

| Code | Description | Primary Axis | Use Case |
|------|-------------|--------------|----------|
| LRTB | Left→Right, Top→Bottom | Horizontal | Western comics |
| LRBT | Left→Right, Bottom→Top | Horizontal | - |
| RLTB | Right→Left, Top→Bottom | Horizontal | Manga |
| RLBT | Right→Left, Bottom→Top | Horizontal | - |
| TBLR | Top→Bottom, Left→Right | Vertical | Vertical panels |
| TBRL | Top→Bottom, Right→Left | Vertical | Manga (vertical) |
| BTLR | Bottom→Top, Left→Right | Vertical | - |
| BTRL | Bottom→Top, Right→Left | Vertical | - |

### Sorting Algorithm

The sorting algorithm uses **overlap-based grouping** to determine row/column membership:

1. **Row Mode** (LRTB, LRBT, RLTB, RLBT):
   - Panels with significant Y-axis overlap (≥30% of smaller height) are in the same row
   - Same row: sort by X position (primary_order)
   - Different rows: sort by Y position (secondary_order)

2. **Column Mode** (TBLR, TBRL, BTLR, BTRL):
   - Panels with significant X-axis overlap (≥30% of smaller width) are in the same column
   - Same column: sort by Y position (primary_order)
   - Different columns: sort by X position (secondary_order)

The 30% overlap threshold prevents panels with minimal overlap (e.g., 5%) from being incorrectly grouped together.

## Navigation

### Keyboard Navigation
- **P key**: Enter panel navigation mode (shows first panel in ImageViewer)
- **Left/Right arrows**: Navigate between panels while in ImageViewer

### Touch Navigation
While viewing a panel in ImageViewer:
- **Tap left 25%**: Previous panel
- **Tap right 25%**: Next panel
- **Tap center**: Toggle UI buttons

### Page Transitions
- Navigating past the last panel goes to the first panel of the next page
- Navigating before the first panel goes to the last panel of the previous page

## Settings

All settings are persisted per-document and can have global defaults:

| Setting | Description |
|---------|-------------|
| `panel_nav_enabled` | Enable/disable panel navigation |
| `panel_direction` | Reading direction code (LRTB, RLTB, etc.) |
| `highlight_current_panel` | Draw red box around current panel |
| `show_panel_boxes` | Debug mode: show all panels with numbers and coordinates |

## Menu Structure

Panel navigation options are in the **Panel zoom** menu (under highlight/selection settings):

```
Panel zoom
├── Allow panel zoom
├── Fall back to text selection
├── Enable panel navigation (requires panel zoom)
├── Panel reading direction (requires panel nav)
├── Highlight current panel (requires panel nav)
└── Show all detected panel boxes (debug) (requires panel nav)
```

## Caching

Panel detection results are cached in `DocCache` to avoid redundant computation:
- **Cache key**: `allpanels|<filepath>|<pageno>`
- Cache is invalidated when the document file changes

## Visualization

### Highlight Current Panel
When enabled, draws a red rectangle around the current panel on the page view.

### Debug Mode (Show All Panel Boxes)
When enabled, draws:
- Green rectangles around all detected panels
- Red rectangle around current panel
- Panel number and coordinates (x1,y1)-(x2,y2) on each panel

## Testing

Unit tests are in `spec/unit/readerpanelnav_spec.lua`:

```bash
./kodev test front readerpanelnav
```

Tests cover:
- Panel sorting for all 8 directions
- Overlap threshold detection
- Nested panel filtering
- Overlapping panel merging
- Page boundary clipping
- Intersection area calculations
- Direction settings validation

## Performance Considerations

- Panel detection uses Leptonica C library (fast native code)
- Results are cached per page
- Processing (merge, filter, sort) is done in Lua but only on page change

## Code References

- Panel navigation module: `frontend/apps/reader/modules/readerpanelnav.lua`
- Menu integration: `frontend/apps/reader/modules/readerhighlight.lua`
- Panel detection interface: `frontend/document/koptinterface.lua`
- Low-level detection: `base/ffi/koptcontext.lua` (`getAllPanelsFromPage`)
- Unit tests: `spec/unit/readerpanelnav_spec.lua`
