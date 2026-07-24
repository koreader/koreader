# AGENTS.md

## KOReader introduction and conventions

KOReader is a document viewer for E Ink devices and Android, supporting a wide
range of formats (PDF, DjVu, EPUB, CBZ, FB2, and more). It is written mostly
in Lua (the `frontend/` directory) with performance-critical parts in C/C++
(the `base/` directory), and is built with a custom `kodev` toolchain.

More information can be found in the [README](README.md) and the
[development guide](doc/Development_guide.md).

## Instruction structure for AI agents and humans

- `AGENTS.md` (this file) is the entry point description for AI coding agents
  and contributors, referencing other documents such as instructions and skills.
- Favour standard conventions over vendor-specific ones.
- To reduce duplication, refer to enforceable configuration files instead of
  excessive free-text repetitions (see `.editorconfig`, `.luacheckrc`,
  `.luarc.json`).
- Note: Please limit AI-assisted pull requests to 5 open at a time per
  contributor.

## Before opening a pull request

- **Check for existing pull requests before opening a new one.** Search the
  repository's open (and recently closed) PRs for work that overlaps with the
  change you are about to propose.
  - If a PR already covers the same change, do not open a duplicate. Instead,
    review it, leave feedback, or ask to take it over.
  - If a related PR exists but is stale or incomplete, consider reviving or
    building on it rather than starting from scratch.
  - Only open a new PR when the change is genuinely new or the existing PR
    cannot be reused.
- Prefer referencing the existing PR/issue number in your PR description when
  your work is related to prior efforts.

## Code structure

- `frontend/` – Lua application code (UI, devices, documents, plugins).
  - `frontend/ui/` – UI widgets and event handling.
  - `frontend/device/` – Per-device backends (e.g. `kobo/`, `kindle/`).
  - `frontend/document/` – Document format providers.
  - `frontend/apps/` – Higher-level applications (reader, filemanager, …).
- `base/` – C/C++ libraries (crengine, mupdf, djvu, blitbuffer, ffi bindings).
- `plugins/` – Optional Lua plugins.
- `resources/` – Static assets (keyboard layouts, icons, CSS).
- `l10n/` – Translations.
- `spec/` – Busted unit tests (mirrors the `frontend/` layout).
- `doc/` – Developer documentation (e.g. `Unit_tests.md`, `Hacking.md`).

## Main development commands

> ℹ Recommended before committing

Run the unit tests with `kodev`:

- run all tests (frontend & base): `./kodev test`
- frontend only: `./kodev test front`
- one specific base test: `./kodev test base util`
- list available tests: `./kodev test -l`

Check the output of `./kodev test -h` for the full usage. See
[doc/Unit_tests.md](doc/Unit_tests.md) for details.

Linting and style are enforced via `.luacheckrc` (LuaCheck) and `.editorconfig`.

## General

- Follow the project's existing code style and conventions.
- Keep changes focused; one logical change per pull request.
- Ensure the build and tests pass before submitting.
