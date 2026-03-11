---@diagnostic disable: undefined-global

require "QuickFits/Data"

QuickFits = QuickFits or {}
QuickFits.Capture = QuickFits.Capture or {}

local Capture = QuickFits.Capture
local Data = QuickFits.Data

local IGNORED_BODY_LOCATIONS = {
    ["transmogde:transmog_location"] = true,
    ["transmogde:hide_everything_location"] = true,
}

local function startsWithTransmogPrefix(value)
    local text = string.lower(tostring(value or ""))
    return string.sub(text, 1, 10) == "transmogde" or string.sub(text, 1, 5) == "tmog:"
end

local function bodyLocationToString(location)
    if location == nil then
        return ""
    end
    return tostring(location)
end

local function isMakeupBodyLocation(location)
    local normalized = string.lower(bodyLocationToString(location))
    return normalized:find("makeup", 1, true) ~= nil
end

local function isIgnoredWearLocation(location)
    local normalized = string.lower(bodyLocationToString(location))
    if normalized == "" then
        return false
    end

    if IGNORED_BODY_LOCATIONS[normalized] then
        return true
    end

    return normalized:find("makeup", 1, true) ~= nil
        or normalized:find("hair", 1, true) ~= nil
        or normalized:find("beard", 1, true) ~= nil
        or normalized:find("stubble", 1, true) ~= nil
        or normalized:find("moustache", 1, true) ~= nil
        or normalized:find("mustache", 1, true) ~= nil
        or normalized:find("eyebrow", 1, true) ~= nil
        or normalized:find("eyelash", 1, true) ~= nil
        or normalized:find("bodyhair", 1, true) ~= nil
        or normalized:find("tattoo", 1, true) ~= nil
end

local function isMakeupItem(item)
    if not item then
        return false
    end

    if item.getMakeUpType and item:getMakeUpType() then
        return true
    end

    local bodyLocation = ""
    if item.getBodyLocation then
        bodyLocation = tostring(item:getBodyLocation() or "")
    end
    if isMakeupBodyLocation(bodyLocation) then
        return true
    end

    local itemType = string.lower(tostring(item.getType and item:getType() or ""))
    local fullType = string.lower(tostring(item.getFullType and item:getFullType() or ""))
    return itemType:find("makeup", 1, true) ~= nil
        or fullType:find("makeup", 1, true) ~= nil
        or itemType == "lipstick"
        or fullType:find("lipstick", 1, true) ~= nil
end

local function hasScriptDefinition(item)
    if not item or not item.getFullType or not ScriptManager or not ScriptManager.instance then
        return false
    end

    local fullType = tostring(item:getFullType() or "")
    if fullType == "" then
        return false
    end

    local ok, scriptItem = pcall(function()
        return ScriptManager.instance:FindItem(fullType)
    end)

    return ok and scriptItem ~= nil
end

local function isSupportedWearableItem(item)
    if not item then
        return false
    end

    if not hasScriptDefinition(item) then
        return false
    end

    if (item.IsClothing and item:IsClothing()) or (instanceof and instanceof(item, "Clothing")) then
        return true
    end

    if item.IsInventoryContainer and item:IsInventoryContainer() then
        local canEquip = tostring(item:canBeEquipped() or "")
        return canEquip ~= "" and canEquip ~= "nil"
    end

    if instanceof and instanceof(item, "AlarmClockClothing") then
        local canEquip = tostring(item:canBeEquipped() or "")
        return canEquip ~= "" and canEquip ~= "nil"
    end

    return false
end

local getItemBodyLocation

local function shouldIgnoreWornItem(wornItem, item)
    local bodyLocation = string.lower(bodyLocationToString(wornItem and wornItem:getLocation() or nil))
    if isIgnoredWearLocation(bodyLocation) then
        return true
    end

    if not isSupportedWearableItem(item) then
        return true
    end

    local sanitizedBodyLocation = getItemBodyLocation(item)
    if sanitizedBodyLocation == "" or isIgnoredWearLocation(sanitizedBodyLocation) then
        return true
    end

    if isMakeupBodyLocation(bodyLocation) or isMakeupItem(item) then
        return true
    end

    local displayName = tostring(item and item:getDisplayName() or "")
    if startsWithTransmogPrefix(displayName) then
        return true
    end

    local fullType = item and item.getFullType and item:getFullType() or ""
    if startsWithTransmogPrefix(fullType) then
        return true
    end

    local itemType = item and item.getType and item:getType() or ""
    if startsWithTransmogPrefix(itemType) then
        return true
    end

    return false
