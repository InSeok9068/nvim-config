return {
  {
    "nvim-treesitter/nvim-treesitter",
    init = function()
      if vim.fn.has("win32") == 1 then
        local gcc = vim.fn.exepath("gcc")
        local gxx = vim.fn.exepath("g++")

        if gcc ~= "" then
          vim.env.CC = gcc
        end

        if gxx ~= "" then
          vim.env.CXX = gxx
        end

        vim.env.CCACHE_DISABLE = vim.env.CCACHE_DISABLE or "1"
      end

      vim.treesitter.language.register("embedded_template", "ejs")
    end,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}

      if not vim.tbl_contains(opts.ensure_installed, "embedded_template") then
        table.insert(opts.ensure_installed, "embedded_template")
      end
    end,
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}

      if not vim.tbl_contains(opts.ensure_installed, "html-lsp") then
        table.insert(opts.ensure_installed, "html-lsp")
      end
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        html = {
          filetypes = { "html", "ejs" },
          init_options = {
            provideFormatter = true,
            embeddedLanguages = {
              css = true,
              javascript = true,
            },
            configurationSection = { "html", "css", "javascript" },
          },
        },
      },
    },
  },
}
