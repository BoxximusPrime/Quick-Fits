---@diagnostic disable: undefined-global

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISToolTip"
require "ISUI/ISModalDialog"
require "ISUI/ISInventoryItem"
require "ISUI/ISContextMenu"
require "ISUI/ISMouseDrag"
require "QuickFits/Localization"
require "QuickFits/Data"
require "QuickFits/Capture"
require "QuickFits/Search"
require "QuickFits/Apply"

QuickFits = QuickFits or {}
QuickFits.UI = QuickFits.UI or {}

local Data = QuickFits.Data
local Capture = QuickFits.Capture
local Search = QuickFits.Search
local Apply = QuickFits.Apply
local Localization = QuickFits.Localization

local OutfitManagerWindow = ISPanel:derive("QuickFitsOutfitManagerWindow")

QuickFits.UI.OutfitManagerWindow = OutfitManagerWindow

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local ICON_SIZE = 20
local CLOSE_ICON_SIZE = 24
local WORN_ICON_SIZE = 24
local PROGRESS_HIDE_DELAY_MS = 2000
local PROGRESS_STOP_GAP = 8
local BOTTOM_SECTION_PADDING = 14
local ACTION_ROW_HEIGHT = 30
local PROGRESS_ROW_HEIGHT = 30
local BOTTOM_ROW_GAP = 10
local STATE_LOOKUP_REFRESH_INTERVAL_MS = 750

local CLOSE_ICON = getTexture("X.png") or getTexture("42.13/X.png")
local CLOSE_ICON_HOVER = getTexture("X_Hover.png") or getTexture("42.13/X_Hover.png") or CLOSE_ICON
local WORN_ICON = getTexture("Worn.png") or getTexture("42.13/Worn.png")

local function tr(key, ...)
    return Localization.getText(key, ...)
end

local function setButtonLabel(button, text)
    if not button then
        return
    end

    button.title = text
    button.text = text

    if button.setTitle then
        button:setTitle(text)
    end
end

local function measureButtonWidth(text, minimumWidth, padding)
    local textWidth = getTextManager():MeasureStringX(UIFont.Small, tostring(text or ""))
    return math.max(minimumWidth or 0, textWidth + (padding or 28))
end

local function resetListState(list, selectedIndex)
    if not list then
        return
    end

    list:clear()
    list.selected = selectedIndex or 0
    list.mouseoverselected = selectedIndex or 0
    list:setYScroll(0)
    list:setScrollHeight(0)
end

local function getScriptItemForDescriptor(descriptor)
    if not descriptor or not descriptor.fullType then
        return nil
    end
    return ScriptManager.instance:FindItem(descriptor.fullType)
end

local function drawDescriptorIcon(ui, descriptor, x, y, size)
    local scriptItem = getScriptItemForDescriptor(descriptor)
    if scriptItem then
        ISInventoryItem.renderScriptItemIcon(ui, scriptItem, x, y, 1, size or ICON_SIZE, size or ICON_SIZE)
    end
end

local function itemLabel(item)
    local displayName = tostring(item and item.displayName or "")
    if displayName ~= "" then
        return displayName
    end

    local fullType = tostring(item and item.fullType or "")
    local shortName = fullType:match("[^%.:]+$")
    if shortName and shortName ~= "" then
        return shortName
    end

    return fullType
end

local function buildDebugItemLabel(item)
    local details = {}

    local fullType = tostring(item and item.fullType or "")
    if fullType ~= "" then
        table.insert(details, tr("debug_full_type", fullType))
    end

    local bodyLocation = tostring(item and item.bodyLocation or "")
    if bodyLocation ~= "" then
        table.insert(details, tr("debug_body", bodyLocation))
    end

    local itemType = tostring(item and item.itemType or "")
    if itemType ~= "" then
        table.insert(details, tr("debug_item_type", itemType))
    end

    if item and item.included == false then
        table.insert(details, tr("debug_included_false"))
    end

    if Data.isIgnoredDescriptor(item) then
        table.insert(details, tr("debug_ignored_true"))
    end

    if #details == 0 then
        return itemLabel(item)
    end

    return string.format("%s [%s]", itemLabel(item), table.concat(details, ", "))
end

local function getDraftRowLabel(item)
    if Data.isDebugMode() then
        return buildDebugItemLabel(item)
    end
    return itemLabel(item)
end

local function truncateText(text, font, maxWidth)
    if not text or maxWidth <= 0 then return "" end
    local textWidth = getTextManager():MeasureStringX(font, text)
    if textWidth <= maxWidth then return text end
    local ellipsis = "..."
    local ellipsisWidth = getTextManager():MeasureStringX(font, ellipsis)
    for i = #text, 1, -1 do
        local sub = string.sub(text, 1, i)
        if getTextManager():MeasureStringX(font, sub) + ellipsisWidth <= maxWidth then
            return sub .. ellipsis
        end
    end
    return ellipsis
end

local function nowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    return os.time() * 1000
end

local function isUiElementVisible(element)
    if not element then
        return false
    end

    if type(element.getIsVisible) == "function" then
        local ok, visible = pcall(function()
            return element:getIsVisible()
        end)
        if ok then
            return visible == true
        end
    end

    if type(element.isReallyVisible) == "function" then
        local ok, visible = pcall(function()
            return element:isReallyVisible()
        end)
        if ok then
            return visible == true
        end
    end

    if type(element.isVisible) == "function" then
        local ok, visible = pcall(function()
            return element:isVisible()
        end)
        if ok then
            return visible == true
        end
    end

    return element.visible == true
end

local function drawProgressFillGradient(ui, x, y, width, height)
    -- Draw base fill
    ui:drawRect(x, y, width, height, 0.9, 0.18, 0.52, 0.2)

    -- Draw 1px highlight at top
    ui:drawRect(x, y, width, 1, 0.92, 0.25, 0.65, 0.3)

    -- Draw 1px shadow at bottom
    ui:drawRect(x, y + height - 1, width, 1, 0.85, 0.12, 0.38, 0.15)
end

local function drawInterruptedProgressFill(ui, x, y, width, height)
    ui:drawRect(x, y, width, height, 0.94, 0.52, 0.12, 0.12)
    ui:drawRect(x, y, width, 1, 0.96, 0.72, 0.24, 0.24)
    ui:drawRect(x, y + height - 1, width, 1, 0.88, 0.34, 0.08, 0.08)
end

local function getProgressEntryDisplayName(entry)
    if not entry then
        return ""
    end

    local displayName = tostring(entry.displayName or "")
    if displayName ~= "" then
        return displayName
    end

    local item = entry.item
    if item and item.getDisplayName then
        local ok, itemDisplayName = pcall(function()
            return item:getDisplayName()
        end)
        if ok and tostring(itemDisplayName or "") ~= "" then
            return tostring(itemDisplayName)
        end
    end

    return tostring(entry.fullType or "")
end

local function getFallbackPhaseForProgress(progress)
    if not progress or not progress.entries or #progress.entries == 0 then
        return nil
    end

    local actionType = "ISUnequipAction"
    local actionKey = "progress_action_removing"
    if progress.mode == "wear" then
        actionType = "ISWearClothing"
        actionKey = "progress_action_wearing"
    elseif progress.mode == "container" then
        actionType = "ISInventoryTransferAction"
        actionKey = "progress_action_moving"
    end

    return {
        mode = progress.mode,
        actionType = actionType,
        actionKey = actionKey,
        entries = progress.entries,
        total = progress.total or #progress.entries,
        targetContainer = progress.targetContainer,
        completed = progress.completed or 0,
    }
end

local function getActualDraggedItems(items)
    local actualItems = {}
    local contains = {}

    for _, item in ipairs(items or {}) do
        if instanceof(item, "InventoryItem") then
            if not contains[item] then
                table.insert(actualItems, item)
                contains[item] = true
            end
        elseif item.items then
            for index = 2, #item.items do
                local child = item.items[index]
                if child and not contains[child] then
                    table.insert(actualItems, child)
                    contains[child] = true
                end
            end
        end
    end

    return actualItems
end

local function clearAcceptedDrag()
    if ISMouseDrag.draggingFocus and ISMouseDrag.draggingFocus.onMouseUp then
        ISMouseDrag.draggingFocus:onMouseUp(0, 0)
    end
    ISMouseDrag.draggingFocus = nil
    ISMouseDrag.dragging = nil
end

local function getDraftRemoveButtonBounds(list, rowY, rowHeight)
    local buttonSize = 16
    local buttonX = list.width - buttonSize - 18
    local buttonY = rowY + math.floor((rowHeight - buttonSize) / 2)
    return buttonX, buttonY, buttonSize, buttonSize
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function getDescriptorLookupKey(item)
    return string.format("%s|%s", tostring(item and item.fullType or ""), tostring(item and item.bodyLocation or ""))
end

