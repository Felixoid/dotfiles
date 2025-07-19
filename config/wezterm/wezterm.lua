local wezterm = require 'wezterm'
local act = wezterm.action

local config = {}

-- don't check for updates
config.check_for_updates = false

config.automatically_reload_config = true

-- cursor

local xcursor_size = nil
local xcursor_theme = nil

local success, stdout, stderr = wezterm.run_child_process({"gsettings", "get", "org.gnome.desktop.interface", "cursor-theme"})
if success then
  xcursor_theme = stdout:gsub("'(.+)'\n", "%1")
end

local success, stdout, stderr = wezterm.run_child_process({"gsettings", "get", "org.gnome.desktop.interface", "cursor-size"})
if success then
  xcursor_size = tonumber(stdout)
end

config.xcursor_theme = xcursor_theme
config.xcursor_size = xcursor_size

config.color_scheme = 'Tomorrow Night Eighties'

-- The fonts and text

config.text_background_opacity = 0.8


config.font = wezterm.font_with_fallback {
  'Consolas ligaturized v3',
  'Consolas ligaturized v2',
  'Code2000',
  'Symbols Nerd Font Mono',
  'Noto Color Emoji',
}

config.font_size = 13

config.scrollback_lines = 100000

config.selection_word_boundary = " \t\n{}[]()'`|" .. '"'

config.quick_select_patterns = {
  -- Match words that start with a letter or underscore, followed by any number of letters, digits, or underscores
  --"(?<=[^-A-z0-9])[-A-z0-9]+"
  "[-_:.A-Za-z0-9]+",
  -- Match words that start with a digit, followed by any number of digits
}

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

config.keys = {
  {
    key = "r",
    mods = 'CTRL|SHIFT',
    action = act.RotatePanes 'CounterClockwise',
  },
  {
    key = "r",
    mods = 'CTRL|SHIFT|ALT',
    action = act.RotatePanes 'Clockwise',
  },
}

-- Overwrite the hyperlink_rules to address markdown issue
-- see https://github.com/wez/wezterm/issues/3803
-- https://github.com/wez/wezterm/pull/4212
config.hyperlink_rules = {
  -- Matches: a URL in parens: (URL)
  {
    regex = '\\((\\w+://\\S+)\\)',
    format = '$1',
    highlight = 1,
  },
  -- Matches: a URL in brackets: [URL]
  {
    regex = '\\[(\\w+://\\S+)\\]',
    format = '$1',
    highlight = 1,
  },
  -- Matches: a URL in curly braces: {URL}
  {
    regex = '\\{(\\w+://\\S+)\\}',
    format = '$1',
    highlight = 1,
  },
  -- Matches: a URL in angle brackets: <URL>
  {
    regex = '<(\\w+://\\S+)>',
    format = '$1',
    highlight = 1,
  },
  -- Then handle URLs not wrapped in brackets
  {
    -- Before
    --regex = '\\b\\w+://\\S+[)/a-zA-Z0-9-]+',
    --format = '$0',
    -- After
    regex = '[^(]\\b(\\w+://\\S+[)/a-zA-Z0-9-]+)',
    format = '$1',
    highlight = 1,
  },
  -- implicit mailto link
  {
    regex = '\\b\\w+@[\\w-]+(\\.[\\w-]+)+\\b',
    format = 'mailto:$0',
  },
}

return config
