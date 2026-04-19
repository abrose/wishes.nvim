local display = require("wishes.display")
local core = require("wishes.core")

local NAMESPACE = "wishes"

local function extmarks(bufnr)
  local ns = vim.api.nvim_create_namespace(NAMESPACE)
  return vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
end

local function config_with(categories, prefix)
  return {
    wishes_file = ".wishes.md",
    virtual_text_prefix = prefix or " ",
    auto_refresh = true,
    categories = categories or {
      fix = { sign = "F", hl = "DiagnosticError", label = "fix" },
      note = { sign = "N", hl = "DiagnosticHint", label = "note" },
    },
  }
end

describe("wishes.display.render", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "line 1", "line 2", "line 3", "line 4", "line 5",
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("places an extmark with sign + virtual text for a single wish", function()
    display.render(bufnr, {
      { category = "fix", path = "x.lua", line_start = 2, line_end = 2, text = "broken" },
    }, config_with())

    local marks = extmarks(bufnr)
    assert.equals(1, #marks)
    local _, row, _, details = unpack(marks[1])
    assert.equals(1, row)
    assert.equals("F", vim.trim(details.sign_text))
    assert.equals("DiagnosticError", details.sign_hl_group)
    assert.equals("DiagnosticError", details.virt_text[1][2])
    assert.truthy(details.virt_text[1][1]:find("broken"))
  end)

  it("places one extmark per wish in the list", function()
    display.render(bufnr, {
      { category = "fix", path = "x.lua", line_start = 1, line_end = 1, text = "a" },
      { category = "note", path = "x.lua", line_start = 3, line_end = 3, text = "b" },
    }, config_with())

    assert.equals(2, #extmarks(bufnr))
  end)

  it("clears previous extmarks before rendering new ones (idempotent re-render)", function()
    display.render(bufnr, {
      { category = "fix", path = "x.lua", line_start = 1, line_end = 1, text = "first" },
    }, config_with())

    display.render(bufnr, {
      { category = "fix", path = "x.lua", line_start = 2, line_end = 2, text = "second" },
    }, config_with())

    local marks = extmarks(bufnr)
    assert.equals(1, #marks)
    local _, row = unpack(marks[1])
    assert.equals(1, row)
  end)

  it("does not error on out-of-range line numbers", function()
    assert.has_no.errors(function()
      display.render(bufnr, {
        { category = "fix", path = "x.lua", line_start = 999, line_end = 999, text = "far" },
      }, config_with())
    end)
  end)

  it("uses Comment highlight as fallback when category is unknown", function()
    display.render(bufnr, {
      { category = "custom", path = "x.lua", line_start = 1, line_end = 1, text = "x" },
    }, config_with({}))

    local marks = extmarks(bufnr)
    assert.equals(1, #marks)
    assert.equals("Comment", marks[1][4].virt_text[1][2])
  end)

  it("prepends virtual_text_prefix to the rendered note", function()
    display.render(bufnr, {
      { category = "fix", path = "x.lua", line_start = 1, line_end = 1, text = "note" },
    }, config_with(nil, " ▎ "))

    local marks = extmarks(bufnr)
    assert.equals(" ▎ note", marks[1][4].virt_text[1][1])
  end)
end)

describe("wishes.display.refresh", function()
  local bufnr, tmp

  before_each(function()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x", "y", "z" })
  end)

  after_each(function()
    vim.fn.delete(tmp, "rf")
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("renders only wishes whose path matches the buffer's file", function()
    core.write_file(tmp .. "/.wishes.md", {
      { category = "fix", path = "src/foo.lua", line_start = 1, line_end = 1, text = "in foo" },
      { category = "note", path = "src/bar.lua", line_start = 1, line_end = 1, text = "in bar" },
    })

    vim.api.nvim_buf_set_name(bufnr, tmp .. "/src/foo.lua")
    display.refresh(bufnr, config_with(), tmp)

    local marks = extmarks(bufnr)
    assert.equals(1, #marks)
    assert.truthy(marks[1][4].virt_text[1][1]:find("in foo"))
  end)

  it("clears marks when the buffer has no matching file", function()
    vim.api.nvim_buf_set_name(bufnr, "/not/under/root.lua")
    display.refresh(bufnr, config_with(), tmp)
    assert.equals(0, #extmarks(bufnr))
  end)

  it("clears marks when the buffer has no name", function()
    display.refresh(bufnr, config_with(), tmp)
    assert.equals(0, #extmarks(bufnr))
  end)

  it("does nothing when the wishes file does not exist", function()
    vim.api.nvim_buf_set_name(bufnr, tmp .. "/src/foo.lua")
    assert.has_no.errors(function()
      display.refresh(bufnr, config_with(), tmp)
    end)
    assert.equals(0, #extmarks(bufnr))
  end)
end)

describe("wishes.display.clear", function()
  it("removes all wishes extmarks in a buffer", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b" })
    display.render(bufnr, {
      { category = "fix", path = "x.lua", line_start = 1, line_end = 1, text = "t" },
    }, config_with())
    assert.equals(1, #extmarks(bufnr))

    display.clear(bufnr)
    assert.equals(0, #extmarks(bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
