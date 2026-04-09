require("config.dadbod_sqlite").setup()

return {
  { import = "lazyvim.plugins.extras.lang.sql" },
  {
    "kristijanhusak/vim-dadbod-completion",
    ft = { "sql", "mysql", "plsql" },
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sql", "mysql", "plsql" },
        callback = function(event)
          vim.bo[event.buf].omnifunc = "vim_dadbod_completion#omni"
        end,
      })
    end,
  },
  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.per_filetype = opts.sources.per_filetype or {}

      for _, filetype in ipairs({ "sql", "mysql", "plsql" }) do
        opts.sources.per_filetype[filetype] = {
          inherit_defaults = false,
          "dadbod",
          "buffer",
        }
      end
    end,
  },
}
