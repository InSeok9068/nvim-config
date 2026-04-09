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
  return vim.fn.stdpath("config") .. "/tools/pocketpages-lsp/run-server.js"
end

function M.tools_dir()
  return vim.fn.stdpath("config") .. "/tools/pocketpages-lsp"
end

function M.data_dir()
  return vim.fn.stdpath("data") .. "/pocketpages-lsp"
end

function M.cache_dir()
  return vim.fn.stdpath("cache") .. "/pocketpages-lsp"
end

function M.node_modules_dir()
  return M.data_dir() .. "/node_modules"
end

function M.package_json()
  return M.tools_dir() .. "/package.json"
end

function M.package_lock_json()
  return M.tools_dir() .. "/package-lock.json"
end

local function copy_if_changed(source, destination)
  local source_lines = vim.fn.readfile(source, "b")
  if vim.v.shell_error ~= 0 then
    return false
  end

  local destination_lines = vim.fn.filereadable(destination) == 1 and vim.fn.readfile(destination, "b") or nil
  if destination_lines and vim.deep_equal(source_lines, destination_lines) then
    return true
  end

  vim.fn.mkdir(vim.fs.dirname(destination), "p")
  vim.fn.writefile(source_lines, destination, "b")
  return true
end

function M.sync_runtime_manifest()
  if vim.fn.filereadable(M.package_json()) ~= 1 then
    return false
  end

  local package_ok = copy_if_changed(M.package_json(), M.data_dir() .. "/package.json")
  local lock_ok = true
  if vim.fn.filereadable(M.package_lock_json()) == 1 then
    lock_ok = copy_if_changed(M.package_lock_json(), M.data_dir() .. "/package-lock.json")
  end

  return package_ok and lock_ok
end

function M.is_available()
  if vim.fn.executable("node") ~= 1 or vim.uv.fs_stat(M.server_script()) == nil then
    return false
  end

  M.sync_runtime_manifest()

  return vim.uv.fs_stat(M.node_modules_dir()) ~= nil
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
