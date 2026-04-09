local formatter_config_path = vim.fs.normalize(vim.fn.stdpath("config") .. "/tools/prettier-pocketpages.config.mjs")

local function to_slash(path)
  return (path or ""):gsub("\\", "/")
end

local function is_pocketpages_ejs_path(path)
  return to_slash(path):match("/pb_hooks/pages/.+%.ejs$") ~= nil
end

local function find_pocketpages_root(ctx)
  local root = vim.fs.root(ctx.dirname, { ".prettierrc", "tailwind.config.js" })
  if not root then
    return nil
  end

  if vim.fn.filereadable(root .. "/package.json") == 0 then
    return nil
  end

  if vim.fn.isdirectory(root .. "/apps") == 0 then
    return nil
  end

  return root
end

return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.ejs = { "pocketpages_prettier_ejs" }

      opts.formatters = opts.formatters or {}
      opts.formatters.pocketpages_prettier_ejs = {
        inherit = "prettier",
        cwd = function(self, ctx)
          return find_pocketpages_root(ctx)
        end,
        require_cwd = true,
        condition = function(self, ctx)
          return is_pocketpages_ejs_path(ctx.filename) and find_pocketpages_root(ctx) ~= nil
        end,
        append_args = function()
          return {
            "--config",
            formatter_config_path,
          }
        end,
      }
    end,
  },
}
