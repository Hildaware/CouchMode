local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Utils: AceModule
local utils      = addon:NewModule('Bags.Utils')

---@class Enums: AceModule
local enums      = addon:GetModule('Bags.Enums')

---@class Session: AceModule
local session    = addon:GetModule('Bags.Session')

---@class Database: AceModule
local database   = addon:GetModule('Bags.Database')

---@return number
function utils:GetFontScale()
    local defaultFontSize = 12
    local defaultWidth = 600
    local defaultHeight = 28

    local itemWidth = database:GetInventoryViewWidth()
    local itemHeight = database:GetItemViewHeight()

    local widthScale = itemWidth / defaultWidth
    local heightScale = itemHeight / defaultHeight

    -- Use the smaller scale to ensure text fits in both dimensions
    local scale = math.min(widthScale, heightScale)
    local fontSize = defaultFontSize * scale

    return fontSize
end

function utils:GetColumnScale()
    local defaultWidth = 600

    local itemWidth = database:GetInventoryViewWidth()
    return itemWidth / defaultWidth
end

---@param frame Frame
---@return Frame?
function utils:GetParentMostNode(frame)
    if type(frame) ~= 'table' then return nil end
    local parent = frame:GetParent()
    if parent == UIParent then
        return frame
    end
    return utils:GetParentMostNode(parent)
end

---@param classId integer
---@return string?
utils.GetItemClass = function(classId)
    for i, v in pairs(Enum.ItemClass) do
        if classId == v then return i end
    end
    return nil
end

utils.GetCategoyIcon = function(classId)
    local className = utils.GetItemClass(classId)
    local path = 'Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Categories\\'

    -- Custom Categories
    if className == nil then
        for key, value in pairs(enums.CustomCategory) do
            if value == classId then
                className = key
                break
            end
        end
    end

    if className == nil then return nil end
    return path .. className
end

utils.IsEquipmentUnbound = function(item)
    if item.bound == true then return false end
    if not item.type then return false end

    if item.type == Enum.ItemClass.Armor or item.type == Enum.ItemClass.Weapon then
        return true
    end
    return false
end

utils.IsJewelry = function(item)
    if item.equipLocation == nil then return false end
    if item.equipLocation == Enum.InventoryType.IndexNeckType or item.equipLocation == Enum.InventoryType.IndexFingerType then
        return true
    end
    return false
end

utils.IsTrinket = function(item)
    if item.equipLocation == nil then return false end
    if item.equipLocation == Enum.InventoryType.IndexTrinketType then
        return true
    end
    return false
end

utils.CopyTable = function(table)
    local orig_type = type(table)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(table) do
            copy[orig_key] = orig_value
        end
    else
        copy = table
    end
    return copy
end

utils.BuildCategoriesTable = function()
    local t = utils.CopyTable(enums.Categories)
    for key, value in pairs(t) do
        value.items = {}
        value.count = 0
        value.key = key
        value.hasNew = false
    end
    return t
end

utils.BuildBankCategoriesTable = function()
    local t = utils.CopyTable(enums.Categories)
    for key, value in pairs(t) do
        value.items = {}
        value.count = 0
        value.key = key
        value.hasNew = false
    end
    return t
end

