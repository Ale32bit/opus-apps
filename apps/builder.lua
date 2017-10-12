if not _G.turtle and not _G.commands then
  error('Must be run on a turtle or a command computer')
end

_G.requireInjector()

local Blocks    = require('blocks')
local Event     = require('event')
local itemDB    = require('itemDB')
local MEAdapter = require('meAdapter')
local Message   = require('message')
local Point     = require('point')
local Schematic = require('schematic')
local TableDB   = require('tableDB')
local UI        = require('ui')
local Util      = require('util')

local commands   = _G.commands
local colors     = _G.colors
local device     = _G.device
local fs         = _G.fs
local multishell = _ENV.multishell
local os         = _G.os
local read       = _G.read
local rs         = _G.rs
local turtle     = _G.turtle

local ChestAdapter = require('chestAdapter')
if Util.checkMinecraftVersion(1.8) then
  ChestAdapter  = require('chestAdapter18')
end

local BUILDER_DIR = 'usr/builder'

local schematic = Schematic()
local blocks = Blocks({ dir = BUILDER_DIR })
local supplyPage, substitutionPage
local pistonFacings

local SUPPLIES_PT = { x = -1, z = -1, y = 0 }

local Builder = {
  version = '1.71',
  isCommandComputer = not turtle,
  slots = { },
  index = 1,
  mode = 'build',
  fuelItem = { id = 'minecraft:coal', dmg = 0 },
  resourceSlots = 14,
  facing = 'south',
  wrenchSucks = false,
  stairBug = false,
}

-- Temp functions until conversion to new adapters is complete
local function convertSingleForward(item)
  item.displayName = item.display_name
  item.name = item.id
  item.damage = item.dmg
  item.count = item.qty
  item.maxCount = item.max_size
  return item
end

local function convertForward(t)
  for _,v in pairs(t) do
    convertSingleForward(v)
  end
  return t
end

local function convertSingleBack(item)
  if item then
    item.id = item.name
    item.dmg = item.damage
    item.qty = item.count
    item.max_size = item.maxCount
    item.display_name = item.displayName
    --item.name = item.displayName
  end
  return item
end

local function convertBack(t)
  for _,v in pairs(t) do
    convertSingleBack(v)
  end
  return t
end

--[[-- SubDB --]]--
local subDB = TableDB({
  fileName = fs.combine(BUILDER_DIR, 'sub.db'),
})

function subDB:load()
  if fs.exists(self.fileName) then
    TableDB.load(self)
  elseif not Builder.isCommandComputer then
    self:seedDB()
  end
end

function subDB:seedDB()
  self.data = {
    [ "minecraft:redstone_wire:0"        ] = "minecraft:redstone:0",
    [ "minecraft:wall_sign:0"            ] = "minecraft:sign:0",
    [ "minecraft:standing_sign:0"        ] = "minecraft:sign:0",
    [ "minecraft:potatoes:0"             ] = "minecraft:potato:0",
    [ "minecraft:unlit_redstone_torch:0" ] = "minecraft:redstone_torch:0",
    [ "minecraft:powered_repeater:0"     ] = "minecraft:repeater:0",
    [ "minecraft:unpowered_repeater:0"   ] = "minecraft:repeater:0",
    [ "minecraft:carrots:0"              ] = "minecraft:carrot:0",
    [ "minecraft:cocoa:0"                ] = "minecraft:dye:3",
    [ "minecraft:unpowered_comparator:0" ] = "minecraft:comparator:0",
    [ "minecraft:powered_comparator:0"   ] = "minecraft:comparator:0",
    [ "minecraft:piston_head:0"          ] = "minecraft:air:0",
    [ "minecraft:piston_extension:0"     ] = "minecraft:air:0",
    [ "minecraft:portal:0"               ] = "minecraft:air:0",
    [ "minecraft:double_wooden_slab:0"   ] = "minecraft:planks:0",
    [ "minecraft:double_wooden_slab:1"   ] = "minecraft:planks:1",
    [ "minecraft:double_wooden_slab:2"   ] = "minecraft:planks:2",
    [ "minecraft:double_wooden_slab:3"   ] = "minecraft:planks:3",
    [ "minecraft:double_wooden_slab:4"   ] = "minecraft:planks:4",
    [ "minecraft:double_wooden_slab:5"   ] = "minecraft:planks:5",
    [ "minecraft:lit_redstone_lamp:0"    ] = "minecraft:redstone_lamp:0",
    [ "minecraft:double_stone_slab:1"    ] = "minecraft:sandstone:0",
    [ "minecraft:double_stone_slab:2"    ] = "minecraft:planks:0",
    [ "minecraft:double_stone_slab:3"    ] = "minecraft:cobblestone:0",
    [ "minecraft:double_stone_slab:4"    ] = "minecraft:brick_block:0",
    [ "minecraft:double_stone_slab:5"    ] = "minecraft:stonebrick:0",
    [ "minecraft:double_stone_slab:6"    ] = "minecraft:nether_brick:0",
    [ "minecraft:double_stone_slab:7"    ] = "minecraft:quartz_block:0",
    [ "minecraft:double_stone_slab:9"    ] = "minecraft:sandstone:2",
    [ "minecraft:double_stone_slab2:0"   ] = "minecraft:sandstone:0",
    [ "minecraft:stone_slab:2"           ] = "minecraft:wooden_slab:0",
    [ "minecraft:wheat:0"                ] = "minecraft:wheat_seeds:0",
    [ "minecraft:flowing_water:0"        ] = "minecraft:air:0",
    [ "minecraft:lit_furnace:0"          ] = "minecraft:furnace:0",
    [ "minecraft:wall_banner:0"          ] = "minecraft:banner:0",
    [ "minecraft:standing_banner:0"      ] = "minecraft:banner:0",
    [ "minecraft:tripwire:0"             ] = "minecraft:string:0",
    [ "minecraft:pumpkin_stem:0"         ] = "minecraft:pumpkin_seeds:0",
  }
  self.dirty = true
  self:flush()
end

function subDB:add(s)
  TableDB.add(self, { s.id, s.dmg }, table.concat({ s.sid, s.sdmg }, ':'))
  self:flush()
end

function subDB:remove(s)
  -- TODO: tableDB.remove should take table key
  TableDB.remove(self, s.id .. ':' .. s.dmg)
  self:flush()
end

function subDB:extract(s)
  local id, dmg = s:match('(.+):(%d+)')
  return id, tonumber(dmg)
end

function subDB:getSubstitutedItem(id, dmg)
  local sub = TableDB.get(self, { id, dmg })
  if sub then
    id, dmg = self:extract(sub)
  end
  return { id = id, dmg = dmg }
end

function subDB:lookupBlocksForSub(sid, sdmg)
  local t = { }
  for k,v in pairs(self.data) do
    local id, dmg = self:extract(v)
    if id == sid and dmg == sdmg then
      id, dmg = self:extract(k)
      t[k] = { id = id, dmg = dmg, sid = sid, sdmg = sdmg }
    end
  end
  return t
end

--[[-- maxStackDB --]]--
local maxStackDB = TableDB({
  fileName = fs.combine(BUILDER_DIR, 'maxstack.db'),
})

function maxStackDB:get(id, dmg)
  return self.data[id .. ':' .. dmg] or 64
end

