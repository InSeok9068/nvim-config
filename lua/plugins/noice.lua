return {
  {
    "folke/noice.nvim",
    opts = function(_, opts)
      opts.lsp = opts.lsp or {}
      opts.lsp.hover = opts.lsp.hover or {}
      opts.lsp.hover.silent = true
    end,
  },
}
