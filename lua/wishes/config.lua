local core = require("wishes.core")

local M = {}

local function deepcopy(v)
  if type(v) ~= "table" then
    return v
  end
  local copy = {}
  for k, val in pairs(v) do
    copy[k] = deepcopy(val)
  end
  return copy
end

local function is_map(t)
  if type(t) ~= "table" then
    return false
  end
  if next(t) == nil then
    return true
  end
  return not vim.islist(t)
end

M.defaults = {
  wishes_file = ".wishes.md",
  root_markers = core.DEFAULT_ROOT_MARKERS,
  keys = {
    add = "<leader>an",
    edit = "<leader>ae",
    delete = "<leader>ad",
    list = "<leader>al",
    install = "<leader>ai",
  },
  categories = {
    fix = { sign = "✗", hl = "DiagnosticError", label = "fix" },
    question = { sign = "?", hl = "DiagnosticWarn", label = "question" },
    refactor = { sign = "↻", hl = "DiagnosticInfo", label = "refactor" },
    note = { sign = "•", hl = "DiagnosticHint", label = "note" },
  },
  default_category = "note",
  virtual_text_prefix = " ▎ ",
  auto_refresh = true,
}

function M.merge(base, overlay)
  if overlay == nil then
    return deepcopy(base)
  end
  if not is_map(overlay) or not is_map(base) then
    return deepcopy(overlay)
  end

  local result = {}
  for k, v in pairs(base) do
    result[k] = deepcopy(v)
  end
  for k, v in pairs(overlay) do
    result[k] = M.merge(result[k], v)
  end
  return result
end

local function parse_string_value(str)
  local trimmed = vim.trim(str)
  local quote = trimmed:sub(1, 1)
  if quote ~= '"' and quote ~= "'" then
    return nil, "expected quoted string"
  end
  local close = trimmed:find(quote, 2, true)
  if not close then
    return nil, "unterminated string"
  end
  local value = trimmed:sub(2, close - 1)
  local rest = vim.trim(trimmed:sub(close + 1))
  if rest ~= "" and rest:sub(1, 1) ~= "#" then
    return nil, "unexpected content after string"
  end
  return value
end

function M.parse_toml(content)
  local root = {}
  local current = root
  local lineno = 0

  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    local stripped = vim.trim(line)

    if stripped == "" or stripped:sub(1, 1) == "#" then
      -- skip
    elseif stripped:sub(1, 1) == "[" then
      local inner = stripped:match("^%[([^%]]+)%]")
      if not inner then
        return nil, string.format("line %d: malformed section header", lineno)
      end
      current = root
      for part in inner:gmatch("[^.]+") do
        local name = vim.trim(part)
        current[name] = current[name] or {}
        current = current[name]
      end
    else
      local key, value_str = stripped:match("^([%w_]+)%s*=%s*(.+)$")
      if not key then
        return nil, string.format("line %d: malformed key-value", lineno)
      end
      local value, err = parse_string_value(value_str)
      if value == nil then
        return nil, string.format("line %d: %s", lineno, err)
      end
      current[key] = value
    end
  end

  return root
end

function M.load_project_file(project_root)
  local path = project_root .. "/.wishes"
  if not vim.uv.fs_stat(path) then
    return nil
  end

  local f, open_err = io.open(path, "r")
  if not f then
    return nil, open_err
  end
  local content = f:read("*a")
  f:close()

  return M.parse_toml(content)
end

function M.resolve(user_opts, project_opts)
  local merged = M.merge(M.defaults, user_opts)
  if project_opts then
    merged = M.merge(merged, project_opts)
  end
  return merged
end

return M
