local M = {}

local INSTRUCTIONS = [[# Wishes

This project uses wishes.nvim for code review annotations.

## Wishes file

Check for a wishes file at the project root. The default location is `.wishes.md`,
but may be overridden in `.wishes` (a TOML config file) under the `wishes_file`
key. If the config file exists, read it to determine the actual path.

## File format

Each line is a wish:

    [category] file/path:line — note text
    [category] file/path:start-end — note text

Categories: fix, question, refactor, note (projects may define additional ones).
Lines starting with # are comments. Empty lines are ignored.

## When you find a wishes file

1. Read every wish.
2. Address each one in the relevant file, guided by the category:
   - [fix]: this is a bug or mistake — correct it.
   - [question]: answer the question in a comment or resolve the ambiguity in code.
   - [refactor]: restructure the code as described.
   - [note]: consider the suggestion, apply if it improves the code.
3. After addressing ALL wishes, delete the wishes file.

## Important

- File paths in wishes are relative to the project root.
- Line numbers may have shifted if you've made prior edits — use the content
  and surrounding context to locate the right spot, not just the line number.
- If a wish is unclear, make your best judgment and note what you did.
]]

local CLAUDE_FRONTMATTER = [[---
description: Read and address all wishes
---

]]

local CODEX_START = "<!-- wishes:start -->"
local CODEX_END = "<!-- wishes:end -->"

local AGENTS = {
	claude = {
		name = "Claude Code",
		markers = { ".claude" },
		target = ".claude/commands/wishes.md",
		mode = "file",
		content = CLAUDE_FRONTMATTER .. INSTRUCTIONS,
	},
	codex = {
		name = "Codex CLI",
		markers = { "AGENTS.md" },
		target = "AGENTS.md",
		mode = "append",
	},
	opencode = {
		name = "OpenCode",
		markers = { ".opencode", ".opencode.json" },
		target = ".opencode/commands/wishes.md",
		mode = "file",
		content = INSTRUCTIONS,
	},
	pi = {
		name = "Pi",
		markers = { ".pi" },
		target = ".pi/skills/wishes.md",
		mode = "file",
		content = INSTRUCTIONS,
	},
	generic = {
		name = "Generic",
		markers = nil,
		target = ".wishes-agent.md",
		mode = "file",
		content = INSTRUCTIONS,
	},
}

local function file_exists(path)
	return vim.uv.fs_stat(path) ~= nil
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

local function write_file(path, content)
	local dir = vim.fs.dirname(path)
	if dir and dir ~= "" then
		vim.fn.mkdir(dir, "p")
	end
	local f, err = io.open(path, "w")
	if not f then
		return nil, err
	end
	local ok, werr = f:write(content)
	f:close()
	if not ok then
		return nil, werr
	end
	return true
end

local function has_any_marker(root, markers)
	if not markers then
		return true
	end
	for _, marker in ipairs(markers) do
		if file_exists(root .. "/" .. marker) then
			return true
		end
	end
	return false
end

function M.detect(root)
	local detected = {}
	for key, agent in pairs(AGENTS) do
		if has_any_marker(root, agent.markers) then
			table.insert(detected, key)
		end
	end
	table.sort(detected)
	return detected
end

local function install_file_mode(root, agent)
	local target_path = root .. "/" .. agent.target
	return write_file(target_path, agent.content)
end

local function install_append_mode(root, agent)
	local target_path = root .. "/" .. agent.target
	local existing = read_file(target_path) or ""
	if existing:find(CODEX_START, 1, true) then
		return nil, "already installed"
	end

	local block = CODEX_START .. "\n\n" .. INSTRUCTIONS .. "\n" .. CODEX_END .. "\n"
	local new_content
	if existing == "" then
		new_content = block
	else
		local separator = existing:sub(-1) == "\n" and "\n" or "\n\n"
		new_content = existing .. separator .. block
	end
	return write_file(target_path, new_content)
end

function M.install(root, agent_key)
	local agent = AGENTS[agent_key]
	if not agent then
		return nil, "unknown agent: " .. tostring(agent_key)
	end
	if agent.mode == "append" then
		return install_append_mode(root, agent)
	end
	return install_file_mode(root, agent)
end

local function uninstall_file_mode(root, agent)
	local target_path = root .. "/" .. agent.target
	if not file_exists(target_path) then
		return false
	end
	local ok, err = os.remove(target_path)
	if not ok then
		return nil, err
	end
	return true
end

local function uninstall_append_mode(root, agent)
	local target_path = root .. "/" .. agent.target
	local content = read_file(target_path)
	if not content then
		return false
	end
	local start_pos = content:find(CODEX_START, 1, true)
	local end_pos = content:find(CODEX_END, 1, true)
	if not start_pos or not end_pos then
		return false
	end

	local before = content:sub(1, start_pos - 1):gsub("%s+$", "")
	local after = content:sub(end_pos + #CODEX_END):gsub("^%s+", "")

	local new_content
	if before == "" and after == "" then
		os.remove(target_path)
		return true
	elseif before == "" then
		new_content = after .. "\n"
	elseif after == "" then
		new_content = before .. "\n"
	else
		new_content = before .. "\n\n" .. after .. "\n"
	end
	return write_file(target_path, new_content)
end

function M.uninstall(root, agent_key)
	local agent = AGENTS[agent_key]
	if not agent then
		return nil, "unknown agent: " .. tostring(agent_key)
	end
	if agent.mode == "append" then
		return uninstall_append_mode(root, agent)
	end
	return uninstall_file_mode(root, agent)
end

function M.agent_name(agent_key)
	local agent = AGENTS[agent_key]
	return agent and agent.name or agent_key
end

function M.agent_target(agent_key)
	local agent = AGENTS[agent_key]
	return agent and agent.target or nil
end

function M.list_agent_keys()
	local keys = {}
	for key, _ in pairs(AGENTS) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

M.AGENTS = AGENTS
M.INSTRUCTIONS = INSTRUCTIONS
M.CODEX_START = CODEX_START
M.CODEX_END = CODEX_END

return M
