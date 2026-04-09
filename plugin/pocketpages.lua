local ok, pocketpages = pcall(require, "config.pocketpages_lsp")
if not ok then
  return
end

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

if not pocketpages.is_available() then
  return
end

vim.lsp.enable("pocketpages")
