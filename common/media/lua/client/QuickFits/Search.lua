---@diagnostic disable: undefined-global

require "QuickFits/Localization"

QuickFits = QuickFits or {}
QuickFits.Search = QuickFits.Search or {}

local Search = QuickFits.Search
local Localization = QuickFits.Localization

local isFloorContainer

isFloorContainer = function(container)
    return container and string.lower(tostring(container:getType() or "")) == "floor"
end

local function getContainerType(container)
    if not container then
        return ""
    end

    local okType, rawType = pcall(function()
        return container:getType()
    end)
    return string.lower(tostring(okType and rawType or ""))
end

local function isPseudoLootAggregate(container)
    local containerType = getContainerType(container)
    return containerType == "proxinv"
        or containerType == "proximityinventory"
        or containerType == "lootwindow"
end

local function canTraverseItemInventory(item)
    if not item then
        return false
    end
    return instanceof and instanceof(item, "InventoryContainer") or false
end

local function getNestedInventory(item)
    if not canTraverseItemInventory(item) then
        return nil
    end

    return item:getInventory()
end

local function eachItemRecursive(container, callback)
    if not container then
        return nil
    end

    local items = container:getItems()
    if not items then
        return nil
    end

    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local result = callback(item)
        if result then
            return result
        end

        local nestedInventory = getNestedInventory(item)
        if nestedInventory then
            result = eachItemRecursive(nestedInventory, callback)
            if result then
                return result
            end
        end
    end

    return nil
end

local function getItemDurabilityFraction(item)
    if not item then
        return -1
    end

    local okConditionMax, conditionMax = pcall(function()
        return item:getConditionMax()
    end)
    if not okConditionMax or not conditionMax or conditionMax <= 0 then
        return -1
    end

    local okCondition, condition = pcall(function()
        return item:getCondition()
    end)
    if not okCondition or condition == nil then
        return -1
    end

    return condition / conditionMax
end

local function getItemDurabilityValue(item)
    local okCondition, condition = pcall(function()
        return item:getCondition()
    end)
    if not okCondition or condition == nil then
        return -1
    end
    return condition
end

local function isPreferredMatch(candidate, currentBest)
    if not candidate then
        return false
    end
    if not currentBest then
        return true
    end

    local candidateFraction = getItemDurabilityFraction(candidate)
    local bestFraction = getItemDurabilityFraction(currentBest)
    if candidateFraction ~= bestFraction then
        return candidateFraction > bestFraction
    end

    local candidateValue = getItemDurabilityValue(candidate)
    local bestValue = getItemDurabilityValue(currentBest)
    if candidateValue ~= bestValue then
        return candidateValue > bestValue
    end

    local candidateWeight = candidate:getUnequippedWeight()
    local bestWeight = currentBest:getUnequippedWeight()
    if candidateWeight ~= bestWeight then
        return candidateWeight < bestWeight
    end

    return false
end

local function addContainer(containers, seen, container)
    if not container then
        return
    end

    if isPseudoLootAggregate(container) then
        return
    end

    if seen[container] then
        return
    end

    seen[container] = true
    table.insert(containers, container)
end

local function addBackpackInventories(containers, seen, backpacks, playerInventory)
    for _, backpack in ipairs(backpacks or {}) do
        local container = backpack and backpack.inventory or nil
        if container and container ~= playerInventory then
            addContainer(containers, seen, container)
        end
    end
end

local function addPlacementCandidate(candidates, seen, container, source)
    if not container or seen[container] then
        return
    end

    if isPseudoLootAggregate(container) then
        return
    end

    seen[container] = true
    table.insert(candidates, {
        container = container,
        source = source,
    })
end

local function addContainersFromObject(containers, seen, object)
    local okSingle, singleContainer = pcall(function()
        return object:getContainer()
    end)
    if okSingle and singleContainer then
        addContainer(containers, seen, singleContainer)
    end

    local okCount, containerCount = pcall(function()
        return object:getContainerCount()
    end)
    if okCount and containerCount and containerCount > 0 then
        for index = 0, containerCount - 1 do
            local okIndexed, indexedContainer = pcall(function()
                return object:getContainerByIndex(index)
            end)
            if okIndexed and indexedContainer then
                addContainer(containers, seen, indexedContainer)
            end
        end
    end
end

local function addContainersFromWorldObject(containers, seen, worldObject)
    local okItem, item = pcall(function()
        return worldObject:getItem()
    end)
    if not okItem or not item then
        return
    end

    local okContainer, container = pcall(function()
        return item:getContainer()
    end)
    if okContainer and container then
        addContainer(containers, seen, container)
    end
end

