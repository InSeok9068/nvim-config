local M = {
  enabled = true,
  filetypes = {
    ejs = true,
  },
  highlight = "PocketPagesServerBoundary",
  separator_width = 512,
}

M.ns = vim.api.nvim_create_namespace("pocketpages_server_boundary")

local function normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function trim(text)
  return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

local function get_pocketpages()
  local ok, pocketpages = pcall(require, "config.pocketpages_lsp")
  if not ok then
    return nil
  end

  return pocketpages
end

local function is_private_partial(path)
  local normalized = normalize_path(path)
  return normalized:match("/pb_hooks/pages/_private/") ~= nil and normalized:match("%.ejs$") ~= nil
end

local function is_target_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  if vim.bo[buf].buftype ~= "" or M.filetypes[vim.bo[buf].filetype] ~= true then
    return false
  end

  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or not name:match("%.ejs$") then
    return false
  end

  local pocketpages = get_pocketpages()
  return pocketpages ~= nil and pocketpages.root_dir(name) ~= nil
end

local function get_document_lines(text)
  local lines = {}

  if text == "" then
    return { "" }
  end

  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end

    table.insert(lines, line)
  end

  return #lines > 0 and lines or { "" }
end

local function get_line_index_at_offset(text, offset)
  local line_index = 0
  local safe_offset = math.max(0, math.min(tonumber(offset) or 0, #text))

  for index = 1, safe_offset do
    if text:byte(index) == 10 then
      line_index = line_index + 1
    end
  end

  return line_index
end

local function is_server_script_line(trimmed_line)
  local lower = tostring(trimmed_line or ""):lower()
  return lower:match("^<script[%s>]") ~= nil and lower:match("%f[%a]server%f[%A]") ~= nil
end

local function extract_server_blocks(text)
  local blocks = {}
  local source_text = tostring(text or "")
  local lower_text = source_text:lower()
  local search_from = 1

  while true do
    local script_start = lower_text:find("<script", search_from, true)
    if not script_start then
      break
    end

    local tag_end = lower_text:find(">", script_start, true)
    if not tag_end then
      break
    end

    local open_tag = lower_text:sub(script_start, tag_end)
    local close_start, close_end = lower_text:find("</script>", tag_end + 1, true)
    if not close_start then
      break
    end

    if open_tag:match("^<script[%s>]") ~= nil and open_tag:match("%f[%a]server%f[%A]") ~= nil then
      table.insert(blocks, {
        index = #blocks,
        full_start = script_start - 1,
        full_end = close_end,
      })
    end

    search_from = close_end + 1
  end

  return blocks
end

local function find_first_top_level_scriptlet_end_offset(text)
  local source_text = tostring(text or "")
  local first_non_whitespace = source_text:find("%S")
  if not first_non_whitespace then
    return -1
  end

  if source_text:sub(first_non_whitespace, first_non_whitespace + 1) ~= "<%" then
    return -1
  end

  local open_tag_suffix = source_text:sub(first_non_whitespace + 2, first_non_whitespace + 2)
  if open_tag_suffix == "=" or open_tag_suffix == "-" or open_tag_suffix == "#" then
    return -1
  end

  local close_tag_start = source_text:find("%%>", first_non_whitespace + 2)
  if not close_tag_start then
    return -1
  end

  return close_tag_start + 1
end

local function get_next_template_line_index(text, start_offset)
  local source_text = tostring(text or "")
  local lines = get_document_lines(source_text)
  local block_end_line_index = get_line_index_at_offset(source_text, start_offset)

  for line_number = block_end_line_index + 2, #lines do
    local trimmed_line = trim(lines[line_number])
    if trimmed_line ~= "" then
      if is_server_script_line(trimmed_line) then
        return nil
      end

      return line_number - 1
    end
  end

  return nil
end

local function get_boundary_line_numbers(text, opts)
  local source_text = tostring(text or "")
  local options = opts or {}
  local seen = {}
  local boundary_line_numbers = {}

  for _, block in ipairs(extract_server_blocks(source_text)) do
    local next_template_line_index = get_next_template_line_index(source_text, block.full_end)
    if type(next_template_line_index) == "number" and not seen[next_template_line_index] then
      seen[next_template_line_index] = true
      table.insert(boundary_line_numbers, next_template_line_index)
    end
  end

  if options.include_top_level_partial_setup then
    local first_top_level_scriptlet_end_offset = find_first_top_level_scriptlet_end_offset(source_text)
    if first_top_level_scriptlet_end_offset ~= -1 then
      local next_template_line_index = get_next_template_line_index(source_text, first_top_level_scriptlet_end_offset)
      if type(next_template_line_index) == "number" and not seen[next_template_line_index] then
        seen[next_template_line_index] = true
        table.insert(boundary_line_numbers, next_template_line_index)
      end
    end
  end

  table.sort(boundary_line_numbers)
  return boundary_line_numbers
end

function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  end
end

local function get_separator()
  return string.rep("─", M.separator_width)
end

local function ensure_highlight()
  vim.api.nvim_set_hl(0, M.highlight, { default = true, link = "Comment" })
end

function M.refresh(buf)
  if not M.enabled or not is_target_buffer(buf) then
    M.clear(buf)
    return
  end

  ensure_highlight()
  M.clear(buf)

  local name = vim.api.nvim_buf_get_name(buf)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local boundary_line_numbers = get_boundary_line_numbers(text, {
    include_top_level_partial_setup = is_private_partial(name),
  })

  for _, line_index in ipairs(boundary_line_numbers) do
    vim.api.nvim_buf_set_extmark(buf, M.ns, line_index, 0, {
      virt_lines = {
        {
          { get_separator(), M.highlight },
        },
      },
      virt_lines_above = true,
      virt_lines_leftcol = true,
      hl_mode = "combine",
      priority = 20,
    })
  end
end

function M.setup()
  if M._did_setup then
    return
  end

  M._did_setup = true
  ensure_highlight()

  local group = vim.api.nvim_create_augroup("pocketpages_server_boundary", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType", "InsertLeave", "TextChanged", "BufWritePost" }, {
    group = group,
    callback = function(args)
      M.refresh(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      ensure_highlight()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          M.refresh(buf)
        end
      end
    end,
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.refresh(buf)
    end
  end
end

M.get_boundary_line_numbers = get_boundary_line_numbers

return M
