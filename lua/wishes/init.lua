local agents = require("wishes.agents")
local config = require("wishes.config")
local core = require("wishes.core")
local display = require("wishes.display")

local M = {}

local function refresh_display()
  if M._root then
    display.refresh_all(M._config, M._root)
  end
end

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

function M.relative_path(abs, root)
  if type(abs) ~= "string" or abs == "" then
    return nil, "empty path"
  end
  if abs:sub(1, #root + 1) == root .. "/" then
    return abs:sub(#root + 2)
  end
  return nil, "path is outside project root"
end

function M.buffer_relative_path(bufnr, root)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local abs = vim.api.nvim_buf_get_name(bufnr)
  return M.relative_path(abs, root)
end

function M.current_wishes_path(user_config, root)
  return root .. "/" .. user_config.wishes_file
end

function M.add_wish_at(user_config, root, file, line_start, line_end, category, text)
  local wish = {
    category = category,
    path = file,
    line_start = line_start,
    line_end = line_end or line_start,
    text = text,
  }
  return core.add_wish(M.current_wishes_path(user_config, root), wish)
end

function M.find_wish_at(user_config, root, file, line)
  local wishes_path = M.current_wishes_path(user_config, root)
  local wishes, warnings_or_err = core.read_file_or_empty(wishes_path)
  if not wishes then
    return nil, warnings_or_err
  end
  for _, w in ipairs(wishes) do
    if core.wish_matches_location(w, file, line) then
      return w
    end
  end
  return nil
end

local function notify_warnings(warnings)
  for _, w in ipairs(warnings or {}) do
    vim.notify("wishes: " .. w, vim.log.levels.WARN)
  end
end

local function require_setup()
  if not M._config or not M._root then
    vim.notify("wishes: not set up or no project root", vim.log.levels.ERROR)
    return nil
  end
  return M._config, M._root
end

local function current_buffer_path(root)
  local file, err = M.buffer_relative_path(nil, root)
  if not file then
    vim.notify("wishes: " .. err, vim.log.levels.ERROR)
    return nil
  end
  return file
end

function M.add(opts)
  opts = opts or {}
  local cfg, root = require_setup()
  if not cfg then return end
  local file = current_buffer_path(root)
  if not file then return end

  local line_start = opts.line_start or opts.line1 or vim.api.nvim_win_get_cursor(0)[1]
  local line_end = opts.line_end or opts.line2 or line_start

  local categories = vim.tbl_keys(cfg.categories)
  table.sort(categories)

  vim.ui.select(categories, {
    prompt = "Category:",
    format_item = function(c)
      local sign = cfg.categories[c] and cfg.categories[c].sign or ""
      return sign .. " " .. c
    end,
  }, function(category)
    if not category then return end

    vim.ui.input({ prompt = "Note: " }, function(text)
      if not text or vim.trim(text) == "" then return end

      local ok, warnings = M.add_wish_at(cfg, root, file, line_start, line_end, category, text)
      if not ok then
        vim.notify("wishes: " .. warnings, vim.log.levels.ERROR)
        return
      end
      notify_warnings(warnings)
      refresh_display()
      local range = line_start == line_end
        and tostring(line_start)
        or (line_start .. "-" .. line_end)
      vim.notify(string.format("wishes: added [%s] %s:%s", category, file, range))
    end)
  end)
end

function M.edit_wish(user_config, root, wish)
  vim.ui.input({ prompt = "Note: ", default = wish.text }, function(new_text)
    if not new_text or vim.trim(new_text) == "" then return end

    local wishes_path = M.current_wishes_path(user_config, root)
    local count, upd_err = core.update_wishes(
      wishes_path,
      function(w)
        return w.path == wish.path
          and w.line_start == wish.line_start
          and w.line_end == wish.line_end
          and w.text == wish.text
      end,
      function(w)
        return vim.tbl_extend("force", w, { text = new_text })
      end
    )
    if not count then
      vim.notify("wishes: " .. upd_err, vim.log.levels.ERROR)
      return
    end
    if count == 0 then
      vim.notify("wishes: wish not found (did the file change?)", vim.log.levels.WARN)
      return
    end
    refresh_display()
    vim.notify("wishes: updated")
  end)
end

function M.edit(opts)
  opts = opts or {}
  local cfg, root = require_setup()
  if not cfg then return end
  local file = current_buffer_path(root)
  if not file then return end

  local line = opts.line_start or opts.line1 or vim.api.nvim_win_get_cursor(0)[1]

  local wish, err = M.find_wish_at(cfg, root, file, line)
  if err then
    vim.notify("wishes: " .. err, vim.log.levels.ERROR)
    return
  end
  if not wish then
    vim.notify("wishes: no wish on this line", vim.log.levels.WARN)
    return
  end

  M.edit_wish(cfg, root, wish)
end

function M.delete_wish(user_config, root, wish)
  local preview = wish.text:sub(1, 50)
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Delete: " .. preview,
  }, function(choice)
    if choice ~= "Yes" then return end

    local wishes_path = M.current_wishes_path(user_config, root)
    local count, del_err = core.delete_wishes(wishes_path, function(w)
      return w.path == wish.path
        and w.line_start == wish.line_start
        and w.line_end == wish.line_end
        and w.text == wish.text
    end)
    if not count then
      vim.notify("wishes: " .. del_err, vim.log.levels.ERROR)
      return
    end
    refresh_display()
    vim.notify("wishes: deleted " .. count .. " wish(es)")
  end)
