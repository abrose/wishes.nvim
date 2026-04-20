local agents = require("wishes.agents")

local function tmpdir()
	local p = vim.fn.tempname()
	vim.fn.mkdir(p, "p")
	return p
end

local function mkdir(path)
	vim.fn.mkdir(path, "p")
end

local function touch(path, content)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local f = io.open(path, "w")
	assert(f)
	f:write(content or "")
	f:close()
end

local function read(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local c = f:read("*a")
	f:close()
	return c
end

describe("wishes.agents.detect", function()
	local tmp

	before_each(function()
		tmp = tmpdir()
	end)

	after_each(function()
		vim.fn.delete(tmp, "rf")
	end)

	it("always includes generic even with no markers", function()
		local detected = agents.detect(tmp)
		assert.is_true(vim.tbl_contains(detected, "generic"))
	end)

	it("detects claude via a .claude directory", function()
		mkdir(tmp .. "/.claude")
		assert.is_true(vim.tbl_contains(agents.detect(tmp), "claude"))
	end)

	it("detects codex via an AGENTS.md file", function()
		touch(tmp .. "/AGENTS.md", "")
		assert.is_true(vim.tbl_contains(agents.detect(tmp), "codex"))
	end)

	it("detects opencode via a .opencode directory", function()
		mkdir(tmp .. "/.opencode")
		assert.is_true(vim.tbl_contains(agents.detect(tmp), "opencode"))
	end)

	it("detects opencode via a .opencode.json file", function()
		touch(tmp .. "/.opencode.json", "{}")
		assert.is_true(vim.tbl_contains(agents.detect(tmp), "opencode"))
	end)

	it("detects pi via a .pi directory", function()
		mkdir(tmp .. "/.pi")
		assert.is_true(vim.tbl_contains(agents.detect(tmp), "pi"))
	end)

	it("returns only generic when no markers exist", function()
		local detected = agents.detect(tmp)
		assert.same({ "generic" }, detected)
	end)
end)

describe("wishes.agents.install (file mode)", function()
	local tmp

	before_each(function()
		tmp = tmpdir()
	end)

	after_each(function()
		vim.fn.delete(tmp, "rf")
	end)

	it("writes .claude/commands/wishes.md with YAML frontmatter", function()
		assert.is_true(agents.install(tmp, "claude"))
		local content = read(tmp .. "/.claude/commands/wishes.md")
		assert.is_not_nil(content)
		assert.truthy(content:find("^---"))
		assert.truthy(content:find("description: Review wishes and address them one at a time"))
		assert.truthy(content:find("# Wishes"))
	end)

	it("writes .opencode/commands/wishes.md without frontmatter", function()
		assert.is_true(agents.install(tmp, "opencode"))
		local content = read(tmp .. "/.opencode/commands/wishes.md")
		assert.is_not_nil(content)
		assert.is_nil(content:find("^---"))
		assert.truthy(content:find("# Wishes"))
	end)

	it("writes .pi/skills/wishes.md", function()
		assert.is_true(agents.install(tmp, "pi"))
		assert.is_not_nil(read(tmp .. "/.pi/skills/wishes.md"))
	end)

	it("writes .wishes-agent.md for generic", function()
		assert.is_true(agents.install(tmp, "generic"))
		assert.is_not_nil(read(tmp .. "/.wishes-agent.md"))
	end)

	it("creates parent directories as needed", function()
		assert.is_true(agents.install(tmp, "claude"))
		assert.is_not_nil(vim.uv.fs_stat(tmp .. "/.claude/commands"))
	end)

	it("returns an error for an unknown agent key", function()
		local ok, err = agents.install(tmp, "bogus")
		assert.is_nil(ok)
		assert.is_string(err)
	end)
end)

describe("wishes.agents.install (codex append mode)", function()
	local tmp

	before_each(function()
		tmp = tmpdir()
	end)

	after_each(function()
		vim.fn.delete(tmp, "rf")
	end)

	it("creates AGENTS.md with a delimited block when absent", function()
		assert.is_true(agents.install(tmp, "codex"))
		local content = read(tmp .. "/AGENTS.md")
		assert.truthy(content:find(agents.CODEX_START, 1, true))
		assert.truthy(content:find(agents.CODEX_END, 1, true))
		assert.truthy(content:find("# Wishes"))
	end)

	it("appends to an existing AGENTS.md preserving prior content", function()
		touch(tmp .. "/AGENTS.md", "Existing project instructions.\n")
		assert.is_true(agents.install(tmp, "codex"))
		local content = read(tmp .. "/AGENTS.md")
		assert.truthy(content:find("Existing project instructions%."))
		assert.truthy(content:find(agents.CODEX_START, 1, true))
	end)

	it("returns 'already installed' when markers are present", function()
		agents.install(tmp, "codex")
		local ok, err = agents.install(tmp, "codex")
		assert.is_nil(ok)
		assert.truthy(err:find("already installed"))
	end)
end)

describe("wishes.agents.uninstall", function()
	local tmp

	before_each(function()
		tmp = tmpdir()
	end)

	after_each(function()
		vim.fn.delete(tmp, "rf")
	end)

	it("removes the installed file for a file-mode agent", function()
		agents.install(tmp, "claude")
		assert.is_true(agents.uninstall(tmp, "claude"))
		assert.is_nil(vim.uv.fs_stat(tmp .. "/.claude/commands/wishes.md"))
	end)

	it("returns false when nothing is installed", function()
		assert.is_false(agents.uninstall(tmp, "claude"))
	end)

	it("removes the delimited block from AGENTS.md", function()
		touch(tmp .. "/AGENTS.md", "Before wishes.\n")
		agents.install(tmp, "codex")
		touch(tmp .. "/AGENTS.md",
			read(tmp .. "/AGENTS.md") .. "\nAfter wishes.\n")

		assert.is_true(agents.uninstall(tmp, "codex"))

		local content = read(tmp .. "/AGENTS.md")
		assert.truthy(content:find("Before wishes%."))
		assert.truthy(content:find("After wishes%."))
		assert.is_nil(content:find(agents.CODEX_START, 1, true))
	end)

	it("deletes AGENTS.md when the block was the only content", function()
		agents.install(tmp, "codex")
		assert.is_true(agents.uninstall(tmp, "codex"))
		assert.is_nil(vim.uv.fs_stat(tmp .. "/AGENTS.md"))
	end)

	it("is idempotent with install (install → uninstall → install works)", function()
		assert.is_true(agents.install(tmp, "codex"))
		assert.is_true(agents.uninstall(tmp, "codex"))
		assert.is_true(agents.install(tmp, "codex"))
	end)
end)
