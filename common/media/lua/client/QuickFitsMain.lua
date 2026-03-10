---@diagnostic disable: undefined-global

QuickFits = QuickFits or {}

local DEFAULT_OPEN_WINDOW_KEY = Keyboard.KEY_BACKSLASH or 43

require "QuickFits/Localization"
require "QuickFits/Data"
require "QuickFits/Capture"
require "QuickFits/Search"
require "QuickFits/Apply"
require "QuickFits/UI/OutfitManagerWindow"
require "QuickFits/Integration/InventoryButton"
require "QuickFits/Integration/ContextFallback"

local Localization = QuickFits.Localization

local function getOpenWindowBindLabel()
    return Localization.getText("bind_open")
end

local function initKeyBindings()
    table.insert(keyBinding, { value = "[" .. Localization.getText("title") .. "]" })
    table.insert(keyBinding, { value = getOpenWindowBindLabel(), key = DEFAULT_OPEN_WINDOW_KEY })
end

local function onKeyPressed(key)
    if isGamePaused() then
        return
    end

    if getCore():isKey(getOpenWindowBindLabel(), key) then
        QuickFits.UI.OutfitManagerWindow.Open(0)
    end
end

Events.OnGameBoot.Add(initKeyBindings)
Events.OnKeyPressed.Add(onKeyPressed)
