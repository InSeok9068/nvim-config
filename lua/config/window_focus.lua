local M = {
  highlights = {
    active_cursorline = "WindowFocusActiveCursorLine",
    active_separator = "WindowFocusActiveSeparator",
    inactive_end_of_buffer = "WindowFocusInactiveEndOfBuffer",
    inactive_line_nr = "WindowFocusInactiveLineNr",
    inactive_normal = "WindowFocusInactiveNormal",
    inactive_separator = "WindowFocusInactiveSeparator",
    inactive_sign_column = "WindowFocusInactiveSignColumn",
  },
}

local managed_keys = {
  "CursorLine",
  "EndOfBuffer",
  "LineNr",
  "Normal",
  "NormalNC",
  "SignColumn",
  "WinSeparator",
}

local function is_valid_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  return vim.api.nvim_win_get_config(win).relative == ""
end

local function parse_winhighlight(value)
  local mappings = {}

  for entry in tostring(value or ""):gmatch("[^,]+") do
    local left, right = entry:match("^([^:]+):(.+)$")
    if left and right then
      mappings[left] = right
    end
  end

  return mappings
end

local function build_winhighlight(mappings)
  local items = {}

  for left, right in pairs(mappings) do
    table.insert(items, ("%s:%s"):format(left, right))
  end

  table.sort(items)

  return table.concat(items, ",")
end

local function read_highlight(name)
  local ok, highlight = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok then
    return highlight
  end

  return {}
end

local function split_color(color)
  if type(color) ~= "number" then
    return nil
  end

  local red = math.floor(color / 0x10000) % 0x100
  local green = math.floor(color / 0x100) % 0x100
  local blue = color % 0x100

  return red, green, blue
end

local function compose_color(red, green, blue)
  return red * 0x10000 + green * 0x100 + blue
end

local function blend(from, to, amount)
  local from_red, from_green, from_blue = split_color(from)
  local to_red, to_green, to_blue = split_color(to)

  if not from_red or not to_red then
    return from or to
  end

  local function channel(start_value, end_value)
    return math.floor(start_value + ((end_value - start_value) * amount) + 0.5)
  end

  return compose_color(
    channel(from_red, to_red),
    channel(from_green, to_green),
    channel(from_blue, to_blue)
  )
end

local function luminance(color)
  local red, green, blue = split_color(color)
  if not red then
    return nil
  end

  return ((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)) / 255
end

local function is_dark(color)
  local value = luminance(color)
  if value == nil then
    return true
  end

  return value < 0.5
end

local function accentuate(color, amount)
  if color == nil then
    return nil
  end

  local target = is_dark(color) and 0xFFFFFF or 0x000000
  return blend(color, target, amount)
end

local function recede(color, amount)
  if color == nil then
    return nil
  end

  local target = is_dark(color) and 0x000000 or 0xFFFFFF
  return blend(color, target, amount)
end

local function create_highlights()
  local normal = read_highlight("Normal")
  local normal_nc = read_highlight("NormalNC")
  local cursorline = read_highlight("CursorLine")
  local sign_column = read_highlight("SignColumn")
  local line_nr = read_highlight("LineNr")
  local end_of_buffer = read_highlight("EndOfBuffer")
  local separator = read_highlight("WinSeparator")

  local normal_bg = normal.bg
  local inactive_bg = normal_nc.bg or normal_bg
  local active_cursorline_bg = cursorline.bg or normal_bg
  local separator_fg = separator.fg or normal.fg

  inactive_bg = recede(inactive_bg, 0.08)
  active_cursorline_bg = accentuate(active_cursorline_bg, 0.08)

  vim.api.nvim_set_hl(0, M.highlights.active_cursorline, {
    bg = active_cursorline_bg,
  })

  vim.api.nvim_set_hl(0, M.highlights.active_separator, {
    bold = true,
    fg = accentuate(separator_fg, 0.18),
  })

  vim.api.nvim_set_hl(0, M.highlights.inactive_normal, {
    bg = inactive_bg,
  })

  vim.api.nvim_set_hl(0, M.highlights.inactive_sign_column, {
    bg = inactive_bg,
    fg = sign_column.fg,
  })

  vim.api.nvim_set_hl(0, M.highlights.inactive_end_of_buffer, {
    bg = inactive_bg,
    fg = end_of_buffer.fg,
  })

  vim.api.nvim_set_hl(0, M.highlights.inactive_line_nr, {
    bg = inactive_bg,
    fg = inactive_bg and line_nr.fg and blend(line_nr.fg, inactive_bg, 0.35) or line_nr.fg,
  })

  vim.api.nvim_set_hl(0, M.highlights.inactive_separator, {
    fg = inactive_bg and separator_fg and blend(separator_fg, inactive_bg, 0.25) or separator_fg,
  })
end

local function clear_window(win)
  if not is_valid_window(win) then
    return
  end

  local mappings = parse_winhighlight(vim.wo[win].winhighlight)
  local changed = false

  for _, key in ipairs(managed_keys) do
    local group = mappings[key]
    if group and vim.tbl_contains(vim.tbl_values(M.highlights), group) then
      mappings[key] = nil
      changed = true
    end
  end

  if changed then
    vim.wo[win].winhighlight = build_winhighlight(mappings)
  end
end

local function apply_window(win, mappings_to_apply)
  if not is_valid_window(win) then
    return
  end

  local mappings = parse_winhighlight(vim.wo[win].winhighlight)

  for key, group in pairs(mappings_to_apply) do
    mappings[key] = group
  end

  vim.wo[win].winhighlight = build_winhighlight(mappings)
end

function M.refresh()
  local current = vim.api.nvim_get_current_win()

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_valid_window(win) then
      clear_window(win)

      if win == current then
        apply_window(win, {
          CursorLine = M.highlights.active_cursorline,
          WinSeparator = M.highlights.active_separator,
        })
      else
        apply_window(win, {
          EndOfBuffer = M.highlights.inactive_end_of_buffer,
          LineNr = M.highlights.inactive_line_nr,
          Normal = M.highlights.inactive_normal,
          NormalNC = M.highlights.inactive_normal,
          SignColumn = M.highlights.inactive_sign_column,
          WinSeparator = M.highlights.inactive_separator,
        })
      end
    end
  end
end

function M.setup()
  if M._did_setup then
    return
  end

  M._did_setup = true

  create_highlights()

  local group = vim.api.nvim_create_augroup("window_focus", { clear = true })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "TabEnter", "WinEnter", "VimEnter" }, {
    group = group,
    callback = function()
      M.refresh()
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      create_highlights()
      M.refresh()
    end,
  })
end

return M