--[[-- Builder --]]--
function Builder:getBlockCounts()
  local blocks = { }

  -- add a couple essential items to the supply list to allow replacements
  if not self.isCommandComputer then
    local wrench = subDB:getSubstitutedItem('SubstituteAWrench', 0)
    wrench.qty = 0
    wrench.need = 1
    blocks[wrench.id .. ':' .. wrench.dmg] = wrench

    local fuel = subDB:getSubstitutedItem(Builder.fuelItem.id, Builder.fuelItem.dmg)
    fuel.qty = 0
    fuel.need = 1
    blocks[fuel.id .. ':' .. fuel.dmg] = fuel

    blocks['minecraft:piston:0'] = {
      id = 'minecraft:piston',
      dmg = 0,
      qty = 0,
      need = 1,
    }
  end

  for k,b in ipairs(schematic.blocks) do
    if k >= self.index then
      local key = tostring(b.id) .. ':' .. b.dmg
      local block = blocks[key]
      if not block then
        block = Util.shallowCopy(b)
        block.qty = 0
        block.need = 0
        blocks[key] = block
      end
      block.need = block.need + 1
    end
  end

  return blocks
end

function Builder:selectItem(id, dmg)

  for k,s in ipairs(self.slots) do
    if s.qty > 0 and s.id == id and s.dmg == dmg then
      -- check to see if someone pulled items from inventory
      -- or we passed over a hopper
      if turtle.getItemCount(s.index) > 0 then
        if k > 1 and s.qty > 1 then
          table.remove(self.slots, k)
          table.insert(self.slots, 1, s)
        end
        turtle.select(s.index)
        return s
      end
    end
  end
end

function Builder:getAirResupplyList(blockIndex)

  local slots = { }

  if self.mode == 'destroy' then
    for i = 1, self.resourceSlots do
      slots[i] = {
        qty = 0,
        need = 0,
        index = i
      }
    end
  else
    slots = self:getGenericSupplyList(blockIndex)
  end

  local fuel = subDB:getSubstitutedItem(Builder.fuelItem.id, Builder.fuelItem.dmg)

  slots[15] = {
    id = 'minecraft:chest', --'ironchest:BlockIronChest',  --
    dmg = 0,
    qty = 0,
    need = 1,
    index = 15,
  }

  slots[16] = {
    id = fuel.id,
    dmg = fuel.dmg,
    wrench = true,
    qty = 0,
    need = 64,
    index = 16,
  }

  return slots
end

function Builder:getSupplyList(blockIndex)

  local slots, lastBlock = self:getGenericSupplyList(blockIndex)

  slots[15] = {
    id = 'minecraft:piston',
    dmg = 0,
    qty = 0,
    need = 1,
    index = 15,
  }

  local wrench = subDB:getSubstitutedItem('SubstituteAWrench', 0)
  slots[16] = {
    id = wrench.id,
    dmg = wrench.dmg,
    wrench = true,
    qty = 0,
    need = 1,
    index = 16,
  }

  self.slots = slots

  return lastBlock
end

function Builder:getGenericSupplyList(blockIndex)

  local slots = { }

  for i = 1, self.resourceSlots do
    slots[i] = {
      qty = 0,
      need = 0,
      index = i
    }
  end

  local function getSlot(id, dmg)
    -- find matching slot
    local maxStack = maxStackDB:get(id, dmg)
    for _, s in ipairs(slots) do
      if s.id == id and s.dmg == dmg and s.need < maxStack then
        return s
      end
    end
    -- return first available slot
    for _, s in ipairs(slots) do
      if not s.id then
        s.key = id .. ':' .. dmg
        s.id = id
        s.dmg = dmg
        return s
      end
    end
  end

  local lastBlock = blockIndex
  for k = blockIndex, #schematic.blocks do
    lastBlock = k
    local b = schematic:getComputedBlock(k)

    if b.id ~= 'minecraft:air' then
      local slot = getSlot(b.id, b.dmg)
      if not slot then
        break
      end
      slot.need = slot.need + 1
    end
  end

  for _,s in pairs(slots) do
    if s.id then
      s.display_name = itemDB:getName({ name = s.id, damage = s.dmg })
    end
  end

  return slots, lastBlock
end

function Builder:substituteBlocks(throttle)

  for _,b in pairs(schematic.blocks) do

    -- replace schematic block type with substitution
    local pb = blocks:getPlaceableBlock(b.id, b.dmg)

    Util.merge(b, pb)

    b.odmg = pb.odmg or pb.dmg

    local sub = subDB:get({ b.id, b.dmg })
    if sub then
      b.id, b.dmg = subDB:extract(sub)
    end
    throttle()
  end
end

function Builder:dumpInventory()

  local success = true

  for i = 1, 16 do
    local qty = turtle.getItemCount(i)
    if qty > 0 then
      self.itemAdapter:insert(i, qty)
    end
    if turtle.getItemCount(i) ~= 0 then
      success = false
    end
  end
  turtle.select(1)

  return success
end

function Builder:dumpInventoryWithCheck()

  while not self:dumpInventory() do
    print('Storage is full or missing - make space or replace')
    print('Press enter to continue')
    turtle.setHeading(0)
    read()
  end
end

function Builder:autocraft(supplies)
  local t = { }

  for _,s in pairs(supplies) do
    local key = s.id .. ':' .. s.dmg
    local item = t[key]
    if not item then
      item = {
        id = s.id,
        dmg = s.dmg,
        qty = 0,
      }
      t[key] = item
    end
    item.qty = item.qty + (s.need - s.qty)
  end

  Builder.itemAdapter:craftItems(convertForward(t))
end

function Builder:getSupplies()

  self.itemAdapter:refresh()

  local t = { }
  for _,s in ipairs(self.slots) do
    if s.need > 0 then
      local item = convertSingleBack(self.itemAdapter:getItemInfo({
        name = s.id,
        damage = s.dmg,
        nbtHash = s.nbt_hash,
      }))
      if item then
        s.display_name = item.display_name

        local qty = math.min(s.need - s.qty, item.qty)

        if qty + s.qty > item.max_size then
          maxStackDB:add({ s.id, s.dmg }, item.max_size)
          maxStackDB.dirty = true
          maxStackDB:flush()
          qty = item.max_size
          s.need = qty
        end
        if qty > 0 then
          self.itemAdapter:provide(convertSingleForward(item), qty, s.index)
          s.qty = turtle.getItemCount(s.index)
        end
      else
        s.display_name = itemDB:getName({ name = s.id, damage = s.dmg })
      end
    end
    if s.qty < s.need then
      table.insert(t, s)
    end
  end

  return t
end

Event.on('build', function()
  Builder:build()
end)

function Builder:refuel()
  while turtle.getFuelLevel() < 4000 and self.fuelItem do
    print('Refueling')
    turtle.select(1)

    local fuel = subDB:getSubstitutedItem(self.fuelItem.id, self.fuelItem.dmg)

    self.itemAdapter:provide(convertSingleForward(fuel), 64, 1)
    if turtle.getItemCount(1) == 0 then
      print('Out of fuel, add fuel to chest/ME system')
      turtle.setHeading(0)
      turtle.status = 'waiting'
      os.sleep(5)
    else
      turtle.refuel(64)
    end
  end
end