end

function M.delete(opts)
  opts = opts or {}
  local cfg, root = require_setup()
  if not cfg then return end
  local file = current_buffer_path(root)
  if not file then return end

  local line = opts.line_start or opts.line1 or vim.api.nvim_win_get_cursor(0)[1]

  local wish, err = M.find_wish_at(cfg, root, file, line)
  if err then
    vim.notify("wishes: " .. err, vim.log.levels.ERROR)
    return
  end
  if not wish then
    vim.notify("wishes: no wish on this line", vim.log.levels.WARN)
    return
  end

  M.delete_wish(cfg, root, wish)
end

function M.clear()
  local cfg, root = require_setup()
  if not cfg then return end
  local wishes_path = M.current_wishes_path(cfg, root)
  if not vim.uv.fs_stat(wishes_path) then
    vim.notify("wishes: no wishes file exists")
    return
  end

  vim.ui.select({ "Yes", "No" }, { prompt = "Delete all wishes?" }, function(choice)
    if choice ~= "Yes" then return end
    local ok, err = os.remove(wishes_path)
    if not ok then
      vim.notify("wishes: " .. err, vim.log.levels.ERROR)
      return
    end
    refresh_display()
    vim.notify("wishes: cleared")
  end)
end

function M.build_summary(wishes)
  local by_file = {}
  for _, w in ipairs(wishes) do
    by_file[w.path] = by_file[w.path] or {}
    table.insert(by_file[w.path], w)
  end

  local file_count = vim.tbl_count(by_file)
  local files = vim.tbl_keys(by_file)
  table.sort(files)

  local lines = {
    string.format("Wishes (%d total across %d file%s)",
      #wishes, file_count, file_count == 1 and "" or "s"),
    "",
  }

  for _, file in ipairs(files) do
    local group = by_file[file]
    table.sort(group, function(a, b) return a.line_start < b.line_start end)
    table.insert(lines, file .. " (" .. #group .. ")")
    for _, wish in ipairs(group) do
      local range = wish.line_start == wish.line_end
        and tostring(wish.line_start)
        or (wish.line_start .. "-" .. wish.line_end)
      table.insert(lines, string.format("  [%s] :%s  %s", wish.category, range, wish.text))
    end
  end

  return lines
end

function M.summary()
  local cfg, root = require_setup()
  if not cfg then return end
  local wishes_path = M.current_wishes_path(cfg, root)
  local wishes, err = core.read_file_or_empty(wishes_path)
  if not wishes then
    vim.notify("wishes: " .. err, vim.log.levels.ERROR)
    return
  end
  if #wishes == 0 then
    vim.notify("wishes: no wishes yet")
    return
  end

  local lines = M.build_summary(wishes)
  vim.api.nvim_echo(vim.tbl_map(function(l) return { l .. "\n" } end, lines), false, {})
end

function M.list()
  local cfg, root = require_setup()
  if not cfg then return end
  local picker = require("wishes.picker")
  local ok, err = picker.show(cfg, root)
  if not ok and err then
    vim.notify("wishes: " .. err, vim.log.levels.ERROR)
  end
end

function M.install()
  local cfg, root = require_setup()
  if not cfg then return end

  local detected = agents.detect(root)
  if #detected == 0 then
    vim.notify("wishes: no agents detected", vim.log.levels.WARN)
    return
  end

  vim.ui.select(detected, {
    prompt = "Install instructions for:",
    format_item = function(key) return agents.agent_name(key) end,
  }, function(choice)
    if not choice then return end
    local ok, err = agents.install(root, choice)
    if not ok then
      vim.notify("wishes: " .. (err or "install failed"), vim.log.levels.ERROR)
      return
    end
    vim.notify(string.format("wishes: installed %s (%s)",
      agents.agent_name(choice), agents.agent_target(choice)))
  end)
end

function M.uninstall()
  local cfg, root = require_setup()
  if not cfg then return end

  local installed = {}
  for _, key in ipairs(agents.list_agent_keys()) do
    local target = agents.agent_target(key)
    if target and vim.uv.fs_stat(root .. "/" .. target) then
      table.insert(installed, key)
    end
  end

  if #installed == 0 then
    vim.notify("wishes: no agents appear to be installed here")
    return
  end

  vim.ui.select(installed, {
    prompt = "Uninstall instructions for:",
    format_item = function(key) return agents.agent_name(key) end,
  }, function(choice)
    if not choice then return end
    local ok, err = agents.uninstall(root, choice)
    if ok == nil then
      vim.notify("wishes: " .. (err or "uninstall failed"), vim.log.levels.ERROR)
      return
    end
    if ok == false then
      vim.notify("wishes: " .. agents.agent_name(choice) .. " was not installed")
      return
    end
    vim.notify("wishes: uninstalled " .. agents.agent_name(choice))
  end)
end

local SUBCOMMANDS = { "add", "edit", "delete", "list", "summary", "clear", "install", "uninstall" }

function M.dispatch(opts)
  local subcommand = opts.fargs and opts.fargs[1]
  if not subcommand then
    vim.notify("wishes: missing subcommand", vim.log.levels.ERROR)
    return
  end
  local handler = M[subcommand]
  if type(handler) ~= "function" or not vim.tbl_contains(SUBCOMMANDS, subcommand) then
    vim.notify("wishes: unknown subcommand '" .. subcommand .. "'", vim.log.levels.ERROR)
    return
  end
  handler({
    line1 = opts.line1,
    line2 = opts.line2,
    range = opts.range,
  })
end

function M.complete(arglead, cmdline)
  local after = cmdline:gsub("^%s*%S+%s*", "")
  if after:find("%s") then
    return {}
  end
  local out = {}
  for _, sc in ipairs(SUBCOMMANDS) do
    if vim.startswith(sc, arglead or "") then
      table.insert(out, sc)
    end
  end
  return out
end

local function register_keymaps(cfg)
  local keys = cfg.keys
  if type(keys) ~= "table" then return end

  local function nmap(lhs, rhs, desc)
    if lhs then
      vim.keymap.set("n", lhs, rhs, { desc = desc, silent = true })
    end
  end

  nmap(keys.add, function() M.add() end, "wishes: add")
  nmap(keys.edit, function() M.edit() end, "wishes: edit")
  nmap(keys.delete, function() M.delete() end, "wishes: delete")
  nmap(keys.list, function() M.list() end, "wishes: list")
  nmap(keys.install, function() M.install() end, "wishes: install agent instructions")

  if keys.add then
    vim.keymap.set("x", keys.add, function()
      local s = vim.fn.line("v")
      local e = vim.fn.line(".")
      if s > e then s, e = e, s end
      vim.api.nvim_input("<Esc>")
      vim.schedule(function() M.add({ line_start = s, line_end = e }) end)
    end, { desc = "wishes: add (visual)", silent = true })
  end
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

  register_keymaps(M._config)
  display.ensure_highlight_groups(M._config)
  display.setup_autocmds(M._config, M._root)
  refresh_display()

  if opts.dev then
    vim.api.nvim_create_user_command("WishesReload", function()
      pcall(function() require("wishes.display").stop_watcher() end)
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
