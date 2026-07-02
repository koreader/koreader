---
name: authoring-instructions-and-skills
description: Creates a new .github/instructions/*.instructions.md file, a new .github/skills/<name>/SKILL.md file, or both, with the dual applyTo/paths frontmatter needed for both GitHub Copilot and Claude Code to scope it correctly, following Anthropic's Agent Skills authoring rules and this repo's conventions. Use when adding a new coding convention, gotcha, workflow, checklist, or template to this repo's agent-facing docs, or when deciding whether new content needs an instructions file, a skill, or both.
---

# Authoring instructions and skills — workflow

This is the **process**: how to decide which mechanism a new piece of
content needs, and the concrete steps to create it correctly.

For the **principles** — why instructions and skills are split this way,
where they intersect, and the discovery mechanics — see
`.github/instructions/doc-architecture.instructions.md`, which applies
automatically whenever you touch `.github/instructions/`, `.github/skills/`,
`.claude/skills/`, or `.claude/rules/`. Read that first if you haven't
already; this skill assumes it.

`.github/skills/` is read natively by GitHub Copilot (December 2025+); the
`.claude/skills` and `.claude/rules` directory symlinks exist only for Claude
Code. **A new file in `.github/skills/` or `.github/instructions/` needs no
symlink step** — both tools see it automatically.

---

## Step 1: decide what you're creating

Ask in order:

1. **Is this a fact or invariant** (always true, no steps to run)?
   → Instructions file only. Go to Step 2a.
2. **Is this a procedure** (a checklist, a template, a multi-step
   workflow, an audit routine)?
   → Skill only. Go to Step 2b.
3. **Does it have both** — standing rules to remember *and* a repeatable
   process to run?
   → Both, paired and cross-linked. Do 2a and 2b, then Step 3.

If you're not sure, check whether an existing instructions file or skill
already covers adjacent ground — extend it rather than fragmenting the
topic across more files than necessary.

---

## Step 2a: create an instructions file

```markdown
---
applyTo: "<glob pattern(s), comma-separated for multiple>"
paths:
  - "<same glob pattern, one per list item>"
# description: "<optional: one sentence — VS Code shows on hover and uses for semantic matching>"
---

# <Topic> conventions

<One-sentence statement of what this file governs and when it applies.>
<If a paired skill exists, one line pointing to it for the workflow side.>

---

## <Rule or principle 1>

<Statement of the rule. State it as a fact, not a step. Include the "why"
only if it's non-obvious — Claude is already smart; don't explain things
it already knows (e.g. don't explain what a PDF is before saying "use
pdfplumber to extract text from PDFs").>

---

## <Rule or principle 2>

...
```

- Name it `.github/instructions/<topic>.instructions.md`.
- **Always include both `applyTo` and `paths`**, with equivalent glob
  values. `applyTo` is GitHub Copilot's key (comma-separated string,
  matches this repo's primary VS Code / Copilot harness). `paths` is
  Claude Code's key (YAML list, required for `.claude/rules/` to scope the
  file — without it Claude Code loads the file unconditionally into every
  session, silently, since it doesn't understand `applyTo` and won't error
  on the missing key). One glob per `paths` list item; `applyTo` keeps
  them comma-joined in a single string.
- **Link it from AGENTS.md** at the point where it's relevant — an
  instructions file that nothing points to won't be discoverable by an
  agent reading AGENTS.md as its starting point (Claude Code itself will
  still pick it up automatically via `.claude/rules/` once `paths`
  matches, but AGENTS.md is how a human or another tool finds it).
- No length ceremony here — instructions files in this repo are short by
  nature (a page or two); if one is growing past that, some of its content
  is probably actually a procedure that belongs in a skill instead.

---

## Step 2b: create a skill

```bash
mkdir -p .github/skills/<name>
```

```markdown
---
name: <name>
description: <what it does, third person, then when to use it>
# when_to_use: "<optional: extra trigger phrases appended to description for skill selection>"
---

# <Skill title>

<What this skill provides, one or two sentences. If a paired instructions
file exists, one line pointing to it for the "why" — don't restate the
principles here.>

---

## <Section — a checklist, template, or workflow step>

...
```

No symlink step needed — `.claude/skills` is a standing directory-level
symlink to `.github/skills`, so the new skill is live for Claude Code the
moment the directory exists. Sanity-check it resolves if you want
confirmation:

```bash
cat .claude/skills/<name>/SKILL.md | head -5
```

---

## Step 3: if you created both, cross-link and verify no duplication

- The instructions file's intro links to the skill for "how to do this."
- The skill's intro links back to the instructions file for "why these
  rules exist."
- Read both once, side by side: if a sentence in one could be deleted
  because the other already says it, delete it. Each file should be
  readable on its own, but neither should restate the other's content.

---

## Checklist before considering a new skill done

Straight from Anthropic's Agent Skills authoring rules — verify all of
these, don't skip any:

- [ ] `name`: max 64 chars, lowercase letters/numbers/hyphens only, no XML
      tags, doesn't contain "anthropic" or "claude", **matches the parent
      directory name exactly** (open-spec requirement). Gerund form
      (`processing-pdfs`) preferred for new skills; a clear noun/action
      phrase is an acceptable alternative if gerund reads awkwardly.
- [ ] `description`: max 1024 chars, non-empty, no XML tags, **written in
      third person** (never "I can..." or "you can..."). Leads with what
      the skill does, then when to use it, packed with the specific terms
      a real request would contain. Not vague ("helps with docs") —
      specific enough that Claude can pick this skill out of 100 others.
- [ ] Body is well under 500 lines. If it's approaching that, split
      detail into a separate reference file linked directly from
      `SKILL.md` — keep all references one level deep (don't reference a
      file that itself references another file).
- [ ] No time-sensitive claims (dates, test counts, "currently") baked in
      — state the check to run instead of a number that will drift.
- [ ] If this is an instructions file: both `applyTo` and `paths` are set,
      with equivalent glob values.
- [ ] If a paired instructions file exists, both link to each other and
      neither duplicates the other's content.
- [ ] AGENTS.md (root or plugin, whichever is relevant) has a one-line
      pointer to the new file — Claude Code will still auto-discover it via
      `.claude/rules/`/`.claude/skills/`, but AGENTS.md is how a human or
      another tool (Copilot, a fresh agent skimming the repo) finds it.

---

## Worked example: this pair

`doc-architecture.instructions.md` (facts: the instructions-vs-skills
distinction, where they intersect, the two symlinks and dual-frontmatter
mechanics, Anthropic's naming/description rules) paired with this skill
(procedure: the decision steps, the two templates, this checklist).
Neither restates the other — the instructions file doesn't include the
templates, this skill doesn't re-explain *why* the split exists beyond a
one-line pointer.
