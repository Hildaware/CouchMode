local addon_name   = ...

---@class CouchMode: AceAddon
local addon        = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class SimpleButton: AceModule
local simpleButton = addon:NewModule('Bags.SimpleButton')

---@class SimpleButtonFrame: Frame
---@field base Frame
---@field widget Button
simpleButton.proto = {}

---@param normalTexture string
---@param normalAtlas string
---@param size Size?
---@param iconOverrideSize Size?
---@overload fun(normalTexture: string, normalAtlas: string, size?: Size)
---@overload fun(normalTexture: string, normalAtlas: string, iconOverrideSize?: Size)
---@return SimpleButtonFrame
function simpleButton:Create(parent, normalTexture, normalAtlas, size, iconOverrideSize)
    size = size or { width = 32, height = 32 }
    iconOverrideSize = iconOverrideSize or { width = 28, height = 28 }

    local i = setmetatable({}, { __index = simpleButton.proto })

    local base = CreateFrame('Frame', nil, parent)
    base:SetPoint('CENTER')
    base:SetSize(size.width, size and size.height)

    local baseTexture = base:CreateTexture(nil, 'BACKGROUND')
    baseTexture:SetAllPoints()
    baseTexture:SetTexture('Interface\\Garrison\\ClassHallUI')
    baseTexture:SetAtlas('ClassHall_Follower-EquipmentFrame')

    local highlightTexture = base:CreateTexture(nil, 'ARTWORK')
    highlightTexture:SetPoint('CENTER')
    highlightTexture:SetSize(size.width - 2, size.height - 2)
    highlightTexture:SetColorTexture(0, 0, 1, 0.25)
    highlightTexture:Hide()

    local button = CreateFrame('Button', nil, base)
    button:SetPoint('CENTER')
    button:SetSize(iconOverrideSize.width, iconOverrideSize.height)
    button:SetNormalTexture(normalTexture)
    button:SetNormalAtlas(normalAtlas)
    button:SetScript('OnEnter', function()
        highlightTexture:Show()
    end)

    button:SetScript('OnLeave', function()
        highlightTexture:Hide()
    end)

    i.widget = button
    i.base = base

    return i
end

---@param parent Frame
function simpleButton.proto:SetParent(parent)
    self.base:SetParent(parent)
end

---@param point FramePoint
---@param relativeTo? Frame
---@param relativePoint? FramePoint
---@param offsetX? uiUnit
---@param offsetY? uiUnit
---@overload fun(self, point: AnchorPoint, relativeTo?: any, ofsx?: number, ofsy?: number)
---@overload fun(self, point: AnchorPoint, ofsx?: number, ofsy?: number)
function simpleButton.proto:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
    self.base:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
end

---@param callback function
function simpleButton.proto:OnClick(callback)
    self.widget:SetScript('OnClick', callback)
end

---@param message string
function simpleButton.proto:SetTooltip(message)
    self.widget:HookScript('OnEnter', function()
        GameTooltip:SetOwner(self.base, 'ANCHOR_TOPRIGHT')
        GameTooltip:SetText(message, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.widget:HookScript('OnLeave', function()
        GameTooltip:Hide()
    end)
end

simpleButton:Enable()
