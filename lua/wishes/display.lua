local core = require("wishes.core")

local M = {}

-- State that must survive plenary.reload so we can stop previous watchers.
_G._wishes_display = _G._wishes_display or {}
local state = _G._wishes_display

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

function M.derived_hl_name(category_name)
  return "WishesCategory_" .. category_name
end

function M.ensure_highlight_groups(user_config)
  local categories = user_config.categories or {}
  for name, cat in pairs(categories) do
    if cat.fg or cat.bg then
      vim.api.nvim_set_hl(0, M.derived_hl_name(name), {
        fg = cat.fg,
        bg = cat.bg,
      })
    end
  end
end

local function resolve_hls(cat, category_name)
  local base = cat.hl or "Comment"
  local derived = (cat.fg or cat.bg) and M.derived_hl_name(category_name) or nil
  return
    cat.sign_hl or derived or base,
    cat.text_hl or derived or base
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
    local sign_hl, text_hl = resolve_hls(cat, wish.category)
    local sign = cat.sign
    if sign == "" then
      sign = nil
    end
    local line0 = wish.line_start - 1

    pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, line0, 0, {
      sign_text = sign,
      sign_hl_group = sign_hl,
      virt_text = { { prefix .. wish.text, text_hl } },
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

function M.stop_watcher()
  if state.timer then
    pcall(state.timer.stop, state.timer)
    pcall(state.timer.close, state.timer)
    state.timer = nil
  end
end

local function start_watcher(user_config, root)
  M.stop_watcher()
  if not user_config.auto_refresh or not root then
    return
  end

  local wishes_path = root .. "/" .. user_config.wishes_file
  local stat = vim.uv.fs_stat(wishes_path)
  local last_mtime = stat and stat.mtime.sec or 0

  local timer = vim.uv.new_timer()
  if not timer then
    return
  end
  state.timer = timer

  timer:start(1000, 1000, vim.schedule_wrap(function()
    local s = vim.uv.fs_stat(wishes_path)
    local current = s and s.mtime.sec or 0
    if current ~= last_mtime then
      last_mtime = current
      M.refresh_all(user_config, root)
    end
  end))
end

function M.setup_autocmds(user_config, root)
  local group = vim.api.nvim_create_augroup("wishes", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      M.ensure_highlight_groups(user_config)
    end,
  })

  if user_config.auto_refresh and root then
    vim.api.nvim_create_autocmd({
      "BufEnter",
      "BufWinEnter",
      "BufWritePost",
      "FileChangedShellPost",
    }, {
      group = group,
      callback = function(args)
        M.refresh(args.buf, user_config, root)
      end,
    })

    start_watcher(user_config, root)
  end
end

return M
