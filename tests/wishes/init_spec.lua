local function reset()
  require("plenary.reload").reload_module("wishes", true)
  pcall(vim.api.nvim_del_augroup_by_name, "wishes")
  pcall(vim.api.nvim_del_user_command, "WishesReload")
end

describe("wishes.setup", function()
  before_each(reset)

  it("module loads", function()
    local wishes = require("wishes")
    assert.is_table(wishes)
    assert.is_function(wishes.setup)
  end)

  it("setup accepts empty opts without erroring", function()
    local wishes = require("wishes")
    assert.has_no.errors(function() wishes.setup() end)
  end)

  it("registers :WishesReload only when opts.dev is true", function()
    local wishes = require("wishes")

    wishes.setup({})
    assert.is_nil(vim.api.nvim_get_commands({})["WishesReload"])

    wishes.setup({ dev = true })
    assert.is_not_nil(vim.api.nvim_get_commands({})["WishesReload"])
  end)

  it("is idempotent when called twice with dev=true", function()
    local wishes = require("wishes")
    wishes.setup({ dev = true })
    assert.has_no.errors(function() wishes.setup({ dev = true }) end)
  end)

  it("stashes a merged config at _config reflecting user overrides", function()
    local wishes = require("wishes")
    wishes.setup({ wishes_file = "override.md" })
    assert.is_table(wishes._config)
    assert.equals("override.md", wishes._config.wishes_file)
  end)
end)

describe("wishes.compute_config", function()
  local tmp

  local function tmpdir()
    local p = vim.fn.tempname()
    vim.fn.mkdir(p, "p")
    return p
  end

  local function write(path, content)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = io.open(path, "w")
    assert(f)
    f:write(content)
    f:close()
  end

  before_each(function()
    reset()
    tmp = tmpdir()
  end)

  after_each(function()
    vim.fn.delete(tmp, "rf")
  end)

  it("returns defaults + user opts with no root when stop_at is reached first", function()
    vim.fn.mkdir(tmp .. "/proj/src", "p")
    local wishes = require("wishes")
    local r = wishes.compute_config({ wishes_file = "u.md" }, tmp .. "/proj/src", tmp)
    assert.equals("u.md", r.config.wishes_file)
    assert.is_nil(r.root)
    assert.is_nil(r.via)
  end)

  it("finds root via fallback marker and returns user config when no .wishes exists", function()
    vim.fn.mkdir(tmp .. "/proj/.git", "p")
    vim.fn.mkdir(tmp .. "/proj/src", "p")
    local wishes = require("wishes")
    local r = wishes.compute_config({ wishes_file = "u.md" }, tmp .. "/proj/src", tmp)
    assert.equals("u.md", r.config.wishes_file)
    assert.equals(tmp .. "/proj", r.root)
    assert.equals(".git", r.via)
  end)

  it("layers project config on top of user opts (.wishes wins)", function()
    write(tmp .. "/proj/.wishes", 'wishes_file = "project.md"\n')
    local wishes = require("wishes")
    local r = wishes.compute_config({ wishes_file = "user.md" }, tmp .. "/proj", tmp)
    assert.equals("project.md", r.config.wishes_file)
    assert.equals("config", r.via)
  end)

  it("merges a project-defined category alongside defaults", function()
    write(tmp .. "/proj/.wishes", table.concat({
      "[categories.perf]",
      'sign = "P"',
      'hl = "DiagnosticWarn"',
      'label = "perf"',
    }, "\n"))
    local wishes = require("wishes")
    local r = wishes.compute_config({}, tmp .. "/proj", tmp)
    assert.equals("P", r.config.categories.perf.sign)
    assert.is_not_nil(r.config.categories.fix)
    assert.is_not_nil(r.config.categories.note)
  end)

  it("reports parse errors without crashing and falls back to user+defaults", function()
    write(tmp .. "/proj/.wishes", "wishes_file = unquoted\n")
    local wishes = require("wishes")
    local r = wishes.compute_config({}, tmp .. "/proj", tmp)
    assert.is_string(r.error)
    assert.equals(".wishes.md", r.config.wishes_file)
  end)
end)
