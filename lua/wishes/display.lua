local core = require("wishes.core")

local M = {}

local NAMESPACE = "wishes"
local cached_ns

local function ns()
  cached_ns = cached_ns or vim.api.nvim_create_namespace(NAMESPACE)
  return cached_ns
end

local function buffer_file(bufnr, root)
  local abs = vim.api.nvim_buf_get_name(bufnr)
  if abs == "" then
    return nil
  end
  if abs:sub(1, #root + 1) == root .. "/" then
    return abs:sub(#root + 2)
  end
  return nil
end

function M.clear(bufnr)
  bufnr = bufnr or 0
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns(), 0, -1)
  end
end

function M.render(bufnr, wishes, user_config)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local namespace = ns()
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  local prefix = user_config.virtual_text_prefix or ""
  local categories = user_config.categories or {}

  for _, wish in ipairs(wishes) do
    local cat = categories[wish.category] or {}
    local hl = cat.hl or "Comment"
    local sign = cat.sign
    if sign == "" then
      sign = nil
    end
    local line0 = wish.line_start - 1

    pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, line0, 0, {
      sign_text = sign,
      sign_hl_group = hl,
      virt_text = { { prefix .. wish.text, hl } },
      virt_text_pos = "eol",
      strict = false,
    })
  end
end

function M.refresh(bufnr, user_config, root)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local file = buffer_file(bufnr, root)
  if not file then
    M.clear(bufnr)
    return
  end

  local wishes_path = root .. "/" .. user_config.wishes_file
  local all_wishes = core.read_file_or_empty(wishes_path)
  if not all_wishes then
    M.clear(bufnr)
    return
  end

  local filtered = {}
  for _, w in ipairs(all_wishes) do
    if w.path == file then
      table.insert(filtered, w)
    end
  end

  M.render(bufnr, filtered, user_config)
end

function M.refresh_all(user_config, root)
  if not root then
    return
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.refresh(buf, user_config, root)
    end
  end
end

function M.setup_autocmds(user_config, root)
  if not user_config.auto_refresh or not root then
    return
  end
  local group = vim.api.nvim_create_augroup("wishes", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(args)
      M.refresh(args.buf, user_config, root)
    end,
  })
end

return M
