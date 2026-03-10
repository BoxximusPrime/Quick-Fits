---@diagnostic disable: undefined-global

require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISWearClothing"
require "TimedActions/ISUnequipAction"
require "QuickFits/Localization"
require "QuickFits/Search"
require "QuickFits/Capture"

QuickFits = QuickFits or {}
QuickFits.Apply = QuickFits.Apply or {}

local Apply = QuickFits.Apply
local Localization = QuickFits.Localization
local Search = QuickFits.Search
local Capture = QuickFits.Capture

Apply.lastWearProgress = nil

local function isContainerLikeItem(item)
    return item and instanceof and instanceof(item, "InventoryContainer") or false
end

local function isContainerLikeDescriptor(descriptor)
    local bodyLocation = string.lower(tostring(descriptor and descriptor.bodyLocation or ""))
    if bodyLocation == "back" then
        return true
    end

    local function hasBagHint(value)
        local text = string.lower(tostring(value or ""))
        return string.find(text, "backpack", 1, true)
            or string.find(text, "satchel", 1, true)
            or string.find(text, "fannypack", 1, true)
            or string.find(text, "webbing", 1, true)
            or string.find(text, "bag", 1, true)
            or string.find(text, "pack", 1, true)
    end

    return hasBagHint(descriptor and descriptor.displayName)
        or hasBagHint(descriptor and descriptor.fullType)
        or hasBagHint(descriptor and descriptor.itemType)
        or false
end

local function buildOrderedDescriptors(items)
    local ordered = {}
    for _, descriptor in ipairs(items or {}) do
        table.insert(ordered, descriptor)
    end

    table.sort(ordered, function(left, right)
        local leftIsContainer = isContainerLikeDescriptor(left)
        local rightIsContainer = isContainerLikeDescriptor(right)
        if leftIsContainer ~= rightIsContainer then
            return not leftIsContainer
        end

        local leftName = string.lower(tostring(left.displayName or left.fullType or ""))
        local rightName = string.lower(tostring(right.displayName or right.fullType or ""))
        return leftName < rightName
    end)

    return ordered
end

local function sortPlansWithContainersLast(plans)
    table.sort(plans, function(left, right)
        local leftIsContainer = left.isContainerLike == true
        local rightIsContainer = right.isContainerLike == true
        if leftIsContainer ~= rightIsContainer then
            return not leftIsContainer
        end

        local leftName = string.lower(tostring(left.displayName or left.fullType or ""))
        local rightName = string.lower(tostring(right.displayName or right.fullType or ""))
        return leftName < rightName
    end)
end

local function getWornState(playerObj)
    local entries = {}
    local byFullType = {}
    local byLocation = {}
    local wornItems = playerObj:getWornItems()

    for index = 0, wornItems:size() - 1 do
        local wornItem = wornItems:get(index)
        local item = wornItem and wornItem:getItem() or nil
        if item and Capture.isSupportedWearableItem(item) and not Capture.shouldIgnoreWornItem(wornItem, item) then
            local entry = {
                item = item,
                fullType = item:getFullType(),
                displayName = item:getDisplayName(),
                bodyLocation = tostring(wornItem:getLocation() or ""),
            }
            table.insert(entries, entry)
            byFullType[entry.fullType] = entry
            if entry.bodyLocation ~= "" then
                byLocation[entry.bodyLocation] = entry
            end
        end
    end

    return entries, byFullType, byLocation
end

local function queueTransferIfNeeded(playerObj, playerNum, item)
    local playerInventory = playerObj:getInventory()
    local container = item:getContainer()
    if not container or container == playerInventory then
        return
    end

    luautils.walkToContainer(container, playerNum)
    ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, container, playerInventory))
end

local function queueWear(playerObj, playerNum, item)
    queueTransferIfNeeded(playerObj, playerNum, item)
    ISTimedActionQueue.add(ISWearClothing:new(playerObj, item, 50))
end

local function queueUnequip(playerObj, item)
    ISTimedActionQueue.add(ISUnequipAction:new(playerObj, item, 50))
end

local function itemNeedsUnequip(playerObj, item)
    if not playerObj or not item then
        return false
    end

    if playerObj:isEquipped(item) then
        return true
    end

    local okEquippedClothing, equippedClothing = pcall(function()
        return playerObj:isEquippedClothing(item)
    end)
    if okEquippedClothing and equippedClothing then
        return true
    end

    local okAttached, attached = pcall(function()
        return playerObj:isAttachedItem(item)
    end)
    if okAttached and attached then
        return true
    end

    local okIsWorn, isWorn = pcall(function()
        return item:isWorn()
    end)
    if okIsWorn and isWorn then
        return true
    end

    local okItemEquipped, itemEquipped = pcall(function()
        return item:isEquipped()
    end)
    if okItemEquipped and itemEquipped then
        return true
    end

    local wornItems = playerObj:getWornItems()
    if wornItems then
        local okContains, containsItem = pcall(function()
            return wornItems:contains(item)
        end)
        if okContains and containsItem then
            return true
        end
    end

    return false
