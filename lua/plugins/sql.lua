local sql_ft = { "sql", "mysql", "plsql" }

return {
  {
    "tpope/vim-dadbod",
    optional = true,
    init = function()
      -- Disable Neovim's default SQL maps early so they don't clash with dadbod completion.
      vim.g.omni_sql_no_default_maps = 1
      require("config.dadbod_sqlite").setup()
    end,
  },
  {
    "kristijanhusak/vim-dadbod-completion",
    ft = sql_ft,
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = sql_ft,
        callback = function(event)
          vim.bo[event.buf].omnifunc = "vim_dadbod_completion#omni"
        end,
      })
    end,
  },
  {
    "saghen/blink.cmp",
    optional = true,
    dependencies = { "kristijanhusak/vim-dadbod-completion" },
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.default = vim.tbl_filter(function(source)
        return source ~= "dadbod"
      end, opts.sources.default or {})
      opts.sources.per_filetype = opts.sources.per_filetype or {}
      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.dadbod = {
        name = "Dadbod",
        module = "vim_dadbod_completion.blink",
      }

      for _, filetype in ipairs(sql_ft) do
        opts.sources.per_filetype[filetype] = {
          inherit_defaults = false,
          "snippets",
          "dadbod",
          "buffer",
        }
      end
    end,
  },
}
