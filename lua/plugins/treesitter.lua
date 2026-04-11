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
    end,
  },
}