end

local function queueMoveToContainer(playerObj, playerNum, item, targetContainer, sourceContainer)
    sourceContainer = sourceContainer or item:getContainer()
    if not sourceContainer or sourceContainer == targetContainer then
        return
    end

    luautils.walkToContainer(targetContainer, playerNum)
    ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, sourceContainer,
        targetContainer))
end

local function summarizeMissing(descriptor, list)
    table.insert(list, descriptor.displayName or descriptor.fullType)
end

local function buildWearPlans(playerObj, outfit, wornByType, wornByLocation)
    local reservedItems = {}
    local equipPlans = {}
    local missing = {}
    local blocked = {}

    for _, descriptor in ipairs(buildOrderedDescriptors(outfit.items)) do
        if not wornByType[descriptor.fullType] then
            local blocker = descriptor.bodyLocation ~= "" and wornByLocation and wornByLocation[descriptor.bodyLocation] or
                nil
            if blocker and blocker.fullType ~= descriptor.fullType then
                table.insert(blocked, blocker.displayName or blocker.fullType)
            else
                local item = Search.resolveItem(playerObj, descriptor, reservedItems)
                if item and Capture.isSupportedWearableItem(item) then
                    reservedItems[item] = true
                    table.insert(equipPlans, {
                        item = item,
                        descriptor = descriptor,
                        displayName = descriptor.displayName or item:getDisplayName(),
                        fullType = descriptor.fullType,
                        isContainerLike = isContainerLikeItem(item),
                    })
                else
                    summarizeMissing(descriptor, missing)
                end
            end
        end
    end

    sortPlansWithContainersLast(equipPlans)
    return equipPlans, missing, blocked
end

local function setActionProgress(outfit, mode, entries, targetContainer)
    if not outfit or not entries or #entries == 0 then
        Apply.lastWearProgress = nil
        return
    end

    Apply.lastWearProgress = {
        outfitId = outfit.id,
        outfitName = outfit.name,
        mode = mode,
        entries = entries,
        total = #entries,
        targetContainer = targetContainer,
    }
end

function Apply.consumeLastWearProgress()
    local progress = Apply.lastWearProgress
    Apply.lastWearProgress = nil
    return progress
end

function Apply.isOutfitFullyWorn(playerObj, outfit)
    local _, wornByType = getWornState(playerObj)
    for _, descriptor in ipairs(outfit.items or {}) do
        if not wornByType[descriptor.fullType] then
            return false
        end
    end
    return true
end

function Apply.applyReplacement(playerObj, outfit)
    local playerNum = playerObj:getPlayerNum()
    local wornEntries, wornByType = getWornState(playerObj)
    local keepTypes = {}
    local equippedCount = 0
    local removedCount = 0

    for _, descriptor in ipairs(outfit.items or {}) do
        keepTypes[descriptor.fullType] = true
    end

    for _, entry in ipairs(wornEntries) do
        if not keepTypes[entry.fullType] then
            queueUnequip(playerObj, entry.item)
            removedCount = removedCount + 1
        end
    end

    local equipPlans, missing = buildWearPlans(playerObj, outfit, wornByType)
    setActionProgress(outfit, "wear", equipPlans)
    for _, plan in ipairs(equipPlans) do
        queueWear(playerObj, playerNum, plan.item)
        equippedCount = equippedCount + 1
    end

    return {
        action = "wear",
        removed = removedCount,
        equipped = equippedCount,
        missing = missing,
        blocked = {},
    }
end

