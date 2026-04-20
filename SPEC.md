# wishes.nvim — Plugin Specification

A Neovim plugin for annotating code with review feedback that any AI coding agent can read and act upon. Think inline MR comments, but local — no Git forge required. Agent-agnostic: works with Claude Code, Codex CLI, OpenCode, Pi, or any tool that can read a file.

## Problem

When reviewing AI-generated changes in Neovim, there's no ergonomic way to leave contextual feedback. The current workflow is: open a scratch buffer, write a list of feedback points, copy-paste them into the agent's prompt. This loses the connection between feedback and the exact code location.

## Solution

Wishes (annotations) are stored in a wishes file at the project root. Each wish records file path, line or line range, category, and the note text. The plugin renders wishes as sign column icons + virtual text in the buffer, and provides commands to add, edit, delete, and list wishes.

The agent reads the wishes file to get structured, location-aware feedback it can act on directly. The user simply tells their agent: "read the wishes file and address every item."

## Project Root Discovery

The plugin needs to know where the project root is. It uses a two-tier strategy:

1. **Config file (preferred):** Walk upward from the current file's directory looking for `.wishes` (a project-level config file, see below). If found, that directory is the project root.
2. **Fallback markers:** If no `.wishes` config file is found, walk upward looking for common project root markers in this order: `.git/`, `.claude/`, `.pi/`, `.opencode/`, `.hg/`, `.svn/`, `Makefile`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`. The first match determines the root.

**Safety:** Stop and warn (do not create the wishes file) if the walk reaches `$HOME` or filesystem root `/` without finding a root.

## Project Config File (`.wishes`)

An optional TOML file placed in the project root. If absent, all defaults apply. Example:

```toml
# .wishes

# Path to the wishes file, relative to project root
wishes_file = "reviews/current.txt"

# Custom categories beyond the defaults
[categories.perf]
sign = ""
hl = "DiagnosticWarn"
label = "perf"
```

When present, the `.wishes` file doubles as the root marker, so discovery is unambiguous.

If not present, the wishes file defaults to `.wishes.md` in the discovered project root.

## Wishes File Format

The wishes file is a plain-text file. Each wish is a single line:

```
[category] file/path.lua:42 — the note text here
[category] file/path.lua:10-25 — note about a range of lines
```

- `[category]` is one of the built-in or user-defined categories (see config)
- File paths are relative to the project root
- Line references are either `:<line>` or `:<start>-<end>`
- Separator is `—` (space, em-dash, space)
- Lines starting with `#` are comments/ignored
- Empty lines are ignored

Example:

```
# Review of refactoring PR — 2026-04-17
[fix] src/plugins/lsp.lua:42 — rename this callback, it shadows the outer on_attach
[question] src/plugins/lsp.lua:78 — is this fallback reachable after the early return on line 71?
[refactor] lua/config/keymaps.lua:15-20 — use vim.keymap.set instead of the deprecated API
[note] lua/config/options.lua:8 — consider bumping scrolloff to 10
```

## Plugin Structure

Standard lazy.nvim plugin layout:

```
wishes.nvim/
  lua/
    wishes/
      init.lua          -- setup(), public API
      config.lua        -- defaults, merge with user opts + project config
      core.lua          -- find_root(), parse project config, parse/write wishes file, CRUD
      display.lua       -- signs, virtual text, extmarks, refresh logic
      picker.lua        -- Telescope picker (list, preview, edit, delete)
      agents.lua        -- agent detection, install/uninstall logic, instruction templates
  plugin/
    wishes.lua          -- vim.api.nvim_create_user_command definitions
  lua/telescope/_extensions/
    wishes.lua          -- Telescope extension entry point
```

## Default Configuration

```lua
require('wishes').setup({
  -- Default wishes file name (relative to project root)
  -- Overridden by .wishes project config if present
  wishes_file = '.wishes.md',

  -- Additional root markers beyond .wishes
  root_markers = { '.git', '.claude', '.pi', '.opencode', '.hg', '.svn', 'Makefile', 'package.json', 'Cargo.toml', 'go.mod', 'pyproject.toml' },

  keys = {
    add       = '<leader>an',  -- add wish (normal + visual mode)
    edit      = '<leader>ae',  -- edit wish under cursor
    delete    = '<leader>ad',  -- delete wish under cursor
    list      = '<leader>al',  -- Telescope picker
    install   = '<leader>ai',  -- install agent instructions
  },

  categories = {
    fix      = { sign = '', hl = 'DiagnosticError', label = 'fix' },
    question = { sign = '', hl = 'DiagnosticWarn', label = 'question' },
    refactor = { sign = '', hl = 'DiagnosticInfo', label = 'refactor' },
    note     = { sign = '', hl = 'DiagnosticHint', label = 'note' },
  },

  default_category = 'note',

  -- Prefix shown before virtual text
  virtual_text_prefix = ' ▎ ',

  -- Automatically display wishes when opening a buffer
  auto_refresh = true,
})
```

All keys can be set to `false` to disable them individually. Project-level `.wishes` config merges on top of the plugin config (project config wins for `wishes_file` and `categories`).