function Builder:inAirDropoff()
  if not device.wireless_modem then
    return false
  end

  self:log('Requesting air supply drop for supply #: ' .. 1)
  while true do
    Message.broadcast('needSupplies', { point = turtle.getPoint(), uid = 1 })
    local _, _, msg, _ = Message.waitForMessage('gotSupplies', 1)

    if not msg or not msg.contents then
      Message.broadcast('supplyList', { uid = 1, slots = self:getAirResupplyList() })
      return false
    end

    turtle.status = 'waiting'

    if msg.contents.point then
      local pt = msg.contents.point

      self:log('Received supply location')
      os.sleep(0)

      turtle._goto(pt.x, pt.z, pt.y)
      os.sleep(.1)  -- random computer is not connected error

      local chestAdapter = ChestAdapter({ direction = 'down', wrapSide = 'top' })

      if not chestAdapter:isValid() then
        self:log('Chests above is not valid')
        return false
      end

      local oldAdapter = self.itemAdapter
      self.itemAdapter = chestAdapter

      if not self:dumpInventory() then
        self:log('Unable to dump inventory')
        self.itemAdapter = oldAdapter
        return false
      end

      self.itemAdapter = oldAdapter

      Message.broadcast('thanks', { })

      for _ = 1,12 do -- wait til supplier is idle before sending next request
        if turtle.detectUp() then
          os.sleep(.25)
        end
      end
      os.sleep(.1)

      Message.broadcast('supplyList', { uid = 1, slots = self:getAirResupplyList() })

      return true
    end
  end
end

function Builder:inAirResupply()

  if not device.wireless_modem then
    return false
  end

  local oldAdapter = self.itemAdapter

  self:log('Requesting air supply drop for supply #: ' .. self.slotUid)
  while true do
    Message.broadcast('needSupplies', { point = turtle.getPoint(), uid = Builder.slotUid })
    local _, _, msg, _ = Message.waitForMessage('gotSupplies', 1)

    if not msg or not msg.contents then
      self.itemAdapter = oldAdapter
      return false
    end

    turtle.status = 'waiting'

    if msg.contents.point then
      local pt = msg.contents.point

      self:log('Received supply location')
      os.sleep(0)

      turtle._goto(pt.x, pt.z, pt.y)
      os.sleep(.1)  -- random computer is not connected error

      local chestAdapter = ChestAdapter({ direction = 'down', wrapSide = 'top' })

      if not chestAdapter:isValid() then
        Util.print('not valid')
        read()
      end

      self.itemAdapter = chestAdapter

      if not self:dumpInventory() then
        self.itemAdapter = oldAdapter
        return false
      end
      self:refuel()

      local lastBlock = self:getSupplyList(self.index)
      local supplies = self:getSupplies()

      Message.broadcast('thanks', { })

      self.itemAdapter = oldAdapter

      if #supplies == 0 then

        for _ = 1,12 do -- wait til supplier is idle before sending next request
          if turtle.detectUp() then
            os.sleep(.25)
          end
        end
        os.sleep(.1)
        if lastBlock < #schematic.blocks then
          self:sendSupplyRequest(lastBlock)
        else
          Message.broadcast('finished')
        end

        return true
      end
      self:log('Missing supplies - manually resupplying')
      return false
    end
  end
end

function Builder:sendSupplyRequest(lastBlock)

  if device.wireless_modem then
    local slots = self:getAirResupplyList(lastBlock)
    self.slotUid = os.clock()

    Message.broadcast('supplyList', { uid = self.slotUid, slots = slots })
  end
end

function Builder:resupply()

  if self.slotUid and self:inAirResupply() then
    os.queueEvent('build')
    return
  end

  turtle.status = 'resupplying'

  self:log('Resupplying')
  turtle.gotoYlast(SUPPLIES_PT)
  os.sleep(.1) -- random 'Computer is not connected' error...
  self:dumpInventoryWithCheck()
  self:refuel()
  local lastBlock = self:getSupplyList(self.index)
  if lastBlock < #schematic.blocks then
    self:sendSupplyRequest(lastBlock)
  elseif device.wireless_modem then
    Message.broadcast('finished')
  end
  os.sleep(1)
  local supplies = self:getSupplies()

  if #supplies == 0 then
    os.queueEvent('build')
  else
    turtle.setHeading(0)
    self:autocraft(supplies)
    supplyPage:setSupplies(supplies)
    UI:setPage('supply')
  end
end

function Builder:placeDown(slot)
  return turtle.placeDown(slot.index)
end

function Builder:placeUp(slot)
  return turtle.placeUp(slot.index)
end

function Builder:place(slot)
  return turtle.place(slot.index)
end

function Builder:getWrenchSlot()
  local wrench = subDB:getSubstitutedItem('SubstituteAWrench', 0)
  return Builder:selectItem(wrench.id, wrench.dmg)
end

-- figure out our orientation in the world
function Builder:getTurtleFacing()
  local directions = { -- reversed directions
    [5] = 'west',
    [3] = 'north',
    [4] = 'east',
    [2] = 'south',
  }

  local function getItem(item)
    turtle.select(1)
    local msg = false
    while true do
      self.itemAdapter:provide(item, 1, 1)
      if turtle.getItemCount(1) == 1 then
        break
      end
      if not msg then
        print('Place ' .. itemDB:getName(item) .. ' in supply chest')
        msg = true
      end
      os.sleep(1)
    end
  end

  getItem({ name = 'minecraft:piston', damage = 0 })
  turtle.placeUp()
  local _, bi = turtle.inspectUp()
  turtle.digUp()
  self:dumpInventoryWithCheck()

  if directions[bi.metadata] then
    self.facing = directions[bi.metadata]
    return
  end

  -- if the piston faces up when placed above, then this version
  -- has the stair bug
  self.stairBug = true

  getItem({ name = 'minecraft:chest', damage = 0 })
  turtle.placeUp()
  local _, bi2 = turtle.inspectUp()
  turtle.digUp()
  self:dumpInventoryWithCheck()

  self.facing = directions[bi2.metadata]
end

function Builder:wrenchBlock(side, facing, cache)
  local s = Builder:getWrenchSlot()

  if not s then
    return false
  end

  local key = turtle.point.heading .. '-' .. facing
  if cache then
    local count = cache[side][key]

    if count then
      turtle.select(s.index)
      for _ = 1,count do
        turtle.getAction(side).place()
      end
      return true
    end
  end

  local directions = {
    [5] = 'east',
    [3] = 'south',
    [4] = 'west',
    [2] = 'north',
    [0] = 'down',
    [1] = 'up',
  }

  if turtle.getHeadingInfo(facing).heading < 4 then
    local offsetDirection = (turtle.getHeadingInfo(Builder.facing).heading +
                turtle.getHeadingInfo(facing).heading) % 4
    facing = turtle.getHeadingInfo(offsetDirection).direction
  end

  local count = 0
  print('determining wrench count')
  for _ = 1, 6 do
    local _, bi = turtle.getAction(side).inspect()

    if facing == directions[bi.metadata] then
      if cache then
        cache[side][key] = count
      end
      return true
    end
    count = count + 1
    turtle.getAction(side).place()
  end

  return false
end

function Builder:rotateBlock(side, facing)

  local s = Builder:getWrenchSlot()

  if not s then
    return false
  end

  for _ = 1, facing do
    turtle.getAction(side).place()
  end

  return true

  --[[
  local origFacing
  while true do
    local _, bi = turtle.getAction(side).inspect()

    -- spin until it repeats
    if not origFacing then
      origFacing = bi.metadata
    elseif bi.metadata == origFacing then
      return false
    end

    if facing == bi.metadata then
      return true
    end
    turtle.getAction(side).place()
  end

  return false
  ]]--
end

