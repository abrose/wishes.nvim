if vim.g.loaded_wishes then
  return
end
vim.g.loaded_wishes = true

vim.api.nvim_create_user_command("Wishes", function(opts)
  require("wishes").dispatch(opts)
end, {
  nargs = "+",
  range = true,
  complete = function(arglead, cmdline, _)
    return require("wishes").complete(arglead, cmdline)
  end,
  desc = "wishes.nvim command dispatcher",
})
