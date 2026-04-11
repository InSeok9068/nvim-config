require("config.window_focus").setup()

local im = "kren-select"
local last = "en"
local group = vim.api.nvim_create_augroup("input_method", { clear = true })

vim.api.nvim_create_autocmd("InsertLeave", {
  group = group,
  callback = function()
    last = vim.fn.system(im):gsub("%s+", "")
    vim.fn.system(im .. " en")
  end,
})

vim.api.nvim_create_autocmd("InsertEnter", {
  group = group,
  callback = function()
    vim.fn.system(im .. " " .. last)
  end,
})