local function copyLookupCounts(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function areContainerListsEqual(left, right)
    if left == right then
        return true
    end

    if not left or not right or #left ~= #right then
        return false
    end

    for index = 1, #left do
        if left[index] ~= right[index] then
            return false
        end
    end

    return true
end

local function buildDraftItemsSignature(items)
    local parts = {}

    for _, item in ipairs(items or {}) do
        table.insert(parts, string.format("%s|%s|%s",
            tostring(item and item.fullType or ""),
            tostring(item and item.bodyLocation or ""),
            item and item.included ~= false and "1" or "0"))
    end

    return table.concat(parts, "\n")
end

local function getOutfitByName(playerObj, name)
    local desired = string.lower(tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if desired == "" then
        return nil
    end

    for _, outfit in ipairs(Data.getOutfits(playerObj)) do
        if string.lower(tostring(outfit.name or "")) == desired then
            return outfit
        end
    end

    return nil
end

local function getCloseIconBounds(window)
    local iconX = window.width - CLOSE_ICON_SIZE - 12
    local iconY = 10
    return iconX, iconY, CLOSE_ICON_SIZE, CLOSE_ICON_SIZE
end

local function getEditorTitle(window)
    local selected = window:getSelectedOutfit()
    if selected and selected.name and selected.name ~= "" then
        return tr("editor_editing_named", selected.name)
    end
    return tr("editor_editing_new")
end

local function summarizeResult(outfit, result)
    if not result then
        return tr("result_apply_failed"), true
    end

    local parts = {}
    local actionText = tr("result_action_apply")
    if result.action == "remove" then
        actionText = tr("result_action_remove")
    elseif result.action == "add" then
        actionText = tr("result_action_add")
    elseif result.action == "wear" then
        actionText = tr("result_action_wear")
    elseif result.action == "place" then
        actionText = tr("result_action_place")
    elseif result.action == "grab" then
        actionText = tr("result_action_grab")
    end
    table.insert(parts, tr("result_outfit_action", outfit.name or tr("fallback_outfit_name"), actionText))

    if result.equipped and result.equipped > 0 then
        table.insert(parts, tr("result_equipped", result.equipped))
    end
    if result.removed and result.removed > 0 then
        table.insert(parts, tr("result_removed", result.removed))
    end
    if result.blocked and #result.blocked > 0 then
        table.insert(parts, tr("result_blocked", table.concat(result.blocked, ", ")))
    end
    if result.transferred and result.transferred > 0 then
        if result.targetLabel and tostring(result.targetLabel) ~= "" then
            table.insert(parts, tr("result_moved_target", result.transferred, tostring(result.targetLabel)))
        else
            table.insert(parts, tr("result_moved", result.transferred))
        end
    end
    if result.missing and #result.missing > 0 then
        table.insert(parts, tr("result_missing", table.concat(result.missing, ", ")))
    end

    return table.concat(parts, " "), (#result.missing > 0 or #result.blocked > 0)
end

function OutfitManagerWindow.Open(playerNum)
    if OutfitManagerWindow.instance then
        OutfitManagerWindow.instance:bringToTop()
        OutfitManagerWindow.instance:forceRefreshStateLookups()
        return OutfitManagerWindow.instance
    end

    local playerObj = getSpecificPlayer(playerNum or 0)
    if not playerObj then
        return nil
    end

    local width = 920
    local height = 676
    local uiState = Data.getWindowState(playerObj)
    local x = uiState.windowX or math.floor((getCore():getScreenWidth() - width) / 2)
    local y = uiState.windowY or math.floor((getCore():getScreenHeight() - height) / 2)

    local window = OutfitManagerWindow:new(x, y, width, height, playerNum)
    window:initialise()
    window:instantiate()
    if #window.children == 0 then
        window:createChildren()
    end
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
    OutfitManagerWindow.instance = window
    window:forceRefreshStateLookups()
    return window
end

function OutfitManagerWindow:new(x, y, width, height, playerNum)
    local window = ISPanel.new(self, x, y, width, height)
    setmetatable(window, self)
    self.__index = self

    window.playerNum = playerNum or 0
    window.playerObj = getSpecificPlayer(window.playerNum)
    window.moveWithMouse = false
    window.backgroundColor = { r = 0.04, g = 0.04, b = 0.05, a = 0.96 }
    window.borderColor = { r = 0.32, g = 0.28, b = 0.16, a = 1 }
    window.headerHeight = 38
    window.resizable = false
    window.outfits = {}
    window.selectedOutfitId = nil
    window.editorDraft = nil
    window.didHandleDragRelease = false
    window.draftOverlayText = nil
    window.draftOverlayIsError = false
    window.draftOverlayUntil = 0
    window.statusText = ""
    window.statusIsError = false
    window.currentWornLookup = {}
    window.currentWornTypeLookup = {}
    window.currentWornItemLookup = {}
    window.currentNearbyLookup = {}
    window.currentNearbyTypeLookup = {}
    window.wornLookupDirty = true
    window.nearbyLookupDirty = true
    window.lastPlayerSquareX = nil
    window.lastPlayerSquareY = nil
    window.lastPlayerSquareZ = nil
    window.lastSelectedLootContainer = nil
    window.lastReachableLootContainers = {}
    window.lastWornLookupRefreshAt = 0
    window.lastNearbyLookupRefreshAt = 0
    window.draftReorderDrag = nil
    window.activeDraftContextRow = nil
    window.activeDraftContextMenu = nil
    window.draftRowHitBounds = {}
    window.activeProgress = nil
    window.savedDraftSnapshot = nil
    Localization.setPreviewLanguage(Data.getPreviewLanguage(window.playerObj) or Localization.PREVIEW_LANGUAGE_AUTO)
    return window
end

function OutfitManagerWindow:initialise()
    ISPanel.initialise(self)
end

function OutfitManagerWindow:createChildren()
    local headerY = self.headerHeight + 12
    local leftPaneX = 12
    local leftPaneW = 280
    local rightPaneX = leftPaneX + leftPaneW + 14
    local rightPaneW = self.width - rightPaneX - 12
    local outfitListY = headerY + 34
    local itemListY = headerY + 119
    local bottomSectionHeight = (ACTION_ROW_HEIGHT * 2) + PROGRESS_ROW_HEIGHT + (BOTTOM_ROW_GAP * 2) +
        BOTTOM_SECTION_PADDING
    local listHeight = self.height - outfitListY - bottomSectionHeight

    self.outfitListX = leftPaneX
    self.outfitListY = outfitListY
    self.outfitListW = leftPaneW
    self.outfitListH = listHeight
    self.leftPaneX = leftPaneX
    self.leftPaneW = leftPaneW
    self.rightPaneX = rightPaneX
    self.rightPaneW = rightPaneW
    self.headerY = headerY
    self:createOutfitListWidget()

    self.nameEntry = ISTextEntryBox:new("", rightPaneX + 10, headerY + 32, 340, 24)
    self.nameEntry:initialise()
    self.nameEntry:instantiate()
    self.nameEntry.backgroundColor = { r = 0.03, g = 0.04, b = 0.04, a = 1 }
    self.nameEntry.borderColor = { r = 0.2, g = 0.32, b = 0.3, a = 0.9 }
    self:addChild(self.nameEntry)

    self.saveButton = ISButton:new(rightPaneX + 360, headerY + 32, 74, 30, "", self, self.onSaveNew)
    self.saveButton:initialise()
    self.saveButton:instantiate()
    self.saveButton.borderColor = { r = 0.3, g = 0.6, b = 0.3, a = 0.9 }
    self.saveButton.backgroundColor = { r = 0.08, g = 0.18, b = 0.08, a = 0.95 }
    self:addChild(self.saveButton)

    self.itemListX = rightPaneX
    self.itemListY = itemListY
    self.itemListW = rightPaneW
    self.itemListH = self.height - itemListY - (bottomSectionHeight + 11)

    self.captureButton = ISButton:new(rightPaneX, self.itemListY + self.itemListH + 8, 140, 30, "",
        self,
        self.onCaptureCurrent)
    self.captureButton:initialise()
    self.captureButton:instantiate()
    self.captureButton.borderColor = { r = 0.7, g = 0.55, b = 0.2, a = 0.9 }
    self.captureButton.backgroundColor = { r = 0.2, g = 0.15, b = 0.06, a = 0.95 }
    self:addChild(self.captureButton)

    self.newButton = ISButton:new(leftPaneX + 195, headerY, 80, 27, "", self, self.onNewDraft)
    self.newButton:initialise()
    self.newButton:instantiate()
    self.newButton.borderColor = { r = 0.35, g = 0.45, b = 0.55, a = 0.9 }
    self.newButton.backgroundColor = { r = 0.1, g = 0.14, b = 0.18, a = 0.95 }
    self:addChild(self.newButton)

    self:createDraftItemListWidget()

    self.wearButton = ISButton:new(leftPaneX, self.height - 94, 90, 30, "", self, self.onWear)
    self.wearButton:initialise()
    self.wearButton:instantiate()
    self.wearButton.borderColor = { r = 0.3, g = 0.65, b = 0.3, a = 0.9 }
    self.wearButton.backgroundColor = { r = 0.08, g = 0.2, b = 0.08, a = 0.95 }
    self:addChild(self.wearButton)

    self.addButton = ISButton:new(self.wearButton:getRight() + 10, self.height - 94, 90, 30, "", self, self.onAdd)
    self.addButton:initialise()
    self.addButton:instantiate()
    self.addButton.borderColor = { r = 0.3, g = 0.5, b = 0.68, a = 0.9 }
    self.addButton.backgroundColor = { r = 0.08, g = 0.13, b = 0.22, a = 0.95 }
    self:addChild(self.addButton)

    self.removeButton = ISButton:new(self.addButton:getRight() + 18, self.height - 94, 100, 30, "", self, self.onRemove)
    self.removeButton:initialise()
    self.removeButton:instantiate()
    self.removeButton.borderColor = { r = 0.7, g = 0.5, b = 0.22, a = 0.9 }
    self.removeButton.backgroundColor = { r = 0.2, g = 0.12, b = 0.04, a = 0.95 }
    self:addChild(self.removeButton)

    self.placeButton = ISButton:new(self.removeButton:getRight() + 10, self.height - 94, 160, 30, "", self,
        self.onPlaceInContainer)
    self.placeButton:initialise()
    self.placeButton:instantiate()
    self.placeButton.borderColor = { r = 0.3, g = 0.45, b = 0.65, a = 0.9 }
    self.placeButton.backgroundColor = { r = 0.08, g = 0.12, b = 0.2, a = 0.95 }
    self:addChild(self.placeButton)

    self.grabButton = ISButton:new(self.placeButton:getRight() + 10, self.height - 94, 110, 30, "", self,
        self.onGrabAll)
    self.grabButton:initialise()
    self.grabButton:instantiate()
    self.grabButton.borderColor = { r = 0.28, g = 0.48, b = 0.72, a = 0.9 }
    self.grabButton.backgroundColor = { r = 0.08, g = 0.16, b = 0.26, a = 0.95 }
    self:addChild(self.grabButton)

    self.deleteButton = ISButton:new(rightPaneX + 360 + 90, headerY + 32, 90, 30, "", self,
        self.onDelete)
    self.deleteButton:initialise()
    self.deleteButton:instantiate()
    self.deleteButton.borderColor = { r = 0.65, g = 0.25, b = 0.25, a = 0.9 }
    self.deleteButton.backgroundColor = { r = 0.2, g = 0.08, b = 0.08, a = 0.95 }
    self:addChild(self.deleteButton)

    self.stopProgressButton = ISButton:new(self.width - 88, self.height - 44, 76, 30, "", self, self.onStopProgress)
    self.stopProgressButton:initialise()
    self.stopProgressButton:instantiate()
    self.stopProgressButton.borderColor = { r = 0.72, g = 0.28, b = 0.28, a = 0.92 }
    self.stopProgressButton.backgroundColor = { r = 0.24, g = 0.08, b = 0.08, a = 0.96 }
    self.stopProgressButton:setVisible(false)
    self:addChild(self.stopProgressButton)

    if Data.isDebugMode() then
        self.languageCombo = ISComboBox:new(rightPaneX + rightPaneW - 190, headerY, 180, 24, self,
            self.onPreviewLanguageSelected)
        self.languageCombo:initialise()
        self.languageCombo:instantiate()
        self.languageCombo.backgroundColor = { r = 0.03, g = 0.04, b = 0.04, a = 1 }
        self.languageCombo.borderColor = { r = 0.2, g = 0.32, b = 0.3, a = 0.9 }
        self:addChild(self.languageCombo)
        self:populatePreviewLanguageCombo()
    end

    self:applyLocalizedText()

    self:reloadOutfits()
    if self.outfits[1] then
        self.selectedOutfitId = self.outfits[1].id
        self.outfitList.selected = 1
        self:loadDraftFromOutfit(self.outfits[1])
    else
        self:resetDraftFromCurrent(nil, true)
    end

    self:refreshStateLookups()
end

function OutfitManagerWindow:populatePreviewLanguageCombo()
    if not self.languageCombo then
        return
    end

    local selectedLanguage = Localization.getPreviewLanguage()
    self.languageCombo:clear()
    self.languageCombo.selected = 0

    for index, languageCode in ipairs(Localization.getAvailablePreviewLanguages()) do
        self.languageCombo:addOptionWithData(Localization.getLanguageLabel(languageCode), languageCode)
        if languageCode == selectedLanguage then
            self.languageCombo.selected = index
        end
    end

    if self.languageCombo.selected == 0 then
        self.languageCombo.selected = 1
    end
end

function OutfitManagerWindow:layoutLocalizedControls()
    local topRowY = self.headerY + 32
    local nameEntryX = self.rightPaneX + 10
    local rightInset = self.rightPaneX + self.rightPaneW - 10
    local saveWidth = measureButtonWidth(tr("button_save"), 74, 26)
    local deleteWidth = measureButtonWidth(tr("button_delete"), 90, 26)

    self.deleteButton:setWidth(deleteWidth)
    self.deleteButton:setX(rightInset - deleteWidth)
    self.deleteButton:setY(topRowY)

    self.saveButton:setWidth(saveWidth)
    self.saveButton:setX(self.deleteButton:getX() - saveWidth - 10)
    self.saveButton:setY(topRowY)

    self.nameEntry:setX(nameEntryX)
    self.nameEntry:setY(topRowY)
    self.nameEntry:setWidth(math.max(180, self.saveButton:getX() - nameEntryX - 10))

    local captureWidth = measureButtonWidth(tr("button_capture_current"), 140, 30)
    self.captureButton:setWidth(captureWidth)
    self.captureButton:setX(self.rightPaneX)

    local actionY = self.height - (BOTTOM_SECTION_PADDING + PROGRESS_ROW_HEIGHT + BOTTOM_ROW_GAP + ACTION_ROW_HEIGHT)
    local progressY = self.height - (BOTTOM_SECTION_PADDING + PROGRESS_ROW_HEIGHT)
    local rowGap = 8
    local minActionSpacing = 6
    local maxActionSpacing = 18
    local actionAreaWidth = self.width - (self.leftPaneX * 2)
    local actionButtons = {
        { button = self.wearButton,   width = measureButtonWidth(tr("button_wear"), 90, 28) },
        { button = self.addButton,    width = measureButtonWidth(tr("button_add"), 90, 28) },
        { button = self.removeButton, width = measureButtonWidth(tr("button_take_off"), 100, 28) },
        { button = self.placeButton,  width = measureButtonWidth(tr("button_place_container"), 160, 32) },
        { button = self.grabButton,   width = measureButtonWidth(tr("button_grab_all"), 110, 32) },
    }
    local preferredGaps = { 6, 14, 6, 8 }
    local preferredWidth = 0
    for index, spec in ipairs(actionButtons) do
        preferredWidth = preferredWidth + spec.width + (preferredGaps[index] or 0)
    end

    if preferredWidth <= actionAreaWidth then
        local x = self.leftPaneX
        local widestRightEdge = self.leftPaneX
        for index, spec in ipairs(actionButtons) do
            spec.button:setX(x)
            spec.button:setY(actionY)
            spec.button:setWidth(spec.width)
            widestRightEdge = math.max(widestRightEdge, spec.button:getRight())
            x = x + spec.width + (preferredGaps[index] or 0)
        end

        self.actionButtonsRightEdge = widestRightEdge
        self.actionButtonsBaseY = actionY
        self.progressBarY = progressY
        self.progressBarX = self.leftPaneX

        self:updateProgressButtonLayout()

        if self.languageCombo then
            self.languageCombo:setX(self.rightPaneX + self.rightPaneW - self.languageCombo:getWidth() - 10)
            self.languageCombo:setY(self.headerY)
        end
        return
    end

    local actionRows = { {}, {} }
    local currentRow = 1
    local currentWidth = 0

    for _, spec in ipairs(actionButtons) do
        local gapWidth = #actionRows[currentRow] > 0 and minActionSpacing or 0
        if #actionRows[currentRow] > 0 and currentRow < #actionRows
            and (currentWidth + gapWidth + spec.width) > actionAreaWidth then
            currentRow = currentRow + 1
            currentWidth = 0
            gapWidth = 0
        end

        table.insert(actionRows[currentRow], spec)
        currentWidth = currentWidth + gapWidth + spec.width
    end

    local rowCount = #actionRows[2] > 0 and 2 or 1
    local rowStartY = actionY - ((rowCount - 1) * (30 + rowGap))
    local widestRightEdge = self.leftPaneX

    for rowIndex = 1, rowCount do
        local row = actionRows[rowIndex]
        local rowWidth = 0
        local y = rowStartY + ((rowIndex - 1) * (30 + rowGap))

        for _, spec in ipairs(row) do
            rowWidth = rowWidth + spec.width
        end

        local spacing = minActionSpacing
        if #row > 1 then
            spacing = math.floor((actionAreaWidth - rowWidth) / (#row - 1))
            spacing = math.max(minActionSpacing, math.min(maxActionSpacing, spacing))
        end

        local x = self.leftPaneX
        for _, spec in ipairs(row) do
            spec.button:setX(x)
            spec.button:setY(y)
            spec.button:setWidth(spec.width)
            x = x + spec.width + spacing
            widestRightEdge = math.max(widestRightEdge, spec.button:getRight())
        end
    end

    self.actionButtonsRightEdge = widestRightEdge
    self.actionButtonsBaseY = actionY
    self.progressBarY = progressY
    self.progressBarX = self.leftPaneX

    self:updateProgressButtonLayout()

    if self.languageCombo then
        self.languageCombo:setX(self.rightPaneX + self.rightPaneW - self.languageCombo:getWidth() - 10)
        self.languageCombo:setY(self.headerY)
    end
end

function OutfitManagerWindow:updateProgressButtonLayout()
    if not self.stopProgressButton then
        return
    end

    local buttonWidth = measureButtonWidth(tr("button_stop"), 72, 22)
    local buttonX = self.width - buttonWidth - 12
    local buttonY = self.progressBarY or (self.height - (BOTTOM_SECTION_PADDING + PROGRESS_ROW_HEIGHT))
    local isVisible = self.activeProgress ~= nil and self.activeProgress.state == "active" and
        (self.activeProgress.total or 0) > 0

    self.stopProgressButton:setWidth(buttonWidth)
    self.stopProgressButton:setX(buttonX)
    self.stopProgressButton:setY(buttonY)
    self.stopProgressButton:setVisible(isVisible)
end

function OutfitManagerWindow:applyLocalizedText()
    setButtonLabel(self.saveButton, tr("button_save"))
    setButtonLabel(self.captureButton, tr("button_capture_current"))
    setButtonLabel(self.newButton, tr("button_new"))
    setButtonLabel(self.wearButton, tr("button_wear"))
    setButtonLabel(self.addButton, tr("button_add"))
    setButtonLabel(self.removeButton, tr("button_take_off"))
    setButtonLabel(self.placeButton, tr("button_place_container"))
    setButtonLabel(self.grabButton, tr("button_grab_all"))
    setButtonLabel(self.deleteButton, tr("button_delete"))
    setButtonLabel(self.stopProgressButton, tr("button_stop"))

    self.wearButton.tooltip = tr("tooltip_wear")
    self.addButton.tooltip = tr("tooltip_add")
    self.removeButton.tooltip = tr("tooltip_take_off")
    self.placeButton.tooltip = tr("tooltip_place_container")
    self.grabButton.tooltip = tr("tooltip_grab_all")

    self:layoutLocalizedControls()
end

function OutfitManagerWindow:onPreviewLanguageSelected(combo)
    local selectedLanguage = tostring(combo:getOptionData(combo.selected) or Localization.PREVIEW_LANGUAGE_AUTO)
    Localization.setPreviewLanguage(selectedLanguage)
    if self.playerObj then
        Data.savePreviewLanguage(self.playerObj, selectedLanguage)
    end

    self:applyLocalizedText()
    self:reloadOutfits()
    self:refreshDraftList(true)
    self:updateSaveButtonState()
end

function OutfitManagerWindow:createOutfitListWidget()
    if self.outfitList then
        self:removeChild(self.outfitList)
        self.outfitList = nil
    end

    self.outfitList = ISScrollingListBox:new(self.outfitListX, self.outfitListY, self.outfitListW, self.outfitListH)
    self.outfitList:initialise()
    self.outfitList:instantiate()
    self.outfitList.itemheight = 60
    self.outfitList.font = UIFont.Small
    self.outfitList:setOnMouseDownFunction(self, self.onOutfitSelected)
    self.outfitList.doDrawItem = function(list, y, item, alt)
        return self:drawOutfitRow(list, y, item, alt)
    end
    self:addChild(self.outfitList)
end

function OutfitManagerWindow:createDraftItemListWidget()
    if self.itemList then
        self:removeChild(self.itemList)
        self.itemList = nil
    end

    self.itemList = ISScrollingListBox:new(self.itemListX, self.itemListY, self.itemListW, self.itemListH)
    self.itemList:initialise()
    self.itemList:instantiate()
    self.itemList.itemheight = 32
    self.itemList.font = UIFont.Small
    self.itemList.backgroundColor = { r = 0.02, g = 0.03, b = 0.03, a = 0.96 }
    self.itemList.borderColor = { r = 0.18, g = 0.28, b = 0.26, a = 0.28 }
    self.itemList.drawBorder = true
    self.itemList.onMouseDown = function(list, x, y)
        return self:onDraftListMouseDown(x, y)
    end
    self.itemList.onMouseMove = function(list, dx, dy)
        return self:onDraftListMouseMove(dx, dy)
    end
    self.itemList.onMouseMoveOutside = function(list, dx, dy)
        return self:onDraftListMouseMoveOutside(dx, dy)
    end
    self.itemList.onMouseUp = function(list, x, y)
        return self:onDraftListMouseUp(x, y)
    end
    self.itemList.onMouseUpOutside = function(list, x, y)
        return self:onDraftListMouseUp(x, y)
    end
    self.itemList.onRightMouseUp = function(list, x, y)
        return self:onDraftListRightMouseUp(x, y)
    end
    self.itemList.doDrawItem = function(list, y, item, alt)
        return self:drawDraftRow(list, y, item, alt)
    end
    self:addChild(self.itemList)
end

function OutfitManagerWindow:drawOutfitRow(list, y, item, alt)
    local rowHeight = item.height or list.itemheight
    if y + list:getYScroll() + rowHeight < 0 or y + list:getYScroll() >= list.height then
        return y + rowHeight
    end

    local matchedCount, totalCount = self:getOutfitMatchCounts(item.item)

    if item.index % 2 == 0 then
        list:drawRect(0, y, list.width, rowHeight, 0.1, 0.15, 0.15, 0.17)
    else
        list:drawRect(0, y, list.width, rowHeight, 0.06, 0.11, 0.11, 0.13)
    end

    if list.selected == item.index then
        list:drawRect(0, y, list.width, rowHeight, 0.2, 0.3, 0.4, 0.24)
        list:drawRectBorder(0, y, list.width, rowHeight, 0.45, 0.5, 0.48, 0.32)
        list:drawRect(0, y, 6, rowHeight, 1, 0.2, 1, 0.1)
    elseif list.mouseoverselected == item.index and list:isMouseOver() and not list:isMouseOverScrollBar() then
        list:drawRect(1, y + 1, list.width - 2, rowHeight - 2, 0.08, 0.26, 0.26, 0.2)
        list:drawRectBorder(1, y + 1, list.width - 2, rowHeight - 2, 0.5, 1, 0.97, 0.92)
    end

    list:drawRectBorder(0, y, list.width, rowHeight, 0.18, 0.38, 0.34, 0.18)
    -- drawDescriptorIcon(list, item.item.items and item.item.items[1] or nil, 14, y + 12, 18)

    local maxTextW = list.width - 42
    local nameText = truncateText(item.text or "", UIFont.Small, maxTextW)
    list:drawText(nameText, 24, y + 8, 0.97, 0.95, 0.9, 1, UIFont.Small)

    local itemLabelText = totalCount == 1 and tr("label_item_singular") or tr("label_item_plural")
    local subtitle = string.format("%d / %d %s", matchedCount, totalCount, itemLabelText)
    local subText = truncateText(subtitle, UIFont.Small, maxTextW)
    local subtitleColor = (totalCount > 0 and matchedCount == totalCount)
        and { 0.6, 0.9, 0.62, 1 }
        or { 0.6, 0.58, 0.5, 0.85 }
    list:drawText(subText, 24, y + 30, subtitleColor[1], subtitleColor[2], subtitleColor[3], subtitleColor[4],
        UIFont.Small)

    return y + rowHeight
end

function OutfitManagerWindow:drawDraftRow(list, y, item, alt)
    local rowHeight = item.height or list.itemheight
    if y + list:getYScroll() + rowHeight < 0 or y + list:getYScroll() >= list.height then
        return y + rowHeight
    end

    self.draftRowHitBounds[item.index] = {
        rowY = y,
        rowHeight = rowHeight,
    }

    local draftItem = item.item
    local isIncluded = draftItem.included ~= false
    local isCurrentlyWorn = self:isDraftItemCurrentlyWorn(draftItem)
    local isNearbyAvailable = not isCurrentlyWorn and self:isDraftItemNearbyAvailable(draftItem)
    local isContextActive = self.activeDraftContextRow == item.index and self:isDraftContextMenuOpen()
    local isRowHovered = not isContextActive and list.mouseoverselected == item.index and list:isMouseOver() and
        not list:isMouseOverScrollBar()
    local contentOffsetX = isContextActive and 2 or (isRowHovered and 1 or 0)

    if item.index % 2 == 0 then
        list:drawRect(0, y, list.width, rowHeight, 0.12, 0.16, 0.16, 0.18)
    else
        list:drawRect(0, y, list.width, rowHeight, 0.06, 0.11, 0.11, 0.13)
    end

    if isContextActive then
        list:drawRect(1, y + 1, list.width - 2, rowHeight - 2, 0.15, 0.18, 0.36, 0.28)
        list:drawRect(1, y + 1, 5, rowHeight - 2, 0.72, 0.34, 0.78, 0.72)
        list:drawRectBorder(1, y + 1, list.width - 2, rowHeight - 2, 0.48, 0.76, 0.84, 0.84)
    elseif isRowHovered then
        list:drawRect(1, y + 1, list.width - 2, rowHeight - 2, 0.09, 0.16, 0.28, 0.18)
        list:drawRect(1, y + 1, 4, rowHeight - 2, 0.42, 0.28, 0.52, 0.5)
        list:drawRectBorder(1, y + 1, list.width - 2, rowHeight - 2, 0.3, 0.58, 0.66, 0.68)
    end

    list:drawRectBorder(0, y, list.width, rowHeight, 0.1, 0.28, 0.26, 0.16)
    drawDescriptorIcon(list, draftItem, 8 + contentOffsetX, y + 6, ICON_SIZE)

    local cbX, cbY, cbSize = getDraftRemoveButtonBounds(list, y, rowHeight)
    self.draftRowHitBounds[item.index].buttonX = cbX
    self.draftRowHitBounds[item.index].buttonY = cbY
    self.draftRowHitBounds[item.index].buttonSize = cbSize
    local mouseX = getMouseX() - list:getAbsoluteX()
    local mouseY = getMouseY() - list:getAbsoluteY()
    local isHovered = mouseX >= cbX and mouseX <= (cbX + cbSize) and mouseY >= cbY and mouseY <= (cbY + cbSize)
    local buttonTexture = isHovered and CLOSE_ICON_HOVER or CLOSE_ICON
    if buttonTexture then
        list:drawTextureScaled(buttonTexture, cbX, cbY, cbSize, cbSize, isIncluded and 1 or 0.45, 1, 1, 1)
    else
        list:drawRect(cbX, cbY, cbSize, cbSize, isIncluded and 0.92 or 0.5, 0.22, 0.08, 0.08)
        list:drawRectBorder(cbX, cbY, cbSize, cbSize, isIncluded and 0.95 or 0.6, 0.7, 0.22, 0.22)
        list:drawTextCentre("X", cbX + math.floor(cbSize / 2), cbY - 1, 0.96, 0.94, 0.92, isIncluded and 1 or 0.7,
            UIFont.Small)
    end

    local wornIndicatorX = cbX - WORN_ICON_SIZE - 8
    local wornIndicatorY = y + math.floor((rowHeight - WORN_ICON_SIZE) / 2)
    if isCurrentlyWorn then
        if WORN_ICON then
            list:drawTextureScaled(WORN_ICON, wornIndicatorX + contentOffsetX, wornIndicatorY, WORN_ICON_SIZE,
                WORN_ICON_SIZE,
                isIncluded and 1 or 0.45, 1, 1, 1)
        else
            list:drawText(tr("label_worn"), wornIndicatorX - 6 + contentOffsetX, y + 8, 0.94, 0.93, 0.88,
                isIncluded and 1 or 0.4, UIFont.Small)
        end
    end

    local labelText = item.text or getDraftRowLabel(draftItem)
    local maxTextW = (isCurrentlyWorn and wornIndicatorX or cbX) - 42
    local displayText = truncateText(labelText, UIFont.Small, maxTextW)
    local textAlpha = isIncluded and 1 or 0.4
    local textColor = isCurrentlyWorn and { 0.82, 0.96, 0.84 }
        or (isNearbyAvailable and { 0.62, 0.8, 0.98 } or { 0.94, 0.93, 0.88 })
    if isContextActive then
        textColor = isCurrentlyWorn and { 0.9, 0.98, 0.92 }
            or (isNearbyAvailable and { 0.78, 0.9, 1 } or { 0.98, 0.97, 0.92 })
    elseif isRowHovered then
        textColor = isCurrentlyWorn and { 0.88, 0.98, 0.9 }
            or (isNearbyAvailable and { 0.68, 0.84, 0.98 } or { 0.97, 0.96, 0.9 })
    end

    if self.draftReorderDrag and self.draftReorderDrag.sourceIndex == item.index then
        list:drawRect(0, y, list.width, rowHeight, 0.16, 0.26, 0.32, 0.22)
    end

    if isContextActive then
        list:drawText(displayText, 35 + contentOffsetX, y + 3, 0.06, 0.08, 0.1, textAlpha * 0.45, UIFont.Small)
    elseif isRowHovered then
        list:drawText(displayText, 35 + contentOffsetX, y + 3, 0.08, 0.1, 0.12, textAlpha * 0.55, UIFont.Small)
    end

    list:drawText(displayText, 34 + contentOffsetX, y + 2, textColor[1], textColor[2], textColor[3], textAlpha,
        UIFont.Small)

    if self.draftReorderDrag and self.draftReorderDrag.insertIndex == item.index then
        list:drawRect(6, y, list.width - 12, 2, 0.95, 0.44, 0.82, 0.98)
    end

    if self.draftReorderDrag and self.draftReorderDrag.insertIndex == (#(self.itemList.items or {}) + 1)
        and item.index == #(self.itemList.items or {}) then
        list:drawRect(6, y + rowHeight - 2, list.width - 12, 2, 0.95, 0.44, 0.82, 0.98)
    end

    return y + rowHeight
end

function OutfitManagerWindow:refreshCurrentWornLookup()
    self.currentWornLookup = {}
    self.currentWornTypeLookup = {}
    self.currentWornItemLookup = {}

    if not self.playerObj then
        self.wornLookupDirty = false
        return
    end

    for _, descriptor in ipairs(Capture.captureWornItems(self.playerObj) or {}) do
        local exactKey = getDescriptorLookupKey(descriptor)
        self.currentWornLookup[exactKey] = (self.currentWornLookup[exactKey] or 0) + 1

        if descriptor.item then
            self.currentWornItemLookup[descriptor.item] = true
        end

        local fullType = tostring(descriptor.fullType or "")
        if fullType ~= "" then
            self.currentWornTypeLookup[fullType] = (self.currentWornTypeLookup[fullType] or 0) + 1
        end
    end

    self.lastWornLookupRefreshAt = nowMs()
    self.wornLookupDirty = false
end

function OutfitManagerWindow:refreshCurrentNearbyLookup()
    self.currentNearbyLookup = {}
    self.currentNearbyTypeLookup = {}

    if not self.playerObj then
        self.nearbyLookupDirty = false
        return
    end

    local exactLookup, typeLookup = Search.getReachableDescriptorLookups(self.playerObj,
        self.editorDraft and self.editorDraft.items or nil)
    self.currentNearbyLookup = exactLookup or {}
    self.currentNearbyTypeLookup = typeLookup or {}
    self.lastSelectedLootContainer = Search.getSelectedLootContainer(self.playerObj)
    self.lastReachableLootContainers = Search.getReachableLootContainers(self.playerObj) or {}
    self.lastNearbyLookupRefreshAt = nowMs()

    self.nearbyLookupDirty = false
end

function OutfitManagerWindow:forceRefreshStateLookups()
    self:markWornLookupDirty()
    self:markNearbyLookupDirty()
    self:refreshStateLookups()
end

function OutfitManagerWindow:markWornLookupDirty()
    self.wornLookupDirty = true
end

function OutfitManagerWindow:markNearbyLookupDirty()
    self.nearbyLookupDirty = true
end

function OutfitManagerWindow:updateNearbyLookupDirtyState()
    if not self.playerObj then
        return
    end

    local square = self.playerObj:getCurrentSquare()
    local squareX = square and square:getX() or nil
    local squareY = square and square:getY() or nil
    local squareZ = square and square:getZ() or nil
    if squareX ~= self.lastPlayerSquareX or squareY ~= self.lastPlayerSquareY or squareZ ~= self.lastPlayerSquareZ then
        self.lastPlayerSquareX = squareX
        self.lastPlayerSquareY = squareY
        self.lastPlayerSquareZ = squareZ
        self:markNearbyLookupDirty()
    end

    local selectedLootContainer = Search.getSelectedLootContainer(self.playerObj)
    if selectedLootContainer ~= self.lastSelectedLootContainer then
        self.lastSelectedLootContainer = selectedLootContainer
        self:markNearbyLookupDirty()
    end

    local reachableLootContainers = Search.getReachableLootContainers(self.playerObj) or {}
    if not areContainerListsEqual(reachableLootContainers, self.lastReachableLootContainers) then
        self.lastReachableLootContainers = reachableLootContainers
        self:markNearbyLookupDirty()
    end
end

function OutfitManagerWindow:refreshStateLookups()
    self:updateNearbyLookupDirtyState()

    local currentTime = nowMs()
    if not self.wornLookupDirty and (currentTime - (self.lastWornLookupRefreshAt or 0)) >= STATE_LOOKUP_REFRESH_INTERVAL_MS then
        self:markWornLookupDirty()
    end

    if not self.nearbyLookupDirty and (currentTime - (self.lastNearbyLookupRefreshAt or 0)) >= STATE_LOOKUP_REFRESH_INTERVAL_MS then
        self:markNearbyLookupDirty()
    end

    if self.wornLookupDirty then
        self:refreshCurrentWornLookup()
    end

    if self.nearbyLookupDirty then
        self:refreshCurrentNearbyLookup()
    end
end

function OutfitManagerWindow:isDraftItemCurrentlyWorn(draftItem)
    if not draftItem then
        return false
    end

    local exactKey = getDescriptorLookupKey(draftItem)
    if (self.currentWornLookup[exactKey] or 0) > 0 then
        return true
    end

    local fullType = tostring(draftItem.fullType or "")
    return fullType ~= "" and (self.currentWornTypeLookup[fullType] or 0) > 0
end

function OutfitManagerWindow:isDraftItemNearbyAvailable(draftItem)
    if not draftItem then
        return false
    end

    local exactKey = getDescriptorLookupKey(draftItem)
    if (self.currentNearbyLookup[exactKey] or 0) > 0 then
        return true
    end

    local fullType = tostring(draftItem.fullType or "")
    return fullType ~= "" and (self.currentNearbyTypeLookup[fullType] or 0) > 0
end

function OutfitManagerWindow:getOutfitMatchCounts(outfit)
    local items = outfit and outfit.items or nil
    if not items or #items == 0 then
        return 0, 0
    end

    local exactCounts = copyLookupCounts(self.currentWornLookup)
    local typeCounts = copyLookupCounts(self.currentWornTypeLookup)
    local matchedCount = 0

    for _, descriptor in ipairs(items) do
        local exactKey = getDescriptorLookupKey(descriptor)
        if (exactCounts[exactKey] or 0) > 0 then
            exactCounts[exactKey] = exactCounts[exactKey] - 1

            local fullType = tostring(descriptor.fullType or "")
            if fullType ~= "" and (typeCounts[fullType] or 0) > 0 then
                typeCounts[fullType] = typeCounts[fullType] - 1
            end

            matchedCount = matchedCount + 1
        else
            local fullType = tostring(descriptor.fullType or "")
            if fullType ~= "" and (typeCounts[fullType] or 0) > 0 then
                typeCounts[fullType] = typeCounts[fullType] - 1
                matchedCount = matchedCount + 1
            end
        end
    end

    return matchedCount, #items
end

function OutfitManagerWindow:getActionProgressCount(progress)
    local entries = progress and progress.entries or nil
    if not entries or #entries == 0 then
        return 0, 0
    end

    local matchedCount = 0

    for _, entry in ipairs(entries) do
        local item = entry.item
        if item then
            if progress.mode == "wear" then
                if self.currentWornItemLookup[item] then
                    matchedCount = matchedCount + 1
                end
            elseif progress.mode == "inventory" then
                if not self.currentWornItemLookup[item] and item:getContainer() == self.playerObj:getInventory() then
                    matchedCount = matchedCount + 1
                end
            elseif progress.mode == "container" then
                if not self.currentWornItemLookup[item] and item:getContainer() == progress.targetContainer then
                    matchedCount = matchedCount + 1
                end
            end
        end
    end

    return matchedCount, #entries
end

function OutfitManagerWindow:getActiveProgressPhase()
    if not self.activeProgress then
        return nil
    end

    local phases = self.activeProgress.phases
    local index = self.activeProgress.phaseIndex or 1
    return phases and phases[index] or nil
end

function OutfitManagerWindow:syncActiveProgressPhaseState(currentEntryName)
    if not self.activeProgress then
        return
    end

    local phase = self:getActiveProgressPhase()
    if not phase then
        self.activeProgress.mode = nil
        self.activeProgress.entries = nil
        self.activeProgress.targetContainer = nil
        self.activeProgress.total = 0
        self.activeProgress.completed = 0
        self.activeProgress.phaseActionKey = nil
        self.activeProgress.currentEntryName = nil
        return
    end

    self.activeProgress.mode = phase.mode
    self.activeProgress.entries = phase.entries
    self.activeProgress.targetContainer = phase.targetContainer
    self.activeProgress.total = phase.total or #(phase.entries or {})
    self.activeProgress.completed = math.min(phase.completed or 0, self.activeProgress.total)
    self.activeProgress.phaseActionKey = phase.actionKey
    self.activeProgress.currentEntryName = currentEntryName or phase.currentEntryName
end

function OutfitManagerWindow:advanceWearProgressPhase()
    if not self.activeProgress then
        return false
    end

    local currentPhase = self:getActiveProgressPhase()
    if currentPhase then
        currentPhase.completed = currentPhase.total or #(currentPhase.entries or {})
    end

    local phases = self.activeProgress.phases or {}
    local nextIndex = (self.activeProgress.phaseIndex or 1) + 1
    while nextIndex <= #phases do
        local nextPhase = phases[nextIndex]
        if nextPhase and nextPhase.entries and #nextPhase.entries > 0 then
            self.activeProgress.phaseIndex = nextIndex
            nextPhase.completed = nextPhase.completed or 0
            nextPhase.currentEntryName = nil
            self:syncActiveProgressPhaseState()
            self:updateProgressButtonLayout()
            return true
        end

        nextIndex = nextIndex + 1
    end

    return false
end

function OutfitManagerWindow:getQueueBackedProgressCount(phase)
    if not phase or not phase.entries or #phase.entries == 0 then
        return 0, nil
    end

    local entryLookup = {}
    for _, entry in ipairs(phase.entries) do
        if entry.item then
            entryLookup[entry.item] = entry
        end
    end

    local snapshot = Apply.getTimedActionQueueSnapshot and Apply.getTimedActionQueueSnapshot(self.playerObj) or nil
    local remaining = 0
    local queuedEntry = nil
    local matchedActionCount = 0
    local stateCompleted = self:getActionProgressCount(phase)

    local function countQueuedTransferEntries(action)
        local queueList = action and action.queueList or nil
        if not queueList then
            return 0, nil
        end

        local count = 0
        local firstEntry = nil
        local seenItems = {}

        for _, queuedGroup in ipairs(queueList) do
            for _, queuedItem in ipairs(queuedGroup.items or {}) do
                if queuedItem and not seenItems[queuedItem] then
                    seenItems[queuedItem] = true
                    local entry = entryLookup[queuedItem]
                    if entry then
                        count = count + 1
                        if not firstEntry then
                            firstEntry = entry
                        end
                    end
                end
            end
        end

        return count, firstEntry
    end

    if snapshot and snapshot.actions then
        local seenActions = {}
        local expectedActionType = tostring(phase.actionType or "")

        local function scanQueuedAction(action)
            if not action or seenActions[action] then
                return
            end

            seenActions[action] = true

            local actionType = tostring(action and action.Type or "")
            local actionItem = action and action.item or nil
            local entry = actionItem and entryLookup[actionItem] or nil
            if not entry then
                return
            end

            local isPrimaryPhaseAction = actionType == expectedActionType
            local isWearTransferAction = phase.mode == "wear" and actionType == "ISInventoryTransferAction"

            if isPrimaryPhaseAction or isWearTransferAction then
                if not queuedEntry then
                    queuedEntry = entry
                end
            end

            if isPrimaryPhaseAction then
                if actionType == "ISInventoryTransferAction" then
                    local queuedCount, transferEntry = countQueuedTransferEntries(action)
                    if queuedCount > 0 then
                        matchedActionCount = matchedActionCount + queuedCount
                        remaining = remaining + queuedCount
                        if not queuedEntry then
                            queuedEntry = transferEntry
                        end
                    else
                        matchedActionCount = matchedActionCount + 1
                        remaining = remaining + 1
                    end
                else
                    matchedActionCount = matchedActionCount + 1
                    remaining = remaining + 1
                end
            end
        end

        scanQueuedAction(snapshot.current)
        for _, action in ipairs(snapshot.actions) do
            scanQueuedAction(action)
        end
    end

    local completed = stateCompleted
    if matchedActionCount > 0 then
        completed = math.max(completed, math.max((phase.total or #phase.entries) - remaining, 0))
    end

    local total = phase.total or #phase.entries
    if not queuedEntry and completed < total then
        queuedEntry = phase.entries[completed + 1]
    end

    return math.min(completed, total), queuedEntry
end

function OutfitManagerWindow:beginWearProgress(progress)
    local phases = {}
    if progress and progress.phases then
        for _, phase in ipairs(progress.phases) do
            if phase and phase.entries and #phase.entries > 0 then
                table.insert(phases, phase)
            end
        end
    else
        local fallbackPhase = getFallbackPhaseForProgress(progress)
        if fallbackPhase then
            table.insert(phases, fallbackPhase)
        end
    end

    if #phases == 0 then
        self.activeProgress = nil
        self:updateProgressButtonLayout()
        return
    end

    self.activeProgress = {
        outfitId = progress.outfitId,
        outfitName = progress.outfitName,
        phases = phases,
        phaseIndex = 1,
        completed = 0,
        total = phases[1].total or #(phases[1].entries or {}),
        endedAt = nil,
        state = "active",
    }

    self:syncActiveProgressPhaseState()
    self:updateProgressButtonLayout()
end

function OutfitManagerWindow:setProgressEnded(state)
    if not self.activeProgress then
        return
    end

    self.activeProgress.state = state
    self.activeProgress.endedAt = nowMs()
    if state == "completed" then
        local phase = self:getActiveProgressPhase()
        if phase then
            phase.completed = phase.total or #(phase.entries or {})
        end
        self:syncActiveProgressPhaseState()
        self.activeProgress.completed = self.activeProgress.total or self.activeProgress.completed or 0
    end

    self:updateProgressButtonLayout()
end

function OutfitManagerWindow:clearWearProgress()
    self.activeProgress = nil
    self:updateProgressButtonLayout()
end

function OutfitManagerWindow:updateWearProgress()
    if not self.activeProgress then
        return
    end

    if self.activeProgress.state ~= "active" then
        if nowMs() >= ((self.activeProgress.endedAt or nowMs()) + PROGRESS_HIDE_DELAY_MS) then
            self:clearWearProgress()
        end
        return
    end

    local phase = self:getActiveProgressPhase()
    if not phase then
        self:clearWearProgress()
        return
    end

    local total = phase.total or #(phase.entries or {})
    local completed, queuedEntry = self:getQueueBackedProgressCount(phase)
    phase.completed = completed
    phase.currentEntryName = getProgressEntryDisplayName(queuedEntry)
    self:syncActiveProgressPhaseState(phase.currentEntryName)

    if total <= 0 then
        if not self:advanceWearProgressPhase() then
            self:clearWearProgress()
        end
        return
    end

    if completed >= total then
        if not self:advanceWearProgressPhase() then
            self:setProgressEnded("completed")
        end
        return
    end

    if not Apply.isTimedActionQueueActive(self.playerObj) then
        self:setProgressEnded("interrupted")
    end
end

function OutfitManagerWindow:drawWearProgressBar()
    if not self.activeProgress or (self.activeProgress.total or 0) <= 0 then
        return
    end

    local barX = self.progressBarX or self.leftPaneX or 12
    local barY = self.progressBarY or (self.height - (BOTTOM_SECTION_PADDING + PROGRESS_ROW_HEIGHT))
    local reserveStopSpace = self.activeProgress.state == "active"
    local stopButtonWidth = reserveStopSpace and
        (self.stopProgressButton and self.stopProgressButton:getWidth() or measureButtonWidth(tr("button_stop"), 72, 22))
        or 0
    local stopGap = reserveStopSpace and PROGRESS_STOP_GAP or 0
    local barW = self.width - barX - 12 - stopButtonWidth - stopGap
    local barH = PROGRESS_ROW_HEIGHT
    if barW <= 2 then
        return
    end

    local isInterrupted = self.activeProgress.state == "interrupted"
    local isCompleted = self.activeProgress.state == "completed"
    local completed = math.min(self.activeProgress.completed or 0, self.activeProgress.total or 0)
    local total = math.max(self.activeProgress.total or 0, 1)
    local fillW = math.floor((barW - 2) * (completed / total))

    if isInterrupted then
        self:drawRect(barX, barY, barW, barH, 0.46, 0.12, 0.03, 0.03)
        self:drawRectBorder(barX, barY, barW, barH, 0.68, 0.62, 0.18, 0.18)
        drawInterruptedProgressFill(self, barX + 1, barY + 1, barW - 2, barH - 2)
    else
        self:drawRect(barX, barY, barW, barH, 0.4, 0.06, 0.08, 0.1)
        self:drawRectBorder(barX, barY, barW, barH, 0.45, 0.28, 0.34, 0.32)
        if fillW > 0 then
            drawProgressFillGradient(self, barX + 1, barY + 1, fillW, barH - 2)
        end
    end

    local actionText = tr(self.activeProgress.phaseActionKey or "progress_action_wearing")
    local currentEntryName = tostring(self.activeProgress.currentEntryName or "")
    local label = ""
    if isInterrupted then
        label = tr("progress_interrupted_phase", actionText, completed, total)
    elseif isCompleted then
        label = tr("progress_completed_phase", actionText, completed, total)
    elseif currentEntryName ~= "" then
        label = tr("progress_status_with_item", actionText, currentEntryName, completed, total)
    else
        label = tr("progress_status_count", actionText, completed, total)
    end
    self:drawTextCentre(label, barX + math.floor(barW / 2), barY + 1,
        0.96, 0.94, 0.9, 1, UIFont.Small)
end

function OutfitManagerWindow:hideDraftDebugTooltip()
    if self.draftDebugTooltip and self.draftDebugTooltip:getIsVisible() then
        self.draftDebugTooltip:setVisible(false)
        self.draftDebugTooltip:removeFromUIManager()
    end
end

function OutfitManagerWindow:updateDraftDebugTooltip()
    if not Data.isDebugMode() or not self.itemList or not self.itemList:isMouseOver() then
        self:hideDraftDebugTooltip()
        return
    end

    local mouseX = getMouseX() - self.itemList:getAbsoluteX()
    local mouseY = getMouseY() - self.itemList:getAbsoluteY()
    local row = self:getDraftRowIndexAtPosition(mouseX, mouseY)
    local rowItem = row and self.itemList.items[row] or nil
    if not rowItem or not rowItem.item then
        self:hideDraftDebugTooltip()
        return
    end

    local tooltipText = rowItem.text or getDraftRowLabel(rowItem.item)
    if tooltipText == "" then
        self:hideDraftDebugTooltip()
        return
    end

    if not self.draftDebugTooltip then
        self.draftDebugTooltip = ISToolTip:new()
        self.draftDebugTooltip:setOwner(self.itemList)
        self.draftDebugTooltip:setVisible(false)
        self.draftDebugTooltip:setAlwaysOnTop(true)
        self.draftDebugTooltip.maxLineWidth = 1000
    end

    if not self.draftDebugTooltip:getIsVisible() then
        self.draftDebugTooltip:addToUIManager()
        self.draftDebugTooltip:setVisible(true)
    end

    self.draftDebugTooltip.description = tooltipText
    self.draftDebugTooltip:setX(getMouseX() + 23)
    self.draftDebugTooltip:setY(getMouseY() + 23)
end

function OutfitManagerWindow:drawDraftDropHint()
    local x = self.itemList:getX()
    local y = self.itemList:getY()
    local width = self.itemList:getWidth()
    local height = self.itemList:getHeight()
    local isHovered = self:hasDraggedInventoryItems() and self.itemList:isMouseOver()
    local hasItems = #(self.editorDraft.items or {}) > 0
    local hasOverlay = self.draftOverlayText and self.draftOverlayUntil > nowMs()

    self:drawRect(x, y, width, height, hasItems and 0.06 or 0.14, 0.04, 0.07, 0.07)

    self:drawRectBorder(x, y, width, height, isHovered and 0.45 or 0.2, isHovered and 0.4 or 0.22,
        isHovered and 0.6 or 0.3,
        isHovered and 0.28 or 0.18)

    if hasOverlay then
        self:drawRect(x + 1, y + 1, width - 2, height - 2, self.draftOverlayIsError and 0.86 or 0.72,
            self.draftOverlayIsError and 0.18 or 0.1,
            self.draftOverlayIsError and 0.08 or 0.18,
            self.draftOverlayIsError and 0.08 or 0.1)
        self:drawTextCentre(self.draftOverlayText, x + (width / 2), y + math.floor(height / 2) - 6,
            0.96, 0.92, 0.88, 1, UIFont.Medium)
    elseif not hasItems then
        self:drawTextCentre(tr("drop_hint_drag_here"), x + (width / 2), y + math.floor(height / 2) - 10,
            isHovered and 0.92 or 0.62, isHovered and 0.92 or 0.64, isHovered and 0.82 or 0.56, 0.95, UIFont.Medium)
        self:drawTextCentre(tr("drop_hint_capture"), x + (width / 2),
            y + math.floor(height / 2) + 10,
            0.5, 0.52, 0.48, 0.85, UIFont.Small)
    elseif isHovered then
        self:drawTextCentre(tr("drop_hint_release"), x + (width / 2), y + 10, 0.86, 0.9, 0.76, 0.95,
            UIFont.Small)
    end
end

function OutfitManagerWindow:render()
    self.draftRowHitBounds = {}
    ISPanel.render(self)
    self:updateDraftDebugTooltip()

    local mouseX = getMouseX() - self:getAbsoluteX()
    local mouseY = getMouseY() - self:getAbsoluteY()
    local closeX, closeY, closeW, closeH = getCloseIconBounds(self)
    local closeHovered = mouseX >= closeX and mouseX <= (closeX + closeW) and mouseY >= closeY and
        mouseY <= (closeY + closeH)

    self:drawRect(0, 0, self.width, self.headerHeight, 0.95, 0.11, 0.11, 0.13)
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g,
        self.borderColor.b)
    self:drawText(tr("title"), 14, 2, 0.99, 0.96, 0.88, 1, UIFont.Medium)

    if closeHovered and CLOSE_ICON_HOVER then
        self:drawTextureScaled(CLOSE_ICON_HOVER, closeX, closeY, closeW, closeH, 1, 1, 1, 1)
    elseif CLOSE_ICON then
        self:drawTextureScaled(CLOSE_ICON, closeX, closeY, closeW, closeH, 1, 1, 1, 1)
    else
        self:drawText("X", closeX + 4, closeY - 1, 0.95, 0.9, 0.88, 1, UIFont.Medium)
    end

    local paneTopY = self.headerHeight + 8
    local paneBottomY = (self.actionButtonsBaseY or (self.height - 84)) - 12
    local paneHeight = math.max(0, paneBottomY - paneTopY)

    self:drawRect(12, paneTopY, 280, paneHeight, 0.2, 0.1, 0.1, 0.12)
    self:drawRectBorder(12, paneTopY, 280, paneHeight, 0.22, 0.36, 0.32, 0.2)
    self:drawRect(306, paneTopY, self.width - 318, paneHeight, 0.16, 0.1, 0.1, 0.12)
    self:drawRectBorder(306, paneTopY, self.width - 318, paneHeight, 0.2, 0.36, 0.32, 0.2)

    self:drawText(tr("label_outfits"), 20, self.headerHeight + 12, 0.92, 0.86, 0.68, 1, UIFont.Small)
    self:drawText(getEditorTitle(self), 308, self.headerHeight + 10, 0.92, 0.86, 0.68, 1, UIFont.Small)

    if self.languageCombo then
        self:drawText(tr("debug_preview_language"), self.languageCombo:getX(), self.languageCombo:getY() - 18,
            0.76, 0.82, 0.78, 0.95, UIFont.Small)
    end

    self:drawRect(310, self.headerHeight + 100, self.width - 326, 1, 0.16, 0.38, 0.34, 0.2)
    self:drawText(tr("label_items_in_outfit"), 308, self.headerHeight + 104, 0.6, 0.58, 0.5, 1, UIFont.Small)

    self:drawRect(12, paneBottomY + 4, self.width - 24, 1, 0.14, 0.32, 0.3, 0.18)

    self:drawDraftDropHint()
    self:drawWearProgressBar()
end

function OutfitManagerWindow:update()
    ISPanel.update(self)
    self:refreshStateLookups()
    self:updateDraftContextHighlightState()
    self:updateWearProgress()
    self:updateSaveButtonState()

    if self.draftReorderDrag then
        self:updateDraftReorderInsertIndex()
    end

    if self.draftOverlayUntil > 0 and self.draftOverlayUntil <= nowMs() then
        self.draftOverlayText = nil
        self.draftOverlayIsError = false
        self.draftOverlayUntil = 0
    end

    local hasDrag = self:hasDraggedInventoryItems()
    if hasDrag and not isMouseButtonDown(0) then
        if not self.didHandleDragRelease then
            self.didHandleDragRelease = true
            self:tryAcceptDraggedItems()
        end
    else
        self.didHandleDragRelease = false
    end
end

function OutfitManagerWindow:onMouseDown(x, y)
    local closeX, closeY, closeW, closeH = getCloseIconBounds(self)
    if x >= closeX and x <= (closeX + closeW) and y >= closeY and y <= (closeY + closeH) then
        self:onCloseButton()
        return true
    end

    if y <= self.headerHeight then
        self.moveWithMouse = true
        self.dragStartX = x
        self.dragStartY = y
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function OutfitManagerWindow:onMouseMove(dx, dy)
    if self.moveWithMouse then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
        return true
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function OutfitManagerWindow:onMouseMoveOutside(dx, dy)
    if self.moveWithMouse then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
        return true
    end
    return ISPanel.onMouseMoveOutside(self, dx, dy)
end

function OutfitManagerWindow:onMouseUp(x, y)
    self.moveWithMouse = false
    self:finishDraftReorderDrag()
    return ISPanel.onMouseUp(self, x, y)
end

function OutfitManagerWindow:onMouseUpOutside(x, y)
    self.moveWithMouse = false
    self:finishDraftReorderDrag()
    return ISPanel.onMouseUpOutside(self, x, y)
end

function OutfitManagerWindow:onCloseButton()
    self:close()
end

function OutfitManagerWindow:close()
    self:hideDraftDebugTooltip()
    self:clearDraftContextHighlight()
    if self.playerObj then
        Data.saveWindowState(self.playerObj, self:getX(), self:getY(), self:getWidth(), self:getHeight())
    end
    if OutfitManagerWindow.instance == self then
        OutfitManagerWindow.instance = nil
    end
    self:removeFromUIManager()
end

function OutfitManagerWindow:setStatus(text, isError)
    self.statusText = text
    self.statusIsError = isError == true
end

function OutfitManagerWindow:setDraftOverlay(text, isError, durationMs)
    self.draftOverlayText = text
    self.draftOverlayIsError = isError == true
    self.draftOverlayUntil = nowMs() + (durationMs or 2200)
end

function OutfitManagerWindow:getCurrentDraftSnapshot()
    return {
        name = self.nameEntry and self.nameEntry:getText() or tostring(self.editorDraft and self.editorDraft.name or ""),
        itemsSignature = buildDraftItemsSignature(self.editorDraft and self.editorDraft.items or {}),
    }
end

function OutfitManagerWindow:setSavedDraftSnapshot(draft)
    self.savedDraftSnapshot = {
        name = tostring(draft and draft.name or ""),
        itemsSignature = buildDraftItemsSignature(draft and draft.items or {}),
    }
    self:updateSaveButtonState()
end

function OutfitManagerWindow:hasUnsavedChanges()
    if not self.editorDraft or not self.savedDraftSnapshot then
        return false
    end

    local current = self:getCurrentDraftSnapshot()
    return current.name ~= self.savedDraftSnapshot.name
        or current.itemsSignature ~= self.savedDraftSnapshot.itemsSignature
end

function OutfitManagerWindow:updateSaveButtonState()
    if not self.saveButton then
        return
    end

    local isDirty = self:hasUnsavedChanges()
    self.saveButton.enable = isDirty
    self.saveButton.borderColor = isDirty
        and { r = 0.3, g = 0.6, b = 0.3, a = 0.9 }
        or { r = 0.2, g = 0.24, b = 0.22, a = 0.65 }
    self.saveButton.backgroundColor = isDirty
        and { r = 0.08, g = 0.18, b = 0.08, a = 0.95 }
        or { r = 0.08, g = 0.09, b = 0.09, a = 0.72 }
end

function OutfitManagerWindow:hasDraggedInventoryItems()
    return ISMouseDrag and ISMouseDrag.dragging and #ISMouseDrag.dragging > 0
end

function OutfitManagerWindow:getDraggedInventoryItems()
    if not self:hasDraggedInventoryItems() then
        return {}
    end
    return getActualDraggedItems(ISMouseDrag.dragging)
end

function OutfitManagerWindow:tryAcceptDraggedItems()
    if not self.itemList or not self.itemList:isMouseOver() then
        return false
    end

    local draggedItems = self:getDraggedInventoryItems()
    if #draggedItems == 0 then
        return false
    end

    local added, duplicate, rejected = Capture.addInventoryItemsToDraft(self.editorDraft, draggedItems)
    if added <= 0 then
        if rejected > 0 and duplicate > 0 then
            self:setStatus(tr("draft_error_wearable_duplicates"), true)
            self:setDraftOverlay(tr("draft_overlay_wearable_duplicates"), true)
        elseif rejected > 0 then
            self:setStatus(tr("draft_error_only_wearable"), true)
            self:setDraftOverlay(tr("draft_overlay_only_wearable"), true)
        else
            self:setStatus(tr("draft_error_already_present"), true)
            self:setDraftOverlay(tr("draft_overlay_already_present"), true)
        end
        clearAcceptedDrag()
        return true
    end

    self:refreshDraftList(true)

    local status = tr("draft_added", added)
    if duplicate > 0 or rejected > 0 then
        status = status .. tr("draft_added_ignored", duplicate, rejected)
    end
    self:setStatus(status, false)
    clearAcceptedDrag()
    return true
end

function OutfitManagerWindow:reloadOutfits()
    self.outfits = Data.getOutfits(self.playerObj)
    resetListState(self.outfitList, 0)
    for _, outfit in ipairs(self.outfits) do
        self.outfitList:addItem(outfit.name, outfit)
    end

    if self.selectedOutfitId then
        self.outfitList.selected = 0
        for index, item in ipairs(self.outfitList.items) do
            if item.item.id == self.selectedOutfitId then
                self.outfitList.selected = index
                break
            end
        end
    else
        self.outfitList.selected = 0
    end
end

function OutfitManagerWindow:refreshDraftList(preserveNameText)
    local currentNameText = nil
    local selectedIndex = -1
    local yScroll = 0
    local preserveScroll = false

    if type(preserveNameText) == "table" then
        preserveScroll = preserveNameText.preserveScroll == true
        preserveNameText = preserveNameText.preserveNameText == true
    end

    if preserveNameText and self.nameEntry then
        currentNameText = self.nameEntry:getText()
        if self.editorDraft then
            self.editorDraft.name = currentNameText
        end
    end

    if preserveScroll and self.itemList then
        selectedIndex = self.itemList.selected or -1
        yScroll = self.itemList:getYScroll() or 0
    end

    resetListState(self.itemList, -1)
    self.itemList.smoothScrollTargetY = preserveScroll and yScroll or nil
    self.itemList.smoothScrollY = preserveScroll and yScroll or nil
    for _, item in ipairs(self.editorDraft.items or {}) do
        self.itemList:addItem(getDraftRowLabel(item), item)
    end

    if preserveScroll then
        self.itemList.selected = selectedIndex > 0 and math.min(selectedIndex, #self.itemList.items) or -1
        self.itemList.mouseoverselected = self.itemList.selected
        self.itemList:setYScroll(math.max(0, yScroll))
    end

    self.nameEntry:setText(currentNameText or self.editorDraft.name or "")
    self:markNearbyLookupDirty()
end

function OutfitManagerWindow:getDraftVisibleRowY(row)
    if not self.itemList or not row then
        return nil
    end

    local bounds = self.draftRowHitBounds and self.draftRowHitBounds[row] or nil
    if bounds then
        return bounds.rowY
    end

    local y = self.itemList:getYScroll() or 0
    for index = 1, row - 1 do
        y = y + self:getDraftRowHeight(index)
    end

    return y
end

function OutfitManagerWindow:getDraftRowHeight(row)
    if not self.itemList or not row then
        return nil
    end

    local rowItem = self.itemList.items and self.itemList.items[row] or nil
    return rowItem and (rowItem.height or self.itemList.itemheight) or self.itemList.itemheight
end

function OutfitManagerWindow:getDraftRowIndexAtPosition(x, y)
    if not self.itemList or #self.itemList.items == 0 then
        return nil
    end

    if x < 0 or x > self.itemList.width then
        return nil
    end

    for row, bounds in pairs(self.draftRowHitBounds or {}) do
        if bounds and y >= bounds.rowY and y < (bounds.rowY + bounds.rowHeight) then
            return row
        end
    end

    for row = 1, #self.itemList.items do
        local rowY = self:getDraftVisibleRowY(row)
        local rowHeight = self:getDraftRowHeight(row)
        if rowY and rowHeight and y >= rowY and y < (rowY + rowHeight) then
            return row
        end
    end

    return nil
end

function OutfitManagerWindow:getDraftRowAtPosition(x, y)
    if not self.itemList or #self.itemList.items == 0 then
        return nil, nil
    end

    local row = self:getDraftRowIndexAtPosition(x, y)
    local rowItem = row and self.itemList.items[row] or nil
    if not rowItem or not rowItem.item then
        return nil, nil
    end

    return row, rowItem
end

function OutfitManagerWindow:runDraftItemAction(draftItem, actionFn)
    if not draftItem or not actionFn then
        return
    end

    local result, err = actionFn(self.playerObj, draftItem)
    if not result then
        self:setStatus(err, true)
        return
    end

    self:beginWearProgress(Apply.consumeLastWearProgress())

    local summary, isError = summarizeResult({ name = itemLabel(draftItem) }, result)
    self:setStatus(summary, isError)
end

function OutfitManagerWindow:showDraftItemContextMenu(row, draftItem)
    if not draftItem then
        return false
    end

    self.itemList.selected = row
    self.itemList.mouseoverselected = row

    local context = ISContextMenu.get(self.playerNum, getMouseX(), getMouseY())
    self.activeDraftContextRow = row
    self.activeDraftContextMenu = context
    context:addOption(tr("context_item_wear"), self, function(window, item)
        window:runDraftItemAction(item, Apply.addItem)
    end, draftItem)
    context:addOption(tr("context_item_take_off"), self, function(window, item)
        window:runDraftItemAction(item, Apply.removeItemToInventory)
    end, draftItem)
    context:addOption(tr("context_item_grab"), self, function(window, item)
        window:runDraftItemAction(item, Apply.grabItemToInventory)
    end, draftItem)
    context:addOption(tr("context_item_place"), self, function(window, item)
        window:runDraftItemAction(item, Apply.placeItemInContainer)
    end, draftItem)

    return true
end

function OutfitManagerWindow:clearDraftContextHighlight()
    self.activeDraftContextRow = nil
    self.activeDraftContextMenu = nil
end

function OutfitManagerWindow:isDraftContextMenuOpen()
    return isUiElementVisible(self.activeDraftContextMenu)
end

function OutfitManagerWindow:updateDraftContextHighlightState()
    if self.activeDraftContextMenu and not self:isDraftContextMenuOpen() then
        self:clearDraftContextHighlight()
    end
end

function OutfitManagerWindow:getDraftReorderInsertIndexFromMouse()
    if not self.itemList or not self.editorDraft then
        return nil
    end

    local itemCount = #(self.editorDraft.items or {})
    if itemCount <= 1 then
        return nil
    end

    local mouseX = getMouseX() - self.itemList:getAbsoluteX()
    local mouseY = getMouseY() - self.itemList:getAbsoluteY()
    local row = self:getDraftRowIndexAtPosition(mouseX, mouseY)

    if not row then
        if mouseY < 0 then
            return 1
        end

        return itemCount + 1
    end

    local rowItem = self.itemList.items[row]
    if not rowItem then
        return itemCount + 1
    end

    local rowTop = self:getDraftVisibleRowY(row)
    local rowHeight = rowItem.height or self.itemList.itemheight
    if rowTop and mouseY >= (rowTop + math.floor(rowHeight / 2)) then
        return row + 1
    end

    return row
end

function OutfitManagerWindow:updateDraftReorderInsertIndex()
    if not self.draftReorderDrag then
        return
    end

    local itemCount = #(self.editorDraft and self.editorDraft.items or {})
    if itemCount <= 1 then
        self.draftReorderDrag.insertIndex = nil
        return
    end

    local insertIndex = self:getDraftReorderInsertIndexFromMouse()
    if not insertIndex then
        self.draftReorderDrag.insertIndex = nil
        return
    end

    self.draftReorderDrag.insertIndex = clamp(insertIndex, 1, itemCount + 1)
end

function OutfitManagerWindow:startDraftReorderDrag(sourceIndex)
    local itemCount = #(self.editorDraft and self.editorDraft.items or {})
    if not sourceIndex or sourceIndex < 1 or sourceIndex > itemCount or itemCount <= 1 then
        return false
    end

    self.draftReorderDrag = {
        sourceIndex = sourceIndex,
        insertIndex = sourceIndex,
    }
    self:updateDraftReorderInsertIndex()
    return true
end

function OutfitManagerWindow:moveDraftItem(sourceIndex, targetIndex)
    local items = self.editorDraft and self.editorDraft.items or nil
    if not items then
        return false
    end

    local itemCount = #items
    sourceIndex = clamp(sourceIndex or 0, 1, itemCount)
    targetIndex = clamp(targetIndex or 0, 1, itemCount + 1)

    if targetIndex > sourceIndex then
        targetIndex = targetIndex - 1
    end

    if targetIndex == sourceIndex then
        return false
    end

    local movedItem = table.remove(items, sourceIndex)
    table.insert(items, targetIndex, movedItem)
    self:refreshDraftList({ preserveNameText = true, preserveScroll = true })
    self.itemList.selected = targetIndex
    self.itemList.mouseoverselected = targetIndex
    return true
end

function OutfitManagerWindow:finishDraftReorderDrag()
    local drag = self.draftReorderDrag
    if not drag then
        return false
    end

    self.draftReorderDrag = nil
    local didMove = self:moveDraftItem(drag.sourceIndex, drag.insertIndex or drag.sourceIndex)
    return didMove
end

function OutfitManagerWindow:updateDraftListHoverFromMouse()
    if not self.itemList then
        return nil
    end

    if not self.itemList:isMouseOver() or self.itemList:isMouseOverScrollBar() then
        self.itemList.mouseoverselected = 0
        return nil
    end

    local mouseX = getMouseX() - self.itemList:getAbsoluteX()
    local mouseY = getMouseY() - self.itemList:getAbsoluteY()
    local row = self:getDraftRowIndexAtPosition(mouseX, mouseY)
    self.itemList.mouseoverselected = row or 0
    return row
end

function OutfitManagerWindow:onDraftListMouseMove(dx, dy)
    self:updateDraftListHoverFromMouse()

    if self.draftReorderDrag then
        self:updateDraftReorderInsertIndex()
        return true
    end

    return false
end

function OutfitManagerWindow:onDraftListMouseMoveOutside(dx, dy)
    if self.itemList then
        self.itemList.mouseoverselected = 0
    end

    return false
end

function OutfitManagerWindow:onDraftListMouseUp(x, y)
    self:updateDraftListHoverFromMouse()

    if self.draftReorderDrag then
        self:updateDraftReorderInsertIndex()
        self:finishDraftReorderDrag()
        return true
    end

    return false
end

function OutfitManagerWindow:getSelectedOutfit()
    if not self.selectedOutfitId then
        return nil
    end
    return Data.getOutfitById(self.playerObj, self.selectedOutfitId)
end

function OutfitManagerWindow:resetDraftFromCurrent(selectedOutfit, markClean)
    self.editorDraft = Capture.buildDraftFromCurrent(self.playerObj, selectedOutfit)
    if selectedOutfit then
        self.editorDraft.name = selectedOutfit.name
    end
    self:refreshDraftList()

    if markClean then
        self:setSavedDraftSnapshot(self.editorDraft)
    elseif selectedOutfit then
        self:setSavedDraftSnapshot(selectedOutfit)
    end
end

function OutfitManagerWindow:loadDraftFromOutfit(outfit)
    self.editorDraft = Data.buildEditableDraft(outfit)
    self:refreshDraftList()
    self:setSavedDraftSnapshot(outfit)
end

function OutfitManagerWindow:onOutfitSelected(outfit)
    self.selectedOutfitId = outfit.id
    self:loadDraftFromOutfit(outfit)
    self:forceRefreshStateLookups()
    self:setStatus(tr("status_selected_outfit", outfit.name), false)
end

function OutfitManagerWindow:onDraftListMouseDown(x, y)
    if #self.itemList.items == 0 then
        return true
    end

    local localMouseX = getMouseX() - self.itemList:getAbsoluteX()
    local localMouseY = getMouseY() - self.itemList:getAbsoluteY()

    local row, rowItem = self:getDraftRowAtPosition(localMouseX, localMouseY)
    if not rowItem then
        return true
    end

    local bounds = self.draftRowHitBounds and self.draftRowHitBounds[row] or nil
    local buttonX = bounds and bounds.buttonX or nil
    local buttonY = bounds and bounds.buttonY or nil
    local buttonW = bounds and bounds.buttonSize or nil
    local buttonH = bounds and bounds.buttonSize or nil
    if not buttonX or not buttonY or not buttonW or not buttonH then
        local rowY = self:getDraftVisibleRowY(row)
        buttonX, buttonY, buttonW, buttonH = getDraftRemoveButtonBounds(self.itemList, rowY,
            rowItem.height or self.itemList.itemheight)
    end
    if localMouseX >= buttonX and localMouseX <= (buttonX + buttonW)
        and localMouseY >= buttonY and localMouseY <= (buttonY + buttonH) then
        rowItem.item.included = rowItem.item.included == false
        self.itemList.selected = row
        self.itemList.mouseoverselected = row
        self:refreshDraftList({ preserveNameText = true, preserveScroll = true })
        return true
    end

    self.itemList.selected = row
    self.itemList.mouseoverselected = row
    self:startDraftReorderDrag(row)
    return true
end

function OutfitManagerWindow:onDraftListRightMouseUp(x, y)
    local localMouseX = getMouseX() - self.itemList:getAbsoluteX()
    local localMouseY = getMouseY() - self.itemList:getAbsoluteY()
    local row, rowItem = self:getDraftRowAtPosition(localMouseX, localMouseY)
    if not rowItem then
        return false
    end

    self.draftReorderDrag = nil
    return self:showDraftItemContextMenu(row, rowItem.item)
end

function OutfitManagerWindow:buildDraftFromEditor()
    return {
        name = self.nameEntry:getText(),
        items = self.editorDraft.items,
    }
end

function OutfitManagerWindow:onCaptureCurrent()
    local selectedOutfit = self:getSelectedOutfit()
    self:resetDraftFromCurrent(selectedOutfit, false)
    self:forceRefreshStateLookups()
    self:setStatus(tr("status_captured_current"), false)
end

function OutfitManagerWindow:onNewDraft()
    self.selectedOutfitId = nil
    self.outfitList.selected = 0
    self.editorDraft = Capture.buildEmptyDraft(self.playerObj)
    self.activeProgress = nil
    self.draftOverlayText = nil
    self.draftOverlayIsError = false
    self.draftOverlayUntil = 0
    self:refreshDraftList()
    self:setSavedDraftSnapshot(self.editorDraft)
    self:forceRefreshStateLookups()
    self:setStatus(tr("status_new_draft"), false)
end

function OutfitManagerWindow:onSaveNew()
    if not self:hasUnsavedChanges() then
        return
    end

    local draft = self:buildDraftFromEditor()
    local selected = self:getSelectedOutfit()
    local existing = selected or getOutfitByName(self.playerObj, draft.name)
    local outfit, err = Data.saveOutfit(self.playerObj, draft, existing and existing.id or nil)
    if not outfit then
        self:setStatus(err, true)
        return
    end

    self.selectedOutfitId = outfit.id
    self:reloadOutfits()
    self:loadDraftFromOutfit(outfit)
    if selected or existing then
        self:setStatus(tr("status_saved_changes", outfit.name), false)
    else
        self:setStatus(tr("status_saved_new", outfit.name), false)
    end
end

function OutfitManagerWindow:onDelete()
    local selected = self:getSelectedOutfit()
    if not selected then
        self:setStatus(tr("status_select_before_delete"), true)
        return
    end

    local modal = ISModalDialog:new(self:getX() + 180, self:getY() + 160, 320, 140, tr("delete_confirm", selected.name),
        true, self, self.onDeleteConfirmed, self.playerNum, selected.id)
    modal:initialise()
    modal:addToUIManager()
end

function OutfitManagerWindow:onDeleteConfirmed(button, outfitId)
    if button.internal ~= "YES" then
        return
    end

    if Data.deleteOutfit(self.playerObj, outfitId) then
        self.selectedOutfitId = nil
        self:reloadOutfits()
        self:onNewDraft()
        self:setStatus(tr("status_deleted"), false)
    else
        self:setStatus(tr("status_delete_failed"), true)
    end
end

function OutfitManagerWindow:onWear()
    local selected = self:getSelectedOutfit()
    if not selected then
        self:setStatus(tr("status_select_before_wear"), true)
        return
    end

    local result, err = Apply.wearOutfit(self.playerObj, selected)
    if not result then
        self:setStatus(err, true)
        return
    end

    self:beginWearProgress(Apply.consumeLastWearProgress())

    local summary, isError = summarizeResult(selected, result)
    self:setStatus(summary, isError)
end

function OutfitManagerWindow:onAdd()
    local selected = self:getSelectedOutfit()
    if not selected then
        self:setStatus(tr("status_select_before_add"), true)
        return
    end

    local result, err = Apply.addOutfit(self.playerObj, selected)
    if not result then
        self:setStatus(err, true)
        return
    end

    self:beginWearProgress(Apply.consumeLastWearProgress())

    local summary, isError = summarizeResult(selected, result)
    self:setStatus(summary, isError)
end

function OutfitManagerWindow:onPlaceInContainer()
    local selected = self:getSelectedOutfit()
    if not selected then
        self:setStatus(tr("status_select_before_place"), true)
        return
    end

    local result, err = Apply.placeOutfitInContainer(self.playerObj, selected)
    if not result then
        self:setStatus(err, true)
        return
    end

    self:beginWearProgress(Apply.consumeLastWearProgress())

    local summary, isError = summarizeResult(selected, result)
    self:setStatus(summary, isError)
end

function OutfitManagerWindow:onGrabAll()
    local selected = self:getSelectedOutfit()
    if not selected then
        self:setStatus(tr("status_select_before_grab"), true)
        return
    end

    local result, err = Apply.grabOutfitToInventory(self.playerObj, selected)
    if not result then
        self:setStatus(err, true)
        return
    end

    self:beginWearProgress(Apply.consumeLastWearProgress())

    local summary, isError = summarizeResult(selected, result)
    self:setStatus(summary, isError)
end

function OutfitManagerWindow:onRemove()
    local selected = self:getSelectedOutfit()
    if not selected then
        self:setStatus(tr("status_select_before_remove"), true)
        return
    end

    local result, err = Apply.removeOutfitToInventory(self.playerObj, selected)
    if not result then
        self:setStatus(err, true)
        return
    end

    self:beginWearProgress(Apply.consumeLastWearProgress())

    local summary, isError = summarizeResult(selected, result)
    self:setStatus(summary, isError)
end

function OutfitManagerWindow:onStopProgress()
    if not self.activeProgress or self.activeProgress.state ~= "active" then
        return
    end

    Apply.stopTimedActionQueue(self.playerObj)
    self:setProgressEnded("interrupted")
end

local function getOpenWindow()
    return OutfitManagerWindow.instance
end

local function markOpenWindowNearbyLookupDirty()
    local window = getOpenWindow()
    if window then
        window:markNearbyLookupDirty()
    end
end

local function markOpenWindowWornLookupDirty(playerObj)
    local window = getOpenWindow()
    if not window then
        return
    end

    if not playerObj or window.playerObj == playerObj then
        window:markWornLookupDirty()
    end
end

if not QuickFits.UI._outfitManagerWindowEventsRegistered then
    QuickFits.UI._outfitManagerWindowEventsRegistered = true

    Events.OnClothingUpdated.Add(function(playerObj)
        markOpenWindowWornLookupDirty(playerObj)
    end)

    Events.OnContainerUpdate.Add(function()
        markOpenWindowNearbyLookupDirty()
    end)

    Events.OnRefreshInventoryWindowContainers.Add(function(page)
        local window = getOpenWindow()
        if not window then
            return
        end

        if not page or page.player == window.playerNum then
            window:markNearbyLookupDirty()
        end
    end)

    Events.OnObjectAdded.Add(function()
        markOpenWindowNearbyLookupDirty()
    end)

    Events.OnObjectAboutToBeRemoved.Add(function()
        markOpenWindowNearbyLookupDirty()
    end)
end
