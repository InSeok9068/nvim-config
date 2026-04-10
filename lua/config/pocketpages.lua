local M = {}

local pocketpages = require("config.pocketpages_lsp")

local function create_install_command()
  vim.api.nvim_create_user_command("PocketPagesLspInstallDeps", function()
    if vim.fn.executable("npm") ~= 1 then
      vim.notify("npm is required to install PocketPages LSP dependencies.", vim.log.levels.ERROR, {
        title = "PocketPages",
      })
      return
    end

    if not pocketpages.sync_runtime_manifest() then
      vim.notify("Unable to sync PocketPages LSP package manifests.", vim.log.levels.ERROR, {
        title = "PocketPages",
      })
      return
    end

    vim.notify("Installing PocketPages LSP dependencies...", vim.log.levels.INFO, {
      title = "PocketPages",
    })

    vim.system({ "npm", "ci", "--omit=dev" }, { cwd = pocketpages.data_dir(), text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          vim.notify("PocketPages LSP dependencies installed.", vim.log.levels.INFO, {
            title = "PocketPages",
          })
        else
          vim.notify(result.stderr ~= "" and result.stderr or "PocketPages LSP dependency install failed.", vim.log.levels.ERROR, {
            title = "PocketPages",
          })
        end
      end)
    end)
  end, {
    desc = "Install PocketPages LSP dependencies into stdpath('data')",
  })
end

function M.setup()
  if M._did_setup then
    return
  end

  M._did_setup = true

  create_install_command()

  if pocketpages.is_available() then
    vim.lsp.enable("pocketpages")
  end
end

return M
