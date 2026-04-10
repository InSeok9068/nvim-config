local ok, boundary = pcall(require, "config.pocketpages_server_boundary")
if not ok then
  return
end

boundary.setup()