-- place piston, wrench piston to face downward, extend, remove piston
function Builder:placePiston(b)

  local ps = Builder:selectItem('minecraft:piston', 0)
  local ws = Builder:getWrenchSlot()

  if not ps or not ws then
    b.needResupply = true
    -- a hopper may have eaten the piston
    return
  end

  if not turtle.place(ps.index) then
    return
  end

  if self.wrenchSucks then
    turtle.turnRight()
    turtle.forward()
    turtle.turnLeft()
    turtle.forward()
    turtle.turnLeft()
  end

  local success = self:wrenchBlock('forward', 'down', pistonFacings) --wrench piston to point downwards

  rs.setOutput('front', true)
  os.sleep(.25)
  rs.setOutput('front', false)
  os.sleep(.25)
  turtle.select(ps.index)
  turtle.dig()

  if not success and not self.wrenchSucks then
    self.wrenchSucks = true
    success = self:placePiston(b)
  end

  return success
end

function Builder:_goto(x, z, y, heading)
  if not turtle._goto(x, z, y, heading) then
    print('stuck')
    print('Press enter to continue')
    os.sleep(1)
    turtle.status = 'stuck'
    read()
  end
end

-- goto used when turtle could be below travel plane
-- if the distance is no more than 1 block, there's no need to pop back to the travel plane
function Builder:gotoEx(x, z, y, h, travelPlane)
  local distance = math.abs(turtle.getPoint().x - x) + math.abs(turtle.getPoint().z - z)

  -- following code could be better
  if distance == 0 then
    turtle.gotoY(y)
  elseif distance == 1 then
    if turtle.point.y < y then
      turtle.gotoY(y)
    end
  elseif distance > 1 then
    self:gotoTravelPlane(travelPlane)
  end
  self:_goto(x, z, y, h)
end

function Builder:placeDirectionalBlock(b, slot, travelPlane)
  local d = b.direction

  local function getAdjacentPoint(pt, direction)
    local hi = turtle.getHeadingInfo(direction)
    return { x = pt.x + hi.xd, z = pt.z + hi.zd, y = pt.y + hi.yd, heading = (hi.heading + 2) % 4 }
  end

  local directions = {
    [ 'north' ] = 'north',
    [ 'south' ] = 'south',
    [ 'east'  ] = 'east',
    [ 'west'  ] = 'west',
  }
  if directions[d] then
    self:gotoEx(b.x, b.z, b.y, turtle.getHeadingInfo(directions[d]).heading, travelPlane)
    b.placed = self:placeDown(slot)
  end

  if d == 'top' then
    self:gotoEx(b.x, b.z, b.y+1, nil, travelPlane)
    if self:placeDown(slot) then
      turtle.goback()
      b.placed = self:placePiston(b)
    end
  end

  if d == 'bottom' then
    local t = {
      [1] = getAdjacentPoint(b, 'east'),
      [2] = getAdjacentPoint(b, 'south'),
      [3] = getAdjacentPoint(b, 'west'),
      [4] = getAdjacentPoint(b, 'north'),
    }

    local c = Point.closest(turtle.getPoint(), t)
    self:gotoEx(c.x, c.z, c.y, c.heading, travelPlane)

    if self:place(slot) then
      turtle.up()
      b.placed = self:placePiston(b)
    end
  end

  local stairDownDirections = {
    [ 'north-down' ] = 'north',
    [ 'south-down' ] = 'south',
    [ 'east-down'  ] = 'east',
    [ 'west-down'  ] = 'west'
  }
  if stairDownDirections[d] then
    self:gotoEx(b.x, b.z, b.y+1, turtle.getHeadingInfo(stairDownDirections[d]).heading, travelPlane)
    if self:placeDown(slot) then
      turtle.goback()
      b.placed = self:placePiston(b)
    end
  end

  local stairUpDirections = {
    [ 'north-up' ] = 'south',
    [ 'south-up' ] = 'north',
    [ 'east-up'  ] = 'west',
    [ 'west-up'  ] = 'east'
  }
  if stairUpDirections[d] then

    local isSouth = (turtle.getHeadingInfo(Builder.facing).heading +
                    turtle.getHeadingInfo(stairUpDirections[d]).heading) % 4 == 1

    if not self.stairBug then
      isSouth = false
    end

    if isSouth then
      -- for some reason, the south facing stair doesn't place correctly
      -- jump through some hoops to place it
      self:gotoEx(b.x, b.z, b.y, (turtle.getHeadingInfo(stairUpDirections[d]).heading + 2) % 4, travelPlane)
      if self:placeUp(slot) then
        turtle.goback()
        turtle.gotoY(turtle.point.y + 2)
        b.placed = self:placePiston(b)
        turtle.down()
        b.placed = self:placePiston(b)

        b.heading = turtle.point.heading -- stop debug message below since we are pointing in wrong direction
      end
    else
      local hi = turtle.getHeadingInfo(stairUpDirections[d])
      self:gotoEx(b.x - hi.xd, b.z - hi.zd, b.y, hi.heading, travelPlane)
      if self:place(slot) then
        turtle.up()
        b.placed = self:placePiston(b)
      end
    end
  end

  local horizontalDirections = {
    [ 'east-west-block'   ] = { 'east', 'west' },
    [ 'north-south-block' ] = { 'north', 'south' },
  }
  if horizontalDirections[d] then

    local t = {
      [1] = getAdjacentPoint(b, horizontalDirections[d][1]),
      [2] = getAdjacentPoint(b, horizontalDirections[d][2]),
    }

    local c = Point.closest(turtle.getPoint(), t)
    self:gotoEx(c.x, c.z, c.y, c.heading, travelPlane)

    if self:place(slot) then
      turtle.up()
      b.placed = self:placePiston(b)
    end
  end

  local pistonDirections = {
    [ 'piston-north' ] = 'north',
    [ 'piston-south' ] = 'south',
    [ 'piston-west'  ] = 'west',
    [ 'piston-east'  ] = 'east',
    [ 'piston-down'  ] = 'down',
    [ 'piston-up'    ] = 'up',
  }

  if pistonDirections[d] then
    -- why are pistons so broke in cc 1.7 ??????????????????????

    local ws = Builder:getWrenchSlot()

    if not ws then
      b.needResupply = true
      -- a hopper may have eaten the piston
      return false
    end

    -- piston turns relative to turtle position :)
    local rotatedPistonDirections = {
      [ 'piston-east' ] = 0,
      [ 'piston-south' ] = 1,
      [ 'piston-west' ] = 2,
      [ 'piston-north' ] = 3,
    }

    self:gotoEx(b.x, b.z, b.y, nil, travelPlane)

    local heading = rotatedPistonDirections[d]
    if heading and turtle.point.heading % 2 ~= heading % 2 then
      turtle.setHeading(heading)
    end

    if self:placeDown(slot) then
      b.placed = self:wrenchBlock('down', pistonDirections[d], pistonFacings)
    end
  end

  local wrenchDirections = {
    [ 'wrench-down' ] = 'down',
    [ 'wrench-up'   ] = 'up',
  }

  if wrenchDirections[d] then

    local ws = Builder:getWrenchSlot()

    if not ws then
      b.needResupply = true
      -- a hopper may have eaten the piston
      return false
    end

    self:gotoEx(b.x, b.z, b.y, nil, travelPlane)

    if self:placeDown(slot) then
      b.placed = self:wrenchBlock('down', wrenchDirections[d])
    end
  end

  local doorDirections = {
    [ 'east-door' ] = 'east',
    [ 'south-door' ] = 'south',
    [ 'west-door'  ] = 'west',
    [ 'north-door'  ] = 'north',
  }
  if doorDirections[d] then
    local hi = turtle.getHeadingInfo(doorDirections[d])
    self:gotoEx(b.x - hi.xd, b.z - hi.zd, b.y - 1, hi.heading, travelPlane)
    b.placed = self:place(slot)
  end

  local blockDirections = {
    [ 'north-block' ] = 'north',
    [ 'south-block' ] = 'south',
    [ 'east-block'  ] = 'east',
    [ 'west-block'  ] = 'west',
  }
  if blockDirections[d] then
    local hi = turtle.getHeadingInfo(blockDirections[d])
    self:gotoEx(b.x - hi.xd, b.z - hi.zd, b.y-1, hi.heading, travelPlane)
    b.placed = self:place(slot)
  end

  if b.facing then
    self:rotateBlock('down', b.facing)
  end

