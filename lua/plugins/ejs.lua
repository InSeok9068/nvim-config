return {
  {
    "nvim-treesitter/nvim-treesitter",
    init = function()
      vim.treesitter.language.register("embedded_template", "ejs")
    end,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}

      if not vim.tbl_contains(opts.ensure_installed, "embedded_template") then
        table.insert(opts.ensure_installed, "embedded_template")
      end
    end,
  },
}
