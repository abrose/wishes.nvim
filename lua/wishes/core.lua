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

M.DEFAULT_ROOT_MARKERS = DEFAULT_ROOT_MARKERS
M.SEPARATOR = SEPARATOR

return M
