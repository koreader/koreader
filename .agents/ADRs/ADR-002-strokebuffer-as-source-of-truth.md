# ADR-002: StrokeBuffer is the source of truth, BlitBuffer is a display cache

**Status:** Accepted  
**Date:** 2026-05 (Stage 1)

## Context

Two data structures hold drawing state:

- **BlitBuffer** (`_bb`) — raw pixel data, composited directly to screen
- **StrokeBuffer** (`_stroke_buf`) — ordered list of `Stroke` objects, each a
  flat `{x,y,w, x,y,w, ...}` point array plus a color

One of them must be the authority for: serialization, undo, erase, color changes.

## Decision

**StrokeBuffer is the source of truth.** BlitBuffer is a derived display cache
that can be fully rebuilt at any time by replaying `StrokeBuffer:repaintTo(bb)`.

All persistent operations (SVG save/load, undo push/pop, erase) operate on
`StrokeBuffer` and then trigger a full repaint. The BlitBuffer is never serialized.

## Consequences

- **Undo/erase are trivial:** mutate the stroke list, call `_repaintAll()`.
- **Color toggle (dark mode) is possible:** iterate strokes, invert `.color`,
  repaint. Would be impossible if only pixel data were kept.
- **`_repaintAll()` is the only path to display update** for structural changes;
  fast `setDirty("fast")` is used only for individual live stroke segments.
- **Memory:** both structures coexist. On a 1448×1072 canvas, the BB8 buffer
  is ~1.5 MB. Acceptable for a Kobo's RAM budget.
- **Never treat BlitBuffer as authoritative.** Any code that reads pixel data
  back from `_bb` to make decisions is a bug.
