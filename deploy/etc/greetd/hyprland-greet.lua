-- Minimal Hyprland config for the greetd greeter session.
hl.config({
  misc = {
    disable_watchdog_warning = true,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },
})

hl.monitor({
  output = " ",
  mode = "preferred",
  position = "auto",
  scale = 1,
})
hl.on("hyprland.start", function()
  hl.exec_cmd("qs -p /etc/greetd/quickshell-greeter")
end)
