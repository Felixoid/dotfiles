-- pi-tab-title.lua
-- Colors tag portions of pi's tab title (e.g. "(working)", "(subagents:3)").
-- Pi sets the title as:
--   π (tag)(tag) - <session> - <cwd>
-- Zero or more tags may appear, back to back, right after "π ".
-- Unrecognized tags render without color.

local wezterm = require 'wezterm'

-- Lua pattern -> color, checked in order. Plain tags (no dynamic value) use
-- an exact-match pattern; tags carrying a dynamic value use a wildcard, e.g.
-- "(subagents:3)".
local TAG_RULES = {
  { pattern = '^%(working%)$', color = '#f5a623' },        -- orange: main agent turn is running
  { pattern = '^%(subagents:%d+%)$', color = '#9b59b6' },  -- purple: active subagent runs
}

local function tag_color(tag)
  for _, rule in ipairs(TAG_RULES) do
    if tag:find(rule.pattern) then
      return rule.color
    end
  end
  return nil
end

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local title = (tab.tab_title and #tab.tab_title > 0)
    and tab.tab_title
    or tab.active_pane.title

  local prefix = title:match('^(π )')
  if not prefix then
    return { { Text = ' ' .. title .. ' ' } }
  end

  local rest = title:sub(#prefix + 1)
  local items = { { Text = ' ' .. prefix } }

  while true do
    local tag = rest:match('^(%b())')
    if not tag then
      break
    end
    local color = tag_color(tag)
    if color then
      table.insert(items, { Foreground = { Color = color } })
      table.insert(items, { Text = tag })
      table.insert(items, 'ResetAttributes')
    else
      table.insert(items, { Text = tag })
    end
    rest = rest:sub(#tag + 1)
  end

  table.insert(items, { Text = rest .. ' ' })
  return items
end)
