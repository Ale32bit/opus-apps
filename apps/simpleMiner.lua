requireInjector(getfenv(1))

local Logger  = require('logger')
local Pathing = require('turtle.pathfind')
local Point   = require('point')
local Util    = require('util')

if device and device.wireless_modem then
  Logger.setWirelessLogging()
end

local args = { ... }
local options = {
  chunks      = { arg = 'c', type = 'number', value = -1,
                 desc = 'Number of chunks to mine' },
  depth       = { arg = 'd', type = 'number', value = 9000,
                 desc = 'Mining depth' },
--  enderChest = { arg = 'e', type = 'flag',   value = false,
--                 desc = 'Use ender chest' },
  resume      = { arg = 'r', type = 'flag',   value = false,
                 desc = 'Resume mining' },
  fortunePick = { arg = 'p', type = 'string', value = nil,
                 desc = 'Pick to use with CCTweaks toolhost' },
  setTrash    = { arg = 's', type = 'flag',   value = false,
                 desc = 'Set trash items' },
  help        = { arg = 'h', type = 'flag',   value = false,
                 desc = 'Displays the options' },
}

local fortuneBlocks = {
  [ 'minecraft:redstone_ore' ] = true,
  [ 'minecraft:lapis_ore'    ] = true,
  [ 'minecraft:coal_ore'     ] = true,
  [ 'minecraft:diamond_ore'  ] = true,
  [ 'minecraft:emerald_ore'  ] = true,
}

local MIN_FUEL = 7500
local LOW_FUEL = 1500
local MAX_FUEL = 100000

local PROGRESS_FILE = 'usr/config/mining.progress'
local TRASH_FILE    = 'usr/config/mining.trash'

if not term.isColor() then
  MAX_FUEL = 20000
end

local mining = {
  diameter = 1,
  chunkIndex = 0,
  chunks = -1,
}

local trash
local boreDirection

function getChunkCoordinates(diameter, index, x, z)
  local dirs = { -- circumference of grid
    { xd =  0, zd =  1, heading = 1 }, -- south
    { xd = -1, zd =  0, heading = 2 },
    { xd =  0, zd = -1, heading = 3 },
    { xd =  1, zd =  0, heading = 0 }  -- east
  }
  -- always move east when entering the next diameter
  if index == 0 then
    dirs[4].x = x + 16
    dirs[4].z = z
    return dirs[4]
  end
  dir = dirs[math.floor(index / (diameter - 1)) + 1]
  dir.x = x + dir.xd * 16
  dir.z = z + dir.zd * 16
  return dir
end

function getBoreLocations(x, z)

  local locations = {}

  while true do
    local a = math.abs(z)
    local b = math.abs(x)

    if x > 0 and z > 0 or
       x < 0 and z < 0 then
       -- rotate coords
       a = math.abs(x)
       b = math.abs(z)
    end
    if (a % 5 == 0 and b % 5 == 0) or
       (a % 5 == 2 and b % 5 == 1) or
       (a % 5 == 4 and b % 5 == 2) or
       (a % 5 == 1 and b % 5 == 3) or
       (a % 5 == 3 and b % 5 == 4) then
       table.insert(locations, { x = x, z = z, y = 0 })
    end
    if z % 2 == 0 then -- forward dir
      if (x + 1) % 16 == 0 then
        z = z + 1
      else
        x = x + 1
      end
    else
      if (x - 1) % 16 == 15 then
        if (z + 1) % 16 == 0 then
          break
        end
        z = z + 1
      else
        x = x - 1
      end
    end
  end
  return locations
end

-- get the bore location closest to the miner
local function getClosestLocation(points, b)
  local key = 1
  local leastMoves = 9000
  for k,pt in pairs(points) do

    local moves = Point.calculateMoves(turtle.point, pt)

    if moves < leastMoves then
      key = k 
      leastMoves = moves
      if leastMoves == 0 then
        break
      end 
    end 
  end 
  return table.remove(points, key)
end 

function getCornerOf(c)
  return math.floor(c.x / 16) * 16, math.floor(c.z / 16) * 16
end

