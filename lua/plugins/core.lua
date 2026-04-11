return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      opts.completion = opts.completion or {}
      opts.completion.ghost_text = opts.completion.ghost_text or {}
      opts.completion.ghost_text.enabled = false
    end,
  },
  {
    "folke/noice.nvim",
    opts = function(_, opts)
      opts.lsp = opts.lsp or {}
      opts.lsp.hover = opts.lsp.hover or {}
      opts.lsp.hover.silent = true
    end,
  },
}
