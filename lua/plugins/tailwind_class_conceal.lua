return {
  {
    "folke/snacks.nvim",
    init = function()
      require("config.tailwind_class_conceal").setup()
    end,
    keys = {
      {
        "<leader>uK",
        function()
          require("config.tailwind_class_conceal").toggle()
        end,
        desc = "Tailwind Class Conceal",
      },
    },
  },
}
