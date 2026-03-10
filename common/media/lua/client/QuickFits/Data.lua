---@diagnostic disable: undefined-global

QuickFits = QuickFits or {}
QuickFits.Data = QuickFits.Data or {}

local Data = QuickFits.Data

Data.SCHEMA_VERSION = 3

local IGNORED_BODY_LOCATIONS = {
    ["transmogde:transmog_location"] = true,
    ["transmogde:hide_everything_location"] = true,
}

local function startsWithTransmogPrefix(value)
    local text = string.lower(tostring(value or ""))
    return string.sub(text, 1, 10) == "transmogde" or string.sub(text, 1, 5) == "tmog:"
end

local function nowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    return os.time() * 1000
end

function Data.isDebugMode()
    local okDebugEnabled, debugEnabled = pcall(function()
        return isDebugEnabled and isDebugEnabled()
    end)
    if okDebugEnabled and debugEnabled then
        return true
    end

    local okGetDebug, debugValue = pcall(function()
        return getDebug and getDebug()
    end)
    if okGetDebug and debugValue then
        return true
    end

    return false
end

local function sanitizeName(name)
    local trimmed = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function normalizeMode(mode)
    if mode == "additive" then
        return "additive"
    end
    return "replacement"
end

function Data.isIgnoredDescriptor(item)
    local bodyLocation = string.lower(tostring(item and item.bodyLocation or ""))
    if IGNORED_BODY_LOCATIONS[bodyLocation] then
        return true
    end

    local displayName = tostring(item and item.displayName or "")
    if startsWithTransmogPrefix(displayName) then
        return true
    end

    local fullType = tostring(item and item.fullType or "")
    if startsWithTransmogPrefix(fullType) then
        return true
    end

    local itemType = tostring(item and item.itemType or "")
    if startsWithTransmogPrefix(itemType) then
        return true
    end

    return false
end

local function cloneItem(item)
    return {
        fullType = item.fullType,
        displayName = item.displayName,
        bodyLocation = item.bodyLocation,
        itemType = item.itemType,
        included = item.included ~= false,
    }
end

function Data.cloneItems(items, includeIgnored)
    local copy = {}
    for _, item in ipairs(items or {}) do
        if item.fullType and (includeIgnored or not Data.isIgnoredDescriptor(item)) then
            table.insert(copy, cloneItem(item))
        end
    end
    return copy
end

local function sanitizeOutfitItems(outfit)
    local sanitized = Data.cloneItems(outfit and outfit.items or {}, false)
    local changed = #sanitized ~= #(outfit and outfit.items or {})
    outfit.items = sanitized
    return changed
end

function Data.cloneOutfit(outfit)
    if not outfit then
        return nil
    end

    local includeIgnored = Data.isDebugMode()

    return {
        id = outfit.id,
        name = outfit.name,
        mode = outfit.mode,
        createdAt = outfit.createdAt,
        updatedAt = outfit.updatedAt,
        items = Data.cloneItems(outfit.items, includeIgnored),
    }
end

local function sortOutfits(outfits)
    table.sort(outfits, function(a, b)
        local left = string.lower(tostring(a.name or ""))
        local right = string.lower(tostring(b.name or ""))
        if left == right then
            return tostring(a.id or "") < tostring(b.id or "")
        end
        return left < right
    end)
end

function Data.ensureStore(playerObj)
    local modData = playerObj:getModData()
    modData.QuickFits = modData.QuickFits or {}

    local store = modData.QuickFits
    local previousVersion = tonumber(store.schemaVersion or 0) or 0
    store.schemaVersion = Data.SCHEMA_VERSION
    store.outfits = store.outfits or {}
    store.ui = store.ui or {}

    local didMutate = previousVersion < Data.SCHEMA_VERSION
    local allowIgnoredForDebug = Data.isDebugMode()
    for _, outfit in ipairs(store.outfits) do
        if not allowIgnoredForDebug then
            didMutate = sanitizeOutfitItems(outfit) or didMutate
        end
    end

    if didMutate then
        sortOutfits(store.outfits)
        Data.transmit(playerObj)
    end

    return store
