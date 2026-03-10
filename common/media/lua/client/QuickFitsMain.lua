---@diagnostic disable: undefined-global

QuickFits = QuickFits or {}

local OPEN_WINDOW_BIND = "Open Quick Fits"
local DEFAULT_OPEN_WINDOW_KEY = Keyboard.KEY_BACKSLASH or 43

require "QuickFits/Data"
require "QuickFits/Capture"
require "QuickFits/Search"
require "QuickFits/Apply"
require "QuickFits/UI/OutfitManagerWindow"
require "QuickFits/Integration/InventoryButton"
require "QuickFits/Integration/ContextFallback"

local function initKeyBindings()
    table.insert(keyBinding, { value = "[Quick Fits]" })
    table.insert(keyBinding, { value = OPEN_WINDOW_BIND, key = DEFAULT_OPEN_WINDOW_KEY })
end

local function onKeyPressed(key)
    if isGamePaused() then
        return
    end

    if getCore():isKey(OPEN_WINDOW_BIND, key) then
        QuickFits.UI.OutfitManagerWindow.Open(0)
    end
end

Events.OnGameBoot.Add(initKeyBindings)
Events.OnKeyPressed.Add(onKeyPressed)
