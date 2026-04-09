local pocketpages = require("config.pocketpages_lsp")

return {
  cmd = { "node", pocketpages.server_script(), "--stdio" },
  cmd_env = {
    NVIM_POCKETPAGES_CACHE_DIR = pocketpages.cache_dir(),
    NODE_PATH = pocketpages.node_modules_dir(),
  },
  filetypes = { "ejs", "javascript" },
  root_dir = pocketpages.config_root_dir,
  single_file_support = false,
}