-- debug
if d ~= 'top' and d ~= 'bottom' and not horizontalDirections[d] and not pistonDirections[d] then
  if not b.heading or turtle.getHeading() ~= b.heading then
    self:log(d .. ' - ' .. turtle.getHeading() .. ' - ' .. (b.heading or 'nil'))
    --read()
  end
end

  return b.placed
end

function Builder:reloadSchematic(throttle)
  schematic:reload(throttle)
  self:substituteBlocks(throttle)
end

function Builder:log(...)
  Util.print(...)
end

function Builder:logBlock(index, b)
  local bdir = b.direction or ''
  local logText = string.format('%d %s:%d (x:%d,z:%d:y:%d) %s',
    index, b.id, b.dmg, b.x, b.z, b.y, bdir)
  self:log(logText)
  -- self:log(b.index) -- unique identifier of block

  if device.wireless_modem then
    Message.broadcast('builder', { x = b.x, y = b.y, z = b.z, heading = b.heading })
  end
end

function Builder:saveProgress(index)
  Util.writeTable(
    fs.combine(BUILDER_DIR, schematic.filename .. '.progress'),
    { index = index, facing = Builder.facing }
  )
end

function Builder:loadProgress(filename)
  local progress = Util.readTable(fs.combine(BUILDER_DIR, filename))
  if progress then
    Builder.index = progress.index
    if Builder.index > #schematic.blocks then
      Builder.index = 1
    end
    Builder.facing = progress.facing or 'south'
  end
end

-- find the highest y in the last 2 planes
function Builder:findTravelPlane(index)

  local travelPlane

  for i = index, 1, -1 do
    local b = schematic.blocks[i]

    local y = b.y
    if b.twoHigh then
      y = y + 1
    end
    if not travelPlane or y > travelPlane then
      travelPlane = y
    elseif travelPlane and travelPlane - y > 2 then
      break
    end
  end

  return travelPlane or 0
end

function Builder:gotoTravelPlane(travelPlane)
  if travelPlane > turtle.point.y then
    turtle.gotoY(travelPlane)
  end
end

function Builder:build()

  local direction = 1
  local last = #schematic.blocks
  local travelPlane = 0
  local minFuel = schematic.height + schematic.width + schematic.length + 100
  local throttle = Util.throttle()

  if self.mode == 'destroy' then
    direction = -1
    last = 1
    turtle.status = 'destroying'
  elseif not self.isCommandComputer then
    travelPlane = self:findTravelPlane(self.index)
    turtle.status = 'building'
  end

  UI:setPage('blank')

  for i = self.index, last, direction do
    self.index = i

    local b = schematic:getComputedBlock(i)

    if b.id ~= 'minecraft:air' then

      if self.isCommandComputer then
        self:logBlock(self.index, b)

        local id = b.id
        if self.mode == 'destroy' then
          id = 'minecraft:air'
        end

        local function placeBlock(id, dmg, x, y, z)

          local cx, _, cz = commands.getBlockPosition()

          local command = table.concat({
            "setblock",
            cx + x + 1,
            "~" .. y,
            cz + z + 1,
            id,
            dmg,
          }, ' ')

          commands.execAsync(command)

          local result = { os.pullEvent("task_complete") }
          if not result[4] then
            Util.print(result[5])
            if self.mode ~= 'destroy' then
              read()
            end
          end
        end

        placeBlock(id, b.odmg, b.x, b.y, b.z)

        if b.twoHigh then
          local _, topBlock = schematic:findIndexAt(b.x, b.z, b.y + 1, true)
          if topBlock then
            placeBlock(id, topBlock.odmg, b.x, b.y + 1, b.z)
          end
        end

      elseif self.mode == 'destroy' then

        b.heading = nil -- don't make the supplier follow the block heading
        self:logBlock(self.index, b)
        if b.y ~= turtle.getPoint().y then
          turtle.gotoY(b.y)
        end
        self:_goto(b.x, b.z, b.y)
        turtle.digDown()

        -- if no supplier, then should fill all slots

        if turtle.getItemCount(self.resourceSlots) > 0 or turtle.getFuelLevel() < minFuel then
          if turtle.getFuelLevel() < minFuel or not self:inAirDropoff() then
            turtle.gotoPoint(SUPPLIES_PT)
            os.sleep(.1) -- random 'Computer is not connected' error...
            self:dumpInventoryWithCheck()
            self:refuel()
          end
          turtle.status = 'destroying'
        end

      else -- Build mode

        local slot = Builder:selectItem(b.id, b.dmg)
        if not slot or turtle.getFuelLevel() < minFuel then

          if turtle.getPoint().x > -1 or turtle.getPoint().z > -1 then
            self:gotoTravelPlane(travelPlane)
          end
          self:resupply()
          return
        end
        local y = b.y
        if b.twoHigh then
          y = b.y + 1
        end
        if y > travelPlane then
          travelPlane = y
        end

        self:logBlock(self.index, b)

        if b.direction then
          b.needResupply = false
          self:placeDirectionalBlock(b, slot, travelPlane)
          if b.needResupply then -- lost our piston in a hopper probably
            self:gotoTravelPlane(travelPlane)
            self:resupply()
            return
          end
        else
          self:gotoTravelPlane(travelPlane)
          self:_goto(b.x, b.z, b.y)
          b.placed = self:placeDown(slot)
        end

        if b.placed then
          slot.qty = slot.qty - 1
        else
          print('failed to place block')
        end
      end
      if self.mode == 'destroy' then
        self:saveProgress(math.max(self.index, 1))
      else
        self:saveProgress(self.index + 1)
      end
    else
      throttle() -- sleep in case there are a large # of skipped blocks
    end

    if turtle.abort then
      turtle.status = 'aborting'
      self:gotoTravelPlane(travelPlane)
      turtle.gotoPoint(SUPPLIES_PT)
      turtle.setHeading(0)
      Builder:dumpInventory()
      Event.exitPullEvents()
      UI.term:reset()
      print('Aborted')
      return
    end
  end

  if device.wireless_modem then
    Message.broadcast('finished')
  end
  if not self.isCommandComputer then
    self:gotoTravelPlane(travelPlane)
    turtle.gotoPoint(SUPPLIES_PT)
    turtle.setHeading(0)
    Builder:dumpInventory()

    for _ = 1, 4 do
      turtle.turnRight()
    end
  end

--self.index = 1
--os.queueEvent('build')
  --UI.term:reset()
  fs.delete(schematic.filename .. '.progress')
  print('Finished')
  Event.exitPullEvents()
end

