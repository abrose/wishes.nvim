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

describe("wishes helpers", function()
  before_each(reset)

  it("relative_path strips the root prefix", function()
    local wishes = require("wishes")
    assert.equals("src/foo.lua", wishes.relative_path("/proj/src/foo.lua", "/proj"))
  end)

  it("relative_path rejects paths outside the root", function()
    local wishes = require("wishes")
    local p, err = wishes.relative_path("/elsewhere/x.lua", "/proj")
    assert.is_nil(p)
    assert.is_string(err)
  end)

  it("relative_path rejects empty paths", function()
    local wishes = require("wishes")
    local p, err = wishes.relative_path("", "/proj")
    assert.is_nil(p)
    assert.is_string(err)
  end)

  it("current_wishes_path joins root and config.wishes_file", function()
    local wishes = require("wishes")
    assert.equals("/proj/.wishes.md",
      wishes.current_wishes_path({ wishes_file = ".wishes.md" }, "/proj"))
    assert.equals("/proj/reviews/current.txt",
      wishes.current_wishes_path({ wishes_file = "reviews/current.txt" }, "/proj"))
  end)
end)

describe("wishes.add_wish_at / find_wish_at", function()
  local tmp

  before_each(function()
    reset()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
  end)

  after_each(function()
    vim.fn.delete(tmp, "rf")
  end)

  it("add_wish_at writes a wish through core.add_wish", function()
    local wishes = require("wishes")
    local cfg = { wishes_file = ".wishes.md" }
    local ok = wishes.add_wish_at(cfg, tmp, "src/a.lua", 1, 1, "fix", "broken")
    assert.is_true(ok)

    local list = require("wishes.core").read_file(tmp .. "/.wishes.md")
    assert.equals(1, #list)
    assert.equals("fix", list[1].category)
    assert.equals("src/a.lua", list[1].path)
  end)

  it("find_wish_at locates a wish by file and line", function()
    local wishes = require("wishes")
    local cfg = { wishes_file = ".wishes.md" }
    wishes.add_wish_at(cfg, tmp, "src/a.lua", 10, 20, "fix", "range wish")
    wishes.add_wish_at(cfg, tmp, "src/a.lua", 30, 30, "note", "single")

    local wish = wishes.find_wish_at(cfg, tmp, "src/a.lua", 15)
    assert.is_not_nil(wish)
    assert.equals("range wish", wish.text)

    wish = wishes.find_wish_at(cfg, tmp, "src/a.lua", 30)
    assert.equals("single", wish.text)

    wish = wishes.find_wish_at(cfg, tmp, "src/a.lua", 999)
    assert.is_nil(wish)
  end)

  it("find_wish_at returns nil when no wishes file exists", function()
    local wishes = require("wishes")
    local cfg = { wishes_file = ".wishes.md" }
    assert.is_nil(wishes.find_wish_at(cfg, tmp, "src/a.lua", 1))
  end)
end)

describe("wishes.dispatch / complete", function()
  before_each(reset)

  it("complete returns all subcommands when arglead is empty", function()
    local wishes = require("wishes")
    local out = wishes.complete("", "Wishes ")
    assert.is_true(vim.tbl_contains(out, "add"))
    assert.is_true(vim.tbl_contains(out, "edit"))
    assert.is_true(vim.tbl_contains(out, "delete"))
    assert.is_true(vim.tbl_contains(out, "clear"))
  end)

  it("complete filters by prefix", function()
    local wishes = require("wishes")
    local out = wishes.complete("de", "Wishes de")
    assert.same({ "delete" }, out)
  end)

  it("complete returns empty list past the first argument", function()
    local wishes = require("wishes")
    local out = wishes.complete("", "Wishes add ")
    assert.same({}, out)
  end)

  it("dispatch rejects unknown subcommands without crashing", function()
    local wishes = require("wishes")
    wishes.setup({})
    local notified
    local original_notify = vim.notify
    vim.notify = function(msg, level) notified = { msg = msg, level = level } end
    wishes.dispatch({ fargs = { "bogus" }, line1 = 1, line2 = 1, range = 0 })
    vim.notify = original_notify
    assert.is_not_nil(notified)
    assert.truthy(notified.msg:find("unknown subcommand"))
  end)

  it("dispatch rejects a missing subcommand", function()
    local wishes = require("wishes")
    local notified
    local original_notify = vim.notify
    vim.notify = function(msg) notified = msg end
    wishes.dispatch({ fargs = {}, line1 = 1, line2 = 1, range = 0 })
    vim.notify = original_notify
    assert.truthy(notified and notified:find("missing subcommand"))
  end)
end)
