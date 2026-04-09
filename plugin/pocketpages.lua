local ok, pocketpages = pcall(require, "config.pocketpages_lsp")
if not ok or not pocketpages.is_available() then
  return
end

vim.lsp.enable("pocketpages")
