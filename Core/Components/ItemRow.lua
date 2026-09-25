local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

addon.Components = addon.Components or {}
addon.Components.ItemRow = addon.Components.ItemRow or {}
local itemRow = addon.Components.ItemRow

local HIGHLIGHT_TEXTURE = 'Interface\\AddOns\\CouchMode\\Resources\\Media\\Item_Highlight'
local SOLID_TEXTURE = 'Interface\\AddOns\\CouchMode\\Resources\\Media\\Item_Highlight_Solid'

local function discardTexture(texture)
    if not texture then return end
    texture:Hide()
    texture:SetParent(nil)
end

---Creates the shared visual shell for a catalog item row. Callers own text,
---data binding, and interaction scripts.
---@param parent Frame?
---@param options { plainButton: boolean? }?
---@return Frame
function itemRow.Create(parent, options)
    local frame = CreateFrame('Frame', nil, parent or UIParent)

    local button
    if options and options.plainButton then
        button = CreateFrame('Button', nil, frame)
    else
        button = CreateFrame('ItemButton', nil, frame, 'ContainerFrameItemButtonTemplate')
    end
    button:SetAllPoints(frame)
    button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')

    discardTexture(button.NormalTexture)
    button.NormalTexture = nil
    discardTexture(button.PushedTexture)
    button.PushedTexture = nil
    if button.NewItemTexture then button.NewItemTexture:Hide() end
    if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
    discardTexture(button:GetHighlightTexture())

    local undermark = button:CreateTexture(nil, 'BACKGROUND')
    undermark:SetBlendMode('ADD')
    undermark:SetPoint('TOPLEFT', button, 'BOTTOMLEFT', 0, 1)
    undermark:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT')
    undermark:SetColorTexture(1, 1, 1, 0.2)

    local highlight = button:CreateTexture(nil, 'BACKGROUND')
    highlight:SetBlendMode('ADD')
    highlight:SetAllPoints(button)
    highlight:SetTexture(HIGHLIGHT_TEXTURE)
    highlight:Hide()
    button.HighlightTexture = highlight

    local new = button:CreateTexture(nil, 'BACKGROUND')
    new:SetBlendMode('ADD')
    new:SetAllPoints(button)
    new:SetTexture(HIGHLIGHT_TEXTURE)
    new:SetVertexColor(1, 1, 0, 1)
    new:Hide()
    button.NewTexture = new

    local warning = button:CreateTexture(nil, 'BACKGROUND')
    warning:SetBlendMode('ADD')
    warning:SetAllPoints(button)
    warning:SetTexture(SOLID_TEXTURE)
    warning:SetVertexColor(1, 0, 0, 0.5)
    warning:Hide()
    button.Desaturate = warning

    button:HookScript('OnEnter', function(self) self.HighlightTexture:Show() end)
    button:HookScript('OnLeave', function(self) self.HighlightTexture:Hide() end)

    local iconContainer = CreateFrame('Frame', nil, frame)
    iconContainer:SetPoint('LEFT', frame, 'LEFT', 4, 0)
    local iconFrame = CreateFrame('Frame', nil, iconContainer)
    iconFrame:SetPoint('CENTER', iconContainer, 'CENTER')
    local icon = CreateFrame('ItemButton', nil, iconFrame, 'ContainerFrameItemButtonTemplate')
    icon:SetAllPoints(iconFrame)
    if _G.SmartNavigation_MarkFrameIgnored then
        SmartNavigation_MarkFrameIgnored(icon)
    else
        icon.smartNavigationIgnored = true
    end
    icon.frame = iconFrame
    icon:EnableMouse(false)

    frame.itemButton = button
    frame.iconContainer = iconContainer
    frame.icon = icon
    frame.undermark = undermark
    frame:Hide()
    return frame
end

---Sizes a shared item row and its display-only icon.
---@param frame Frame
---@param width number
---@param height number
---@param iconColumnWidth number?
function itemRow.SetGeometry(frame, width, height, iconColumnWidth)
    local iconSize = math.max(1, height - 6)
    frame:SetSize(width, height)
    frame.iconContainer:SetSize(iconColumnWidth or iconSize, iconSize)
    frame.icon.frame:SetSize(iconSize, iconSize)
    frame.icon:SetAllPoints(frame.icon.frame)
    frame.icon:SetSize(iconSize, iconSize)
    frame.icon.icon:SetAllPoints(frame.icon)
    frame.icon.NormalTexture:SetSize(iconSize * 1.5, iconSize * 1.5)
    frame.icon.IconBorder:SetAllPoints(frame.icon)
    frame.icon.IconQuestTexture:SetAllPoints(frame.icon)
end

---Applies item quality to the icon border and row hover tint.
---@param frame Frame
---@param quality number?
---@param itemLinkOrID string|number?
---@param isBound boolean?
---@return number, number, number
function itemRow.SetQuality(frame, quality, itemLinkOrID, isBound)
    local r, g, b = 1, 0.82, 0
    if quality ~= nil then
        r, g, b = C_Item.GetItemQualityColor(quality)
    end
    frame.itemButton.HighlightTexture:SetVertexColor(r, g, b, 1)
    SetItemButtonQuality(frame.icon, quality, itemLinkOrID, false, isBound)
    return r, g, b
end

---Returns the font size used by an item row at this geometry.
---@param width number
---@param height number
---@param baseSize number?
---@return number
function itemRow.GetFontSize(width, height, baseSize)
    return (baseSize or 16) * math.min(width / 600, height / 28)
end

---Clears reusable visual state and releases the row from its parent.
---@param frame Frame
function itemRow.Reset(frame)
    frame.itemButton.HighlightTexture:Hide()
    frame.itemButton.NewTexture:Hide()
    frame.itemButton.Desaturate:Hide()
    if frame.itemButton.SetHasItem then frame.itemButton:SetHasItem(nil) end
    ClearItemButtonOverlay(frame.icon)
    frame.icon:SetHasItem(nil)
    frame.icon:SetItemButtonTexture(nil)
    SetItemButtonQuality(frame.icon, nil, nil)
    SetItemButtonCount(frame.icon, 0)
    SetItemButtonDesaturated(frame.icon, false)
    frame.icon:Hide()
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(nil)
end
