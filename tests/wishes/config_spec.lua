local config = require("wishes.config")

describe("wishes.config.defaults", function()
  it("default_category exists in categories", function()
    assert.is_not_nil(config.defaults.categories[config.defaults.default_category])
  end)

  it("every category has sign, hl, and label fields", function()
    for name, cat in pairs(config.defaults.categories) do
      assert.is_string(cat.sign, name .. ".sign")
      assert.is_string(cat.hl, name .. ".hl")
      assert.is_string(cat.label, name .. ".label")
    end
  end)

  it("root_markers is a list of strings", function()
    assert.is_true(vim.islist(config.defaults.root_markers))
    assert.is_true(#config.defaults.root_markers > 0)
  end)
end)

describe("wishes.config.merge", function()
  it("deep-merges maps", function()
    local r = config.merge(
      { a = 1, b = { c = 2, d = 3 } },
      { b = { d = 99, e = 4 } }
    )
    assert.same({ a = 1, b = { c = 2, d = 99, e = 4 } }, r)
  end)

  it("replaces non-empty lists instead of merging by index", function()
    local r = config.merge(
      { markers = { "a", "b", "c" } },
      { markers = { "x" } }
    )
    assert.same({ markers = { "x" } }, r)
  end)

  it("lets `false` override a previous value (for disabling keymaps)", function()
    local r = config.merge(
      { keys = { add = "<leader>an", edit = "<leader>ae" } },
      { keys = { add = false } }
    )
    assert.is_false(r.keys.add)
    assert.equals("<leader>ae", r.keys.edit)
  end)

  it("treats empty overlay as a no-op", function()
    assert.same({ a = 1, b = { c = 2 } }, config.merge({ a = 1, b = { c = 2 } }, {}))
  end)

  it("returns a deep copy when overlay is nil", function()
    local r = config.merge({ a = { b = 1 } }, nil)
    assert.same({ a = { b = 1 } }, r)
  end)

  it("does not mutate base or overlay", function()
    local base = { a = { b = 1 } }
    local overlay = { a = { c = 2 } }
    local _ = config.merge(base, overlay)
    assert.same({ a = { b = 1 } }, base)
    assert.same({ a = { c = 2 } }, overlay)
  end)

  it("result is disconnected from base (mutations don't leak back)", function()
    local base = { a = { b = 1 } }
    local r = config.merge(base, {})
    r.a.b = 99
    assert.equals(1, base.a.b)
  end)
end)

describe("wishes.config.parse_toml", function()
  it("parses a top-level string value", function()
    local r = config.parse_toml('wishes_file = "foo/bar.md"')
    assert.equals("foo/bar.md", r.wishes_file)
  end)

  it("parses a nested section with string fields", function()
    local r = config.parse_toml(table.concat({
      "[categories.perf]",
      'sign = "P"',
      'hl = "DiagnosticWarn"',
      'label = "perf"',
    }, "\n"))
    assert.same({ sign = "P", hl = "DiagnosticWarn", label = "perf" }, r.categories.perf)
  end)

  it("supports multiple sections", function()
    local r = config.parse_toml(table.concat({
      "[categories.perf]",
      'sign = "P"',
      "",
      "[categories.security]",
      'sign = "S"',
    }, "\n"))
    assert.equals("P", r.categories.perf.sign)
    assert.equals("S", r.categories.security.sign)
  end)

  it("ignores comments and blank lines", function()
    local r = config.parse_toml(table.concat({
      "# top comment",
      "",
      'wishes_file = "x.md"   # trailing comment',
      "",
      "# another comment",
    }, "\n"))
    assert.equals("x.md", r.wishes_file)
  end)

  it("supports single-quoted strings", function()
    local r = config.parse_toml("wishes_file = 'single.md'")
    assert.equals("single.md", r.wishes_file)
  end)

  it("preserves `#` inside a string value", function()
    local r = config.parse_toml('wishes_file = "has#hash"')
    assert.equals("has#hash", r.wishes_file)
  end)

  it("returns an error for an unterminated string", function()
    local r, err = config.parse_toml('wishes_file = "no close')
    assert.is_nil(r)
    assert.is_string(err)
  end)

  it("returns an error for an unquoted value", function()
    local r, err = config.parse_toml("wishes_file = unquoted")
    assert.is_nil(r)
    assert.is_string(err)
  end)

  it("returns an error for a malformed section header", function()
    local r, err = config.parse_toml("[unclosed")
    assert.is_nil(r)
    assert.is_string(err)
  end)
end)

describe("wishes.config.load_project_file", function()
  local tmp

  local function tmpdir()
    local p = vim.fn.tempname()
    vim.fn.mkdir(p, "p")
    return p
  end

  local function write(path, content)
    local f = io.open(path, "w")
    assert(f)
    f:write(content)
    f:close()
  end

  before_each(function()
    tmp = tmpdir()
  end)

  after_each(function()
    vim.fn.delete(tmp, "rf")
  end)

  it("returns nil when no .wishes file exists", function()
    assert.is_nil(config.load_project_file(tmp))
  end)

  it("parses an existing .wishes file", function()
    write(tmp .. "/.wishes", 'wishes_file = "custom.md"\n')
    local r = config.load_project_file(tmp)
    assert.equals("custom.md", r.wishes_file)
  end)

  it("propagates parse errors", function()
    write(tmp .. "/.wishes", "wishes_file = unquoted\n")
    local r, err = config.load_project_file(tmp)
    assert.is_nil(r)
    assert.is_string(err)
  end)
end)

describe("wishes.config.resolve", function()
  it("returns defaults when no opts are given", function()
    local r = config.resolve()
    assert.equals(config.defaults.wishes_file, r.wishes_file)
    assert.equals(config.defaults.default_category, r.default_category)
  end)

  it("applies user opts on top of defaults", function()
    local r = config.resolve({ wishes_file = "custom.md" })
    assert.equals("custom.md", r.wishes_file)
    assert.equals(config.defaults.default_category, r.default_category)
  end)

  it("applies project opts on top of user opts", function()
    local r = config.resolve(
      { wishes_file = "user.md" },
      { wishes_file = "project.md" }
    )
    assert.equals("project.md", r.wishes_file)
  end)

  it("merges a user-added category with defaults intact", function()
    local r = config.resolve({
      categories = {
        perf = { sign = "P", hl = "DiagnosticWarn", label = "perf" },
      },
    })
    assert.is_not_nil(r.categories.perf)
    assert.is_not_nil(r.categories.fix)
    assert.is_not_nil(r.categories.note)
  end)

  it("does not mutate defaults", function()
    local r = config.resolve({ wishes_file = "custom.md" })
    r.wishes_file = "mutated"
    assert.equals(".wishes.md", config.defaults.wishes_file)
  end)
end)
