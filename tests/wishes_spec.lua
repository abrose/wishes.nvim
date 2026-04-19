describe("wishes", function()
  before_each(function()
    require("plenary.reload").reload_module("wishes", true)
    pcall(vim.api.nvim_del_augroup_by_name, "wishes")
    pcall(vim.api.nvim_del_user_command, "WishesReload")
  end)

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
end)
