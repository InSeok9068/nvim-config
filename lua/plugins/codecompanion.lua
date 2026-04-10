return {
  {
    "olimorris/codecompanion.nvim",
    version = "v18.3.2",
    cmd = {
      "CodeCompanion",
      "CodeCompanionActions",
      "CodeCompanionChat",
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      {
        "<leader>ac",
        "<cmd>CodeCompanionChat Toggle<cr>",
        mode = { "n", "v" },
        desc = "OpenCode Chat",
      },
      {
        "<leader>aa",
        "<cmd>CodeCompanionActions<cr>",
        mode = { "n", "v" },
        desc = "AI Actions",
      },
    },
    opts = {
      adapters = {
        acp = {
          opencode = function()
            local command = vim.fn.has("win32") == 1 and "opencode.cmd" or "opencode"

            return require("codecompanion.adapters").extend("opencode", {
              commands = {
                default = {
                  command,
                  "acp",
                },
              },
            })
          end,
        },
      },
      interactions = {
        chat = {
          adapter = "opencode",
        },
      },
      display = {
        chat = {
          window = {
            layout = "vertical",
            position = "right",
            width = 0.3,
          },
        },
      },
    },
  },
}
