_G.requireInjector(_ENV)

local Peripheral = require('peripheral')
local Point      = require('point')
local Util       = require('util')

local device = _G.device
local os     = _G.os
local turtle = _G.turtle

local args = { ... }
local mob = args[1] or error('Syntax: attack <mob name>')

local function equip(side, item, rawName)
	local equipped = Peripheral.lookup('side/' .. side)

	if equipped and equipped.type == item then
		return true
	end

	if not turtle.equip(side, rawName or item) then
		if not turtle.selectSlotWithQuantity(0) then
			error('No slots available')
		end
		turtle.equip(side)
		if not turtle.equip(side, item) then
			error('Unable to equip ' .. item)
		end
	end

	turtle.select(1)
end

equip('left', 'minecraft:diamond_sword')

equip('right', 'plethora:scanner', 'plethora:module:2')
local scanner = device['plethora:scanner']
local facing = scanner.getBlockMeta(0, 0, 0).state.facing
turtle.point.heading = Point.facings[facing].heading

local scanned = scanner.scan()
local chest = Util.find(scanned, 'name', 'minecraft:chest')
if chest then
	chest.x = Util.round(chest.x) + turtle.point.x
	chest.y = Util.round(chest.y) + turtle.point.y
	chest.z = Util.round(chest.z) + turtle.point.z
end

equip('right', 'plethora:sensor', 'plethora:module:3')

local sensor = device['plethora:sensor']

turtle.setMovementStrategy('goto')

local function dropOff()
	if not chest then
		return
	end
	local inv = turtle.getSummedInventory()
	for _, slot in pairs(inv) do
		if slot.count >= 16 then
			turtle.dropDownAt(chest, slot.name)
		end
	end
end


while true do
	local blocks = sensor.sense()
	local mobs = Util.filterInplace(blocks, function(b)
		if b.name == mob then
			b.x = Util.round(b.x) + turtle.point.x
			b.y = Util.round(b.y) + turtle.point.y
			b.z = Util.round(b.z) + turtle.point.z
			return true
		end
	end)

	if turtle.getFuelLevel() == 0 then
		error('Out of fuel')
	end

	if #mobs == 0 then
		os.sleep(3)
	else
		Point.eachClosest(turtle.point, mobs, function(b)
			repeat until not turtle.attackAt(b)
		end)
	end

	dropOff()
end