# ADR-005: Undo stack is scoped to the current page

**Status:** Accepted  
**Date:** 2026-05 (Stage 11)

## Context

Undo/redo is implemented in `StrokeBuffer`. When navigating between pages,
the `StrokeBuffer` is replaced entirely (the new page is loaded fresh).
The question was: should undo history persist across page turns?

## Decision

**Undo is per-page.** Crossing a page boundary clears the undo stack.

When `_navigatePage` switches pages, `self._stroke_buf = StrokeBuffer.new()`
discards the old buffer and its undo history entirely.

## Consequences

- **Simple implementation:** no cross-page undo state to serialize, no memory
  growth from keeping old pages' undo stacks in memory.
- **Expected UX:** most drawing apps scope undo to the current document/page.
  Users are unlikely to expect cross-page undo.
- **Auto-save before page turn:** `_autoSave()` is called before `_navigatePage`
  replaces the buffer, so work is never lost — just not undo-able after return.
- **If cross-page undo is ever needed:** each page's `StrokeBuffer` would need
  to be retained in a `Notebook` object and swapped on page turn. Not worth the
  complexity for current use cases.
