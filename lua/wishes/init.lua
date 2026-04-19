local M = {}

function M.setup(opts)
  opts = opts or {}
  M._opts = opts

  if opts.dev then
    vim.api.nvim_create_user_command("WishesReload", function()
      require("plenary.reload").reload_module("wishes", true)
      pcall(vim.api.nvim_del_augroup_by_name, "wishes")
      local ns = vim.api.nvim_create_namespace("wishes")
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        end
      end
      require("wishes").setup(M._opts)
      vim.notify("wishes reloaded", vim.log.levels.INFO)
    end, { desc = "Reload wishes.nvim (dev only)" })
  end
end

return M
