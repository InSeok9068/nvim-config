local ok, window_focus = pcall(require, "config.window_focus")
if not ok then
  return
end

window_focus.setup()
