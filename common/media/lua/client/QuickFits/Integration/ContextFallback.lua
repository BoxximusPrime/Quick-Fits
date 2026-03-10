---@diagnostic disable: undefined-global

require "QuickFits/UI/OutfitManagerWindow"

QuickFits = QuickFits or {}
QuickFits.Integration = QuickFits.Integration or {}

local function getOutfitManagerWindow()
    return QuickFits and QuickFits.UI and QuickFits.UI.OutfitManagerWindow or nil
end

local function addQuickFitsContextOption(playerNum, context, items)
    if not context or not playerNum then
        return
    end
    if context.quickFitsOptionAdded then
        return
    end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then
        return
    end

    context.quickFitsOptionAdded = true
    context:addOption("Quick Fits...", playerNum, function(targetPlayerNum)
        local outfitManagerWindow = getOutfitManagerWindow()
        if outfitManagerWindow and outfitManagerWindow.Open then
            outfitManagerWindow.Open(targetPlayerNum)
        end
    end)
end

Events.OnFillInventoryObjectContextMenu.Add(addQuickFitsContextOption)
