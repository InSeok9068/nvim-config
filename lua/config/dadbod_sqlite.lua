local M = {}

local function to_slash(path)
  return (path or ""):gsub("\\", "/")
end

local function clone_entry(entry)
  if type(entry) == "table" then
    return vim.deepcopy(entry)
  end
  return entry
end

local function entry_name(entry)
  return type(entry) == "table" and entry.name or nil
end

local function entry_url(entry)
  if type(entry) == "table" then
    return entry.url
  end
  if type(entry) == "string" then
    return entry
  end
  return nil
end

local function exact_key(entry)
  return table.concat({
    entry_name(entry) or "",
    entry_url(entry) or "",
  }, "\0")
end

local function normalize_dbs(dbs)
  if type(dbs) ~= "table" then
    return {}
  end

  if vim.islist(dbs) then
    return vim.tbl_map(clone_entry, dbs)
  end

  local normalized = {}

  for name, value in pairs(dbs) do
    if type(value) == "string" then
      table.insert(normalized, {
        name = name,
        url = value,
      })
    elseif type(value) == "table" then
      local entry = vim.deepcopy(value)
      entry.name = entry.name or name
      table.insert(normalized, entry)
    end
  end

  table.sort(normalized, function(left, right)
    return (left.name or "") < (right.name or "")
  end)

  return normalized
end

function M.find_project_root(start_path)
  local start = start_path or vim.uv.cwd()
  local apps_dir = vim.fs.find("apps", {
    path = start,
    upward = true,
    type = "directory",
    limit = 1,
  })[1]

  if not apps_dir then
    return nil
  end

  return vim.fs.dirname(apps_dir)
end

function M.scan(root)
  if type(root) ~= "string" or root == "" then
    return {}
  end

  local pattern = to_slash(root) .. "/apps/*/pb_data/data.db"
  local paths = vim.fn.glob(pattern, false, true)
  local dbs = {}

  for _, path in ipairs(paths) do
    local normalized_path = to_slash(path)
    local service = normalized_path:match("/apps/([^/]+)/pb_data/data%.db$")

    if service then
      table.insert(dbs, {
        name = service,
        url = "sqlite:" .. normalized_path,
      })
    end
  end

  table.sort(dbs, function(left, right)
    return left.name < right.name
  end)

  return dbs
end

function M.refresh()
  local root = M.find_project_root()
  local scanned = root and M.scan(root) or {}
  local existing = normalize_dbs(vim.g.dbs)
  local previous_scanned = normalize_dbs(vim.g._dadbod_scanned_dbs)
  local previous_by_key = {}
  local previous_by_url = {}
  local merged = {}
  local used_names = {}
  local used_urls = {}

  for _, entry in ipairs(previous_scanned) do
    previous_by_key[exact_key(entry)] = true

    local url = entry_url(entry)
    if url then
      previous_by_url[url] = true
    end
  end

  for _, entry in ipairs(existing) do
    local url = entry_url(entry)
    local is_previous_scan = previous_by_key[exact_key(entry)] or (url and previous_by_url[url]) or false

    if not is_previous_scan then
      table.insert(merged, clone_entry(entry))

      local name = entry_name(entry)
      if name then
        used_names[name] = true
      end
      if url then
        used_urls[url] = true
      end
    end
  end

  for _, entry in ipairs(scanned) do
    local name = entry.name
    local url = entry.url

    if not used_names[name] and not used_urls[url] then
      table.insert(merged, entry)
      used_names[name] = true
      used_urls[url] = true
    end
  end

  vim.g._dadbod_scanned_dbs = scanned
  vim.g.dbs = merged

  return scanned
end

function M.setup()
  if vim.g._dadbod_sqlite_setup_done == 1 then
    return
  end

  vim.g._dadbod_sqlite_setup_done = 1

  M.refresh()

  local group = vim.api.nvim_create_augroup("DadbodSqliteConnections", { clear = true })

  vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
    group = group,
    callback = function()
      M.refresh()
    end,
  })

  vim.api.nvim_create_user_command("DBUIRefreshConnections", function()
    local scanned = M.refresh()

    vim.notify(
      ("Dadbod SQLite connections refreshed: %d found"):format(#scanned),
      vim.log.levels.INFO,
      { title = "Dadbod" }
    )
  end, {
    desc = "Refresh SQLite connections from apps/*/pb_data/data.db",
  })
end

return M
