# Plan: Bring .github/ skills & instructions up to current vendor guidance

**Status: EXECUTED**

Audit date: 2026-07. Sources verified live: Claude Code docs
(code.claude.com/docs/en/skills, /memory), Anthropic skill-authoring best
practices (platform.claude.com), the Agent Skills open spec
(agentskills.io / github.com/agentskills/agentskills), GitHub Copilot docs
(github/docs@main), VS Code Copilot docs (microsoft/vscode-docs@main,
dated 2026-07-01), agents.md standard (openai/agents.md source), OpenAI
Codex AGENTS.md docs.

---

## What the audit found is ALREADY CORRECT (do not "fix" these)

- All 4 skills: `name` ≤ 64 chars, lowercase-hyphen, matches parent
  directory name (now a REQUIREMENT in the open spec, not just convention).
- All 4 skills: `description` ≤ 1024 chars, third person, leads with
  what-then-when. Bodies 117–181 lines (limit guidance: 500).
- All 3 instructions files: dual `applyTo` (string, comma-separated) +
  `paths` (YAML list) frontmatter — both formats match current docs exactly.
- `.claude/skills` and `.claude/rules` directory symlinks: explicitly
  documented as supported by Claude Code ("resolved and loaded normally").
- Root `CLAUDE.md` → `AGENTS.md` symlink: officially documented pattern
  (Claude Code still does NOT read AGENTS.md natively — confirmed against
  current docs, which state "Claude Code reads CLAUDE.md, not AGENTS.md").
