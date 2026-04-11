local M = {}

local feature_modules = {
  "config.window_focus",
}

local function setup_module(module_name)
  local module = require(module_name)

  if type(module.setup) == "function" then
    module.setup()
  end
end

function M.setup()
  if M._did_setup then
    return
  end

  M._did_setup = true

  for _, module_name in ipairs(feature_modules) do
    setup_module(module_name)
  end
end

return M
