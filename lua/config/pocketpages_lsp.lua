local M = {}

local function normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function is_excluded_script(path)
  local normalized = normalize_path(path)

  if not normalized:match("/pb_hooks/pages/") then
    return false
  end

  local relative = normalized:match("/pb_hooks/pages/(.+)$") or ""
  local segments = vim.split(relative, "/", { plain = true, trimempty = true })

  return vim.tbl_contains(segments, "vendor")
    or normalized:match("%.min%.js$")
    or normalized:match("%.min%.cjs$")
    or normalized:match("%.min%.mjs$")
end

function M.is_target(path)
  local normalized = normalize_path(path)

  if normalized:match("%.ejs$") then
    return true
  end

  if not normalized:match("/pb_hooks/pages/") then
    return false
  end

  return not is_excluded_script(normalized)
    and (normalized:match("%.js$") ~= nil or normalized:match("%.cjs$") ~= nil or normalized:match("%.mjs$") ~= nil)
end

function M.root_dir(fname)
  if not M.is_target(fname) then
    return nil
  end

  local current = vim.fs.dirname(fname)

  while current do
    local pages_dir = vim.fs.joinpath(current, "pb_hooks", "pages")
    local stat = vim.uv.fs_stat(pages_dir)
    if stat and stat.type == "directory" then
      return current
    end

    local parent = vim.fs.dirname(current)
    if not parent or parent == current then
      break
    end

    current = parent
  end

  return nil
end

function M.config_root_dir(bufnr, on_dir)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then
    return
  end

  local root = M.root_dir(bufname)
  if root then
    on_dir(root)
  end
end

function M.server_script()
  return vim.fn.stdpath("config") .. "/tools/pocketpages-lsp/server.js"
end

function M.is_available()
  return vim.fn.executable("node") == 1 and vim.uv.fs_stat(M.server_script()) ~= nil
end

function M.client_config(fname)
  if not M.is_available() or not M.is_target(fname) then
    return nil
  end

  local root = M.root_dir(fname)
  if not root then
    return nil
  end

  return {
    name = "pocketpages",
    cmd = { "node", M.server_script(), "--stdio" },
    root_dir = root,
    workspace_folders = {
      {
        uri = vim.uri_from_fname(root),
        name = root,
      },
    },
  }
end

return M