local function addPlacementContainerFromWorldObject(containers, seen, worldObject)
    local okItem, item = pcall(function()
        return worldObject:getItem()
    end)
    if not okItem or not item or not canTraverseItemInventory(item) then
        return
    end

    local okInventory, inventory = pcall(function()
        return item:getInventory()
    end)
    if okInventory and inventory then
        addContainer(containers, seen, inventory)
    end
end

local function visitNearbySquares(playerObj, radius, visitor)
    local square = playerObj:getCurrentSquare()
    if not square then
        return
    end

    local searchRadius = radius or 2
    local z = square:getZ()

    local function visitSquare(worldX, worldY)
        local targetSquare = getCell():getGridSquare(worldX, worldY, z)
        if targetSquare then
            visitor(targetSquare)
        end
    end

    visitSquare(square:getX(), square:getY())

    for step = 1, searchRadius do
        local minX = square:getX() - step
        local maxX = square:getX() + step
        local minY = square:getY() - step
        local maxY = square:getY() + step

        for worldX = minX, maxX do
            visitSquare(worldX, minY)
            visitSquare(worldX, maxY)
        end
        for worldY = minY + 1, maxY - 1 do
            visitSquare(minX, worldY)
            visitSquare(maxX, worldY)
        end
    end
end

function Search.getNearbyContainers(playerObj, radius)
    local containers = {}
    local seen = {}

    local playerInventory = playerObj:getInventory()
    seen[playerInventory] = true

    visitNearbySquares(playerObj, radius, function(targetSquare)
        local objects = targetSquare:getObjects()
        for index = 0, objects:size() - 1 do
            addContainersFromObject(containers, seen, objects:get(index))
        end

        local worldObjects = targetSquare:getWorldObjects()
        for index = 0, worldObjects:size() - 1 do
            addContainersFromWorldObject(containers, seen, worldObjects:get(index))
        end
    end)

    return containers
end

function Search.getNearbyItemContainers(playerObj, radius)
    local containers = {}
    local seen = {}
    seen[playerObj:getInventory()] = true

    visitNearbySquares(playerObj, radius, function(targetSquare)
        local worldObjects = targetSquare:getWorldObjects()
        for index = 0, worldObjects:size() - 1 do
            addPlacementContainerFromWorldObject(containers, seen, worldObjects:get(index))
        end
    end)

    return containers
end

function Search.getSelectedLootContainer(playerObj)
    local playerNum = playerObj:getPlayerNum()
    local ok, lootWindow = pcall(function()
        return getPlayerLoot(playerNum)
    end)
    if not ok or not lootWindow or not lootWindow.inventoryPane then
        return nil
    end

    local container = lootWindow.inventoryPane.inventory
    if not container or container == playerObj:getInventory() then
        return nil
    end
    if isPseudoLootAggregate(container) then
        return nil
    end
    if isFloorContainer(container) then
        return nil
    end
    return container
end

function Search.getReachableLootContainers(playerObj)
    local containers = {}
    local seen = {}
    local playerInventory = playerObj and playerObj:getInventory() or nil

    if playerInventory then
        seen[playerInventory] = true
    end

    local playerNum = playerObj and playerObj:getPlayerNum() or -1
    local ok, lootWindow = pcall(function()
        return getPlayerLoot(playerNum)
    end)
    if not ok or not lootWindow or not lootWindow.inventoryPane or not lootWindow.inventoryPane.inventoryPage then
        return containers
    end

    addBackpackInventories(containers, seen, lootWindow.inventoryPane.inventoryPage.backpacks, playerInventory)
    return containers
end

function Search.resolvePlacementContainer(playerObj)
    local selectedContainer = Search.getSelectedLootContainer(playerObj)
    if selectedContainer then
        return selectedContainer, "selected"
    end

    for _, container in ipairs(Search.getReachableLootContainers(playerObj)) do
        return container, "loot-window"
    end

    for _, container in ipairs(Search.getNearbyContainers(playerObj, 2)) do
        if not isFloorContainer(container) then
            return container, "nearby"
        end
    end

    for _, container in ipairs(Search.getNearbyItemContainers(playerObj, 2)) do
        return container, "ground-item"
    end

    return nil, nil
end

