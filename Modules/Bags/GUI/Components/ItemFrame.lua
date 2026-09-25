local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Bags: AceModule
local bags       = addon:GetModule('Bags')

---@class ItemFrame: AceModule
local itemFrame  = addon:NewModule('Bags.ItemFrame')

---@class Session: AceModule
local session    = addon:GetModule('Bags.Session')

---@class Database: AceModule
local database   = addon:GetModule('Bags.Database')

---@class Utils: AceModule
local utils      = addon:GetModule('Bags.Utils')
local rowStyle   = addon.Components.ItemRow

local Masque     = LibStub('Masque', true)

---@class ItemButton : Button
---@field NewItemTexture Texture
---@field BattlepayItemTexture Texture
---@field NewTexture Texture
---@field Desaturate Texture
---@field SetHasItem function
---@field SetItemButtonTexture function
---@field SetMatchesSearch function
---@field UpdateExtended function
---@field UpdateQuestItem function
---@field UpdateNewItem function
---@field UpdateJunkItem function
---@field UpdateItemContextMatching function
---@field UpdateCooldown function
---@field SetReadable function
---@field CheckUpdateTooltip function

---@class CanIMogItFrame : Frame
---@field text FontString

---@class ItemIconButton : ItemButton
---@field frame Frame
---@field upgrade Texture
---@field canI CanIMogItFrame
---@field scrap Frame

---@class ItemRow : Frame
---@field itemButton ItemButton
---@field icon ItemIconButton
---@field name FontString
---@field ilvl FontString
---@field reqlvl FontString
---@field value FontString
---@field isItem boolean
---@field index number

---@class ListItem
---@field widget ItemRow
---@field bag number
---@field slot number
---@field itemId number
---@field item Item
---@field Build function
---@field Clear function
itemFrame.proto  = {}

function itemFrame:OnInitialize()
    -- CatalogView owns pools so inventory, bank, and future catalogs stay isolated.
end

---@param item Item
---@param offset number
---@param parent Frame
function itemFrame.proto:Build(item, offset, parent)
    self.item = item
    local frame = self.widget

    local font = database:GetFont()
    local itemWidth = database:GetInventoryViewWidth()
    local itemHeight = database:GetItemViewHeight()
    local columnScale = utils:GetColumnScale()
    local fontSize = rowStyle.GetFontSize(itemWidth, itemHeight)

    frame:SetParent(parent)
    rowStyle.SetGeometry(frame, itemWidth, itemHeight,
        session.Settings.Defaults.Columns.Icon * columnScale)
    frame:ClearAllPoints()
    frame:SetPoint('TOP', 0, -((offset - 1) * itemHeight))

    local tooltipOwner = GameTooltip:GetOwner()

    frame.itemButton:SetID(item.slot)
    frame:SetID(item.bag)

    frame.itemButton:SetHasItem(item.texture)

    local questInfo = item.questInfo
    local isQuestItem = questInfo.isQuestItem;
    local questID = questInfo.questID;
    local isActive = questInfo.isActive

    -- Utilize the Icon as an ItemButton
    frame.icon:SetID(item.slot)
    frame.icon.frame:SetID(item.bag)

    ClearItemButtonOverlay(frame.icon)
    frame.icon:SetHasItem(item.texture)
    frame.icon:SetItemButtonTexture(item.texture)
    local r, g, b = rowStyle.SetQuality(frame, item.quality or 0, item.link, item.bound)
    SetItemButtonCount(frame.icon, item.stackCount)
    SetItemButtonDesaturated(frame.icon, item.isLocked)
    frame.icon:UpdateExtended()
    frame.icon:UpdateQuestItem(isQuestItem, questID, isActive)
    frame.icon:UpdateNewItem(item.quality)
    frame.icon:UpdateJunkItem(item.quality, item.hasNoValue)
    frame.icon:UpdateItemContextMatching()
    frame.icon:UpdateCooldown(item.texture)
    frame.icon:SetReadable(item.isReadable)
    frame.icon:CheckUpdateTooltip(tooltipOwner)
    frame.icon:SetMatchesSearch(not item.isFiltered)
    frame.icon:Show()
    frame.icon:EnableMouse(false)

    -- Pawn Support
    if _G['PawnIsContainerItemAnUpgrade'] then
        if _G['PawnIsContainerItemAnUpgrade'](item.bag, item.slot) then
            frame.icon.upgrade:Show()
        else
            frame.icon.upgrade:Hide()
        end
    end

    -- Can I Mog It? Support
    if _G['CanIMogIt'] then
        local iconText = _G['CanIMogIt']:GetIconText(item.link, item.bag, item.slot)
        if iconText and iconText ~= '' then
            frame.icon.canI.text:SetText(iconText)
            frame.icon.canI:Show()
        else
            frame.icon.canI.text:SetText('')
            frame.icon.canI:Hide()
        end
    end

    -- Masque Support
    if Masque then
        ---@diagnostic disable-next-line: undefined-field
        local cBags = Masque:Group('Bags')
        cBags:AddButton(frame.icon)
    end

    local stackString = (item.stackCount and item.stackCount > 1) and '(' .. item.stackCount .. ')' or nil
    local nameString = item.name
    if stackString then
        nameString = nameString .. ' ' .. stackString
    end

    frame.nameContainer:SetSize(session.Settings.Defaults.Columns.Name * columnScale, itemHeight)

    if item.setName ~= '' then
        frame.nameWithSet:Show()
        frame.nameWithSet:SetText(nameString)
        frame.nameWithSet:SetTextColor(r, g, b)
        frame.nameWithSet:SetFont(font.path, fontSize)
        frame.setText:Show()
        frame.setText:SetText('Set: ' .. item.setName)
        frame.setText:SetFont(font.path, fontSize)

        frame.name:Hide()
    else
        frame.nameWithSet:Hide()
        frame.setText:Hide()
        frame.name:Show()

        frame.name:SetText(nameString)
        frame.name:SetTextColor(r, g, b)
        frame.name:SetFont(font.path, fontSize)
    end

    -- frame.type:SetTexture(CB.U.GetCategoyIcon(item.type))

    frame.ilvlContainer:SetSize(session.Settings.Defaults.Columns.Ilvl * columnScale, itemHeight)
    if item.type == Enum.ItemClass.Armor or item.type == Enum.ItemClass.Weapon
        or item.category == Enum.ItemClass.Battlepet then
        frame.ilvl:SetText(item.ilvl)
        frame.ilvl:SetFont(font.path, fontSize)
    else
        frame.ilvl:SetText('')
    end

    frame.reqlvlContainer:SetSize(session.Settings.Defaults.Columns.ReqLvl * columnScale, itemHeight)
    if item.reqLvl and item.reqLvl > 1 then
        frame.reqlvl:SetText(item.reqLvl)
        frame.reqlvl:SetFont(font.path, fontSize)
    else
        frame.reqlvl:SetText('')
    end

    frame.valueContainer:SetSize(session.Settings.Defaults.Columns.Value * columnScale, itemHeight)
    if item.value and item.value > 1 then
        frame.value:SetText(C_CurrencyInfo.GetCoinTextureString(item.value, fontSize))
        frame.value:SetFont(font.path, fontSize)
    else
        frame.value:SetText('')
    end

    frame.index = offset

    if bags.status.visitingWarbank and not item.isAccountBankable then
        frame.itemButton.Desaturate:Show()
    else
        frame.itemButton.Desaturate:Hide()
    end

    self:Update()

    frame:Show()
    frame.itemButton:Show()
