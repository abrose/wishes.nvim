local M = {}

local DEFAULT_ROOT_MARKERS = {
  ".git",
  ".claude",
  ".pi",
  ".opencode",
  ".hg",
  ".svn",
  "Makefile",
  "package.json",
  "Cargo.toml",
  "go.mod",
  "pyproject.toml",
}

local SEPARATOR = " — "

local function find_upward(markers, start_dir, stop_at)
  local dir = start_dir
  while dir ~= stop_at and dir ~= "/" do
    for _, marker in ipairs(markers) do
      if vim.uv.fs_stat(dir .. "/" .. marker) then
        return dir, marker
      end
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      return nil
    end
    dir = parent
  end
  return nil
end

function M.find_root(start_dir, opts)
  opts = opts or {}
  local markers = opts.root_markers or DEFAULT_ROOT_MARKERS
  local stop_at = opts.stop_at or vim.uv.os_homedir()

  local config_root = find_upward({ ".wishes" }, start_dir, stop_at)
  if config_root then
    return config_root, "config"
  end

  local fallback_root, via = find_upward(markers, start_dir, stop_at)
  if fallback_root then
    return fallback_root, via
  end

  return nil, "reached_boundary"
end

function M.parse_line(raw)
  if type(raw) ~= "string" then
    return nil
  end
  local line = vim.trim(raw)
  if line == "" or line:sub(1, 1) == "#" then
    return nil
  end

  local sep_start, sep_end = line:find(SEPARATOR, 1, true)
  if not sep_start then
    return nil
  end

  local head = line:sub(1, sep_start - 1)
  local text = vim.trim(line:sub(sep_end + 1))

  local category, path, line_start, line_end =
    head:match("^%[([^%]]+)%]%s+(.+):(%d+)%-?(%d*)$")
  if not category then
    return nil
  end

  line_start = tonumber(line_start)
  line_end = line_end == "" and line_start or tonumber(line_end)

  return {
    category = category,
    path = path,
    line_start = line_start,
    line_end = line_end,
    text = text,
  }
end

function M.format_line(wish)
  if type(wish) ~= "table" then
    return nil, "wish must be a table"
  end
  if type(wish.category) ~= "string" or wish.category == "" then
    return nil, "wish.category must be a non-empty string"
  end
  if type(wish.path) ~= "string" or wish.path == "" then
    return nil, "wish.path must be a non-empty string"
  end
  if type(wish.line_start) ~= "number" then
    return nil, "wish.line_start must be a number"
  end
  if type(wish.text) ~= "string" then
    return nil, "wish.text must be a string"
  end
  if wish.text:find("\n") then
    return nil, "wish.text cannot contain newlines"
  end

  local line_end = wish.line_end or wish.line_start
  local line_ref
  if line_end ~= wish.line_start then
    line_ref = string.format("%d-%d", wish.line_start, line_end)
  else
    line_ref = tostring(wish.line_start)
  end

  return string.format(
    "[%s] %s:%s%s%s",
    wish.category,
    wish.path,
    line_ref,
    SEPARATOR,
    wish.text
  )
end

function M.parse_content(content)
  local wishes = {}
  local warnings = {}
  local lineno = 0

  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    local stripped = vim.trim(line)
    if stripped ~= "" and stripped:sub(1, 1) ~= "#" then
      local wish = M.parse_line(line)
      if wish then
        table.insert(wishes, wish)
      else
        table.insert(warnings, string.format("line %d: malformed: %s", lineno, stripped))
      end
    end
  end

  return wishes, warnings
end

function M.read_file(path)
  local f, err = io.open(path, "r")
  if not f then
    return nil, err
  end
  local content = f:read("*a")
  f:close()
  return M.parse_content(content)
end

function M.write_file(path, wishes)
  local lines = {}
  for i, wish in ipairs(wishes) do
    local line, err = M.format_line(wish)
    if not line then
      return nil, string.format("wish at index %d: %s", i, err)
    end
    table.insert(lines, line)
  end

  local dir = vim.fs.dirname(path)
  if dir and dir ~= "" then
    vim.fn.mkdir(dir, "p")
  end

  local content = table.concat(lines, "\n")
  if #lines > 0 then
    content = content .. "\n"
  end

  local f, open_err = io.open(path, "w")
  if not f then
    return nil, open_err
  end
  local ok, write_err = f:write(content)
  f:close()
  if not ok then
    return nil, write_err
  end
  return true
end

function M.read_file_or_empty(path)
  if vim.uv.fs_stat(path) then
    return M.read_file(path)
  end
  return {}, {}
end

function M.wish_matches_location(wish, file, line)
  if wish.path ~= file then
    return false
  end
  local start_line = wish.line_start
  local end_line = wish.line_end or start_line
  return start_line <= line and line <= end_line
end

function M.add_wish(path, wish)
  local existing, warnings_or_err = M.read_file_or_empty(path)
  if not existing then
    return nil, warnings_or_err
  end
  table.insert(existing, wish)
  local ok, err = M.write_file(path, existing)
  if not ok then
    return nil, err
  end
  return true, warnings_or_err
end

function M.delete_wishes(path, predicate)
  local existing, warnings_or_err = M.read_file_or_empty(path)
  if not existing then
    return nil, warnings_or_err
  end

  local kept = {}
  local count = 0
  for _, wish in ipairs(existing) do
    if predicate(wish) then
      count = count + 1
    else
      table.insert(kept, wish)
    end
  end

  if count == 0 then
    return 0, warnings_or_err
  end

  local ok, err = M.write_file(path, kept)
  if not ok then
    return nil, err
  end
  return count, warnings_or_err
end

function M.update_wishes(path, predicate, mutator)
  local existing, warnings_or_err = M.read_file_or_empty(path)
  if not existing then
    return nil, warnings_or_err
  end

  local count = 0
  for i, wish in ipairs(existing) do
    if predicate(wish) then
      existing[i] = mutator(wish)
      count = count + 1
    end
  end

  if count == 0 then
    return 0, warnings_or_err
  end

  local ok, err = M.write_file(path, existing)
  if not ok then
    return nil, err
  end
  return count, warnings_or_err
end

M.DEFAULT_ROOT_MARKERS = DEFAULT_ROOT_MARKERS
M.SEPARATOR = SEPARATOR

return M
