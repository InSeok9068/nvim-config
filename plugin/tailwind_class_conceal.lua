local ok, conceal = pcall(require, "config.tailwind_class_conceal")
if not ok then
  return
end

conceal.setup()

vim.keymap.set("n", "<leader>uK", function()
  conceal.toggle()
end, { desc = "Tailwind Class Conceal" })