end

function itemFrame.proto:Update()
    -- Scrap Support
    if _G['Scrap'] then
        if _G['Scrap']:IsJunk(self.item.id) then
            self.widget.icon.scrap:Show()
        else
            self.widget.icon.scrap:Hide()
        end
    end

    if self.item.isNew == true then
        self.widget.itemButton.NewTexture:Show()
    else
        self.widget.itemButton.NewTexture:Hide()
    end
end

function itemFrame.proto:Empty()
    self.item = nil
end

function itemFrame.proto:Clear()
    self.item = nil
    rowStyle.Reset(self.widget)
end

---@return ListItem
function itemFrame:_DoCreate()
    local i = setmetatable({}, { __index = itemFrame.proto })

    local font = database:GetFont()
    local itemHeight = database:GetItemViewHeight()
    local itemWidth = database:GetInventoryViewWidth()
    local columnScale = utils:GetColumnScale()
    local fontSize = rowStyle.GetFontSize(itemWidth, itemHeight)

    ---@class ItemRow
    local f = rowStyle.Create(UIParent)
    rowStyle.SetGeometry(f, itemWidth, itemHeight,
        session.Settings.Defaults.Columns.Icon * columnScale)
    f.itemButton:HookScript('OnLeave', function(s)
        s.NewTexture:Hide()
        if i.item ~= nil then
            i.item.isNew = false
        end
    end)

    local iconSpace = f.iconContainer
    local iconTexture = f.icon

    local upgradeIcon = iconTexture:CreateTexture(nil, 'ARTWORK')
    upgradeIcon:SetPoint('TOPLEFT', iconTexture, 'TOPLEFT', 2, -2)
    upgradeIcon:SetSize(12, 12)
    upgradeIcon:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Upgrade')
    upgradeIcon:Hide()

    iconTexture.upgrade = upgradeIcon

    ---@class CanIMogItFrame
    local canIFrame = CreateFrame('Frame', nil, iconTexture)
    canIFrame:SetPoint('TOPRIGHT', iconTexture, 'TOPRIGHT', -2, -2)
    canIFrame:SetSize(14, 14)
    canIFrame.tex = canIFrame:CreateTexture(nil, 'BACKGROUND')
    canIFrame.tex:SetAllPoints(canIFrame)
    canIFrame.tex:SetColorTexture(0, 0, 0, 1)

    local canIMogIt = canIFrame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalTiny')
    canIMogIt:SetAllPoints(canIFrame)
    canIMogIt:SetJustifyH('RIGHT')

    canIFrame:Hide()

    canIFrame.text = canIMogIt
    iconTexture.canI = canIFrame

    local scrapFrame = CreateFrame('Frame', nil, iconTexture)
    scrapFrame:SetPoint('BOTTOMRIGHT', iconTexture, 'BOTTOMRIGHT', -2, -1)
    scrapFrame:SetSize(14, 14)
    scrapFrame.tex = scrapFrame:CreateTexture(nil, 'BACKGROUND')
    scrapFrame.tex:SetAllPoints(scrapFrame)
    scrapFrame.tex:SetColorTexture(0, 0, 0, 1)
    scrapFrame.tex:SetTexture('Interface\\Buttons\\UI-GroupLoot-Coin-Up')

    scrapFrame:Hide()
    iconTexture.scrap = scrapFrame

    --#region Name

    local name = CreateFrame('Frame', nil, f)
    name:SetPoint('LEFT', iconSpace, 'RIGHT', 8, 0)
    name:SetHeight(itemHeight)
    name:SetWidth(session.Settings.Defaults.Columns.Name * columnScale)

    local nameOnlyText = name:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    nameOnlyText:SetAllPoints(name)
    nameOnlyText:SetJustifyH('LEFT')
    nameOnlyText:SetFont(font.path, fontSize)

    local nameText = name:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    nameText:SetPoint('BOTTOMLEFT', name, 'LEFT', 0, 2)
    nameText:SetJustifyH('LEFT')
    nameText:SetFont(font.path, fontSize)

    local setText = name:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    setText:SetPoint('TOPLEFT', name, 'LEFT', 0, -2)
    setText:SetJustifyH('LEFT')
    setText:SetFont(font.path, fontSize)

    f.nameContainer = name
    f.name = nameOnlyText
    f.setText = setText
    f.nameWithSet = nameText

    --#endregion

    -- type
    -- local type = CreateFrame('Frame', nil, f)
    -- type:SetPoint('LEFT', name, 'RIGHT')
    -- type:SetHeight(CB.Settings.Defaults.Sections.ListItemHeight)
    -- type:SetWidth(CB.Settings.Defaults.Columns.Category)

    -- local typeTex = type:CreateTexture(nil, 'ARTWORK')
    -- typeTex:SetPoint('CENTER', type, 'CENTER')
    -- typeTex:SetSize(24, 24)

    -- f.type = typeTex

    -- ilvl
    local ilvl = CreateFrame('Frame', nil, f)
    ilvl:SetPoint('LEFT', name, 'RIGHT')
    ilvl:SetHeight(itemHeight)
    ilvl:SetWidth(session.Settings.Defaults.Columns.Ilvl * columnScale)
    local ilvlText = ilvl:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    ilvlText:SetAllPoints(ilvl)
    ilvlText:SetJustifyH('CENTER')
    ilvlText:SetFont(font.path, fontSize)

    f.ilvlContainer = ilvl
    f.ilvl = ilvlText

    -- reqlvl
    local reqlvl = CreateFrame('Frame', nil, f)
    reqlvl:SetPoint('LEFT', ilvl, 'RIGHT')
    reqlvl:SetHeight(itemHeight)
    reqlvl:SetWidth(session.Settings.Defaults.Columns.ReqLvl * columnScale)
    local reqlvlText = reqlvl:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    reqlvlText:SetAllPoints(reqlvl)
    reqlvlText:SetJustifyH('CENTER')
    reqlvlText:SetFont(font.path, fontSize)

    f.reqlvlContainer = reqlvl
    f.reqlvl = reqlvlText

    -- value
    local value = CreateFrame('Frame', nil, f)
    value:SetPoint('LEFT', reqlvl, 'RIGHT')
    value:SetHeight(itemHeight)
    value:SetWidth(session.Settings.Defaults.Columns.Value * columnScale)
    local valueText = value:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    valueText:SetAllPoints(value)
    valueText:SetJustifyH('RIGHT')
    valueText:SetFont(font.path, fontSize)

    f.valueContainer = value
    f.value = valueText

    f.isItem = true

    f:Hide()

    i.widget = f

    return i
end

---@param item ListItem
function itemFrame:_DoReset(item)
end

---@return ListItem
function itemFrame:Create()
    return self:_DoCreate()
end

---Creates CatalogView renderer components; CatalogView owns their reuse.
function itemFrame:CreateRenderer()
    return {
        create = function()
            local component = self:Create()
            component.frame = component.widget
            component.height = database:GetItemViewHeight()
            function component:bind(item, offset, parent)
                self:Build(item, math.floor(offset / database:GetItemViewHeight()) + 1, parent)
                self.height = database:GetItemViewHeight()
            end
            function component:reset() self:Clear() end
            return component
        end
    }
end

itemFrame:Enable()
