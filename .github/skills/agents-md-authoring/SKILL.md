---
name: agents-md-authoring
description: Use when creating or editing any AGENTS.md, adding an ADR, adding a topic note under .agents/notes/, writing a planning/phase doc under .agents/planning/ or .agents/plans/, or auditing this repo's docs for staleness. Applies to both the repo-root AGENTS.md and plugins/fastnote.koplugin/AGENTS.md.
---

# Authoring AGENTS.md and .agents/ docs in this repo

This repo's docs went through a restructuring pass (2026-07) after AGENTS.md
had accumulated inline code examples, full architecture explanations, and
stage-by-stage prose. That content misled a reading agent into treating
tangential topics as relevant to whatever task it was actually doing, and
cost context on every read regardless of relevance. This skill exists so
that lesson doesn't need to be relearned.

---

## The core principle

**AGENTS.md is an index, not a reference manual.** It answers "what exists
and where is it handled" — never "how it works" or "why it was built that
way." If you're about to write more than one sentence explaining a decision,
a gotcha, or a piece of behavior inside AGENTS.md, stop — that content
belongs in a linked file instead, loaded only when the topic is relevant.

Detail files must be **self-contained**: a reader who opens only that one
file (with no other context) can act on it correctly.

---

## Decision tree: where does new content go?

Ask this in order — stop at the first match:

1. **"Where is X handled?" (a location, not an explanation)**
   → One line in AGENTS.md's File Map or Architecture section. No elaboration
   beyond a 3-8 word description.

2. **A settled architectural decision — this approach over that, and why**
   → New ADR: `.agents/ADRs/ADR-NNN-slug.md` (repo root). Use the next
   sequential number. See "ADR template" below.

3. **A gotcha or invariant scoped to one code area, that causes silent
   misbehavior (not a crash) if violated**
   → New note: `.agents/notes/<topic>.md` (repo root). Add one row to
   AGENTS.md's "Topics" table. See "Topic note template" below.

4. **A multi-step plan, phase breakdown, or research writeup for upcoming
   or in-progress work**
   → `.agents/planning/` (design docs, research) or `.agents/plans/`
   (chunk-level implementation plans with a Status line). Not linked from
   AGENTS.md's Topics table unless it's a primary reference like the dev
   plan — most planning docs are found by scanning the directory, not
   indexed individually.

5. **A language-level convention (naming, syntax gotchas) that applies
   repo-wide, not to one feature area**
   → `.github/instructions/<lang>.instructions.md`.

6. **Current status / stage completion**
   → One line in AGENTS.md's "Current State", pointing to the planning doc
   for the full breakdown. Never a full stage table or checklist in
   AGENTS.md itself — those go stale fast and belong in the planning doc,
   which is expected to be edited as phases complete.

If nothing above fits, it probably doesn't belong in `.agents/` at all —
consider whether it's just a code comment, or genuinely not worth writing
down.

---

## This repo's specific layout (don't rediscover this)

- **Two `.agents/` directories exist.** The canonical one is at the **repo
  root** (`/koreader/.agents/`), even though its contents are almost
  entirely about the fastnote plugin. There's also a smaller, mostly
  superseded `plugins/fastnote.koplugin/.agents/planning/` — new content
  goes in the repo-root one unless you have a specific reason to use the
  plugin-local one.
- **AGENTS.md files must state paths as repo-root-relative when the
  AGENTS.md itself isn't at repo root.** `plugins/fastnote.koplugin/AGENTS.md`
  references `.agents/ADRs/...` — a relative link from that file's own
  directory would resolve wrong. Say so explicitly ("relative to the repo
  root") rather than relying on the reader to guess.
- **`plugins/fastnote.koplugin/dev-plan-v2.md` is a convenience copy** of
  `.agents/planning/fastnote-dev-plan-v2.md` (repo root). If you edit one,
  `diff` them and sync the other — don't let them silently drift.
- Root `AGENTS.md` should stay minimal and route to the plugin's AGENTS.md
  fast — nearly all active work happens inside the plugin, not at repo root.

---

## Checklist for every AGENTS.md edit

- [ ] No inline code examples — link to the instructions/notes file instead.
- [ ] No paragraph-plus explaining *why* — one clause, then a link.
- [ ] Every File Map / Topics entry points to a file that **actually
      exists** — verify with `ls`/`find` before writing the line. (This repo
      has shipped phantom entries before: `ui/colorpicker.lua`,
      `ui/chrome.lua`, `input/buttondev.lua`, and a `state.lua` were all
      listed as real files when the functionality was actually inline
      elsewhere or never built as a separate file.)
- [ ] No hardcoded volatile numbers (test counts, "as of" dates, stage
      counts) that will silently drift. Say "run `busted spec/`" instead of
      "187 tests"; say "see the planning doc for current stage status"
      instead of embedding a stage table.
- [ ] Any claim about what's implemented/not-implemented is checked against
      the actual code in this pass, not copied from the previous AGENTS.md
      revision. Docs drift; code doesn't lie.
- [ ] If a linked note file's underlying implementation changed, update the
      note file — not AGENTS.md. AGENTS.md's line for that topic should stay
      a stable one-liner across many implementation changes underneath it.

---

## ADR template

```markdown
# ADR-NNN: <short decision title>

**Status:** Accepted
**Date:** YYYY-MM (Stage N, if applicable)

## Context

<the problem; the options considered, briefly>

## Decision

<what was chosen, concretely — include the actual format/algorithm/structure
if that's the substance of the decision>

## Consequences

- <what this makes easy>
- <what this makes hard, or a tradeoff accepted>
- <a landmine or non-obvious follow-on effect, if any>
```

ADRs are **historical records** — once Accepted, don't rewrite the Decision
to match later implementation drift. If reality diverges from what an ADR
describes (e.g. a planned file that got folded into another module), add a
short parenthetical or line in Consequences noting the drift. Don't silently
edit the original decision text.

---

## Topic note template (`.agents/notes/<topic>.md`)

```markdown
# <Topic name>

Applies to: <file path(s)>
See also: <related ADR/note, if any>

---

## The rule

<the invariant or gotcha, stated as a rule — one paragraph>

## Why this matters

<what breaks if violated — concrete, ideally referencing a real incident>

## Where to check when touching this area

<a short list of specific functions/call sites to verify>
```

Keep notes scoped to one topic. If a note grows past ~80 lines or starts
covering two unrelated gotchas, split it — the whole point is that an agent
loads only what's relevant to its current task.

---

## Periodic audit procedure

Run this whenever asked to "review the docs" or before a large refactor
that will touch many files referenced in AGENTS.md:

1. For every path mentioned in AGENTS.md's File Map and Topics table,
   confirm the file exists (`ls`/`find`). Remove or correct any that don't.
2. For every "not started" / "not implemented" / "planned" claim, grep the
   actual code to confirm it's still true.
3. Diff any "convenience copy" files against their canonical source.
4. Check ADRs for implementation drift (a referenced file/function that no
   longer exists or was renamed) — add a Consequences addendum, don't
   rewrite the Decision.
5. Check `.agents/notes/` files for descriptions of behavior that has since
   shipped or changed — update the note in place.
