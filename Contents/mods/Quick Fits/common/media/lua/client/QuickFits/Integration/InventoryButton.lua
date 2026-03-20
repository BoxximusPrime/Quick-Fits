---@diagnostic disable: undefined-global

require "ISUI/InventoryWindow/ISInventoryWindowControlHandler"
require "ISUI/InventoryWindow/ISInventoryWindowContainerControls"
require "QuickFits/Localization"
require "QuickFits/UI/OutfitManagerWindow"

QuickFits = QuickFits or {}
QuickFits.Integration = QuickFits.Integration or {}

local Localization = QuickFits.Localization

local function getOutfitManagerWindow()
    return QuickFits and QuickFits.UI and QuickFits.UI.OutfitManagerWindow or nil
end

local InventoryButtonHandler = ISInventoryWindowControlHandler:derive("QuickFitsInventoryButtonHandler")
InventoryButtonHandler.Type = "QuickFitsInventoryButtonHandler"

function InventoryButtonHandler:shouldBeVisible()
    if not self.playerObj or not self.container then
        return false
    end
    return self.container == self.playerObj:getInventory()
end

function InventoryButtonHandler:getControl()
    self.control = self:getButtonControl(Localization.getText("inventory_button"))
    return self.control
end

function InventoryButtonHandler:perform()
    local outfitManagerWindow = getOutfitManagerWindow()
    if outfitManagerWindow and outfitManagerWindow.Open then
        outfitManagerWindow.Open(self.playerNum)
    end
end

function InventoryButtonHandler:new()
    local handler = ISInventoryWindowControlHandler.new(self)
    return handler
end

ISInventoryWindowContainerControls.AddHandler(InventoryButtonHandler)
