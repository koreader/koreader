---
applyTo: "**/AGENTS.md,**/.agents/**"
---

# AGENTS.md and .agents/ conventions

Mindset and content rules for this repo's agent-facing documentation —
applies automatically whenever you're editing an `AGENTS.md` file or
anything under a `.agents/` directory. For the step-by-step editing
checklist, ADR/note templates, and the periodic audit procedure, see
`.github/skills/agents-md-authoring/SKILL.md` instead — this file is
principles, that skill is process. Don't restate one in the other.

---

## The core principle

**AGENTS.md is an index, not a reference manual.** It answers "what exists
and where is it handled" — never "how it works" or "why it was built that
way." If you're about to write more than one sentence explaining a
decision, a gotcha, or a piece of behavior inside AGENTS.md, stop — that
content belongs in a linked file instead, loaded only when the topic is
relevant to the task at hand.

This isn't a style preference. An AGENTS.md padded with implementation
detail misleads a reading agent into treating tangential topics as
relevant to whatever it's actually doing, and costs context on every read
regardless of relevance — the opposite of what an index is for.

Every linked detail file must be **self-contained**: a reader who opens
only that one file, with no other context, can act on it correctly.

---

## Decision tree: where does new content go?

Ask this in order — stop at the first match:

1. **"Where is X handled?" (a location, not an explanation)**
   → One line in AGENTS.md's File Map or Architecture section. No
   elaboration beyond a 3-8 word description.

2. **A settled architectural decision — this approach over that, and why**
   → New ADR: `.agents/ADRs/ADR-NNN-slug.md`.

3. **A gotcha or invariant scoped to one code area, that causes silent
   misbehavior (not a crash) if violated**
   → New note: `.agents/notes/<topic>.md`, linked from AGENTS.md's Topics
   table.

4. **A multi-step plan, phase breakdown, or research writeup for upcoming
   or in-progress work**
   → `.agents/planning/` (design docs, research) or `.agents/plans/`
   (chunk-level implementation plans with a Status line). Not linked from
   AGENTS.md's Topics table unless it's a primary reference like the dev
   plan — most planning docs are found by scanning the directory, not
   indexed individually.

5. **A convention that applies repo-wide, not scoped to `.agents/` or one
   feature area**
   → mindset/conventions go in a sibling `.github/instructions/<topic>.instructions.md`
   (applies automatically via `applyTo`, same mechanism as this file);
   step-by-step workflow, tools, and templates go in
   `.github/skills/<topic>/SKILL.md` (invoked explicitly for a task). This
   file plus `.github/skills/agents-md-authoring/SKILL.md` is the reference
   example of that split — mirror it rather than mixing both kinds of
   content into one file.

6. **Current status / stage completion**
   → One line in AGENTS.md's "Current State", pointing to the planning doc
   for the full breakdown. Never a full stage table or checklist in
   AGENTS.md itself — those go stale fast and belong in the planning doc,
   which is expected to be edited as phases complete.

If nothing above fits, it probably doesn't belong in `.agents/` at all —
consider whether it's just a code comment, or genuinely not worth writing
down.

---

## ADRs are historical records

Once an ADR's Status is Accepted, its Decision text is a record of what was
decided and why at the time — not a living document. If reality later
diverges from what an ADR describes (a planned file that got folded into
another module, an approach later superseded), add a short note to its
Consequences section. Don't silently edit the original Decision text to
match implementation drift — that erases the history the ADR exists to
preserve.

---

## This repo's specific layout (don't rediscover this)

- **Two `.agents/` directories exist.** The canonical one is at the **repo
  root** (`/koreader/.agents/`), even though its contents are almost
  entirely about the fastnote plugin. There's also a smaller, mostly
  superseded `plugins/fastnote.koplugin/.agents/planning/` — new content
  goes in the repo-root one unless there's a specific reason to use the
  plugin-local one.
- **State paths as repo-root-relative when the AGENTS.md itself isn't at
  repo root.** `plugins/fastnote.koplugin/AGENTS.md` references
  `.agents/ADRs/...` — a relative link from that file's own directory
  would resolve wrong. Say so explicitly ("relative to the repo root")
  rather than relying on the reader to guess.
- **`plugins/fastnote.koplugin/dev-plan-v2.md` is a convenience copy** of
  `.agents/planning/fastnote-dev-plan-v2.md` (repo root). They must stay
  byte-identical — `diff` them whenever either is touched.
- **Root `AGENTS.md` stays minimal and routes to the plugin's AGENTS.md
  fast.** Nearly all active work happens inside the plugin, not at repo
  root.
