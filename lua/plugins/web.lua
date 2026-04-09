local custom_data_path = vim.fn.stdpath("config") .. "/html-custom-data.json"

local function read_custom_data(_, path)
  local file = path

  if type(file) == "table" then
    file = file[1]
  end

  if type(file) ~= "string" or file == "" then
    return ""
  end

  if file:match("^file://") then
    file = vim.uri_to_fname(file)
  end

  local lines = vim.fn.readfile(file)
  if vim.v.shell_error ~= 0 then
    return ""
  end

  return table.concat(lines, "\n")
end

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}

      local tools = {
        "html-lsp",
      }

      if vim.fn.executable("cargo") == 1 or vim.fn.executable("htmx-lsp") == 1 then
        table.insert(tools, "htmx-lsp")
      end

      for _, tool in ipairs(tools) do
        if not vim.tbl_contains(opts.ensure_installed, tool) then
          table.insert(opts.ensure_installed, tool)
        end
      end
    end,
  },
  {
    "neovim/nvim-lspconfig",
    init = function()
      vim.lsp.handlers["html/customDataContent"] = read_custom_data
    end,
    opts = {
      servers = {
        html = {
          filetypes = { "html", "ejs" },
          handlers = {
            ["html/customDataContent"] = read_custom_data,
          },
          init_options = {
            provideFormatter = true,
            embeddedLanguages = {
              css = true,
              javascript = true,
            },
            configurationSection = { "html", "css", "javascript" },
            dataPaths = { custom_data_path },
          },
        },
        htmx = {
          enabled = vim.fn.executable("htmx-lsp") == 1 or vim.fn.executable("cargo") == 1,
          mason = vim.fn.executable("cargo") == 1,
        },
      },
    },
  },
}
