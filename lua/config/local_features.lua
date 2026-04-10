local M = {}

local feature_modules = {
  "config.window_focus",
  "config.pocketpages_server_boundary",
  "config.tailwind_class_conceal",
}

local function setup_module(module_name)
  local module = require(module_name)

  if type(module.setup) == "function" then
    module.setup()
  end
end

local function register_keymaps()
  vim.keymap.set("n", "<leader>uK", function()
    require("config.tailwind_class_conceal").toggle()
  end, { desc = "Tailwind Class Conceal" })
end

function M.setup()
  if M._did_setup then
    return
  end

  M._did_setup = true

  for _, module_name in ipairs(feature_modules) do
    setup_module(module_name)
  end

  register_keymaps()
end

return M