--[[-- blankPage --]]--
local blankPage = UI.Page()
function blankPage:draw()
  self:clear(colors.black)
  self:setCursorPos(1, 1)
end

function blankPage:enable()
  self:sync()
  UI.Page.enable(self)
end

--[[-- selectSubstitutionPage --]]--
local selectSubstitutionPage = UI.Page({
  titleBar = UI.TitleBar({
    title = 'Select a substitution',
    previousPage = 'listing'
  }),
  grid = UI.ScrollingGrid({
    columns = {
      { heading = 'id',  key = 'id'  },
      { heading = 'dmg', key = 'dmg' },
    },
    sortColumn = 'id',
    height = UI.term.height-1,
    autospace = true,
    y = 2,
  }),
})

function selectSubstitutionPage:enable()
  self.grid:adjustWidth()
  self.grid:setIndex(1)
  UI.Page.enable(self)
end

function selectSubstitutionPage:eventHandler(event)

  if event.type == 'grid_select' then
    substitutionPage.sub = event.selected
    UI:setPage(substitutionPage)
  elseif event.type == 'key' and event.key == 'q' then
    UI:setPreviousPage()
  else
    return UI.Page.eventHandler(self, event)
  end
  return true
end

--[[-- substitutionPage --]]--
substitutionPage = UI.Page {
  titleBar = UI.TitleBar {
    previousPage = true,
    title = 'Substitute a block'
  },
  menuBar = UI.MenuBar {
    y = 2,
    buttons = {
      { text = 'Accept', event = 'accept', help = 'Accept'              },
      { text = 'Revert', event = 'revert', help = 'Restore to original' },
      { text = 'Air',    event = 'air',    help = 'Air'                 },
    },
  },
  info = UI.Window { y = 4, width = UI.term.width, height = 3 },
  grid = UI.ScrollingGrid {
    columns = {
      { heading = 'Name', key = 'display_name', width = UI.term.width-9 },
      { heading = 'Qty',  key = 'fQty', width = 5               },
    },
    sortColumn = 'display_name',
    height = UI.term.height-7,
    y = 7,
  },
  throttle = UI.Throttle { },
  statusBar = UI.StatusBar { }
}

substitutionPage.menuBar:add({
  filterLabel = UI.Text({
    value = 'Search',
    x = UI.term.width-14,
  }),
  filter = UI.TextEntry({
    x = UI.term.width-7,
    width = 7,
  })
})

function substitutionPage.info:draw()

  local sub = self.parent.sub
  local inName = itemDB:getName({ name = sub.id, damage = sub.dmg })
  local outName = ''
  if sub.sid then
    outName = itemDB:getName({ name = sub.sid, damage = sub.sdmg })
  end

  self:clear()
  self:setCursorPos(1, 1)
  self:print(' Replace ' .. inName .. '\n')
  --self:print('         ' .. sub.id .. ':' .. sub.dmg .. '\n', nil, colors.yellow)
  self:print(' With    ' .. outName)
end

function substitutionPage:enable()

  self.allItems = convertBack(Builder.itemAdapter:refresh())
  self.grid.values = self.allItems
  for _,item in pairs(self.grid.values) do
    item.key = item.id .. ':' .. item.dmg
    item.lname = string.lower(item.display_name)
    item.fQty = Util.toBytes(item.qty)
  end
  self.grid:update()

  self.menuBar.filter.value = ''
  self.menuBar.filter.pos = 1
  self:setFocus(self.menuBar.filter)
  UI.Page.enable(self)
end

--function substitutionPage:focusFirst()
--  self.menuBar.filter:focus()
--end

function substitutionPage:applySubstitute(id, dmg)
  self.sub.sid = id
  self.sub.sdmg = dmg
end

function substitutionPage:eventHandler(event)

  if event.type == 'grid_focus_row' then
    local s = string.format('%s:%d',
      event.selected.id,
      event.selected.dmg)

    self.statusBar:setStatus(s)
    self.statusBar:draw()

  elseif event.type == 'grid_select' then
--    if not item:lookupName(event.selected.id, event.selected.dmg) then
--      blocks.nameDB:add({event.selected.id, event.selected.dmg}, event.selected.name)
--      blocks.nameDB:flush()
--    end

    self:applySubstitute(event.selected.id, event.selected.dmg)
    self.info:draw()

  elseif event.type == 'text_change' then
    local text = event.text
    if #text == 0 then
      self.grid.values = self.allItems
    else
      self.grid.values = { }
      for _,item in pairs(self.allItems) do
        if string.find(item.lname, text) then
          table.insert(self.grid.values, item)
        end
      end
    end
    --self.grid:adjustWidth()
    self.grid:update()
    self.grid:setIndex(1)
    self.grid:draw()

  elseif event.type == 'accept' or event.type == 'air' or event.type == 'revert' then
    self.statusBar:setStatus('Saving changes...')
    self.statusBar:draw()
    self:sync()

    if event.type == 'air' then
      self:applySubstitute('minecraft:air', 0)
    end

    if event.type == 'revert' then
      subDB:remove(self.sub)
    elseif not self.sub.sid then
      self.statusBar:setStatus('Select a substition')
      self.statusBar:draw()
      return UI.Page.eventHandler(self, event)
    else
      subDB:add(self.sub)
    end

    self.throttle:enable()
    Builder:reloadSchematic(function() self.throttle:update() end)
    self.throttle:disable()
    UI:setPage('listing')

  elseif event.type == 'cancel' then
    UI:setPreviousPage()
  end

  return UI.Page.eventHandler(self, event)
end

--[[-- SupplyPage --]]--
supplyPage = UI.Page {
  titleBar = UI.TitleBar {
    title = 'Waiting for supplies',
    previousPage = 'start'
  },
  menuBar = UI.MenuBar {
    y = 2,
    buttons = {
      --{ text = 'Refresh', event = 'refresh', help = 'Refresh inventory' },
      { text = 'Continue',    event = 'build', help = 'Continue building' },
      { text = 'Menu',        event = 'menu',  help = 'Return to main menu' },
--      { text = 'Force Craft', event = 'craft', help = 'Request crafting (again)' },
    }
  },
  grid = UI.Grid {
    columns = {
      { heading = 'Name', key = 'display_name',  width = UI.term.width - 7 },
      { heading = 'Need', key = 'need',  width = 4                 },
    },
    sortColumn = 'display_name',
    y = 3,
    width = UI.term.width,
    height = UI.term.height - 3
  },
  statusBar = UI.StatusBar {
    columns = {
      { 'Help', 'help', UI.term.width - 13 },
      { 'Fuel', 'fuel', 11 }
    }
  },
  accelerators = {
    c = 'craft',
    r = 'refresh',
    b = 'build',
    m = 'menu',
  },
}

function supplyPage:eventHandler(event)

--[[
  if event.type == 'craft' then
    local s = self.grid:getSelected()
    if Builder.itemAdapter:craftItems({{ name = s.id, damage = s.dmg, nbtHash = s.nbt_hash }}, s.need-s.qty) then
      local name = s.display_name or ''
      self.statusBar:timedStatus('Requested ' .. s.need-s.qty .. ' ' .. name, 3)
    else
      self.statusBar:timedStatus('Unable to craft')
    end

  elseif event.type == 'refresh' then
    self:refresh()
]]

  if event.type == 'build' then
    Builder:build()

  elseif event.type == 'menu' then
    Builder:dumpInventory()
    --Builder.status = 'idle'
    UI:setPage('start')
    turtle.status = 'idle'

  elseif event.type == 'grid_focus_row' then
    self.statusBar:setValue('help', event.selected.id .. ':' .. event.selected.dmg)
    self.statusBar:draw()

  elseif event.type == 'focus_change' then
    self.statusBar:timedStatus(event.focused.help, 3)
  end

  return UI.Page.eventHandler(self, event)
