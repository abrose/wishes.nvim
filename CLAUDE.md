# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Names

- I (Claude) am **Wrench Goblin**.
- My colleague is **Chebu**, who also answers to **Chebuchadnezzar**.

## Project status

This repo is in the **design phase**. The only content is `SPEC.md`, which is the
source of truth for everything we're building. No Lua source has been written yet.
When `SPEC.md` and this file disagree, re-read `SPEC.md` — CLAUDE.md is an
orientation map, not a second copy of the spec.

## What wishes.nvim is

A Neovim plugin for annotating code with review feedback that any AI coding agent
can read and act on — think inline MR comments, but stored as a plain-text file at
the project root with no Git forge required. Agent-agnostic by design: works with
Claude Code, Codex CLI, OpenCode, Pi, or anything that can read a file.

## Planned architecture (see `SPEC.md` §"Plugin Structure")

Standard lazy.nvim layout. One-line purpose per module:

- `lua/wishes/init.lua` — public API, `setup()`.
- `lua/wishes/config.lua` — defaults + merge of user opts and project `.wishes` TOML.
- `lua/wishes/core.lua` — project-root discovery, wishes-file parse/write/CRUD.
- `lua/wishes/display.lua` — signs, virtual text, extmarks (single namespace).
- `lua/wishes/picker.lua` — Telescope picker (list, preview, edit, delete).
- `lua/wishes/agents.lua` — agent detection + install/uninstall of instruction files.
- `plugin/wishes.lua` — `:Wishes` user command with subcommand completion.
- `lua/telescope/_extensions/wishes.lua` — Telescope extension entry point.

Two configuration layers: plugin defaults (via `setup()`) merged with an optional
project-level `.wishes` TOML file. Project config wins for `wishes_file` and
`categories`.

## Non-obvious design rules (easy to miss, painful to get wrong)

- **Root-walk safety:** walk upward for `.wishes` first, then fallback markers.
  Stop and warn at `$HOME` or `/`. Never create the wishes file above a real
  project root.
- **Paths are always relative to the project root** in the wishes file — never
  absolute.
- **Extmarks use `strict = false`** — line numbers drift after edits; out-of-range
  lines must not error.
- **Parser is tolerant:** skip malformed wish lines with a warning, don't error.
- **TOML parser is minimal and inline** — no external dep. Only `wishes_file`
  (string) and `[categories.<name>]` tables (with `sign`/`hl`/`label` string
  fields) need to be supported.
- **Install must be idempotent.** Codex CLI append to `AGENTS.md` uses
  `<!-- wishes:start -->` / `<!-- wishes:end -->` markers so uninstall can remove
  cleanly without touching the rest of the file.
- **All prompts go through `vim.ui.input` / `vim.ui.select`** — this respects the
  user's UI backend (dressing.nvim etc.). Never use raw `input()`.
- **One namespace for everything:** `vim.api.nvim_create_namespace('wishes')` for
  all signs, virtual text, and extmarks.
- **Agent-instruction templates live as string constants in `agents.lua`** — not
  as separate template files. Keeps the plugin self-contained.

## Dev commands

No build, lint, or test harness is in place yet. Typical Neovim-plugin toolchain
options to pick from when implementation starts:

- Format: `stylua`.
- Lint: `luacheck` or `selene`.
- Test: `plenary.nvim`'s busted-style harness, run headless via
  `nvim --headless -c "PlenaryBustedDirectory tests/"`.

**Decide these with Chebu before writing the first test, then update this section
with the actual commands.** Don't invent commands that don't exist in the repo.

## Scope guardrails

`SPEC.md` has a **"Future Ideas (post-v1)"** section. Do not implement any of
those in v1 unless Chebu explicitly greenlights it — they are listed precisely
because they are *out* of scope for the first cut.
