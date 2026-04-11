return {
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
