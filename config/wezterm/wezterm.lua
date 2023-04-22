local wezterm = require 'wezterm'
local act = wezterm.action

local config = {}

config.color_scheme = 'Tomorrow Night Eighties'

config.text_background_opacity = 0.8


config.font = wezterm.font_with_fallback {
  'Consolas ligaturized v2',
  'Code2000',
}

config.font_size = 13

config.mouse_bindings = {
  -- Scrolling up while holding CTRL increases the font size
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'SHIFT',
    action = act.ScrollByPage(-1),
  },
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'SHIFT',
    action = act.ScrollByPage(1),
  },
}


return config
