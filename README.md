# wishes.nvim

A Neovim plugin for annotating code with review feedback that any AI coding agent can read and
act upon. Inline MR comments, but local — no Git forge required. Agent-agnostic: works with
Claude Code, Codex CLI, OpenCode, Pi, or any tool that can read a file.

## Why

When reviewing AI-generated changes in Neovim, there's no ergonomic way to leave contextual
feedback. The usual flow is: open a scratch buffer, write a list of gripes, paste them into the
agent's prompt. That loses the connection between feedback and its code location.

`wishes.nvim` stores annotations as plain-text "wishes" in a file at the project root. Each
wish records file, line (or range), category, and text. The plugin renders wishes as sign-column
icons + virtual text in the buffer. The agent reads the wishes file to get structured,
location-aware feedback it can act on directly.

## About the name

The framing comes from Kent Beck, who uses *genie* to describe an AI coding assistant — something
that listens to what you want and grants it. This plugin is the other half of that picture: a
durable place to write your *wishes* down, attached to the exact line they refer to, so the genie
can grant them without you having to re-explain the context every time.

## Requirements

- Neovim >= 0.10
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) or
  [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for `:Wishes list`
- Optional: [trouble.nvim](https://github.com/folke/trouble.nvim) — automatically renders the
  quickfix fallback if neither picker is installed

No hard external dependencies. Everything except `:Wishes list` works out of the box.

## Installation

### lazy.nvim

```lua
{
  "abrose/wishes.nvim",
  event = "VeryLazy",
  opts = {},
}
```

To use a local clone for development:

```lua
{
  dir = "~/path/to/wishes.nvim",
  dev = true,
  event = "VeryLazy",
  opts = {
    dev = true, -- enables :WishesReload
  },
}
```

## Quick start

1. In any project, run:

   ```
   :Wishes install
   ```

   Detects the AI agent(s) configured in your project (Claude Code via `.claude/`, Codex via
   `AGENTS.md`, OpenCode, Pi, or a generic fallback) and writes the appropriate instruction
   file so the agent knows how to consume wishes.

2. Annotate some code:

   ```
   :Wishes add
   ```

   Prompts for a category, then note text. Works in normal mode (single line) and visual mode
   (line range). The current file and line are captured automatically.

3. Tell your agent to address the wishes:

   - **Claude Code**: type `/wishes` in your session
   - **Codex CLI**: the appended section in `AGENTS.md` already tells it what to do
   - **OpenCode / Pi**: the installed skill/command is available to the agent
   - **Generic**: point your agent at `.wishes-agent.md`

4. Add the wishes file to your `.gitignore` — it's per-user and ephemeral (agents delete it
   after addressing all items):

   ```
   echo ".wishes.md" >> .gitignore
   ```

## Commands

| Command             | Action                                                 |
| ------------------- | ------------------------------------------------------ |
| `:Wishes add`       | Add a wish on the current line (or visual range)       |
| `:Wishes edit`      | Edit the wish on the current line                      |
| `:Wishes delete`    | Delete the wish on the current line                    |
| `:Wishes list`      | Browse all wishes (snacks / telescope / qflist picker) |
| `:Wishes summary`   | Print a grouped-by-file summary of all wishes          |
| `:Wishes clear`     | Delete the entire wishes file (with confirmation)      |
| `:Wishes install`   | Install agent instructions into the detected agent     |
| `:Wishes uninstall` | Remove installed agent instructions                    |

All subcommands support tab-completion.

## Keymaps

Default mappings (set any to `false` in config to disable):

| Key          | Mode   | Action                     |
| ------------ | ------ | -------------------------- |
| `<leader>an` | normal | Add wish                   |
| `<leader>an` | visual | Add wish (line range)      |
| `<leader>ae` | normal | Edit wish under cursor     |
| `<leader>ad` | normal | Delete wish under cursor   |
| `<leader>al` | normal | List wishes                |
| `<leader>ai` | normal | Install agent instructions |

Inside the `:Wishes list` picker:

| Key     | Action              |
| ------- | ------------------- |
| `<CR>`  | Jump to wish        |
| `<C-e>` | Edit wish text      |
| `<C-d>` | Delete wish         |

### Telescope extension

If you use Telescope, you can also invoke the picker as a Telescope extension:

```lua
require("telescope").load_extension("wishes")
-- :Telescope wishes
```

## Configuration

Full default options:

```lua
require("wishes").setup({
  -- Path to the wishes file, relative to project root.
  -- Overridden by a project `.wishes` config file if present.
  wishes_file = ".wishes.md",

  -- Markers that identify a project root when no `.wishes` file exists.
  root_markers = {
    ".git", ".claude", ".pi", ".opencode", ".hg", ".svn",
    "Makefile", "package.json", "Cargo.toml", "go.mod", "pyproject.toml",
  },

  -- Set any value to false to disable that keymap.
  keys = {
    add = "<leader>an",
    edit = "<leader>ae",
    delete = "<leader>ad",
    list = "<leader>al",
    install = "<leader>ai",
  },

  -- Sign + highlight group + label per category. Add your own.
  -- Each category accepts:
  --   sign     (string) icon shown in the sign column
  --   hl       (string) highlight group used for both sign and virtual text
  --   label    (string) display name
  --   sign_hl  (string, optional) override just the sign column highlight
  --   text_hl  (string, optional) override just the virtual text highlight
  --   fg       (string, optional) inline foreground color, e.g. "#ff5555"
  --   bg       (string, optional) inline background color, e.g. "#2d1a1a"
  -- Resolution order for each element:
  --   sign_hl (or text_hl) > derived hl from fg/bg > hl
  categories = {
    fix = { sign = "✗", hl = "DiagnosticError", label = "fix" },
    question = { sign = "?", hl = "DiagnosticWarn", label = "question" },
    refactor = { sign = "↻", hl = "DiagnosticInfo", label = "refactor" },
    note = { sign = "•", hl = "DiagnosticHint", label = "note" },
  },
  default_category = "note",

  -- Prefix shown before the virtual text at end of line.
  virtual_text_prefix = " ▎ ",

  -- When true:
  --   * Re-render wishes on BufEnter / BufWinEnter / BufWritePost / FileChangedShellPost
  --   * Poll the wishes file once a second to catch external changes
  --     (e.g., the agent deleted addressed wishes)
  auto_refresh = true,

  -- Enables :WishesReload (plugin development only).
  dev = false,
})
```

### Customizing category appearance

Two ways to tweak how wishes render, from quickest to most colorscheme-aware:

**Inline colors** — specify `fg`/`bg` directly:

```lua
categories = {
  fix = { sign = "🔥", fg = "#ff5555", bg = "#2d1a1a", label = "fix" },
  perf = { sign = "", fg = "#f1fa8c", label = "perf" },
},
```

wishes.nvim creates a derived highlight group named `WishesCategory_<name>` for each
category that uses inline colors, and re-creates it on `ColorScheme` changes.

**Named highlight groups** — more colorscheme-aware:

```lua
categories = {
  fix = { sign = "✗", sign_hl = "DiagnosticSignError", text_hl = "DiagnosticVirtualTextError", label = "fix" },
},
```

If both are set, `sign_hl` / `text_hl` win over `fg` / `bg`, which win over the catch-all `hl`.

## Project config: `.wishes`

Override `wishes_file` and add custom categories per project by creating a `.wishes` TOML file
at the project root:

```toml
# .wishes

# Store the wishes file somewhere else.
wishes_file = "reviews/current.txt"

# Add a custom category.
[categories.perf]
sign = ""
hl = "DiagnosticWarn"
label = "perf"
```

If `.wishes` is present it doubles as a root marker, so project-root detection becomes
unambiguous.

**Supported TOML subset:** top-level string values and `[categories.<name>]` tables with
`sign`, `hl`, and `label` string fields. Anything else is ignored. No arrays, numbers, or
nested non-category tables — keep it simple.

## Wishes file format

Each wish is a single line:

```
[category] path/to/file.lua:42 — note text
[category] path/to/file.lua:10-25 — note about a range
```

- Paths are relative to the project root.
- Line references are `:N` (single) or `:start-end` (range).
- Separator is an em-dash surrounded by spaces: ` — `.
- Lines starting with `#` are comments.
- Empty lines are ignored.

The format is intentionally human-readable, so you (or the agent) can edit it by hand.

## Agent support

| Agent         | Detected by                      | Install target                                    |
| ------------- | -------------------------------- | ------------------------------------------------- |
| Claude Code   | `.claude/` directory             | `.claude/commands/wishes.md` (slash command)      |
| Codex CLI     | `AGENTS.md` file                 | Appends delimited section to `AGENTS.md`          |
| OpenCode      | `.opencode/` or `.opencode.json` | `.opencode/commands/wishes.md` (custom command)   |
| Pi            | `.pi/` directory                 | `.pi/skills/wishes.md` (skill)                    |
| Generic       | (always offered)                 | `.wishes-agent.md` (standalone instructions file) |

`:Wishes install` is idempotent — running it twice for the same agent is safe. For Codex, the
appended section in `AGENTS.md` is delimited by `<!-- wishes:start -->` / `<!-- wishes:end -->`
markers so `:Wishes uninstall` can remove it cleanly without touching the rest of your file.

## Development

```
make test              # runs the full test suite headlessly
```

Add `dev = true` to your setup opts to enable `:WishesReload`, which re-requires all wishes
modules, clears autocmds and extmarks, and re-runs setup — no Neovim restart needed between
edits.

Tests use plenary.nvim's busted harness. `tests/minimal_init.lua` bootstraps plenary into
`/tmp/plenary.nvim` (override with `PLENARY_DIR` env var).
