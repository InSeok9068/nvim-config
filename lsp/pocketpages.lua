local pocketpages = require("config.pocketpages_lsp")

return {
  cmd = { "node", pocketpages.server_script(), "--stdio" },
  filetypes = { "ejs", "javascript" },
  root_dir = pocketpages.config_root_dir,
  single_file_support = false,
}