end

function Data.transmit(playerObj)
    if playerObj and playerObj.transmitModData then
        playerObj:transmitModData()
    end
end

function Data.getOutfits(playerObj)
    return Data.ensureStore(playerObj).outfits
end

function Data.getOutfitById(playerObj, outfitId)
    for _, outfit in ipairs(Data.getOutfits(playerObj)) do
        if outfit.id == outfitId then
            return outfit
        end
    end
    return nil
end

function Data.generateId(playerObj)
    local playerNum = playerObj and playerObj:getPlayerNum() or 0
    return string.format("%s-%d-%06d", tostring(nowMs()), playerNum, ZombRand(1000000))
end

function Data.generateDefaultName(playerObj)
    local used = {}
    for _, outfit in ipairs(Data.getOutfits(playerObj)) do
        used[string.lower(tostring(outfit.name or ""))] = true
    end

    local index = 1
    while true do
        local candidate = string.format("Outfit %d", index)
        if not used[string.lower(candidate)] then
            return candidate
        end
        index = index + 1
    end
end

function Data.buildEditableDraft(outfit)
    if not outfit then
        return nil
    end

    local includeIgnored = Data.isDebugMode()

    return {
        id = outfit.id,
        name = outfit.name,
        mode = outfit.mode,
        items = Data.cloneItems(outfit.items, includeIgnored),
    }
end

function Data.saveOutfit(playerObj, draft, existingId)
    local store = Data.ensureStore(playerObj)
    local name = sanitizeName(draft and draft.name) or Data.generateDefaultName(playerObj)
    local mode = normalizeMode(draft and draft.mode)
    local items = {}

    for _, item in ipairs(draft and draft.items or {}) do
        if item.included ~= false and item.fullType and not Data.isIgnoredDescriptor(item) then
            table.insert(items, {
                fullType = item.fullType,
                displayName = item.displayName or item.fullType,
                bodyLocation = item.bodyLocation or "",
                itemType = item.itemType,
            })
        end
    end

    if #items == 0 then
        return nil, "Select at least one worn item to save this outfit."
    end

    local target = existingId and Data.getOutfitById(playerObj, existingId) or nil
    local createdAt = target and target.createdAt or nowMs()
    local outfit = {
        id = target and target.id or Data.generateId(playerObj),
        name = name,
        mode = mode,
        createdAt = createdAt,
        updatedAt = nowMs(),
        items = items,
    }

    if target then
        for key, value in pairs(outfit) do
            target[key] = value
        end
    else
        table.insert(store.outfits, outfit)
    end

    sortOutfits(store.outfits)
    Data.transmit(playerObj)
    return Data.cloneOutfit(outfit)
end

function Data.renameOutfit(playerObj, outfitId, newName)
    local outfit = Data.getOutfitById(playerObj, outfitId)
    if not outfit then
        return nil, "Select an outfit first."
    end

    local name = sanitizeName(newName)
    if not name then
        return nil, "Enter a name before renaming the outfit."
    end

    outfit.name = name
    outfit.updatedAt = nowMs()
    sortOutfits(Data.getOutfits(playerObj))
    Data.transmit(playerObj)
    return Data.cloneOutfit(outfit)
end

function Data.deleteOutfit(playerObj, outfitId)
    local outfits = Data.getOutfits(playerObj)
    for index, outfit in ipairs(outfits) do
        if outfit.id == outfitId then
            table.remove(outfits, index)
            Data.transmit(playerObj)
            return true
        end
    end
    return false
end

function Data.saveWindowState(playerObj, x, y, width, height)
    local ui = Data.ensureStore(playerObj).ui
    ui.windowX = math.floor(x)
    ui.windowY = math.floor(y)
    ui.windowW = math.floor(width)
    ui.windowH = math.floor(height)
    Data.transmit(playerObj)
end

function Data.getWindowState(playerObj)
    return Data.ensureStore(playerObj).ui
end
