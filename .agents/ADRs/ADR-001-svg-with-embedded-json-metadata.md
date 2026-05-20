# ADR-001: SVG files with embedded JSON metadata for page storage

**Status:** Accepted  
**Date:** 2026-05 (Stage 4/5)

## Context

Each fastnote page needs to be persisted. Options considered:

1. **Plain SVG only** — write `<polyline>` elements, discard stroke data
2. **SVG + separate `.json` sidecar** — two files per page
3. **SVG with embedded JSON in `<metadata>`** — one file, lossless

## Decision

One file: SVG with stroke data embedded in a `<metadata>` block.

The `<metadata>` block contains the full JSON `[{color, pts:[x,y,w,...]}, ...]`
array. `svg.write` always emits both the `<metadata>` JSON and the visual
`<polyline>` elements. `svg.read` prefers the `<metadata>` block; if absent
(e.g. hand-edited externally), falls back to parsing `<polyline>` elements.

## Consequences

- **Lossless round-trip:** `svg.read(svg.write(buf))` is identity on stroke data.
  Pressure values, exact point counts, and per-stroke color survive save/load.
- **Human-readable fallback:** Files open in any SVG viewer without plugin.
- **No sidecar management:** Moving/copying a page file is atomic.
- **Slightly larger files** than plain SVG, but negligible for typical stroke counts.
- **`svg.read` must be robust** to malformed `<metadata>` — falls back to polylines,
  never crashes on corrupt input.
