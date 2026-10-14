hs.hotkey.bind({"alt"}, "f4", function()
  local w = hs.window.focusedWindow()
  if w then w:close() end
end)

require("hs.ipc")

-- Make the first click on an inactive window act as a real click.
local MARK = 0x436C6B54
local props = hs.eventtap.event.properties
local types = hs.eventtap.event.types
local MENU_ROLES = { AXMenu = true, AXMenuItem = true, AXMenuBar = true, AXMenuBarItem = true }
local pending, live = nil, false

-- Copies keep routing data from when the app was inactive, and Cocoa apps drop them.
local function forward(old)
  local mods = {}
  for k, v in pairs(old:getFlags()) do
    if v then table.insert(mods, k) end
  end
  local ev = hs.eventtap.event.newMouseEvent(old:getType(), old:location(), mods)
  ev:setProperty(props.mouseEventClickState, 1)
  ev:setProperty(props.eventSourceUserData, MARK)
  ev:post()
end

-- Activation raises the app's last key window, so make ours the focused one first.
local function focusOnly(w)
  local axApp = hs.axuielement.applicationElement(w:application())
  local axWin = hs.axuielement.windowElement(w)
  axApp:setAttributeValue("AXFocusedWindow", axWin)
  w:focus()
end

clickThrough = hs.eventtap.new(
  { types.leftMouseDown, types.leftMouseDragged, types.leftMouseUp },
  function(e)
    if e:getProperty(props.eventSourceUserData) == MARK then return false end
    if pending then
      -- Once replay starts, forward real events too, so mouseUp can't overtake the replayed mouseDown.
      if live then
        forward(e)
        if e:getType() == types.leftMouseUp then pending, live = nil, false end
      else
        table.insert(pending, e:copy())
      end
      return true
    end
    if e:getType() ~= types.leftMouseDown then return false end

    local pt = e:location()
    local focused = hs.window.focusedWindow()
    if focused and hs.geometry.point(pt):inside(focused:frame()) then return false end

    -- Accessibility sees the topmost element under the pointer, menus included.
    local el = hs.axuielement.systemElementAtPosition(pt)
    local role = el and el:attributeValue("AXRole")
    local w = nil
    if el and not MENU_ROLES[role] then
      local win = role == "AXWindow" and el or el:attributeValue("AXWindow")
      w = win and win:asHSWindow()
    end
    if not w or not w:isStandard() then return false end
    -- Activating Hammerspoon from itself raises its last key window too.
    if w:application():pid() == hs.processInfo.processID then return false end
    if focused and w:id() == focused:id() then return false end

    pending = { e:copy() }
    focusOnly(w)
    local started = hs.timer.secondsSinceEpoch()
    local function replay()
      local q = pending
      local released = false
      for _, old in ipairs(q) do
        forward(old)
        if old:getType() == types.leftMouseUp then released = true end
      end
      if released then pending = nil else live = true end
    end
    -- Apps like Firefox drop clicks that arrive before they finish activating.
    local refocus = 3
    local function hasFocus()
      local f = hs.window.focusedWindow()
      return f and f:id() == w:id(), f
    end
    local function timedOut()
      return hs.timer.secondsSinceEpoch() - started > 1
    end
    local waitFocus
    -- Focus can flip to another window of the same app once activation finishes.
    local function settle()
      if hasFocus() or timedOut() then replay() else waitFocus() end
    end
    waitFocus = function()
      local ok, f = hasFocus()
      if ok or timedOut() then
        replayTimer = hs.timer.doAfter(0.05, settle)
      else
        if f and refocus > 0 and f:application():pid() == w:application():pid() then
          refocus = refocus - 1
          focusOnly(w)
        end
        replayTimer = hs.timer.doAfter(0.01, waitFocus)
      end
    end
    waitFocus()
    return true
  end
)
clickThrough:start()

-- Slack has no macOS menu bar icon; mirror its Dock badge instead.
local SLACK = "com.tinyspeck.slackmacgap"
local function slackApp() return hs.application.get(SLACK) end

local slackIcon = hs.image.imageFromAppBundle(SLACK):setSize({ w = 18, h = 18 })
slackBar = nil

-- A menubar item with a menu never fires its click callback, so right click gets a separate popup.
slackMenu = hs.menubar.new(false):setMenu(function()
  return {
    { title = "Open Slack", fn = function() hs.application.launchOrFocusByBundleID(SLACK) end },
    { title = "-" },
    { title = "Quit Slack", fn = function() local a = slackApp() if a then a:kill() end end },
  }
end)

slackRightClick = hs.eventtap.new({ hs.eventtap.event.types.rightMouseDown }, function(e)
  local f = slackBar and slackBar:frame()
  if not f or not hs.geometry.point(e:location()):inside(f) then return false end
  hs.timer.doAfter(0, function() slackMenu:popupMenu({ x = f.x, y = f.y + f.h }) end)
  return true
end)
slackRightClick:start()

-- returnToMenuBar() drops the icon, so recreate the item instead of hiding it.
local function updateSlack(running)
  if running == nil then running = slackApp() ~= nil end
  if not running then
    if slackBar then slackBar:delete() slackBar = nil end
    return
  end
  if not slackBar then
    -- A fixed autosave name lets macOS and Ice keep the position across recreations.
    slackBar = hs.menubar.new(true, "SlackBadge"):setIcon(slackIcon, false)
    slackBar:setClickCallback(function() hs.application.launchOrFocusByBundleID(SLACK) end)
  end
  local out = hs.execute([[lsappinfo info -only StatusLabel "Slack"]])
  local label = out:match('"label"="([^"]*)"')
  slackBar:setTitle(label ~= "" and label or nil)
end

slackWatcher = hs.application.watcher.new(function(_, event, app)
  if app and app:bundleID() == SLACK then
    if event == hs.application.watcher.launched then updateSlack(true)
    elseif event == hs.application.watcher.terminated then updateSlack(false) end
  end
end)
slackWatcher:start()

slackTimer = hs.timer.doEvery(5, function() updateSlack() end)
updateSlack()