function Search.getPlacementCandidates(playerObj)
    local candidates = {}
    local seen = {}

    local selectedContainer = Search.getSelectedLootContainer(playerObj)
    if selectedContainer then
        addPlacementCandidate(candidates, seen, selectedContainer, "selected")
    end

    for _, container in ipairs(Search.getReachableLootContainers(playerObj)) do
        addPlacementCandidate(candidates, seen, container, "loot-window")
    end

    local floorCandidates = {}
    for _, container in ipairs(Search.getNearbyContainers(playerObj, 2)) do
        if isFloorContainer(container) then
            addPlacementCandidate(floorCandidates, seen, container, "floor")
        else
            addPlacementCandidate(candidates, seen, container, "nearby")
        end
    end

    for _, container in ipairs(Search.getNearbyItemContainers(playerObj, 2)) do
        addPlacementCandidate(candidates, seen, container, "ground-item")
    end

    for _, candidate in ipairs(floorCandidates) do
        table.insert(candidates, candidate)
    end

    return candidates
end

function Search.getExternalSearchContainers(playerObj)
    local containers = {}
    local seen = {}

    local selectedContainer = Search.getSelectedLootContainer(playerObj)
    if selectedContainer then
        addContainer(containers, seen, selectedContainer)
    end

    for _, container in ipairs(Search.getReachableLootContainers(playerObj)) do
        addContainer(containers, seen, container)
    end

    local floorContainers = {}
    for _, container in ipairs(Search.getNearbyContainers(playerObj, 2)) do
        if isFloorContainer(container) then
            addContainer(floorContainers, seen, container)
        else
            addContainer(containers, seen, container)
        end
    end

    for _, container in ipairs(Search.getNearbyItemContainers(playerObj, 2)) do
        addContainer(containers, seen, container)
    end

    for _, container in ipairs(floorContainers) do
        table.insert(containers, container)
    end

    return containers
end

function Search.getContainerLabel(container)
    if not container then
        return Localization.getText("container_generic")
    end

    local containingItem = nil
    local ok, result = pcall(function()
        return container:getContainingItem()
    end)
    if ok then
        containingItem = result
    end
    if containingItem then
        return containingItem:getDisplayName()
    end

    local containerType = tostring(container:getType() or "")
    if containerType == "" then
        return Localization.getText("container_nearby")
    end
    return containerType
end

function Search.findPlayerOwnedItem(playerObj, descriptor, reservedItems)
    return Search.findItemByDescriptor(playerObj:getInventory(), descriptor, reservedItems)
end

function Search.findItemByDescriptor(container, descriptor, reservedItems)
    local bestMatch = nil

    eachItemRecursive(container, function(item)
        if reservedItems[item] then
            return nil
        end

        if item:getFullType() == descriptor.fullType then
            if isPreferredMatch(item, bestMatch) then
                bestMatch = item
            end
        end
        return nil
    end)

    return bestMatch
end

function Search.findBestItemInContainers(containers, descriptor, reservedItems)
    local bestMatch = nil

    for _, container in ipairs(containers or {}) do
        local candidate = Search.findItemByDescriptor(container, descriptor, reservedItems)
        if isPreferredMatch(candidate, bestMatch) then
            bestMatch = candidate
        end
    end

    return bestMatch
end

function Search.resolveItem(playerObj, descriptor, reservedItems)
    reservedItems = reservedItems or {}

    local inventoryItem = Search.findItemByDescriptor(playerObj:getInventory(), descriptor, reservedItems)
    if inventoryItem then
        return inventoryItem, "inventory"
    end

    local selectedContainer = Search.getSelectedLootContainer(playerObj)
    if selectedContainer then
        local selectedItem = Search.findItemByDescriptor(selectedContainer, descriptor, reservedItems)
        if selectedItem then
            return selectedItem, "selected"
        end
    end

    local reachableLootContainers = Search.getReachableLootContainers(playerObj)
    local lootWindowItem = Search.findBestItemInContainers(reachableLootContainers, descriptor, reservedItems)
    if lootWindowItem then
        return lootWindowItem, "loot-window"
    end

    local nearbyContainers = Search.getNearbyContainers(playerObj, 2)
    local nearbyPool = {}
    local groundPool = {}

    for _, container in ipairs(nearbyContainers) do
        if not isFloorContainer(container) then
            table.insert(nearbyPool, container)
        else
            table.insert(groundPool, container)
        end
    end

    local externalItem = Search.findBestItemInContainers(nearbyPool, descriptor, reservedItems)
    if externalItem then
        return externalItem, "nearby"
    end

    local floorItem = Search.findBestItemInContainers(groundPool, descriptor, reservedItems)
    if floorItem then
        return floorItem, "ground"
    end

    return nil, nil
end

function Search.resolveExternalItem(playerObj, descriptor, reservedItems)
    reservedItems = reservedItems or {}

    local bestMatch = Search.findBestItemInContainers(Search.getExternalSearchContainers(playerObj), descriptor,
        reservedItems)
    if bestMatch then
        return bestMatch, "external"
    end

    return nil, nil
end
