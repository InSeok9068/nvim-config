local M = {
  enabled = false,
  filetypes = {
    ejs = true,
    html = true,
  },
  patterns = {
    [[class\s*=\s*"\zs[^"]\+\ze"]],
    [[class\s*=\s*'\zs[^']\+\ze']],
  },
  windows = {},
}

local function is_valid_target(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local filetype = vim.bo[buf].filetype

  return M.filetypes[filetype] == true
end

local function win_call(win, fn)
  return vim.api.nvim_win_call(win, fn)
end

function M.clear(win)
  local state = M.windows[win]
  if not state then
    return
  end

  if vim.api.nvim_win_is_valid(win) then
    win_call(win, function()
      for _, id in ipairs(state.match_ids or {}) do
        pcall(vim.fn.matchdelete, id)
      end

      if state.prev_conceallevel ~= nil then
        vim.wo.conceallevel = state.prev_conceallevel
      end

      if state.prev_concealcursor ~= nil then
        vim.wo.concealcursor = state.prev_concealcursor
      end
    end)
  end

  M.windows[win] = nil
end

function M.apply(win)
  if not is_valid_target(win) then
    M.clear(win)
    return
  end

  M.clear(win)

  local state = {}

  win_call(win, function()
    state.prev_conceallevel = vim.wo.conceallevel
    state.prev_concealcursor = vim.wo.concealcursor
    state.match_ids = {}

    vim.wo.conceallevel = math.max(vim.wo.conceallevel, 2)
    vim.wo.concealcursor = "nc"

    for _, pattern in ipairs(M.patterns) do
      local id = vim.fn.matchadd("Conceal", pattern, 10, -1, { conceal = "*" })
      table.insert(state.match_ids, id)
    end
  end)

  M.windows[win] = state
end

function M.refresh(win)
  if M.enabled and is_valid_target(win) then
    M.apply(win)
    return
  end

  M.clear(win)
end

function M.refresh_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    M.refresh(win)
  end
end

function M.toggle()
  M.enabled = not M.enabled
  M.refresh_all()

  vim.notify(
    ("Tailwind class conceal %s"):format(M.enabled and "enabled" or "disabled"),
    vim.log.levels.INFO
  )
end

function M.setup()
  if M._did_setup then
    return
  end

  M._did_setup = true

  local group = vim.api.nvim_create_augroup("tailwind_class_conceal", { clear = true })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType", "WinEnter" }, {
    group = group,
    callback = function()
      M.refresh(vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if win then
        M.clear(win)
      end
    end,
  })
end

return M