function nextChunk()

  local x, z = getCornerOf({ x = mining.x, z = mining.z })
  local points = math.pow(mining.diameter, 2) - math.pow(mining.diameter-2, 2)
  mining.chunkIndex = mining.chunkIndex + 1

  if mining.chunkIndex >= points then
    mining.diameter = mining.diameter + 2
    mining.chunkIndex = 0
  end

  if mining.chunks ~= -1 then
    local chunks = math.pow(mining.diameter-2, 2) + mining.chunkIndex
    if chunks >= mining.chunks then
      return false
    end
  end

  local nc = getChunkCoordinates(mining.diameter, mining.chunkIndex, x, z)
  mining.locations = getBoreLocations(nc.x, nc.z)

  -- enter next chunk
  mining.x = nc.x
  mining.z = nc.z

  Util.writeTable(PROGRESS_FILE, mining)

  return true
end

function addTrash()

  if not trash then
    trash = { }
  end

  local slots = turtle.getFilledSlots()
 
  for k,slot in pairs(slots) do
    trash[slot.iddmg] = true
  end

  trash['minecraft:bucket:0'] = nil
  Util.writeTable(TRASH_FILE, trash)
end

function log(text)
  print(text)
  Logger.log('mineWorker', text)
end

function status(status)
  turtle.status = status
  log(status)
end

function refuel()
  if turtle.getFuelLevel() < MIN_FUEL then
    local oldStatus = turtle.status
    status('refueling')

    if turtle.select('minecraft:coal:0') then
      local qty = turtle.getItemCount()
      print('refueling ' .. qty)
      turtle.refuel(qty)
    end
    if turtle.getFuelLevel() < MIN_FUEL then
      log('desperate fueling')

      turtle.eachFilledSlot(function(slot)
        if turtle.getFuelLevel() < MIN_FUEL then
          turtle.select(slot.index)
          turtle.refuel(64)
        end
      end)
    end
    log('Fuel: ' .. turtle.getFuelLevel())
    status(oldStatus)
  end

  turtle.select(1)
end
 
function enderChestUnload()
  log('unloading')
  turtle.select(1)
  if not Util.tryTimed(5, function()
      turtle.digDown()
      return turtle.placeDown()
    end) then
    log('placedown failed')
  else
    turtle.reconcileInventory(slots, turtle.dropDown)
 
    turtle.select(1)
    turtle.drop(64)
    turtle.digDown()
  end
end

function safeGoto(x, z, y, h)
  local oldStatus = turtle.status

  -- only pathfind above or around other turtles (never down)
  Pathing.setBox({ x = 0, y = 0, z = 0, ex = x, ey = y + 1, ez = z })
  while not turtle.pathfind({ x = x, z = z, y = y or turtle.point.y, heading = h }) do
    --status('stuck')
    if turtle.abort then
      return false
    end
    --os.sleep(1)
  end
  turtle.status = oldStatus
  return true
end

function safeGotoY(y)
  local oldStatus = turtle.status
  while not turtle.gotoY(y) do
    status('stuck')
    if turtle.abort then
      return false
    end
    os.sleep(1)
  end
  turtle.status = oldStatus
  return true
end

function makeWalkableTunnel(action, tpt, pt)
  if action ~= 'turn' and not Point.compare(tpt, { x = 0, z = 0 }) then -- not at source
    if not Point.compare(tpt, pt) then                                  -- not at dest
      local r, block = turtle.inspectUp()
      if r and not turtle.isTurtleAtSide('top') then
        if block.name ~= 'minecraft:cobblestone' and
           block.name ~= 'minecraft:chest' then
          turtle.digUp()
        end
      end
    end
  end
end

function normalChestUnload()
  local oldStatus = turtle.status
  status('unloading')
  local pt = Util.shallowCopy(turtle.point)
  safeGotoY(0)

  turtle.setMoveCallback(function(action, tpt)
      makeWalkableTunnel(action, tpt, { x = pt.x, z = pt.z })
    end)

  safeGoto(0, 0)
  if not turtle.detectUp() then
    error('no chest')
  end
  local slots = turtle.getFilledSlots()
  for _,slot in pairs(slots) do
    if not trash[slot.iddmg] and 
      slot.iddmg ~= 'minecraft:bucket:0' and
      slot.id ~= 'minecraft:diamond_pickaxe' and
      slot.id ~= 'cctweaks:toolHost' then
      if slot.id ~= options.fortunePick.value then
        turtle.select(slot.index)
        turtle.dropUp(64)
      end
    end
  end
  turtle.condense()
  turtle.select(1)
  safeGoto(pt.x, pt.z, 0, pt.heading)

  turtle.clearMoveCallback()

  safeGotoY(pt.y)
  status(oldStatus)
