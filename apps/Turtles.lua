requireInjector(getfenv(1))

local Config   = require('config')
local Event    = require('event')
local itemDB   = require('itemDB')
local Socket   = require('socket')
local Terminal = require('terminal')
local UI       = require('ui')
local Util     = require('util')

multishell.setTitle(multishell.getCurrent(), 'Turtles')
UI.Button.defaults.focusIndicator = ' '
UI:configure('Turtles', ...)

local config = { }
Config.load('Turtles', config)

local options = {
  turtle      = { arg = 'i', type = 'number', value = config.id or -1,
                 desc = 'Turtle ID' },
  tab         = { arg = 's', type = 'string', value = config.tab or 'Sel',
                 desc = 'Selected tab to display' },
  help        = { arg = 'h', type = 'flag',   value = false,
                 desc = 'Displays the options' },
}

local SCRIPTS_PATH = 'usr/etc/scripts'

local nullTerm = Terminal.getNullTerm(term.current())
local turtles = { }
local socket
local policies = { 
  { label = 'none' },
  { label = 'digOnly' },
  { label = 'attackOnly' },
  { label = 'digAttack' },
  { label = 'turtleSafe' },
}

local page = UI.Page {
--[[
  policy = UI.Chooser {
    x = 2, y = 8,
    choices = {
      { name = ' None ', value = 'none'       },
      { name = ' Safe ', value = 'turtleSafe' },
    },
  },
]]
  coords = UI.Window {
    x = 2, y = 2, height = 3, rex = -2,
  },
  tabs = UI.Tabs {
    x = 1, y = 5, rey = -2,
    scripts = UI.Grid {
      tabTitle = 'Run',
      backgroundColor = UI.TabBar.defaults.selectedBackgroundColor,
      columns = {
        { heading = '', key = 'label' },
      },
      disableHeader = true,
      sortColumn = 'label',
      autospace = true,
    },
    turtles = UI.Grid {
      tabTitle = 'Sel',
      backgroundColor = UI.TabBar.defaults.selectedBackgroundColor,
      columns = {
        { heading = 'label',  key = 'label'    },
        { heading = 'Dist',   key = 'distance' },
        { heading = 'Status', key = 'status'   },
        { heading = 'Fuel',   key = 'fuel'     },
      },
      disableHeader = true,
      sortColumn = 'label',
      autospace = true,
    },
    inventory = UI.Grid {
      backgroundColor = UI.TabBar.defaults.selectedBackgroundColor,
      tabTitle = 'Inv',
      columns = {
        { heading = '',          key = 'index', width = 2 },
        { heading = '',          key = 'qty', width = 2 },
        { heading = 'Inventory', key = 'id',  width = UI.term.width - 7 },
      },
      disableHeader = true,
      sortColumn = 'index',
    },
    policy = UI.Grid {
      tabTitle = 'Mod',
      backgroundColor = UI.TabBar.defaults.selectedBackgroundColor,
      columns = {
        { heading = 'label', key = 'label' },
      },
      values = policies,
      disableHeader = true,
      sortColumn = 'label',
      autospace = true,
    },
    action = UI.Window {
      tabTitle = 'Act',
      moveUp = UI.Button {
        x = 5, y = 2,
        text = '/\\',
        fn = 'turtle.up',
      },
      moveDown = UI.Button {
        x = 5, y = 4,
        text = '\\/',
        fn = 'turtle.down',
      },
      moveForward = UI.Button {
        x = 9, y = 3,
        text = '>',
        fn = 'turtle.forward',
      },
      moveBack = UI.Button {
        x = 2, y = 3,
        text = '<',
        fn = 'turtle.back',
      },
      turnLeft = UI.Button {
        x = 2, y = 6,
        text = '<-',
        fn = 'turtle.turnLeft',
      },
      turnRight = UI.Button {
        x = 8, y = 6,
        text = '->',
        fn = 'turtle.turnRight',
      },
    },
  },
  statusBar = UI.StatusBar(),
  notification = UI.Notification(),
  accelerators = {
    q = 'quit',
  },
}

function page:enable(turtle)
  self.turtle = turtle
  UI.Page.enable(self)
end

function page:runFunction(script, nowrap)
  for i = 1, 2 do
    if not socket then
      socket = Socket.connect(self.turtle.id, 161)
    end

    if socket then
      if not nowrap then
        script = 'turtle.run(' .. script .. ')'
      end
      if socket:write({ type = 'script', args = script }) then
        return true
      end
    end
    socket = nil
  end
  self.notification:error('Unable to connect')
end

function page:runScript(scriptName)
  if self.turtle then
    self.notification:info('Connecting')
    self:sync()

    local cmd = string.format('Script %d %s', self.turtle.id, scriptName)
    local ot = term.redirect(nullTerm)
    pcall(function() shell.run(cmd) end)
    term.redirect(ot)
    self.notification:success('Sent')
  end