end

function supplyPage:enable()
  self.grid:setIndex(1)
  self.statusBar:setValue('fuel',
    string.format('Fuel: %dk', math.floor(turtle.getFuelLevel() / 1024)))
--  self.statusBar:setValue('block',
--   string.format('Block: %d', Builder.index))

  Event.addNamedTimer('supplyRefresh', 6, true, function()
    if self.enabled then
      Builder:autocraft(Builder:getSupplies())
      self:refresh()
      self.statusBar:timedStatus('Refreshed ', 2)
      self:sync()
    end
  end)
  UI.Page.enable(self)
end

function supplyPage:disable()
  Event.cancelNamedTimer('supplyRefresh')
end

function supplyPage:setSupplies(supplies)
  local t = { }
  for _,s in pairs(supplies) do
    local key = s.id .. ':' .. s.dmg
    local entry = t[key]
    if not entry then
      entry = Util.shallowCopy(s)
      t[key] = entry
    else
      entry.need = entry.need + s.need
    end
    entry.need = entry.need - turtle.getItemCount(s.index)
  end

  self.grid:setValues(t)
end

function supplyPage:refresh()
  self.statusBar:timedStatus('Refreshed ', 3)
  local supplies = Builder:getSupplies()
  if #supplies == 0 then
    Builder:build()
  else
    self:setSupplies(supplies)
    self.grid:draw()
  end
end

--[[-- ListingPage --]]--
local listingPage = UI.Page({
  titleBar = UI.TitleBar({
    title = 'Supply List',
    previousPage = 'start'
  }),
  menuBar = UI.MenuBar({
    y = 2,
    buttons = {
      { text = 'Craft',      event = 'craft',   help = 'Request crafting'      },
      { text = 'Refresh',    event = 'refresh', help = 'Refresh inventory'     },
      { text = 'Toggle',     event = 'toggle',  help = 'Toggles needed blocks' },
      { text = 'Substitute', event = 'edit',    help = 'Substitute a block'    },
    }
  }),
  grid = UI.ScrollingGrid({
    columns = {
      { heading = 'Name', key = 'display_name', width = UI.term.width - 14 },
      { heading = 'Need', key = 'need', width = 5                  },
      { heading = 'Have', key = 'qty',  width = 5                  },
    },
    sortColumn = 'display_name',
    y = 3,
    height = UI.term.height-3,
    help = 'Set a block type or pick a substitute block'
  }),
  accelerators = {
    q = 'menu',
    c = 'craft',
    r = 'refresh',
    t = 'toggle',
  },
  statusBar = UI.StatusBar(),
  fullList = true
})

function listingPage:enable(throttle)
  listingPage:refresh(throttle)
  UI.Page.enable(self)
end

function listingPage:eventHandler(event)

  if event.type == 'craft' then
    local s = self.grid:getSelected()
    local item = convertSingleBack(Builder.itemAdapter:getItemInfo({
      name = s.id,
      damage = s.dmg,
      nbtHash = s.nbt_hash,
    }))
    if item and item.is_craftable then
      local qty = math.max(0, s.need - item.qty)

      if item then
        Builder.itemAdapter:craftItems({{ name = s.id, damage = s.dmg, nbtHash = s.nbt_hash, count = qty }})
        local name = s.display_name or s.id
        self.statusBar:timedStatus('Requested ' .. qty .. ' ' .. name, 3)
      end
    else
      self.statusBar:timedStatus('Unable to craft')
    end

   elseif event.type == 'grid_focus_row' then
    self.statusBar:setStatus(event.selected.id .. ':' .. event.selected.dmg)
    self.statusBar:draw()

  elseif event.type == 'refresh' then
    self:refresh()
    self:draw()
    self.statusBar:timedStatus('Refreshed ', 3)

  elseif event.type == 'toggle' then
    self.fullList = not self.fullList
    self:refresh()
    self:draw()

  elseif event.type == 'menu' then
    UI:setPage('start')

  elseif event.type == 'edit' or event.type == 'grid_select' then
    self:manageBlock(self.grid:getSelected())

  elseif event.type == 'focus_change' then
    if event.focused.help then
      self.statusBar:timedStatus(event.focused.help, 3)
    end
  end

  return UI.Page.eventHandler(self, event)
end

function listingPage.grid:getDisplayValues(row)
  row = Util.shallowCopy(row)
  row.need = Util.toBytes(row.need)
  row.qty = Util.toBytes(row.qty)
  return row
end

function listingPage.grid:getRowTextColor(row, selected)
  if row.is_craftable then
    return colors.yellow
  end
  return UI.Grid:getRowTextColor(row, selected)
end

function listingPage:refresh(throttle)

  local supplyList = Builder:getBlockCounts()

  Builder.itemAdapter:refresh(throttle)

  for _,b in pairs(supplyList) do
    if b.need > 0 then
      local item = convertSingleBack(Builder.itemAdapter:getItemInfo({
        name = b.id,
        damage = b.dmg,
        nbtHash = b.nbt_hash,
      }))

      if item then
--        local block = blocks.blockDB:lookup(b.id, b.dmg)
--        if not block then
--          blocks.nameDB:add({b.id, b.dmg}, item.display_name)
--        elseif not block.name and item.display_name then
--          blocks.nameDB:add({b.id, b.dmg}, item.display_name)
--        end
        b.display_name = item.display_name
        b.qty = item.qty
        b.is_craftable = item.is_craftable
      else
        b.display_name = itemDB:getName({ name = b.id, damage = b.dmg })
      end
    end
    if throttle then
      throttle()
    end
  end
  --blocks.nameDB:flush()

  if self.fullList then
    self.grid:setValues(supplyList)
  else
    local t = {}
    for _,b in pairs(supplyList) do
      if self.fullList or b.qty < b.need then
        table.insert(t, b)
      end
    end
    self.grid:setValues(t)
  end
  self.grid:setIndex(1)
end

function listingPage:manageBlock(selected)

  local substitutes = subDB:lookupBlocksForSub(selected.id, selected.dmg)

  if Util.empty(substitutes) then
    substitutionPage.sub = { id = selected.id, dmg = selected.dmg }
    UI:setPage(substitutionPage)
  elseif Util.size(substitutes) == 1 then
    local _,sub = next(substitutes)
    substitutionPage.sub = sub
    UI:setPage(substitutionPage)
  else
    selectSubstitutionPage.selected = selected
    selectSubstitutionPage.grid:setValues(substitutes)
    UI:setPage(selectSubstitutionPage)
  end
end

--[[-- startPage --]]--
local wy = 2
local my = 3

if UI.term.width < 30 then
  wy = 9
  my = 2
end

