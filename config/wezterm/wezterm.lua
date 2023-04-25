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
  -- Scrolling up while holding SHIFT scrolls by pages
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
  -- Do not open links on a simple click
  {
    event = { Up = { streak = 1, button = "Left" } },
    action = act.CompleteSelection "ClipboardAndPrimarySelection",
  },
  -- Use CTRL+LClick to select the block
  {
    event = { Down = { streak = 1, button = "Left" } },
    mods = 'CTRL',
    action = act.SelectTextAtMouseCursor "Block",
  },
  {
    event = { Drag = { streak = 1, button = "Left" } },
    mods = 'CTRL',
    action = act.ExtendSelectionToMouseCursor "Block",
  },
  {
    event = { Up = { streak = 1, button = "Left" } },
    mods = 'CTRL',
    action = act.CompleteSelectionOrOpenLinkAtMouseCursor "ClipboardAndPrimarySelection",
  },
}


return config
