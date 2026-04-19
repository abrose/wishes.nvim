local core = require("wishes.core")

describe("wishes.core.parse_line", function()
  it("parses a single-line wish", function()
    local wish = core.parse_line("[fix] src/foo.lua:42 — rename this callback")
    assert.same({
      category = "fix",
      path = "src/foo.lua",
      line_start = 42,
      line_end = 42,
      text = "rename this callback",
    }, wish)
  end)

  it("parses a line range", function()
    local wish = core.parse_line("[refactor] lua/config/keymaps.lua:15-20 — use vim.keymap.set")
    assert.equals(15, wish.line_start)
    assert.equals(20, wish.line_end)
    assert.equals("refactor", wish.category)
  end)

  it("ignores comment lines", function()
    assert.is_nil(core.parse_line("# a comment"))
  end)

  it("ignores blank and whitespace-only lines", function()
    assert.is_nil(core.parse_line(""))
    assert.is_nil(core.parse_line("   "))
  end)

  it("returns nil when the separator is missing", function()
    assert.is_nil(core.parse_line("[fix] src/foo.lua:42 missing em-dash"))
  end)

  it("returns nil when the line number is missing", function()
    assert.is_nil(core.parse_line("[fix] src/foo.lua — no colon or line"))
  end)

  it("preserves em-dashes inside the text", function()
    local wish = core.parse_line("[note] x.lua:1 — a — b — c")
    assert.equals("a — b — c", wish.text)
  end)

  it("accepts user-defined category names", function()
    local wish = core.parse_line("[perf] x.lua:1 — hot path")
    assert.equals("perf", wish.category)
  end)

  it("trims leading and trailing whitespace on the raw input", function()
    local wish = core.parse_line("   [fix] a.lua:1 — text   ")
    assert.equals("fix", wish.category)
    assert.equals("text", wish.text)
  end)

  it("handles paths containing colons (takes the last :N as the line)", function()
    local wish = core.parse_line("[note] weird:path.lua:99 — ok")
    assert.equals("weird:path.lua", wish.path)
    assert.equals(99, wish.line_start)
  end)
end)

describe("wishes.core.find_root", function()
  local tmp

  local function tmpdir()
    local p = vim.fn.tempname()
    vim.fn.mkdir(p, "p")
    return p
  end

  local function touch(path, content)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = io.open(path, "w")
    assert(f, "could not open " .. path)
    f:write(content or "")
    f:close()
  end

  local function mkdir(path)
    vim.fn.mkdir(path, "p")
  end

  before_each(function()
    tmp = tmpdir()
  end)

  after_each(function()
    vim.fn.delete(tmp, "rf")
  end)

  it("finds a .wishes config file in an ancestor and reports via='config'", function()
    touch(tmp .. "/proj/.wishes", "")
    mkdir(tmp .. "/proj/src")

    local root, via = core.find_root(tmp .. "/proj/src", { stop_at = tmp })
    assert.equals(tmp .. "/proj", root)
    assert.equals("config", via)
  end)

  it("falls back to .git when no .wishes exists", function()
    mkdir(tmp .. "/proj/.git")
    mkdir(tmp .. "/proj/src/deep")

    local root, via = core.find_root(tmp .. "/proj/src/deep", { stop_at = tmp })
    assert.equals(tmp .. "/proj", root)
    assert.equals(".git", via)
  end)

  it("prefers .wishes over fallback markers when both exist at the same level", function()
    touch(tmp .. "/proj/.wishes", "")
    mkdir(tmp .. "/proj/.git")

    local root, via = core.find_root(tmp .. "/proj", { stop_at = tmp })
    assert.equals(tmp .. "/proj", root)
    assert.equals("config", via)
  end)

  it("returns nil with reason 'reached_boundary' when no marker is found", function()
    mkdir(tmp .. "/proj/src")

    local root, reason = core.find_root(tmp .. "/proj/src", { stop_at = tmp })
    assert.is_nil(root)
    assert.equals("reached_boundary", reason)
  end)

  it("respects a custom root_markers list", function()
    touch(tmp .. "/proj/Custom.toml", "")
    mkdir(tmp .. "/proj/src")

    local root, via = core.find_root(tmp .. "/proj/src", {
      stop_at = tmp,
      root_markers = { "Custom.toml" },
    })
    assert.equals(tmp .. "/proj", root)
    assert.equals("Custom.toml", via)
  end)

  it("does not search at or above stop_at", function()
    touch(tmp .. "/.git", "")
    mkdir(tmp .. "/proj/src")

    local root, reason = core.find_root(tmp .. "/proj/src", { stop_at = tmp })
    assert.is_nil(root)
    assert.equals("reached_boundary", reason)
  end)
end)