local startPage = UI.Page {
  window = UI.Window {
    x = UI.term.width-16,
    y = wy,
    width = 16,
    height = 9,
    backgroundColor = colors.gray,
    grid = UI.Grid {
      columns = {
        { heading = 'Name',  key = 'name',  width = 6 },
        { heading = 'Value', key = 'value', width = 7 },
      },
      disableHeader = true,
      x = 1,
      y = 2,
      width = 16,
      height = 9,
      inactive = true,
      backgroundColor = colors.gray
    },
  },
  menu = UI.Menu {
    x = 2,
    y = my,
    height = 7,
    backgroundColor = UI.Page.defaults.backgroundColor,
    menuItems = {
      { prompt = 'Set starting level', event = 'startLevel' },
      { prompt = 'Set starting block', event = 'startBlock' },
      { prompt = 'Supply list',        event = 'assignBlocks' },
      { prompt = 'Toggle mode',        event = 'toggleMode' },
      { prompt = 'Begin',              event = 'begin' },
      { prompt = 'Quit',               event = 'quit' }
    }
  },
  throttle = UI.Throttle { },
  accelerators = {
    x = 'test',
    q = 'quit'
  }
}

function startPage:draw()
  local t = {
    { name = 'mode', value = Builder.mode },
    { name = 'start', value = Builder.index },
    { name = 'blocks', value = #schematic.blocks },
    { name = 'length', value = schematic.length },
    { name = 'width', value = schematic.width },
    { name = 'height', value = schematic.height },
  }

  self.window.grid:setValues(t)
  UI.Page.draw(self)
end

function startPage:enable()
  self:setFocus(self.menu)
  UI.Page.enable(self)
end

function startPage:eventHandler(event)

  if event.type == 'startLevel' then
    local dialog = UI.Dialog({
      title = 'Enter Starting Level',
      height = 7,
      form = UI.Form {
        y = 3, x = 2, height = 4,
        text = UI.Text({ x = 5, y = 1, textColor = colors.gray, value = '0 - ' .. schematic.height }),
        textEntry = UI.TextEntry({ x = 15, y = 1, '0 - 11', width = 7 }),
      },
      statusBar = UI.StatusBar(),
    })

    function dialog:eventHandler(event)
      if event.type == 'form_complete' then
        local l = tonumber(self.form.textEntry.value)
        if l and l < schematic.height and l >= 0 then
          for k,v in pairs(schematic.blocks) do
            if v.y >= l then
              Builder.index = k
              Builder:saveProgress(Builder.index)
              UI:setPreviousPage()
              break
            end
          end
        else
          self.statusBar:timedStatus('Invalid Level', 3)
        end
      elseif event.type == 'form_cancel' or event.type == 'cancel' then
        UI:setPreviousPage()
      else
        return UI.Dialog.eventHandler(self, event)
      end
      return true
    end

    dialog:setFocus(dialog.form.textEntry)
    UI:setPage(dialog)

  elseif event.type == 'startBlock' then
    local dialog = UI.Dialog {
      title = 'Enter Block Number',
      height = 7,
      form = UI.Form {
        y = 3, x = 2, height = 4,
        text = UI.Text { x = 2, y = 1, value = '1 - ' .. #schematic.blocks, textColor = colors.gray },
        textEntry = UI.TextEntry { x = 16, y = 1, value = tostring(Builder.index), width = 10, limit = 8 }
      },
      statusBar = UI.StatusBar(),
    }

    function dialog:eventHandler(event)
      if event.type == 'form_complete' then
        local bn = tonumber(self.form.textEntry.value)
        if bn and bn < #schematic.blocks and bn >= 0 then
          Builder.index = bn
          Builder:saveProgress(Builder.index)
          UI:setPreviousPage()
        else
          self.statusBar:timedStatus('Invalid Block', 3)
        end
      elseif event.type == 'form_cancel' or event.type == 'cancel' then
        UI:setPreviousPage()
      else
        return UI.Dialog.eventHandler(self, event)
      end
      return true
    end

    dialog:setFocus(dialog.form.textEntry)
    UI:setPage(dialog)

  elseif event.type == 'assignBlocks' then
    -- this might be an approximation of the blocks needed
    -- as the current level's route may or may not have been
    -- computed
    Builder:dumpInventory()
    UI:setPage('listing', function() self.throttle:update() end)
    self.throttle:disable()

  elseif event.type == 'toggleMode' then
    if Builder.mode == 'build' then
      if Builder.index == 1 then
        Builder.index = #schematic.blocks
      end
      Builder.mode = 'destroy'
    else
      if Builder.index == #schematic.blocks then
        Builder.index = 1
      end
      Builder.mode = 'build'
    end
    self:draw()

  elseif event.type == 'begin' then
    UI:setPage('blank')

    turtle.status = 'thinking'
    print('Reloading schematic')
    Builder:reloadSchematic(Util.throttle())
    Builder:dumpInventory()
    Builder:refuel()

    if Builder.mode == 'destroy' then
      if device.wireless_modem then
        Message.broadcast('supplyList', { uid = 1, slots = Builder:getAirResupplyList() })
      end
      print('Beginning destruction')
    else
      print('Starting build')
      Builder:getTurtleFacing()
    end

    -- reset piston cache in case wrench was substituted
    pistonFacings = {
      down = { },
      forward = { },
    }

    Builder:build()

  elseif event.type == 'quit' then
    UI.term:reset()
    Event.exitPullEvents()
  end

  return UI.Page.eventHandler(self, event)
end

--[[-- startup logic --]]--
local args = {...}
if #args < 1 then
  error('supply file name')
end

Builder.itemAdapter = MEAdapter()
if not Builder.itemAdapter:isValid() then
  Builder.itemAdapter = ChestAdapter()
  if not Builder.itemAdapter:isValid() then
    error('A chest or ME interface must be below turtle')
  end
end

if commands then
  turtle = {
    policies = { },
    point = { x = -1, y = 0, z = -1, heading = 0 },
    getFuelLevel = function() return 20000 end,
    select = function() end,
    getItemCount = function() return 0 end,
    getHeadingInfo = function(heading)
      local headings = {
        [ 0 ] = { xd =  1, zd =  0, yd =  0, heading = 0, direction = 'east'  },
        [ 1 ] = { xd =  0, zd =  1, yd =  0, heading = 1, direction = 'south' },
        [ 2 ] = { xd = -1, zd =  0, yd =  0, heading = 2, direction = 'west'  },
        [ 3 ] = { xd =  0, zd = -1, yd =  0, heading = 3, direction = 'north' },
        [ 4 ] = { xd =  0, zd =  0, yd =  1, heading = 4, direction = 'up'    },
        [ 5 ] = { xd =  0, zd =  0, yd = -1, heading = 5, direction = 'down'  }
      }
      local namedHeadings = {
        east  = headings[0],
        south = headings[1],
        west  = headings[2],
        north = headings[3],
        up    = headings[4],
        down  = headings[5]
      }
      if heading and type(heading) == 'string' then
        return namedHeadings[heading]
      end
      heading = heading or 0
      return headings[heading]
    end,
  }
end

multishell.setTitle(multishell.getCurrent(), 'Builder v' .. Builder.version)

maxStackDB:load()
subDB:load()

UI.term:reset()
turtle.status = 'reading'
print('Loading schematic')
schematic:load(args[1])
print('Substituting blocks')

Builder:substituteBlocks(Util.throttle())

if not fs.exists(BUILDER_DIR) then
  fs.makeDir(BUILDER_DIR)
end

Builder:loadProgress(schematic.filename .. '.progress')

UI:setPages({
  listing = listingPage,
  start = startPage,
  supply = supplyPage,
  blank = blankPage
})

UI:setPage('start')

if Builder.isCommandComputer then
  Event.pullEvents()
else
  turtle.run(function()
    turtle.setPolicy(turtle.policies.digAttack)
    turtle.setPoint(SUPPLIES_PT)
    turtle.point.heading = 0
    UI:pullEvents()
  end)
end