- Root AGENTS.md as a short router + linked detail files: matches OpenAI
  guidance ("keep the main file concise and reference task-specific
  markdown files") and community consensus.
- Instructions vs. skills facts/procedures split: still matches Anthropic
  guidance verbatim.

---

## Task 1 (P1): Fix outdated claims in doc-architecture.instructions.md

**File:** `.github/instructions/doc-architecture.instructions.md`

The section "Critical: neither `.github/` mechanism auto-loads in Claude
Code by name" contains claims that were true when written but are now
false or incomplete:

1. **"`.github/skills/<name>/SKILL.md` is a hand-rolled convention in this
   repo" — now FALSE.** GitHub Copilot adopted the open Agent Skills
   standard (changelog 2025-12-18). Copilot reads project skills natively
   from `.github/skills`, `.claude/skills`, or `.agents/skills`. Supported
   surfaces: Copilot cloud agent, code review, Copilot CLI, and agent mode
   in VS Code/JetBrains. Rewrite that bullet to say `.github/skills/` is a
   first-class location for BOTH Copilot (native) and Claude Code (via the
   `.claude/skills` symlink). The Claude-Code-doesn't-read-`.github/`-paths
   half of the claim is still true — keep it.

2. **Add the double-discovery caveat.** Because Copilot now also reads
   `.claude/skills` and (VS Code) `.claude/rules`, our symlinks mean
   Copilot can discover the same skill/instructions file from two paths.
   Anthropic docs say symlinked skills reachable twice are deduped in
   Claude Code; Copilot's dedup behavior is not documented. Add a short
   "watch item" paragraph: if duplicate skill listings or doubled
   instructions context appear in VS Code, the fix is a VS Code setting
   exclusion, not deleting the symlinks (Claude Code needs them).

3. **Update the Anthropic skills-rules section** with what's new:
   - The format is now the **Agent Skills open standard** (agentskills.io,
     stewarded openly; ~30+ tools). `name` MUST match the parent directory
     name (was convention, now spec).
   - New optional Claude Code frontmatter worth knowing when authoring:
     `when_to_use` (extra trigger phrases, appended to description in the
     listing; combined listing text truncates at 1,536 chars), `paths`
     (glob-scoped auto-activation — same format as rules `paths`),
     `argument-hint`, `user-invocable`, `disable-model-invocation`,
     `context: fork`. Spec-compliant tools ignore unrecognized keys, so
     these are safe to add in a portable repo.
   - Open-spec optional fields: `license`, `compatibility`, `metadata`.
   - The ~500-line body guidance is still current; the spec frames it as
     "instructions < 5,000 tokens recommended."

4. **Update the instructions-frontmatter section:** VS Code now supports
   optional `description` (shown on hover AND used for semantic matching
   of instructions to the task — improves auto-application) and `name`
   keys in `.instructions.md` files. Recommend adding `description` to
   each instructions file (Task 3). Also note GitHub's `excludeAgent` key
   exists (`"code-review"` / `"cloud-agent"`) — not needed here, just
   document that it exists.

**Verify:** re-read the file; every claim about what reads what should
match the support matrix in this plan's header sources.

---

## Task 2 (P1): Update authoring-instructions-and-skills/SKILL.md checklist

**File:** `.github/skills/authoring-instructions-and-skills/SKILL.md`

- Checklist item for `name`: add "matches the parent directory name
  exactly" (open-spec requirement).
- Step 2b template: add commented-out optional `when_to_use:` line with a
  one-line explanation.
- Step 2a template: add optional `description:` line (VS Code hover +
  semantic matching).
- Add one line to the intro: `.github/skills/` is read natively by GitHub
  Copilot (Dec 2025+); the `.claude/*` symlinks exist only for Claude
  Code. Keep it to a sentence — the principles live in
  doc-architecture.instructions.md (Task 1), don't duplicate.

**Verify:** cross-read both files side by side; no sentence should appear
in both (repo rule).

---

## Task 3 (P2): Add `description` frontmatter to all three instructions files

**Files:** `.github/instructions/{lua,agents,doc-architecture}.instructions.md`

Add a third frontmatter key to each (keep `applyTo` and `paths` unchanged):

```yaml
description: "<one sentence: what conventions this file governs>"
```

Suggested values:
- lua: "Lua 5.1/LuaJIT conventions and gotchas for fastnote.koplugin code."
- agents: "Content rules for AGENTS.md files and .agents/ docs — index-not-manual principle and where new content goes."
- doc-architecture: "How this repo splits agent docs between instructions files and skills, and the cross-tool discovery mechanics."

Rationale: VS Code uses `description` for semantic matching when deciding
which instructions to apply; Claude Code and GitHub cloud agent ignore the
extra key. Zero risk, better discovery.

**Verify:** YAML parses (three keys); Claude Code `/memory` still lists
the rules; no behavior change expected elsewhere.

---

## Task 4 (P2): Nested CLAUDE.md symlink for the plugin's AGENTS.md

**Action:**
```bash
cd plugins/fastnote.koplugin && ln -s AGENTS.md CLAUDE.md
```

Rationale: Claude Code does not read AGENTS.md, so the plugin's AGENTS.md
(the repo's real entry point) is currently invisible to Claude Code except
via the root file's prose pointer. Nested CLAUDE.md files load lazily —
"included when Claude reads files in those subdirectories" — which is
exactly the progressive-disclosure behavior this repo wants. Copilot cloud
agent reads `**/AGENTS.md` natively (nearest-wins), so Copilot needs no
change.

**Verify:** `readlink plugins/fastnote.koplugin/CLAUDE.md` → `AGENTS.md`;
start a Claude Code session, read a plugin file, confirm the plugin
AGENTS.md content is pulled in (check /context or /memory).

---

## Task 5 (P2): Path-scope the documentation-as-code skill (Claude Code)

**File:** `.github/skills/documentation-as-code/SKILL.md`

Add to frontmatter:

```yaml
paths:
  - "plugins/fastnote.koplugin/**"
  - ".agents/**"
```

Rationale: this skill's own description says it "triggers on the code
change itself" — Claude Code's new `paths` key on skills makes that
literal (auto-activates when working with matching files) instead of
relying on description matching alone. Other tools ignore the key
(spec-compliant behavior), so it stays portable.

**Verify:** edit a plugin file in a Claude Code session and confirm the
skill activates; confirm Copilot still lists the skill normally.

---

## Task 6 (P3): Optional — minimal .github/copilot-instructions.md

**File to create:** `.github/copilot-instructions.md`

github.com Copilot Chat (the web chat surface, as distinct from the cloud
agent) reads ONLY this file — not `.instructions.md`, not AGENTS.md. If
that surface is ever used with this repo, it currently gets zero context.
Create a ~10-line file: one-paragraph project overview (fork hosting
fastnote.koplugin; all dev in the plugin dir), the test command
(`cd plugins/fastnote.koplugin && busted spec/`), and a pointer to
`plugins/fastnote.koplugin/AGENTS.md`. Keep it short — GitHub docs warn
these lines ride along with every chat message.

Skip this task if the github.com chat surface is never used.

---

## Task 7 (P3): Root AGENTS.md hygiene

**File:** `AGENTS.md` (repo root; CLAUDE.md symlinks to it)

1. Remove the `skills/koreader-plugin/ ← ... (not yet added)` line from
   the directory tree — it's an aspirational placeholder, which is this
   repo's own documented anti-pattern (see documentation-as-code SKILL.md
   "anti-patterns" list). Re-add the line when the skill actually exists.
2. Update the `.github/` tree annotation to reflect that Copilot reads
   `instructions/` AND `skills/` natively, symlinks are Claude-Code-only.
3. If Task 4 executed: mention the plugin-level CLAUDE.md symlink in the
   tree.

**Verify:** every path in the tree exists on disk (`ls` each one — the
agents-md-authoring checklist rule).

---

## Explicitly considered and REJECTED (don't do these)

- **Renaming skills to gerund form.** Anthropic still *prefers* gerunds
  but explicitly accepts noun/action phrases; the repo's own
  doc-architecture file already documents this choice. Churn, no benefit.
- **Splitting lua.instructions.md (310 lines).** Copilot favors shorter
  instructions files, but it's path-scoped to Lua edits where all of it is
  relevant, and it's facts (no procedure to extract). Monitor; split only
  if it keeps growing.
- **Converting instructions files to skills** (or vice versa) — the
  facts/procedures split still matches all three vendors' current
  guidance.
- **Removing dual frontmatter.** VS Code reads `.claude/rules` with
  `paths` and `.github/instructions` with `applyTo`; Claude Code needs
  `paths`; GitHub cloud agent needs `applyTo`. Both keys stay.
- **`@AGENTS.md` import instead of the root CLAUDE.md symlink.** The
  import form is only better when Claude-specific content needs to be
  appended below it. There is none today; symlink stays until there is.

---

## Execution order & checklist

- [x] Task 1 — doc-architecture.instructions.md factual updates
- [x] Task 2 — authoring skill checklist/template updates
- [x] Task 3 — `description` on all instructions files
- [x] Task 4 — plugin CLAUDE.md symlink
- [x] Task 5 — `paths` on documentation-as-code skill
- [ ] Task 6 — copilot-instructions.md (confirm surface is used first; skipped pending confirmation)
- [x] Task 7 — root AGENTS.md hygiene
- [ ] Final: run the agents-md-authoring audit procedure (every referenced
      path exists; no claim contradicts the code)
- [x] Commit and push
