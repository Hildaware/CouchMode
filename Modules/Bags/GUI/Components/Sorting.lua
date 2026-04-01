local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Sorting: AceModule
local sorting    = addon:NewModule('Bags.Sorting')

---@class Enums: AceModule
local enums      = addon:GetModule('Bags.Enums')

---@class Session: AceModule
local session    = addon:GetModule('Bags.Session')

---@class Database: AceModule
local database   = addon:GetModule('Bags.Database')

---@class Utils: AceModule
local utils      = addon:GetModule('Bags.Utils')

---@class SortContainerFrame: Frame
---@field fields table<number, table|Button>

---@class SortContainer: Frame
---@field widget SortContainerFrame
---@field Update function
sorting.proto    = {}

function sorting:Build(parent, type, onSelect)
    ---@type SortContainer
    local i = setmetatable({}, { __index = sorting.proto })

    local hFrame = CreateFrame('Frame', nil, parent)
    hFrame:SetSize(parent:GetWidth(), session.Settings.Defaults.Sections.ListViewHeader)
    local offset = session.Settings.Defaults.Sections.Header + (session.Settings.Defaults.Sections.Filters + 20)
    local addedOffset = 2
    hFrame:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, -(offset + addedOffset))

    hFrame.fields = {}

    local tex = hFrame:CreateTexture(nil, 'BACKGROUND')
    tex:SetPoint('TOPLEFT', hFrame, 'TOPLEFT')
    tex:SetPoint('BOTTOMRIGHT', hFrame, 'BOTTOMRIGHT', 0, addedOffset)
    tex:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Underline')
    tex:SetVertexColor(1, 1, 1, 0.5)

    local anchor = hFrame
    local itemWidth = database:GetInventoryViewWidth()
    local defaultWidth = 600
    local columnScale = itemWidth / defaultWidth

    for index, sortType in ipairs(enums.SortFields) do
        local sortSize = session.Settings.Defaults.Columns[sortType.dbColumn] * columnScale
        local sortButton = self:Create(hFrame, anchor, sortType, sortSize, type, onSelect, index == 1)

        if index ~= #enums.SortFields then
            local div = hFrame:CreateTexture(nil, 'BACKGROUND')
            div:SetPoint('TOPLEFT', sortButton, 'TOPRIGHT', 0, 0)
            div:SetSize(1, hFrame:GetHeight() - 5)
            div:SetColorTexture(1, 1, 1, 0.5)
        end

        anchor = sortButton
    end

    i.widget = hFrame --[[@as SortContainerFrame]]

    return i
end

---@param parent SortContainerFrame
---@param anchor Frame
---@param sortType SortType
---@param width integer
---@param type Enums.InventoryType
---@param onSelect function
---@param initial boolean?
---@return table|Button
function sorting:Create(parent, anchor, sortType, width, type, onSelect, initial)
    local font = database:GetFont()
    local fontSize = utils:GetFontScale()

    local frame = CreateFrame('Button', nil, parent)
    frame:SetSize(width, parent:GetHeight())

    local anchorPoint = initial == true and 'LEFT' or 'RIGHT'
    local offset = initial == true and 3 or 0
    frame:SetPoint('LEFT', anchor, anchorPoint, offset, 0)

    local text = frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    text:SetPoint('CENTER', frame, 'CENTER', 0, 0)
    text:SetJustifyH('CENTER')
    text:SetText(sortType.shortName)
    text:SetTextColor(1, 1, 1)
    text:SetFont(font.path, fontSize)

    local arrow = frame:CreateTexture('ARTWORK')
    arrow:SetPoint('LEFT', text, 'RIGHT', 2, 0)
    arrow:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Arrow_Up')
    arrow:SetSize(8, 14)

    local sortData
    if type == enums.InventoryType.Inventory then
        sortData = database:GetInventorySortField()
    elseif type == enums.InventoryType.Bank then
        sortData = database:GetBankSortField()
    end

    if sortData.Sort == enums.SortOrder.Desc then
        arrow:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Arrow_Up')
    else
        arrow:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Arrow_Down')
    end

    if sortData.Field ~= sortType.id then
        arrow:Hide()
    end

    frame:SetScript('OnClick', function()
        local sortOrder = sortData.Sort
        if sortData.Field == sortType.id then
            if sortOrder == enums.SortOrder.Asc then
                sortOrder = enums.SortOrder.Desc
            else
                sortOrder = enums.SortOrder.Asc
            end
        end

        sortData.Field = sortType.id
        sortData.Sort = sortOrder

        if sortData.Sort ~= enums.SortOrder.Desc then
            arrow:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Arrow_Up')
        else
            arrow:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Arrow_Down')
        end

        arrow:Show()
        text:SetTextColor(1, 1, 0)

        -- Remove other arrows
        for _, k in pairs(enums.SortField) do
            if k ~= sortType.id then
                parent.fields[k].arrow:Hide()
                parent.fields[k].text:SetTextColor(1, 1, 1)
            end
        end

        onSelect()
    end)

    frame:SetScript('OnEnter', function(button)
        GameTooltip:SetOwner(button, 'ANCHOR_TOPRIGHT')
        GameTooltip:SetText('Sort By: ' .. sortType.friendlyName, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)

    frame:SetScript('OnLeave', function(_)
        GameTooltip:Hide()
    end)

    parent.fields[sortType.id] = frame
    frame.arrow = arrow
    frame.text = text

    return frame
end

sorting:Enable()
