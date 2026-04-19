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