## Features

### 1. Add Wish (`<leader>an`)

**Normal mode:** Prompts for category (via `vim.ui.select`) then note text (via `vim.ui.input`). Records the current file and line number.

**Visual mode:** Same flow, but records the selected line range (start-end). Exit visual mode before prompting.

After adding, the sign and virtual text appear immediately in the buffer.

### 2. Edit Wish (`<leader>ae`)

If the cursor is on a line that has a wish, open `vim.ui.input` pre-filled with the existing note text. Save the updated text back to the wishes file. If no wish exists on the current line, show a notification saying so.

### 3. Delete Wish (`<leader>ad`)

If the cursor is on a line with a wish, remove it from the wishes file after a `vim.ui.select` yes/no confirmation. Clear the sign and virtual text.

### 4. Buffer Display (signs + virtual text)

Use a dedicated `vim.api.nvim_create_namespace('wishes')` for all extmarks.

For each wish in the current buffer's file:

- Place a sign in the sign column using the category's icon and highlight
- Show the note text as virtual text at the end of the line (or the first line of a range), using the category's highlight group, prefixed with `virtual_text_prefix`
- For ranges, place the sign on the first line only

**Auto-refresh:** If `auto_refresh` is true, set up autocommands on `BufEnter` and `BufWritePost` to re-parse the wishes file and update the display. Also refresh after any CRUD operation (add/edit/delete).

**Performance:** Only parse wishes relevant to the current buffer's file path. Cache the parsed wishes and invalidate the cache when the wishes file's mtime changes.

### 5. Telescope Picker (`<leader>al`)

Open a Telescope picker listing all wishes across the project. Each entry shows:

```
[fix] src/plugins/lsp.lua:42 — rename this callback...
```

- **Preview:** Show the file with the cursor on the annotated line
- **`<CR>`:** Jump to the wish's file and line
- **`<C-e>`:** Edit the wish text inline (same as `<leader>ae`)
- **`<C-d>`:** Delete the wish (with confirmation)

Register as a Telescope extension so it's also available via `:Telescope wishes`.

### 6. Agent Install (`<leader>ai` / `:Wishes install`)

Installs a skill/instruction file into the active agent harness so the agent knows how to find and work with the wishes file. The command auto-detects which agents are configured in the project and lets the user pick.

**Detection:** Look for these markers in the project root:

| Agent       | Marker                                   | Install target                                       |
| ----------- | ---------------------------------------- | ---------------------------------------------------- |
| Claude Code | `.claude/` directory                     | `.claude/commands/wishes.md` (project slash command) |
| Codex CLI   | `.git/` + `AGENTS.md` or `codex` in path | `AGENTS.md` (append section)                         |
| OpenCode    | `.opencode/` or `.opencode.json`         | `.opencode/commands/wishes.md` (custom command)      |
| Pi          | `.pi/` directory                         | `.pi/skills/wishes.md` (skill file)                  |
| Generic     | (always available)                       | `.wishes-agent.md` (standalone instructions file)    |

**Flow:**

1. Scan the project root for agent markers
2. Present detected agents via `vim.ui.select` (plus "Generic" as a fallback option always present)
3. Write the appropriate instruction file for the chosen agent
4. Notify the user where the file was created

**Instruction content per agent:**

Each agent gets the same core instructions adapted to its format. The installed instructions should cover:

```markdown
# Wishes

This project uses wishes.nvim for code review annotations. The wishes file
contains feedback items the user left while reviewing code. Your job is to
address them in a collaborative, reviewable way — not as one big batch.

## Wishes file

Check for a wishes file at the project root. The default location is `.wishes.md`,
but may be overridden in `.wishes` (a TOML config file) under the
`wishes_file` key. If the config file exists, read it to determine the actual path.

## File format

Each line is a wish:

    [category] file/path:line — note text
    [category] file/path:start-end — note text

Categories: fix, question, refactor, note (projects may define additional ones).
Lines starting with # are comments. Empty lines are ignored.

## Workflow

**Do not start changing code immediately.** Follow these steps in order.

1. **Read and summarize.** Read every wish. Summarize them back to the user —
   one line per wish, grouped by file. This confirms understanding before code
   changes.
2. **Discuss before acting.** If any wish is ambiguous, ask. Wait for the user's
   go-ahead before making changes.
3. **Group related wishes.** Wishes that logically belong together (same function,
   same coherent change) may be addressed as one unit. Unrelated wishes must be
   addressed separately.
4. **Address one at a time.** For each wish (or tightly-coupled group):
   - Make the change, guided by the category ([fix] = bug; [question] = answer
     or resolve; [refactor] = restructure; [note] = consider, apply or skip with
     reason).
   - Remove the addressed wish(es) from the wishes file.
   - Pause and let the user review.
   - Wait for the go-ahead before continuing.
5. **Finish.** When all wishes are addressed and the file is empty, delete it.

## Important

- File paths in wishes are relative to the project root.
- Line numbers may have shifted if you've made prior edits — use content and
  surrounding context to locate the right spot, not just the line number.
- If a wish is unclear, ask rather than guess.
- Prefer smaller, reviewable changes over comprehensive sweeps.
```

