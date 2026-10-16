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

local function windowAt(pt)
  -- Accessibility sees the topmost element under the pointer, menus included.
  local el = hs.axuielement.systemElementAtPosition(pt)
  local role = el and el:attributeValue("AXRole")
  if not el or MENU_ROLES[role] then return nil end
  local win = role == "AXWindow" and el or el:attributeValue("AXWindow")
  return win and win:asHSWindow()
end

local GESTURE = { "cmd", "ctrl" }
local function isGesture(e) return e:getFlags():containExactly(GESTURE) end

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
    if e:getType() ~= types.leftMouseDown or isGesture(e) then return false end

    local pt = e:location()
    local focused = hs.window.focusedWindow()
    if focused and hs.geometry.point(pt):inside(focused:frame()) then return false end

    local w = windowAt(pt)
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

-- cmd+ctrl: left drag moves, right drag resizes from the nearest corner, scroll up maximizes, down restores.
local MIN_W, MIN_H = 100, 60
local MOUSE = {
  [types.leftMouseDown] = { "move", "down" },
  [types.leftMouseDragged] = { "move", "drag" },
  [types.leftMouseUp] = { "move", "up" },
  [types.rightMouseDown] = { "resize", "down" },
  [types.rightMouseDragged] = { "resize", "drag" },
  [types.rightMouseUp] = { "resize", "up" },
}
local gesture, pendingOp = nil, nil

-- AX calls are slow; run them outside the tap so macOS doesn't disable it, keeping only the latest frame.
local function schedule(op)
  local idle = pendingOp == nil
  pendingOp = op
  if idle then
    gestureTimer = hs.timer.doAfter(0, function()
      local run = pendingOp
      pendingOp = nil
      run()
    end)
  end
end

local function gestureWindow(pt)
  local w = windowAt(pt)
  if w and w:isStandard() and not w:isFullScreen() then return w end
end

gestureMouse = hs.eventtap.new(
  { types.leftMouseDown, types.leftMouseDragged, types.leftMouseUp,
    types.rightMouseDown, types.rightMouseDragged, types.rightMouseUp },
  function(e)
    if e:getProperty(props.eventSourceUserData) == MARK then return false end
    local mode, phase = table.unpack(MOUSE[e:getType()])
    local pt = e:location()
    if phase == "down" then
      if not isGesture(e) then return false end
      local w = gestureWindow(pt)
      if not w then return false end
      local f = w:frame()
      gesture = { mode = mode, w = w, f = f, p = pt,
        left = pt.x < f.x + f.w / 2, top = pt.y < f.y + f.h / 2 }
      return true
    end
    if not gesture or gesture.mode ~= mode then return false end
    local g = gesture
    local dx, dy = pt.x - g.p.x, pt.y - g.p.y
    if mode == "move" then
      schedule(function() g.w:setTopLeft({ x = g.f.x + dx, y = g.f.y + dy }) end)
    else
      local f = g.f
      local x, y, w, h = f.x, f.y, f.w, f.h
      if g.left then w = math.max(MIN_W, f.w - dx); x = f.x + f.w - w
      else w = math.max(MIN_W, f.w + dx) end
      if g.top then h = math.max(MIN_H, f.h - dy); y = f.y + f.h - h
      else h = math.max(MIN_H, f.h + dy) end
      schedule(function() g.w:setFrame({ x = x, y = y, w = w, h = h }, 0) end)
    end
    if phase == "up" then gesture = nil end
    return true
  end
)
gestureMouse:start()

local savedFrames = {}
local function zoom(up)
  local w = gestureWindow(hs.mouse.absolutePosition())
  if not w then return end
  local id = w:id()
  if up then
    savedFrames[id] = savedFrames[id] or w:frame()
    w:maximize(0)
  elseif savedFrames[id] then
    w:setFrame(savedFrames[id], 0)
    savedFrames[id] = nil
  end
end

-- A trackpad swipe or a fast wheel spin sends many events; act once per gesture.
local ownScroll, scrollFired, lastWheel = false, false, 0
gestureScroll = hs.eventtap.new({ types.scrollWheel }, function(e)
  if e:getProperty(props.scrollWheelEventMomentumPhase) ~= 0 then return ownScroll end
  local phase = e:getProperty(props.scrollWheelEventScrollPhase)
  if phase == 1 then ownScroll, scrollFired = isGesture(e), false end
  if phase == 0 and not isGesture(e) then return false end
  if phase ~= 0 and not ownScroll then return false end

  local dy = e:getProperty(props.scrollWheelEventPointDeltaAxis1)
  local dx = e:getProperty(props.scrollWheelEventPointDeltaAxis2)
  local now = hs.timer.secondsSinceEpoch()
  local ready
  if phase == 0 then
    ready = now - lastWheel > 0.3
    lastWheel = now
  else
    ready = not scrollFired
  end
  if ready and dy ~= 0 and math.abs(dy) >= math.abs(dx) then
    scrollFired = true
    schedule(function() zoom(dy > 0) end)
  end
  return true
end)
gestureScroll:start()

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
