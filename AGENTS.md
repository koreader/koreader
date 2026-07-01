# AGENTS.md — koreader (kittypimms-boop fork)

**This repo is a host shell for one plugin. Read
`plugins/fastnote.koplugin/AGENTS.md` next — that file is the real entry
point for almost all work in this repo.**

---

## What This Repo Is

A fork of [KOReader](https://github.com/koreader/koreader) used as the host
environment for **fastnote.koplugin** — a full-screen hand-drawn notebook
plugin for the Kobo Libra Colour. KOReader core is not modified; essentially
all active development happens inside the plugin directory.

---

## Workflow

**Commit directly to `master`. No pull requests for regular development.**
See `.agents/ADRs/ADR-007-direct-to-master-no-prs.md` for the reasoning.

- Test gate: `cd plugins/fastnote.koplugin && busted spec/`
- The macOS CI workflow is disabled for auto-triggers (workflow_dispatch only).
- Push: `git push origin master`

---

## Where things live

```
plugins/fastnote.koplugin/   ← all active development; has its own AGENTS.md index
.agents/                     ← ADRs, planning, notes, superseded plans (repo root — see below)
.github/
  instructions/              ← facts/conventions, applyTo-scoped (lua, agents.md/.agents, doc-architecture)
  skills/koreader-plugin/    ← KOReader plugin dev reference (not yet added)
  skills/agents-md-authoring/           ← workflow for AGENTS.md and .agents/ docs
  skills/documentation-as-code/         ← keeping all docs in sync with code changes
  skills/test-driven-development/       ← when to write the spec first in this repo, and when not to
  skills/authoring-instructions-and-skills/  ← how to add new instructions/skills correctly
.claude/skills/               ← symlinks into .github/skills/ — see doc-architecture.instructions.md
doc/                         ← upstream KOReader developer docs (not plugin-specific)
```

`.agents/` is at the **repo root**, not inside the plugin directory, even
though its contents (ADRs, planning, notes) are almost entirely about the
plugin. Subdirectories: `ADRs/` (design decisions), `planning/` (dev plans,
research), `notes/` (topic references), `plans/` (chunk-level work plans).
Not exhaustively catalogued here — the plugin's own AGENTS.md links to the
specific files relevant to each area of the code.

**Adding a new instructions file or skill?** Read
`.github/instructions/doc-architecture.instructions.md` and
`.github/skills/authoring-instructions-and-skills/SKILL.md` first — they
cover the facts-vs-procedures split, Anthropic's Agent Skills authoring
rules, and the required `.claude/skills/<name>` symlink step (this repo is
primarily used from a GitHub Copilot / VS Code harness, so `.github/` stays
the portable source of truth; the symlinks give Claude Code live
auto-triggering on top of that).
