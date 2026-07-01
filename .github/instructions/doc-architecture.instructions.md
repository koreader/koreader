---
applyTo: ".github/instructions/**,.github/skills/**,.claude/skills/**"
---

# Instructions vs. Skills: how this repo's agent-facing docs are split

Applies whenever you're authoring or editing anything under
`.github/instructions/`, `.github/skills/`, or `.claude/skills/`. For the
step-by-step procedure — deciding which mechanism a new topic needs,
templates, and the naming/description rules to check before finishing —
see the sibling skill
`.github/skills/authoring-instructions-and-skills/SKILL.md`. This file is
principles; that skill is process. Don't restate one in the other.

---

## The core distinction: facts vs. procedures

This split is directly grounded in Anthropic's own Claude Code guidance:

> Create a skill when you keep pasting the same instructions, checklist, or
> multi-step procedure into chat, or when a section of CLAUDE.md has grown
> into a procedure rather than a fact. Unlike CLAUDE.md content, a skill's
> body loads only when it's used, so long reference material costs almost
> nothing until you need it.

Map that directly onto this repo's two mechanisms:

- **`.github/instructions/*.instructions.md`** — persistent **facts and
  conventions**. Things that are always true about a piece of the codebase:
  naming rules, invariants, gotchas, "this repo does X, not Y." No steps to
  execute, nothing to invoke — just a mindset that should shape how you
  read and write code in the matched paths. Loaded via the `applyTo` glob
  whenever a matched file is in play (mirrors GitHub Copilot's path-scoped
  custom instructions mechanism).
- **`.github/skills/<name>/SKILL.md`** — **procedures**. A checklist, a
  template, a multi-step workflow, an audit routine — something you *run*,
  not just *know*. Triggered by matching the skill's `description` against
  the task at hand, and loaded on demand (progressive disclosure — see
  below), not passively applied to every matching file.

**The test:** if you're about to write "always do X" or "X is true," that's
an instruction. If you're about to write "first do X, then do Y, then
check Z," that's a skill.

---

## Where they intersect on one topic

A topic often needs both — a mindset for the invariants, a procedure for
the workflow. When it does, split it into a paired instructions file and
skill, and **cross-link instead of duplicating**:

- The instructions file states the principles and links to the skill for
  "how to actually do this."
- The skill states the workflow and links to the instructions file for
  "why these rules exist" — it should not re-explain the mindset.

Existing pairs in this repo, as worked examples:

| Topic | Instructions (facts) | Skill (procedure) |
|-------|----------------------|--------------------|
| AGENTS.md / `.agents/` content | `agents.instructions.md` — index-not-manual principle, decision tree for where content goes, ADRs-are-historical rule | `agents-md-authoring/SKILL.md` — editing checklist, ADR/note templates, audit procedure |
| `.github/instructions/` and `.github/skills/` themselves | this file | `authoring-instructions-and-skills/SKILL.md` |

A topic that's pure fact with no procedure (e.g. `lua.instructions.md` —
language gotchas, nothing to "run") only needs an instructions file. A
topic that's pure procedure with no standing invariant to remember
(uncommon, but possible) only needs a skill.

---

## Critical: neither mechanism auto-loads the way you might assume

- **`.github/instructions/*.instructions.md` is a GitHub Copilot
  convention** (path-scoped custom instructions via `applyTo`). Claude Code
  does not natively read this directory. It only reaches Claude Code
  because `AGENTS.md` (which Claude Code *does* read at session start)
  contains an explicit one-line pointer to the relevant instructions file.
  If a new instructions file isn't linked from the AGENTS.md section it's
  most relevant to, Claude Code will never see it.
- **`.github/skills/<name>/SKILL.md` is not auto-discovered or
  auto-triggered by Claude Code either.** Per Anthropic's own docs, Claude
  Code only live-discovers skills from `.claude/skills/<name>/SKILL.md`
  (project) or `~/.claude/skills/<name>/SKILL.md` (personal) — matching
  the `description` field against the current task automatically, even
  mid-session.
- **This repo's fix: every skill under `.github/skills/<name>/` gets a
  relative symlink at `.claude/skills/<name>` pointing back to it.**
  ```bash
  cd .claude/skills && ln -s ../../.github/skills/<name> <name>
  ```
  Relative symlinks survive `git clone` on Linux/macOS (git stores the
  symlink target as a blob, checked out as a real symlink) and keep
  `.github/skills/` as the single source of truth — no duplicated content,
  no drift. This is why every new skill in this repo needs the symlink
  step; it's part of the skill's own creation procedure, not optional
  polish. `.github/skills/` stays the portable, cross-tool location (this
  project is also used from a GitHub Copilot / VS Code harness, where
  `.github/instructions/` and `.github/skills/` are the paths that matter);
  `.claude/skills/` exists purely so Claude Code sessions get live
  auto-triggering on top of that.

---

## Anthropic's Agent Skills rules that apply here

These are binding constraints on any `SKILL.md` in this repo (source:
Anthropic's Agent Skills documentation and authoring best-practices guide):

- **Frontmatter `name`**: max 64 characters, lowercase letters/numbers/
  hyphens only, no XML tags, cannot contain "anthropic" or "claude".
  Gerund form (`authoring-instructions-and-skills`) is Anthropic's stated
  preference for new skills; noun-phrase or action-oriented forms
  (`agents-md-authoring`, `test-driven-development`) are an acceptable
  alternative and are already established in this repo's existing skills
  — don't force a rename for cosmetic consistency alone.
- **Frontmatter `description`**: max 1024 characters, non-empty, no XML
  tags. **Always third person** — this field is injected into the system
  prompt for skill selection, and Anthropic explicitly warns that
  inconsistent point-of-view causes discovery problems. Never "I can help
  you..." or "You can use this to...". Lead with *what the skill does*,
  then *when to use it*, packed with the specific trigger terms a request
  would actually contain.
- **Progressive disclosure**: keep `SKILL.md`'s body under ~500 lines.
  Split larger content into separate reference files linked directly from
  `SKILL.md` (not nested — Claude may only partially read a file
  referenced from another referenced file, so keep all references one
  level deep). This repo's existing pattern for this is `.agents/notes/`:
  each `SKILL.md`/instructions file links out to a focused topic file
  rather than inlining detail.
- **No time-sensitive claims.** Don't write "as of May 2026" or "the
  current test count is N" into a skill or instructions file — those go
  stale silently. State the check to run instead (`busted spec/`), not a
  number that will drift.
