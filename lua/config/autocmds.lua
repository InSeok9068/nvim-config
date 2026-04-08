-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local im = "kren-select"
local last = "en"

-- Insert 나갈 때
vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function()
    -- 현재 상태 저장 (en / kr)
    last = vim.fn.system(im):gsub("%s+", "")

    -- 영어로 강제
    vim.fn.system(im .. " en")
  end,
})

-- Insert 들어갈 때
vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    -- 이전 상태 복구
    vim.fn.system(im .. " " .. last)
  end,
})