**Claude Code specifics:** The install target is `.claude/commands/wishes.md`. This registers `/wishes` as a project slash command. The content should be the core instructions above with a description line at the top (e.g., `Read and address all wishes`). The user then just types `/wishes` in Claude Code to trigger a review pass.

**Codex CLI specifics:** Codex reads `AGENTS.md` at the project root (markdown, concatenated from root to cwd). The install command should append a clearly delimited section to `AGENTS.md`:

```markdown
<!-- wishes:start -->

# Wishes

<instructions here>
<!-- wishes:end -->
```

If `AGENTS.md` doesn't exist, create it. If the markers already exist, skip with a notification. Uninstall removes everything between the markers.

**OpenCode specifics:** OpenCode supports project-local custom commands in `.opencode/commands/`. Each `.md` file becomes a command keyed by filename. Write to `.opencode/commands/wishes.md` with the core instructions. Create the `.opencode/commands/` directory if it doesn't exist.

**Pi specifics:** Pi supports project-local skills in `.pi/skills/`. Write to `.pi/skills/wishes.md` with the core instructions. Create the `.pi/skills/` directory if it doesn't exist.

**Append-mode targets (Codex CLI):** When appending to an existing file, check if wishes instructions are already present (look for the `wishes:start` marker) and skip with a notification if so.

**Uninstall:** `:Wishes uninstall` should detect and remove the installed instruction files with confirmation. Scan the same locations used by install and offer to remove each one found.

### 7. User Commands

Register the following commands in `plugin/wishes.lua`:

| Command             | Action                                            |
| ------------------- | ------------------------------------------------- |
| `:Wishes add`       | Same as `<leader>an`                              |
| `:Wishes edit`      | Same as `<leader>ae`                              |
| `:Wishes delete`    | Same as `<leader>ad`                              |
| `:Wishes list`      | Same as `<leader>al`                              |
| `:Wishes clear`     | Remove all wishes + delete file                   |
| `:Wishes install`   | Install agent instructions (same as `<leader>ai`) |
| `:Wishes uninstall` | Remove installed agent instructions               |

Use a single `:Wishes` command with subcommand completion.

## Dependencies

- **Required:** Neovim >= 0.10
- **Optional:** telescope.nvim (for picker; all other features work without it)

## .gitignore

The plugin should remind users (in the README) to add the wishes file (default `.wishes.md`) to their global or project `.gitignore`. Optionally, the `setup()` function can check and offer to add it automatically on first use.

## Notes for Implementation

- All file paths in the wishes file must be relative to the project root, never absolute
- Use `vim.ui.input` and `vim.ui.select` for all prompts — this respects the user's UI backend (dressing.nvim, etc.)
- Keep the parser tolerant: skip malformed lines with a warning rather than erroring
- The wishes file format is intentionally simple and human-readable so users can also edit it by hand or the agent can modify it (e.g., marking items as addressed)
- Extmarks should use `strict = false` so they don't error on out-of-range lines (e.g., if the file has been edited since the wish was added)
- For TOML parsing of `.wishes`, use a minimal inline parser (the format is simple enough) to avoid requiring an external dependency. Only `wishes_file` (string) and `[categories.<name>]` tables (with `sign`, `hl`, `label` string fields) need to be supported.
- The plugin is agent-agnostic by design. The README should mention `:Wishes install` as the recommended first step after installation, and include manual setup instructions for agents not yet supported by auto-detect.
- Agent instruction templates should be stored as string constants in `agents.lua`, not as separate template files, to keep the plugin self-contained.
- The install command must be idempotent — running it twice for the same agent should not duplicate instructions.

## Future Ideas (post-v1)

These are directions to explore after the core plugin is stable and tested. Do not implement in v1.

- **MCP resource:** Expose wishes as an MCP resource via mcp-neovim-server or a custom MCP server. Agents with MCP support (Claude Code, OpenCode) could query wishes directly instead of reading the file, enabling richer two-way interaction (e.g., the agent marking items as addressed in real-time).
- **claudecode.nvim integration:** For Claude Code users, add an optional integration with claudecode.nvim's `:ClaudeCodeSend` — select the summary output and send it directly to the running Claude Code session without switching terminals.
- **Aider `# AI:` bridge:** Offer an export mode that writes wishes as inline `# AI:` comments directly in the source files, for users who prefer Aider's `--watch-files` auto-trigger workflow.
- **code-review.nvim interop:** Look at code-review.nvim's annotation UX (threaded discussions, richer editing) as inspiration or as a direct integration target — their annotation model could feed into the wishes file.
- **Diff-aware wishes:** When the agent has made changes, show a split view comparing the annotated line's original state vs. the current state to help the user decide during cleanup whether a wish was addressed.
- **Interactive cleanup:** Walk through wishes one by one (showing the wish vs. current code state), picking keep/remove/skip for each. Lets the user prune after the agent has acted on feedback.