utils.FormatMoney = function(moneyValue)
    if moneyValue < 100 then
        return GetMoneyString(moneyValue)
    elseif moneyValue < 10000 then
        return GetMoneyString(math.floor(moneyValue / 100) * 100)
    elseif moneyValue < 10000000 then
        return GetMoneyString(math.floor(moneyValue / 10000) * 10000)
    else
        local n = math.floor(moneyValue / 10000000) * 10000
        local s = tostring(n)
        n = GetMoneyString(n)
        return n:sub(1, #s - 4) .. "K" .. n:sub(#s - 3)
    end
end

-- Bag Killing
local killableFramesParent = CreateFrame('FRAME', nil, UIParent)
killableFramesParent:SetAllPoints()
killableFramesParent:Hide()

local function MakeFrameKillable(frame)
    frame:SetParent(killableFramesParent)
end

local killedFramesParent = CreateFrame('FRAME', nil, UIParent)
killedFramesParent:SetAllPoints()
killedFramesParent:Hide()

local function KillFramePermanently(frame)
    frame:SetParent(killedFramesParent)
end

local function CreateEnableBagButton(parent)
    if parent.ClickableTitleFrame then
        parent.ClickableTitleFrame:Hide()
    end
    if parent.TitleContainer then
        parent.TitleContainer:Hide()
    end

    local button = CreateFrame('Button', nil, parent)
    button:SetFrameLevel(parent:GetFrameLevel() + 420)
    button.text = button:CreateTexture()
    button.text:SetPoint('CENTER', 4, -1)
    button.text:SetSize(20, 20)
    -- button.text:SetTexCoord(0, 0.75, 0, 1)
    button.text:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Logo_Normal')
    button:SetSize(24, 24)
    button:HookScript('OnMouseDown', function(self)
        self.text:SetPoint('CENTER', 3, -2)
        self.text:SetAlpha(0.75)
    end)
    button:HookScript('OnMouseUp', function(self)
        self.text:SetPoint('CENTER', 4, -1)
        self.text:SetAlpha(1)
    end)
    button:HookScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_TOPRIGHT')
        GameTooltip:SetText('Back to Bags', 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript('OnLeave', function(self)
        GameTooltip:Hide()
    end)
    button:HookScript('OnClick', function(self)
        utils.DestroyDefaultBags()
        CloseAllBags()
        OpenAllBags()
    end)
    return button
end

function utils.CreateEnableBagButtons()
    local f = _G['ContainerFrame1']
    f.CB = CreateEnableBagButton(f)
    if _G['ContainerFrameCombinedBags'] then
        f = _G['ContainerFrameCombinedBags']
        f.CB = CreateEnableBagButton(f)
        f.CB:SetPoint('TOPRIGHT', -22, -1)
        f.CB:SetHeight(20)
    end

    if _G['ElvUI_ContainerFrame'] then
        f = _G['ElvUI_ContainerFrame']
        f.CB = CreateEnableBagButton(f)
        f.CB:SetPoint('TOPLEFT', 2, -2)
        f.CB:SetSize(22, 22)
    end
end

-- TODO: After Guild Bank frame is complete, handle this
function utils.BagDestroyer()
    if _G['ElvUI_ContainerFrame'] then
        MakeFrameKillable(_G['ElvUI_ContainerFrame'])
        MakeFrameKillable(_G['ElvUI_BankContainerFrame'])
        -- Get rid of blizz bags permanently, since they are replaced by ElvUI
        if _G['ContainerFrameCombinedBags'] then
            KillFramePermanently(_G['ContainerFrameCombinedBags'])
        end
        for i = 1, NUM_CONTAINER_FRAMES do
            KillFramePermanently(_G['ContainerFrame' .. i])
        end
        KillFramePermanently(_G['BankFrame'])
    else
        if _G['ContainerFrameCombinedBags'] then
            MakeFrameKillable(_G['ContainerFrameCombinedBags'])
        end
        for i = 1, NUM_CONTAINER_FRAMES do
            MakeFrameKillable(_G['ContainerFrame' .. i])
        end
        MakeFrameKillable(_G['BankFrame'])
    end
    if _G['GwBagFrame'] then
        -- MakeFrameKillable(_G['GwBagFrame'])
        -- MakeFrameKillable(_G['GwBankFrame'])
    end
end

function utils.DestroyDefaultBags()
    killableFramesParent:Hide()
    session.Settings.HideBags = false
end

function utils.RestoreDefaultBags()
    killableFramesParent:Show()
    session.Settings.HideBags = true
end

---@param item Item
---@param catTable CategorizedItemSet[]
function utils.AddItemToCategory(item, catTable)
    if item.category ~= nil then
        catTable[item.category] = catTable[item.category] or {}
        catTable[item.category].items = catTable[item.category].items or {}

        catTable[item.category].count =
            (catTable[item.category].count or 0) + 1
        tinsert(catTable[item.category].items, item)
        if item.isNew then
            catTable[item.category].hasNew = true
        end
    else
        catTable[Enum.ItemClass.Miscellaneous] = catTable[Enum.ItemClass.Miscellaneous] or {}
        catTable[Enum.ItemClass.Miscellaneous].items = catTable[Enum.ItemClass.Miscellaneous].items or {}

        catTable[Enum.ItemClass.Miscellaneous].count =
            (catTable[Enum.ItemClass.Miscellaneous].count or 0) + 1
        tinsert(catTable[Enum.ItemClass.Miscellaneous].items, item)
        if item.isNew then
            catTable[Enum.ItemClass.Miscellaneous].hasNew = true
        end
    end
end

function utils.ReplaceBagSlot(bag)
    if bag == -3 then
        return 98
    end

    if bag == -1 then
        return 99
    end

    return bag
end

---@param bagId integer
---@return Enums.InventoryType?
function utils:GetBagType(bagId)
    if enums.PlayerInventoryBagIndex[bagId] then
        return enums.InventoryType.Inventory
    end
    if enums.BankBagIndex[bagId] then
        return enums.InventoryType.Bank
    end
    if enums.WarbankBagIndex[bagId] then
        return enums.InventoryType.Shared
    end
    return nil
end

---@param frame Frame
---@param color ColorMixin?
function utils:CreateBorder(frame, color)
    if not frame.borders then
        frame.borders = {}
        for i = 1, 4 do
            frame.borders[i] = frame:CreateLine(nil, 'BACKGROUND', nil, 0)
            local l = frame.borders[i]
            l:SetThickness(1)
            local c = color or { 0.2, 0.2, 0.2, 1 }
            l:SetColorTexture(c[1], c[2], c[3], c[4])
            if i == 1 then
                l:SetStartPoint('TOPLEFT')
                l:SetEndPoint('TOPRIGHT')
            elseif i == 2 then
                l:SetStartPoint('TOPRIGHT')
                l:SetEndPoint('BOTTOMRIGHT')
            elseif i == 3 then
                l:SetStartPoint('BOTTOMRIGHT')
                l:SetEndPoint('BOTTOMLEFT')
            else
                l:SetStartPoint('BOTTOMLEFT')
                l:SetEndPoint('TOPLEFT')
            end
        end
    end
end

---comment
---@param frame Frame
---@param anchorPoint AnchorPoint
---@param color ColorMixin?
function utils:CreateRegionalBorder(frame, anchorPoint, color)
    if not frame.borders then
        frame.borders = {}
    end

    local border = frame:CreateLine(nil, 'BACKGROUND', nil, 0)
    border:SetThickness(1)
    local c = color or { 0.2, 0.2, 0.2, 1 }
    border:SetColorTexture(c[1], c[2], c[3], c[4])

    if anchorPoint == 'BOTTOM' then
        ---@diagnostic disable-next-line: missing-parameter
        border:SetStartPoint('BOTTOMLEFT')
        ---@diagnostic disable-next-line: missing-parameter
        border:SetEndPoint('BOTTOMRIGHT')
    elseif anchorPoint == 'TOP' then
        ---@diagnostic disable-next-line: missing-parameter
        border:SetStartPoint('TOPLEFT')
        ---@diagnostic disable-next-line: missing-parameter
        border:SetEndPoint('TOPRIGHT')
    end

    tinsert(frame.borders, border)
end

utils:Enable()
