# ADR-006: UUID-named directories for notebook storage

**Status:** Accepted  
**Date:** 2026-05 (Stage 6)

## Context

Notebooks need a stable identifier that survives renames and is sortable by
creation time. Options:

1. **Name-based directories** — `My Notebook/` — breaks on rename
2. **Sequential integers** — `001/`, `002/` — conflicts if notebooks are deleted
3. **Random UUID** — stable but not sortable by time
4. **Timestamp-prefixed UUID** — `nb_<timestamp>_<seq>_<rand>` — sortable

## Decision

Timestamp-prefixed UUID: `nb_{unix_timestamp}_{seq3}_{rand6}`.

Format: `nb_1747000000_001_123456`

- Alphabetical sort = chronological creation order (used in `Library:_scan`)
- `<seq3>` guarantees uniqueness when multiple notebooks are created in the
  same second within one process
- `<rand6>` prevents collision across processes (e.g. two KOReader instances)

Directory layout:
```
<datadir>/fastnote/
  state.lua                    ← last_notebook_uuid, last_page_index
  notebooks/
    nb_<timestamp>_<seq>_<rand>/
      notebook.lua             ← name, created_at, pages list
      page_001.svg
      page_002.svg
      ...
```

## Consequences

- **Rename is free:** `Notebook:rename()` only updates `notebook.lua`; the
  directory name is immutable.
- **Deletion is clean:** `Library:deleteNotebook` does `rm -rf dir` — no
  orphaned page files.
- **App-wide state persists the UUID**, so KOReader re-opens the last-used
  notebook and page on next launch, even after renames. (Implemented inside
  `model/library.lua`, not as the standalone `state.lua` shown in the
  directory layout above.)
- **`io.popen("ls -1 ... | sort")`** for scanning — works on Kobo Linux.
  If a future Kobo ships a shell without `ls`, this breaks. Acceptable tradeoff
  for now; `lfs` (LuaFileSystem) would be the alternative.
