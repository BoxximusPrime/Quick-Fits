---@diagnostic disable: undefined-global

require "QuickFits/Localization"

QuickFits = QuickFits or {}
QuickFits.Data = QuickFits.Data or {}

local Data = QuickFits.Data
local Localization = QuickFits.Localization

Data.SCHEMA_VERSION = 4

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

local function sanitizeOutfit(outfit)
    local sanitized = Data.cloneItems(outfit and outfit.items or {}, false)
    local changed = #sanitized ~= #(outfit and outfit.items or {})
    if outfit and outfit.mode ~= nil then
        outfit.mode = nil
        changed = true
    end
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
            didMutate = sanitizeOutfit(outfit) or didMutate
        elseif outfit and outfit.mode ~= nil then
            outfit.mode = nil
            didMutate = true
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
        local candidate = Localization.getText("default_outfit_name", index)
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
        items = Data.cloneItems(outfit.items, includeIgnored),
    }
end

function Data.saveOutfit(playerObj, draft, existingId)
    local store = Data.ensureStore(playerObj)
    local name = sanitizeName(draft and draft.name) or Data.generateDefaultName(playerObj)
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
        return nil, Localization.getText("error_save_empty")
    end

    local target = existingId and Data.getOutfitById(playerObj, existingId) or nil
    local createdAt = target and target.createdAt or nowMs()
    local outfit = {
        id = target and target.id or Data.generateId(playerObj),
        name = name,
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
        return nil, Localization.getText("error_select_outfit_first")
    end

    local name = sanitizeName(newName)
    if not name then
        return nil, Localization.getText("error_rename_missing")
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

function Data.savePreviewLanguage(playerObj, languageCode)
    local ui = Data.ensureStore(playerObj).ui
    ui.previewLanguage = tostring(languageCode or "")
    Data.transmit(playerObj)
end

function Data.getPreviewLanguage(playerObj)
    local ui = Data.ensureStore(playerObj).ui
    local previewLanguage = tostring(ui.previewLanguage or "")
    if previewLanguage == "" then
        return nil
    end
    return previewLanguage
end
