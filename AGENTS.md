# AGENTS.md — koreader (kittypimms-boop fork)

Read this before making changes to this repository.

---

## What This Repo Is

A fork of [KOReader](https://github.com/koreader/koreader) used as the host
environment for the **fastnote.koplugin** — a full-screen hand-drawn notebook
plugin for the Kobo Libra Colour. KOReader itself is not being modified; all
active development is in the plugin.

See `plugins/fastnote.koplugin/AGENTS.md` for plugin-specific context.

---

## Workflow

**Commit directly to `master`. No pull requests for regular development.**  
See ADR-007 in `.agents/ADRs/` for the reasoning.

- Run `busted spec/` in the plugin directory before pushing (183 tests, ~2s).
- The macOS CI workflow is disabled for auto-triggers (workflow_dispatch only).
- Push: `git push origin master`

---

## Repository Layout

```
plugins/fastnote.koplugin/   ← all active development happens here
.agents/
  ADRs/                      ← Architecture Decision Records for fastnote
  planning/                  ← completed planning docs (dev-plan-v2, landscape research)
.github/
  workflows/build.yml        ← macOS CI (manual trigger only)
  instructions/              ← coding guidelines (lua.instructions.md, etc.)
  skills/koreader-plugin/    ← KOReader plugin dev reference
doc/                         ← upstream KOReader developer docs
```

---

## Agent Artifact Directories

`.agents/` contains materials produced during development that aren't part of
the shipped plugin:

- **`.agents/ADRs/`** — Architecture Decision Records. When a non-obvious design
  choice was made, there's an ADR explaining the options considered and why the
  chosen approach was taken. Check here before re-opening settled questions.

- **`.agents/planning/`** — Planning documents, research notes, and superseded
  plans. Includes the full fastnote dev-plan-v2 (the canonical design doc) and
  the landscape research comparing alternative KOReader stylus plugins.

These directories aren't exhaustively catalogued — scan them when you need
background on a decision or feature area.

---

## Key Technical Context

- **Target hardware:** Kobo Libra Colour (KoboMonza). E-ink color display,
  Elan combo chip for pen+touch on event1.
- **KOReader version:** tip of koreader/koreader master (May 2026).
- **Lua dialect:** LuaJIT / Lua 5.1. See `.github/instructions/lua.instructions.md`.
- **No KOReader core modifications** — the plugin uses only the public plugin API.