end

function ejectTrash()

  local cobbleSlotCount = 0

  turtle.eachFilledSlot(function(slot)
    if slot.iddmg == 'minecraft:cobblestone:0' then
      if cobbleSlotCount == 0 and slot.count > 36 then
        turtle.select(slot.index)
        turtle.dropDown(32)
      end
      cobbleSlotCount = cobbleSlotCount + 1
    end

    if trash[slot.iddmg] then
      -- retain 1 slot with cobble in order to indicate active mining
      if slot.iddmg ~= 'minecraft:cobblestone:0' or cobbleSlotCount > 1 then
        turtle.select(slot.index)
        turtle.dropDown(64)
      end
    end
  end)
end

function mineable(action)
  local r, block = action.inspect()
  if not r then
    return false
  end

  if block.name == 'minecraft:chest' then
    collectDrops(action.suck)
  end

  if turtle.getFuelLevel() < (MAX_FUEL - 1000) then
    if block.name == 'minecraft:lava' or block.name == 'minecraft:flowing_lava' then
      if turtle.select('minecraft:bucket:0') then
        if action.place() then
          log('Lava! ' .. turtle.getFuelLevel())
          turtle.refuel()
          log(turtle.getFuelLevel())
        end
        turtle.select(1)
      end
      return false
    end
  end

  if action.side == 'bottom' then
    return block.name
  end

  if trash[block.name .. ':0'] then
    return false
  end

  return block.name
end

function fortuneDig(action, blockName)
  if options.fortunePick.value and fortuneBlocks[blockName] then
    turtle.select('cctweaks:toolHost')
    turtle.equipRight()
    turtle.select(options.fortunePick.value)
    repeat until not turtle.dig()
    turtle.select('minecraft:diamond_pickaxe')
    turtle.equipRight()
    turtle.select(1)
    return true
  end
end

function mine(action)
  local blockName = mineable(action)
  if blockName then
    checkSpace()
    --collectDrops(action.suck)
    if not fortuneDig(action, blockName) then
      action.dig()
    end
  end
end
 
function bore()

  local loc = turtle.point
  local level = loc.y
 
  turtle.select(1)
  status('boring down')
  boreDirection = 'down'

  while true do
    if turtle.abort then
      status('aborting')
      return false
    end
    if loc.y <= -mining.depth then
      break
    end

    if turtle.point.y < -2 then
--      turtle.setDigPolicy(turtle.digPolicies.turtleSafe)
    end

    mine(turtle.getAction('down'))
    if not Util.tryTimed(3, turtle.down) then
      break
    end
 
    if loc.y < level - 1 then
      mine(turtle.getAction('forward'))
      turtle.turnRight()
      mine(turtle.getAction('forward'))
    end
  end

  boreDirection = 'up'
  status('boring up')

  turtle.turnRight()
  mine(turtle.getAction('forward'))
 
  turtle.turnRight()
  mine(turtle.getAction('forward'))
 
  turtle.turnLeft()
 
  while true do
    if turtle.abort then
      status('aborting')
      return false
    end

    if turtle.point.y > -2 then
--      turtle.setDigPolicy(turtle.digPolicies.turtleSafe)
    end

    while not Util.tryTimed(3, turtle.up) do
      status('stuck')
    end
    if turtle.status == 'stuck' then
      status('boring up')
    end

    if loc.y >= level - 1 then
      break
    end
 
    mine(turtle.getAction('forward'))
    turtle.turnLeft()
    mine(turtle.getAction('forward'))
  end
 
  if turtle.getFuelLevel() < LOW_FUEL then
    refuel()
    local veryMinFuel = Point.turtleDistance(turtle.point, { x = 0, y = 0, z = 0}) + 512
    if turtle.getFuelLevel() < veryMinFuel then
      log('Not enough fuel to continue')
      return false
    end
  end

  return true
