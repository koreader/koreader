# ADR-007: Direct commits to master, no pull request workflow

**Status:** Accepted  
**Date:** 2026-05

## Context

This is a solo-developer project. The default CI triggers (`push`, `pull_request`)
were inherited from the KOReader upstream fork but add friction with no benefit:
no external reviewers, no required checks passing before merge.

## Decision

- **Commit directly to `master`.** No feature branches, no PRs for regular development.
- **macOS CI workflow** (`.github/workflows/build.yml`) trigger changed to
  `[workflow_dispatch]` only — it can be run manually when needed but does not
  auto-trigger on push or PR.
- **`busted spec/`** is the only required test gate before pushing.

## Consequences

- **Faster iteration:** no PR creation/merge cycle between writing code and
  pushing it to the device for testing.
- **Commit log is the change record.** Commit messages should be descriptive
  (what + why). There is no PR description to explain context.
- **Agent sessions** should push to `master` directly. Session-level branch
  restrictions (e.g. Claude Code web session forcing a feature branch) are a
  workaround artifact, not the intended workflow — the canonical branch is `master`.
- **CI can still be run on demand** via workflow_dispatch if a cross-platform
  build check is needed (e.g. before sharing with others).
