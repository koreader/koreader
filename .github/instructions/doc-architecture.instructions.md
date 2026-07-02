---
applyTo: ".github/instructions/**,.github/skills/**,.claude/skills/**,.claude/rules/**"
paths:
  - ".github/instructions/**"
  - ".github/skills/**"
  - ".claude/skills/**"
  - ".claude/rules/**"
description: "How this repo splits agent docs between instructions files and skills, and the cross-tool discovery mechanics."
---

# Instructions vs. Skills: how this repo's agent-facing docs are split

Applies whenever you're authoring or editing anything under
`.github/instructions/`, `.github/skills/`, `.claude/skills/`, or
`.claude/rules/`. For the step-by-step procedure — deciding which
mechanism a new topic needs, templates, and the naming/description rules
to check before finishing — see the sibling skill
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

## Critical: neither `.github/` mechanism auto-loads in Claude Code by name

- **`.github/instructions/*.instructions.md` is a GitHub Copilot
  convention** (path-scoped custom instructions via `applyTo`). Claude
  Code's native equivalent is `.claude/rules/*.md`, which uses a `paths:`
  YAML list instead of `applyTo:` — a different key, same idea. Claude Code
  does not read `.github/instructions/` by that path.
- **`.github/skills/<name>/SKILL.md` is now a first-class Copilot
  location** (GitHub Copilot adopted the open Agent Skills standard in
  December 2025 and reads `.github/skills/` natively across cloud agent,
  code review, Copilot CLI, and VS Code agent mode). Claude Code's native
  equivalent is `.claude/skills/<name>/SKILL.md` — live-discovered and
  `description`-matched against the task automatically, even mid-session.
  Claude Code does not read `.github/skills/` by that path.

**This repo's fix: two directory-level symlinks, not one per file.**

```bash
cd .claude && ln -s ../.github/skills skills && ln -s ../.github/instructions rules
```

`.claude/skills` and `.claude/rules` are each a **single symlink to the
whole sibling directory** — confirmed supported by Anthropic's docs
("The `.claude/rules/` directory supports symlinks... resolved and loaded
normally"). This means:

- A new file dropped into `.github/skills/<name>/` or
  `.github/instructions/<topic>.instructions.md` needs **no extra symlink
  step** — it appears under `.claude/skills/`/`.claude/rules/`
  automatically through the existing directory symlink. (An earlier version
  of this repo's setup symlinked each skill individually; that's obsolete —
  don't recreate that pattern.)
- `.github/` stays the single source of truth and the portable, cross-tool
  location (this project is primarily used from a GitHub Copilot / VS Code
  harness). `.claude/skills` and `.claude/rules` exist purely so Claude
  Code sessions also get live auto-discovery on top of that, with zero
  duplicated content.

**Every `.instructions.md` file needs both frontmatter keys**, with
equivalent glob values, so it scopes correctly under both tools from the
same physical file:

```yaml
---
applyTo: "src/**/*.ts"
paths:
  - "src/**/*.ts"
---
```

Without the `paths` key, Claude Code treats the file as **unconditional**
(loaded into every session, like a rule with no path scope at all) — it
does not understand `applyTo` and silently ignores it rather than erroring,
so a missing `paths` key is easy to overlook. Always add both.

VS Code also supports optional `description` (one sentence — shown on hover
and used for semantic matching when VS Code decides which instructions apply)
and `name` (display label) frontmatter keys. Adding `description` is
low-risk: Claude Code and the GitHub cloud agent ignore the extra key; only
VS Code IDE agent mode uses it. GitHub also defines `excludeAgent`
(`"code-review"` / `"cloud-agent"`) to suppress an instructions file from
specific surfaces — not currently needed here, but worth knowing it exists.

**Watch item: double-discovery.** Because Copilot now reads both
`.github/skills/` and `.claude/skills/` (and both `.github/instructions/`
and `.claude/rules/`), the directory-level symlinks mean each file is
reachable from two paths in VS Code agent mode. Anthropic's docs say
symlinked skills dedup in Claude Code; Copilot's dedup behavior is not
documented. If duplicate skill listings or doubled instructions context
appear in VS Code, the fix is a VS Code workspace exclusion targeting the
`.claude/` paths — do NOT delete the symlinks, as Claude Code requires them.

---

## Agent Skills rules that apply here

The `SKILL.md` format is the **open Agent Skills standard** (agentskills.io,
stewarded openly; adopted by ~30+ tools). Anthropic helped author the spec;
these rules reflect both the open standard and Anthropic's Claude Code
authoring guidance. Binding constraints on any `SKILL.md` in this repo:

- **Frontmatter `name`**: max 64 characters, lowercase letters/numbers/
  hyphens only, no XML tags, cannot contain "anthropic" or "claude",
  **MUST match the parent directory name exactly** — this moved from
  convention to a binding open-spec requirement when the Agent Skills format
  was published. Gerund form (`authoring-instructions-and-skills`) is
  preferred for new skills; noun-phrase or action-oriented forms
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
- **Progressive disclosure**: keep `SKILL.md`'s body under ~500 lines
  (the spec frames this as "instructions < 5,000 tokens recommended").
  Split larger content into separate reference files linked directly from
  `SKILL.md` (not nested — Claude may only partially read a file
  referenced from another referenced file, so keep all references one
  level deep). This repo's existing pattern for this is `.agents/notes/`:
  each `SKILL.md`/instructions file links out to a focused topic file
  rather than inlining detail.
- **Optional Claude Code frontmatter** (spec-compliant tools ignore
  unrecognized keys, so these are safe to add in a portable repo):
  `when_to_use` (extra trigger phrases appended to `description` in skill
  listings; combined text truncates at 1,536 chars), `paths` (glob-scoped
  auto-activation, same format as instructions `paths`), `argument-hint`,
  `user-invocable`, `disable-model-invocation`, `context: fork`.
- **Optional open-spec frontmatter**: `license`, `compatibility`,
  `metadata` — add these if the skill is intended for sharing beyond
  this repo.
- **No time-sensitive claims.** Don't write "as of May 2026" or "the
  current test count is N" into a skill or instructions file — those go
  stale silently. State the check to run instead (`busted spec/`), not a
  number that will drift.