end
 
function checkSpace()
  if turtle.getItemCount(16) > 0 then
    refuel()
    local oldStatus = turtle.status
    status('condensing')
    ejectTrash()
    turtle.condense()
    local lastSlot = 16
    if boreDirection == 'down' then
      lastSlot = 15
    end
    if turtle.getItemCount(lastSlot) > 0 then
      unload()
    end
    status(oldStatus)
    turtle.select(1)
  end
end
 
function collectDrops(suckAction)
  for i = 1, 50 do
    if not suckAction() then
      break
    end
    checkSpace()
  end
end

function Point.compare(pta, ptb)
  if pta.x == ptb.x and pta.z == ptb.z then
    if pta.y and ptb.y then
      return pta.y == ptb.y
    end
    return true
  end
  return false
end

function inspect(action, name)
  local r, block = action.inspect()
  if r and block.name == name then
    return true
  end
end
 
function boreCommand()
  local pt = getClosestLocation(mining.locations, turtle.point)

  turtle.setMoveCallback(function(action, tpt)
      makeWalkableTunnel(action, tpt, pt)
    end)

  safeGotoY(0)
  safeGoto(pt.x, pt.z, 0)

  turtle.clearMoveCallback()

  -- location is either mined, currently being mined or is the
  -- dropoff point for a turtle
  if inspect(turtle.getAction('up'),   'minecraft:cobblestone') or
     inspect(turtle.getAction('up'),   'minecraft:chest') or
     inspect(turtle.getAction('down'), 'minecraft:cobblestone') then
     return true
  end

  turtle.digUp()
  turtle.placeUp('minecraft:cobblestone:0')

  local success = bore()

  safeGotoY(0) -- may have aborted
  turtle.digUp()

  if success then
    turtle.placeDown('minecraft:cobblestone:0') -- cap with cobblestone to indicate this spot was mined out
  end

  return success
end

if not Util.getOptions(options, args) then
  return
end

mining.depth = options.depth.value
mining.chunks = options.chunks.value

unload = normalChestUnload
--if options.enderChest.value then
--  unload = enderChestUnload
--end

mining.x = 0
mining.z = 0
mining.locations = getBoreLocations(0, 0)
trash = Util.readTable(TRASH_FILE)

if options.resume.value then
  mining = Util.readTable(PROGRESS_FILE)
elseif fs.exists(PROGRESS_FILE) then
  print('Use -r to resume')
  print('Teminate or enter to continue')
  read()
end

if not trash or options.setTrash.value then
  print('Add blocks to ignore, press enter when ready')
  read()
  addTrash()
end

if not turtle.getSlot('minecraft:bucket:0') or
   not turtle.getSlot('minecraft:cobblestone:0') then
  print('Add bucket and cobblestone, press enter when ready')
  read()
end

if options.fortunePick.value then
  local s = turtle.getSlot(options.fortunePick.value)
  if not s then
    error('fortunePick not found: ' .. options.fortunePick.value)
  end
  if not turtle.getSlot('cctweaks:toolHost:0') then
    error('CCTweaks tool host not found')
  end
  trash[s.iddmg] = nil
  trash['minecraft:diamond_pickaxe:0'] = nil
  trash['cctweaks:toolHost:0'] = nil
end

local function main()
  repeat
    while #mining.locations > 0 do
      status('searching')
      if not boreCommand() then
        return
      end
      Util.writeTable(PROGRESS_FILE, mining)
    end
  until not nextChunk()
end

turtle.run(function()
  turtle.reset()
  turtle.setPolicy(turtle.policies.digAttack)
  turtle.setDigPolicy(turtle.digPolicies.turtleSafe)

  unload()
  status('mining')

  local s, m = pcall(function() main() end)
  if not s and m then
    printError(m)
  end

  turtle.abort = false
  safeGotoY(0)
  safeGoto(0, 0, 0, 0)
  unload()
  turtle.reset()
end)