end

function page.coords:draw()
  local t = self.parent.turtle
  if t then
    self:clear()
    self:setCursorPos(1, 1)
    local ind = 'GPS'
    if not t.point.gps then
      ind = 'REL'
    end
    self:print(string.format('%s : %d,%d,%d\nFuel: %s\n', 
      ind, t.point.x, t.point.y, t.point.z, Util.toBytes(t.fuel)))
  end
end

--[[ Inventory Tab ]]--
function page.tabs.inventory:getRowTextColor(row, selected)
  if page.turtle and row.selected then
    return colors.yellow
  end
  return UI.Grid.getRowTextColor(self, row, selected)
end

function page.tabs.inventory:draw()
  local t = page.turtle
  Util.clear(self.values)
  if t then
    for _,v in ipairs(t.inventory) do
      if v.qty > 0 then
        table.insert(self.values, v)
        if v.index == t.slotIndex then
          v.selected = true
        end
        if v.id then
--          local item = itemDB:get({ v.id, v.dmg })
--          if item then
--            v.id = item.displayName
--          else
--            v.id = v.id:gsub('.*:(.*)', '%1')
--          end
          v.id = itemDB:getName(v)
        end
      end
    end
  end
  self:adjustWidth()
  self:update()
  UI.Grid.draw(self)
end

function page.tabs.inventory:eventHandler(event)
  if event.type == 'grid_select' then
    local fn = string.format('turtle.select(%d)', event.selected.index)
    page:runFunction(fn)
  else
    return UI.Grid.eventHandler(self, event)
  end
  return true
end

function page.tabs.scripts:draw()

  Util.clear(self.values)
  local files = fs.list(SCRIPTS_PATH)
  for _,path in pairs(files) do
    table.insert(self.values, { label = path, path = fs.combine(SCRIPTS_PATH, path) })
  end
  self:update()
  UI.Grid.draw(self)
end

function page.tabs.scripts:eventHandler(event)
  if event.type == 'grid_select' then
    page:runScript(event.selected.label)
  else
    return UI.Grid.eventHandler(self, event)
  end
  return true
end

function page.tabs.turtles:getDisplayValues(row)
  row = Util.shallowCopy(row)
  if row.fuel then
    row.fuel = Util.toBytes(row.fuel)
  end
  if row.distance then
    row.distance = Util.round(row.distance, 1)
  end
  return row
end

function page.tabs.turtles:draw()
  Util.clear(self.values)
  for _,v in pairs(network) do
    if v.fuel then
      table.insert(self.values, v)
    end
  end
  self:update()
  UI.Grid.draw(self)
end

function page.tabs.turtles:eventHandler(event)
  if event.type == 'grid_select' then
    page.turtle = event.selected
    config.id = event.selected.id
    Config.update('Turtles', config)
    multishell.setTitle(multishell.getCurrent(), page.turtle.label)
    if socket then
      socket:close()
      socket = nil
    end
  else
    return UI.Grid.eventHandler(self, event)
  end
  return true
end

function page.statusBar:draw()
  local t = self.parent.turtle
  if t then
    local status = string.format('%s [ %s ]', t.status, Util.round(t.distance, 2))
    self:setStatus(status, true)
  end
  UI.StatusBar.draw(self)
end

function page.tabs.tabBar:selectTab(tabTitle)
  if tabTitle then
    config.tab = tabTitle
    Config.update('Turtles', config)
    return UI.TabBar.selectTab(self, tab)
  end
end

function page:eventHandler(event)
  if event.type == 'quit' then
    UI:exitPullEvents()
  elseif event.type == 'button_press' then
    if event.button.fn then
      self:runFunction(event.button.fn, event.button.nowrap)
    elseif event.button.script then
      self:runScript(event.button.script)
    end
  else
    return UI.Page.eventHandler(self, event)
  end
  return true
end

function page:enable()
  UI.Page.enable(self)
--  self.tabs:activateTab(page.tabs.turtles)
end

if not Util.getOptions(options, { ... }, true) then
  return
end

if options.turtle.value >= 0 then
  for i = 1, 10 do
    page.turtle = _G.network[options.turtle.value]
    if page.turtle then
      break
    end
    os.sleep(1)
  end
end

Event.onInterval(1, function()
  if page.turtle then
    local t = _G.network[page.turtle.id]
    page.turtle = t
    page:draw()
    page:sync()
  end
end)

UI:setPage(page)

local lookup = {
  Run = page.tabs.scripts,
  Sel = page.tabs.turtles,
  Inv = page.tabs.inventory,
  Mod = page.tabs.policy,
  Act = page.tabs.action,
}

if lookup[options.tab.value] then
  page.tabs:activateTab(lookup[options.tab.value])
end

UI:pullEvents()
