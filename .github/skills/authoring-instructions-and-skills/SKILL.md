---
name: authoring-instructions-and-skills
description: Creates a new .github/instructions/*.instructions.md file, a new .github/skills/<name>/SKILL.md file, or both together with the required .claude/skills/<name> symlink, following Anthropic's Agent Skills authoring rules and this repo's conventions. Use when adding a new coding convention, gotcha, workflow, checklist, or template to this repo's agent-facing docs, or when deciding whether new content needs an instructions file, a skill, or both.
---

# Authoring instructions and skills — workflow

This is the **process**: how to decide which mechanism a new piece of
content needs, and the concrete steps to create it correctly.

For the **principles** — why instructions and skills are split this way,
where they intersect, and the discovery/symlink mechanics — see
`.github/instructions/doc-architecture.instructions.md`, which applies
automatically whenever you touch `.github/instructions/`, `.github/skills/`,
or `.claude/skills/`. Read that first if you haven't already; this skill
assumes it.

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
- `applyTo` uses glob syntax; comma-separate multiple patterns
  (`"**/*.lua"`, `"**/AGENTS.md,**/.agents/**"`). This mirrors GitHub
  Copilot's path-scoped custom instructions format.
- **Link it from AGENTS.md** at the point where it's relevant — an
  instructions file that nothing points to will never be read by Claude
  Code (see the "critical" section in the paired instructions file).
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
---

# <Skill title>

<What this skill provides, one or two sentences. If a paired instructions
file exists, one line pointing to it for the "why" — don't restate the
principles here.>

---

## <Section — a checklist, template, or workflow step>

...
```

Then **immediately** wire the live-discovery symlink — this is not
optional polish, it's part of creating the skill:

```bash
cd .claude/skills && ln -s ../../.github/skills/<name> <name>
```

Verify it resolves before moving on:

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
      tags, doesn't contain "anthropic" or "claude". Gerund form
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
- [ ] The `.claude/skills/<name>` symlink exists and resolves.
- [ ] If a paired instructions file exists, both link to each other and
      neither duplicates the other's content.
- [ ] AGENTS.md (root or plugin, whichever is relevant) has a one-line
      pointer to the new file — otherwise Claude Code has no path to
      discovering it exists via the instructions side of the pair, even
      though the skill side auto-triggers via `.claude/skills/`.

---

## Worked example: this pair

`doc-architecture.instructions.md` (facts: the instructions-vs-skills
distinction, where they intersect, the symlink requirement, Anthropic's
naming/description rules) paired with this skill (procedure: the decision
steps, the two templates, the symlink command, this checklist). Neither
restates the other — the instructions file doesn't include the templates,
this skill doesn't re-explain *why* the split exists beyond a one-line
pointer.
