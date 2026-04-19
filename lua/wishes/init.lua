local config = require("wishes.config")
local core = require("wishes.core")

local M = {}

function M.compute_config(user_opts, start_dir, stop_at)
  user_opts = user_opts or {}
  start_dir = start_dir or vim.fn.getcwd()

  local with_user = config.merge(config.defaults, user_opts)
  local find_opts = { root_markers = with_user.root_markers }
  if stop_at ~= nil then
    find_opts.stop_at = stop_at
  end

  local root, via = core.find_root(start_dir, find_opts)

  if root then
    local project_opts, err = config.load_project_file(root)
    if err then
      return {
        config = config.resolve(user_opts),
        root = root,
        via = via,
        error = err,
      }
    end
    return {
      config = config.resolve(user_opts, project_opts),
      root = root,
      via = via,
    }
  end

  return {
    config = config.resolve(user_opts),
    root = nil,
    via = nil,
  }
end

function M.setup(opts)
  opts = opts or {}
  local result = M.compute_config(opts)

  if result.error then
    vim.notify("wishes: invalid .wishes file: " .. result.error, vim.log.levels.WARN)
  end

  M._user_opts = opts
  M._config = result.config
  M._root = result.root
  M._root_via = result.via

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
      require("wishes").setup(M._user_opts)
      vim.notify("wishes reloaded", vim.log.levels.INFO)
    end, { desc = "Reload wishes.nvim (dev only)", force = true })
  end
end

return M
