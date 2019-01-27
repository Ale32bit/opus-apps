local Craft  = require('milo.craft2')
local Milo   = require('milo')
local Sound  = require('sound')
local Util   = require('util')

local context = Milo:getContext()

local craftTask = {
  name = 'crafting',
  priority = 70,
}

function craftTask:craft(recipe, item)
  if Milo:isCraftingPaused() then
    return
  end

  -- TODO: refactor into craft.lua
  Craft.processPending(item, context.storage)

  -- create a mini-list of items that are required for this recipe
  item.ingredients = Craft.getResourceList(
    recipe, Milo:listItems(), item.requested - item.crafted, item.pending)

  for k, v in pairs(item.ingredients) do
    v.crafted = v.used
    v.count = v.used
    v.key = k
    if v.need > 0 then
      v.status = 'No recipe'
      v.statusCode = Craft.STATUS_ERROR
    end
  end
  item.ingredients[recipe.result] = item
  item.ingredients[recipe.result].total = item.count
  item.ingredients[recipe.result].crafted = item.crafted

  Craft.craftRecipe(recipe, item.requested - item.crafted, context.storage, item)
end

function craftTask:cycle()
  for _,key in pairs(Util.keys(context.craftingQueue)) do
    local item = context.craftingQueue[key]
    if item.requested - item.crafted > 0 then
      local recipe = Craft.findRecipe(key)
      if recipe then

        if not item.notified then
          Sound.play('block.end_portal_frame.fill')
          item.notified = true
        end

        self:craft(recipe, item)

        if item.crafted >= item.requested then
          item.status = 'crafted'
          item.statusCode = Craft.STATUS_SUCCESS
          if item.callback then
            item.callback(item) -- invoke callback
          end
        end

      else
        item.status = '(no recipe)'
        item.statusCode = Craft.STATUS_ERROR
        item.crafted = 0
      end
    end
  end
end

Milo:registerTask(craftTask)