function Apply.applyAdditive(playerObj, outfit)
    local playerNum = playerObj:getPlayerNum()
    local _, wornByType, wornByLocation = getWornState(playerObj)
    local equippedCount = 0
    local removedCount = 0

    local reservedItems = {}
    local equipPlans = {}
    local missing = {}
    local removedItems = {}

    for _, descriptor in ipairs(buildOrderedDescriptors(outfit.items)) do
        if not wornByType[descriptor.fullType] then
            local blocker = descriptor.bodyLocation ~= "" and wornByLocation[descriptor.bodyLocation] or nil
            if blocker and blocker.fullType ~= descriptor.fullType and not removedItems[blocker.item] then
                queueUnequip(playerObj, blocker.item)
                removedItems[blocker.item] = true
                removedCount = removedCount + 1
                wornByType[blocker.fullType] = nil
                if blocker.bodyLocation ~= "" then
                    wornByLocation[blocker.bodyLocation] = nil
                end
            end

            local item = Search.resolveItem(playerObj, descriptor, reservedItems)
            if item and Capture.isSupportedWearableItem(item) then
                reservedItems[item] = true
                table.insert(equipPlans, {
                    item = item,
                    descriptor = descriptor,
                    displayName = descriptor.displayName or item:getDisplayName(),
                    fullType = descriptor.fullType,
                    isContainerLike = isContainerLikeItem(item),
                })
            else
                summarizeMissing(descriptor, missing)
            end
        end
    end

    sortPlansWithContainersLast(equipPlans)
    setActionProgress(outfit, "wear", equipPlans)
    for _, plan in ipairs(equipPlans) do
        queueWear(playerObj, playerNum, plan.item)
        equippedCount = equippedCount + 1
    end

    return {
        action = "add",
        removed = removedCount,
        equipped = equippedCount,
        missing = missing,
        blocked = {},
    }
end

function Apply.placeOutfitInContainer(playerObj, outfit)
    if not playerObj then
        return nil, Localization.getText("error_no_player")
    end
    if not outfit then
        return nil, Localization.getText("error_select_outfit_first")
    end

    local targetContainer, targetSource = Search.resolvePlacementContainer(playerObj)
    if not targetContainer then
        return nil, Localization.getText("error_no_container")
    end

    local playerNum = playerObj:getPlayerNum()
    local reservedItems = {}
    local transferPlan = {}
    local moved = 0
    local missing = {}

    for _, descriptor in ipairs(buildOrderedDescriptors(outfit.items)) do
        local item = Search.findPlayerOwnedItem(playerObj, descriptor, reservedItems)
        if item then
            local needsUnequip = itemNeedsUnequip(playerObj, item)
            reservedItems[item] = true
            table.insert(transferPlan, {
                item = item,
                needsUnequip = needsUnequip,
                displayName = descriptor.displayName or item:getDisplayName(),
                fullType = descriptor.fullType,
                isContainerLike = isContainerLikeItem(item),
                sourceContainer = needsUnequip and playerObj:getInventory() or item:getContainer(),
            })
        else
            summarizeMissing(descriptor, missing)
        end
    end

    sortPlansWithContainersLast(transferPlan)
    setActionProgress(outfit, "container", transferPlan, targetContainer)

    for _, plan in ipairs(transferPlan) do
        queueMoveToContainer(playerObj, playerNum, plan.item, targetContainer, plan.sourceContainer)
        moved = moved + 1
    end

    return {
        action = "place",
        transferred = moved,
        targetLabel = Search.getContainerLabel(targetContainer),
        targetSource = targetSource,
        missing = missing,
        blocked = {},
    }
end

function Apply.removeOutfitToInventory(playerObj, outfit)
    if not playerObj then
        return nil, Localization.getText("error_no_player")
    end
    if not outfit then
        return nil, Localization.getText("error_select_outfit_first")
    end

    local wornEntries = getWornState(playerObj)
    local removeTypes = {}
    local removeEntries = {}
    local removedCount = 0

    for _, descriptor in ipairs(outfit.items or {}) do
        removeTypes[descriptor.fullType] = true
    end

    for _, entry in ipairs(wornEntries) do
        if removeTypes[entry.fullType] then
            table.insert(removeEntries, { item = entry.item })
            queueUnequip(playerObj, entry.item)
            removedCount = removedCount + 1
        end
    end

    setActionProgress(outfit, "inventory", removeEntries)

    return {
        action = "remove",
        removed = removedCount,
        equipped = 0,
        missing = {},
        blocked = {},
    }
end

function Apply.wearOutfit(playerObj, outfit)
    if not playerObj then
        return nil, Localization.getText("error_no_player")
    end
    if not outfit then
        return nil, Localization.getText("error_select_outfit_first")
    end

    return Apply.applyReplacement(playerObj, outfit)
end

function Apply.addOutfit(playerObj, outfit)
    if not playerObj then
        return nil, Localization.getText("error_no_player")
    end
    if not outfit then
        return nil, Localization.getText("error_select_outfit_first")
    end

    return Apply.applyAdditive(playerObj, outfit)
end

function Apply.applyOutfit(playerObj, outfit)
    return Apply.wearOutfit(playerObj, outfit)
end