end

function Capture.shouldIgnoreWornItem(wornItem, item)
    return shouldIgnoreWornItem(wornItem, item)
end

function Capture.isSupportedWearableItem(item)
    return isSupportedWearableItem(item)
end

local function sortDraftItems(items)
    table.sort(items, function(a, b)
        local leftLocation = string.lower(tostring(a.bodyLocation or ""))
        local rightLocation = string.lower(tostring(b.bodyLocation or ""))
        if leftLocation == rightLocation then
            return string.lower(tostring(a.displayName or a.fullType or "")) <
                string.lower(tostring(b.displayName or b.fullType or ""))
        end
        return leftLocation < rightLocation
    end)
end

getItemBodyLocation = function(item)
    if not item then
        return ""
    end

    if isMakeupItem(item) or not isSupportedWearableItem(item) then
        return ""
    end

    local location = ""
    if (item.IsClothing and item:IsClothing()) then
        location = tostring(item:getBodyLocation() or "")
    elseif (item.IsInventoryContainer and item:IsInventoryContainer()) or
        (instanceof and instanceof(item, "AlarmClockClothing")) or item.canBeEquipped then
        location = tostring(item:canBeEquipped() or "")

        local normalized = string.lower(location)
        if normalized == "primary"
            or normalized == "secondary"
            or normalized == "bothhands"
            or normalized == "twohands"
            or normalized == "" then
            location = ""
        end
    end

    if location == "nil" then
        return ""
    end
    if isIgnoredWearLocation(location) then
        return ""
    end
    return location
end

function Capture.inventoryItemToDescriptor(item)
    if not item or not item.getFullType then
        return nil
    end

    if item.IsWeapon and item:IsWeapon() then
        return nil
    end

    local bodyLocation = getItemBodyLocation(item)
    if bodyLocation == "" then
        return nil
    end

    local descriptor = {
        fullType = item:getFullType(),
        displayName = item:getDisplayName(),
        bodyLocation = bodyLocation,
        itemType = item:getType(),
        included = true,
    }

    if Data.isIgnoredDescriptor(descriptor) then
        return nil
    end

    return descriptor
end

function Capture.buildEmptyDraft(playerObj)
    return {
        id = nil,
        name = Data.generateDefaultName(playerObj),
        items = {},
    }
end

function Capture.addInventoryItemsToDraft(draft, inventoryItems)
    draft.items = draft.items or {}

    local existing = {}
    for _, item in ipairs(draft.items) do
        local key = string.format("%s|%s", tostring(item.fullType or ""), tostring(item.bodyLocation or ""))
        existing[key] = true
    end

    local added = 0
    local duplicate = 0
    local rejected = 0

    for _, inventoryItem in ipairs(inventoryItems or {}) do
        local descriptor = Capture.inventoryItemToDescriptor(inventoryItem)
        if not descriptor then
            rejected = rejected + 1
        else
            local key = string.format("%s|%s", tostring(descriptor.fullType), tostring(descriptor.bodyLocation))
            if existing[key] then
                duplicate = duplicate + 1
            else
                existing[key] = true
                table.insert(draft.items, descriptor)
                added = added + 1
            end
        end
    end

    sortDraftItems(draft.items)
    return added, duplicate, rejected
end

function Capture.sortDraftItems(items)
    sortDraftItems(items)
end

function Capture.captureWornItems(playerObj)
    local items = {}
    local wornItems = playerObj:getWornItems()

    for index = 0, wornItems:size() - 1 do
        local wornItem = wornItems:get(index)
        local item = wornItem and wornItem:getItem() or nil
        if item and not shouldIgnoreWornItem(wornItem, item) then
            local bodyLocation = getItemBodyLocation(item)
            if bodyLocation ~= "" then
                table.insert(items, {
                    fullType = item:getFullType(),
                    displayName = item:getDisplayName(),
                    bodyLocation = bodyLocation,
                    itemType = item:getType(),
                    item = item,
                    included = true,
                })
            end
        end
    end

    sortDraftItems(items)
    return items
end

function Capture.buildDraftFromCurrent(playerObj, selectedOutfit)
    local draft = selectedOutfit and Data.buildEditableDraft(selectedOutfit) or nil
    draft = draft or Capture.buildEmptyDraft(playerObj)

    draft.items = Capture.captureWornItems(playerObj)
    if not draft.name or draft.name == "" then
        draft.name = Data.generateDefaultName(playerObj)
    end
    return draft
end