describe("wishes.core.format_line", function()
  it("formats a single-line wish", function()
    local line = core.format_line({
      category = "fix",
      path = "src/foo.lua",
      line_start = 42,
      line_end = 42,
      text = "rename this callback",
    })
    assert.equals("[fix] src/foo.lua:42 — rename this callback", line)
  end)

  it("formats a range wish with start-end", function()
    local line = core.format_line({
      category = "refactor",
      path = "lua/config/keymaps.lua",
      line_start = 15,
      line_end = 20,
      text = "use vim.keymap.set",
    })
    assert.equals("[refactor] lua/config/keymaps.lua:15-20 — use vim.keymap.set", line)
  end)

  it("defaults to single-line form when line_end is absent", function()
    local line = core.format_line({
      category = "note",
      path = "x.lua",
      line_start = 1,
      text = "text",
    })
    assert.equals("[note] x.lua:1 — text", line)
  end)

  it("returns error for text with an embedded newline", function()
    local line, err = core.format_line({
      category = "note",
      path = "x.lua",
      line_start = 1,
      text = "multi\nline",
    })
    assert.is_nil(line)
    assert.is_string(err)
  end)

  it("returns error for missing required fields", function()
    assert.is_nil(core.format_line({ category = "note", path = "x.lua", text = "t" }))
    assert.is_nil(core.format_line({ path = "x.lua", line_start = 1, text = "t" }))
    assert.is_nil(core.format_line({ category = "note", line_start = 1, text = "t" }))
    assert.is_nil(core.format_line({ category = "note", path = "x.lua", line_start = 1 }))
  end)

  it("round-trips through parse_line without loss", function()
    local original = {
      category = "fix",
      path = "src/foo.lua",
      line_start = 10,
      line_end = 20,
      text = "text with — em-dashes inside",
    }
    local parsed = core.parse_line(core.format_line(original))
    assert.same(original, parsed)
  end)
end)

describe("wishes.core.parse_content", function()
  it("parses multiple wishes into a list", function()
    local wishes, warnings = core.parse_content(table.concat({
      "[fix] a.lua:1 — first",
      "[note] b.lua:2-3 — second",
    }, "\n"))
    assert.equals(2, #wishes)
    assert.equals(0, #warnings)
    assert.equals("first", wishes[1].text)
    assert.equals("second", wishes[2].text)
  end)

  it("skips comments and blank lines without warnings", function()
    local wishes, warnings = core.parse_content(table.concat({
      "# review 2026-04-19",
      "",
      "[fix] a.lua:1 — real wish",
      "  ",
      "# another comment",
    }, "\n"))
    assert.equals(1, #wishes)
    assert.equals(0, #warnings)
  end)

  it("collects warnings for malformed lines and keeps parsing", function()
    local wishes, warnings = core.parse_content(table.concat({
      "[fix] a.lua:1 — good",
      "this is garbage",
      "[note] b.lua:2 — also good",
    }, "\n"))
    assert.equals(2, #wishes)
    assert.equals(1, #warnings)
    assert.truthy(warnings[1]:find("line 2"))
  end)

  it("returns empty lists for empty content", function()
    local wishes, warnings = core.parse_content("")
    assert.equals(0, #wishes)
    assert.equals(0, #warnings)
  end)
end)

describe("wishes.core.read_file / write_file", function()
  local tmp

  before_each(function()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
  end)

  after_each(function()
    vim.fn.delete(tmp, "rf")
  end)

  it("returns nil and error when reading a nonexistent file", function()
    local wishes, err = core.read_file(tmp .. "/nope.md")
    assert.is_nil(wishes)
    assert.is_string(err)
  end)

  it("round-trips a list of wishes through write_file and read_file", function()
    local path = tmp .. "/.wishes.md"
    local originals = {
      { category = "fix", path = "a.lua", line_start = 1, line_end = 1, text = "first" },
      { category = "refactor", path = "b.lua", line_start = 10, line_end = 20, text = "second" },
    }
    assert.is_true(core.write_file(path, originals))
    local wishes, warnings = core.read_file(path)
    assert.equals(0, #warnings)
    assert.same(originals, wishes)
  end)

  it("creates parent directories on write", function()
    local path = tmp .. "/nested/dir/file.md"
    assert.is_true(core.write_file(path, {
      { category = "note", path = "x.lua", line_start = 1, line_end = 1, text = "hi" },
    }))
    assert.is_not_nil(vim.uv.fs_stat(path))
  end)

  it("writes an empty file when given an empty list", function()
    local path = tmp .. "/empty.md"
    assert.is_true(core.write_file(path, {}))
    local f = io.open(path, "r")
    local content = f:read("*a")
    f:close()
    assert.equals("", content)
  end)

  it("overwrites existing file contents", function()
    local path = tmp .. "/f.md"
    core.write_file(path, {
      { category = "fix", path = "a.lua", line_start = 1, line_end = 1, text = "old" },
    })
    core.write_file(path, {
      { category = "note", path = "b.lua", line_start = 2, line_end = 2, text = "new" },
    })
    local wishes = core.read_file(path)
    assert.equals(1, #wishes)
    assert.equals("new", wishes[1].text)
    assert.equals("note", wishes[1].category)
  end)

  it("propagates format errors from write_file", function()
    local path = tmp .. "/f.md"
    local ok, err = core.write_file(path, {
      { category = "fix", path = "a.lua", line_start = 1, text = "has\nnewline" },
    })
    assert.is_nil(ok)
    assert.is_string(err)
  end)
end)
