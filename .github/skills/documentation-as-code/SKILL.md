---
name: documentation-as-code
description: Checks whether a code change invalidates a doc comment, ADR, config example, or AGENTS.md entry, and updates it in the same pass — documentation is part of writing the code, not a follow-up step. Use when writing or changing any code in this repo — a new function, changed behavior, a file added/removed/renamed, a changed config default, or a new architectural decision. Triggers on the code change itself, not on a separate "update the docs" request.
paths:
  - "plugins/fastnote.koplugin/**"
  - ".agents/**"
---

# Documentation as code

Documentation is part of writing the code, not a follow-up step. This skill
should fire **while you're making a code change**, not after — check it
before you consider any non-trivial edit finished. If a commit changes
behavior and a doc still describes the old behavior, the change is
incomplete, not "docs debt for later." This skill covers the discipline;
for the specific rules governing AGENTS.md and `.agents/` content, see the
sibling skill `.github/skills/agents-md-authoring/SKILL.md` (this skill
doesn't duplicate that one).

---

## "I'm about to finish this code change — what docs move with it?"

Run this list before considering any non-trivial code edit done — it's the
main reason this skill exists:

- **Changed a function's behavior or signature?** Update its `---` doc
  comment if one exists (add one if the behavior is now non-obvious from
  the name/signature alone).
- **Changed an architectural decision?** Amend the relevant ADR's
  Consequences with a note — don't rewrite the original Decision text (ADRs
  are historical; see agents-md-authoring's ADR rule).
- **Changed a user-facing config default or option?** Update
  `fastnote.conf.example` in the same commit.
- **Fixed a bug that a `.agents/notes/*.md` gotcha file describes?** Check
  whether that note needs updating — a fix can either resolve the gotcha
  entirely (update the note to say so) or reveal it wasn't fully understood
  (strengthen the note with what you learned).
- **Added, removed, or renamed a file?** Update AGENTS.md's File Map. This
  is the single most common thing that silently goes stale — verify with
  `ls`/`find`, don't just remember what you think is there.
- **Changed something a planning doc (`.agents/planning/`,
  `.agents/plans/`) described as "not yet implemented"?** Update its status
  line, or add a note pointing to what actually shipped if the final
  implementation diverged from the plan.

If none of these apply, the change genuinely doesn't need a doc update —
this list is a check, not a mandate to always touch a doc file.

---

## The four doc surfaces in this repo

Each has its own conventions — don't invent new ones, and don't duplicate
one surface's content into another:

1. **Code-level doc comments** — LuaDoc-style `---` above functions,
   `--[[-- ... --]]--` module headers (see any file under `lib/` for the
   pattern). Comment density and the WHY-not-WHAT rule live in
   `.github/instructions/lua.instructions.md` — don't restate that rule
   here, follow it.
2. **`AGENTS.md` / `.agents/`** — the index + ADRs/notes/planning structure.
   Governed entirely by `.github/skills/agents-md-authoring/SKILL.md`.
3. **Commit messages** — the permanent, searchable record of *why* a change
   was made. `git log`/`git blame` are how a future agent (or you, in six
   months) reconstructs reasoning that isn't in the code. Explain the
   motivation, not a restatement of the diff ("fix eraser mid-stroke
   detection by expanding the tool check to move events" beats "update
   drawingcanvas.lua").
4. **User-facing config docs** — `fastnote.conf.example` must stay in sync
   with `lib/config.lua`'s actual `Config.DEFAULTS` table. This is a live
   drift risk in this repo: `config.lua` isn't even wired into `main.lua`
   yet (see `.agents/notes/tech-debt.md`), so it's easy for the example
   file and the defaults table to silently diverge with nothing exercising
   either.

---

## Core disciplines

- **Single source of truth.** Never state the same fact in two files. If
  you're about to write a sentence that's already true somewhere else,
  link to it instead of repeating it. (This is the same rule that drove the
  AGENTS.md restructure — a duplicated fact is a fact that will eventually
  contradict itself when only one copy gets updated.)
- **Docs travel with the commit that invalidates them.** A change that
  alters behavior a doc describes updates that doc in the *same* commit.
  Splitting "code change" and "doc catch-up" across commits is how docs
  drift in the first place — the catch-up commit rarely happens.
- **Review doc changes with the same scrutiny as code.** Read every claim
  back against the actual code before committing it. Check that every
  referenced path/function/file actually exists — don't trust the previous
  revision of the doc to have been accurate when you wrote it.
- **Delete dead docs like dead code.** A note describing removed
  functionality is worse than no note — it actively misleads. When you
  delete or rename something the docs reference, update or remove that
  reference in the same pass, not "when someone notices."
- **Prefer terse-and-linked over comprehensive-and-inline.** Smaller doc
  diffs are easier to keep accurate over time. A one-line pointer to a
  focused file beats three paragraphs embedded where they'll be read out of
  context.

---

## Anti-patterns already seen in this repo (don't repeat these)

- A note describing a feature as "deferred / not implemented" for months
  after it actually shipped (`waveform-refresh-research.md`'s color-refresh
  timer section, and AGENTS.md's "Stage 12: not started" claim about the
  color picker — both were stale by the time they were caught).
- File-map entries pointing at files that were never created
  (`ui/colorpicker.lua`, `ui/chrome.lua`, `input/buttondev.lua`, a
  `state.lua` that became `model/library.lua` instead). These start as
  aspirational placeholders in a design doc and never get corrected once
  the implementation goes a different way.
- A resolved tech-debt item (`model/page.lua` deleted, `StrokeBuffer:isDirty()`
  renamed) left listed as still-open in `tech-debt.md` — the fix shipped,
  the doc didn't follow.
- Two copies of the same 874-line design doc
  (`plugins/fastnote.koplugin/dev-plan-v2.md` and
  `.agents/planning/fastnote-dev-plan-v2.md`) that can silently diverge if
  only one is edited — `diff` them whenever you touch either.

If you're auditing docs for staleness generally (not tied to a specific
code change), use the periodic audit procedure in
`.github/skills/agents-md-authoring/SKILL.md` — it covers this repo's
`.agents/` structure specifically.
