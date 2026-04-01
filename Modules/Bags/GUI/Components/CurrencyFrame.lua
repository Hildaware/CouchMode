local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)


---@class Bags: AceModule
local bags         = addon:GetModule('Bags')

---@class Currency: AceModule
local currency     = addon:NewModule('Bags.Currency')

---@class Database: AceModule
local database     = addon:GetModule('Bags.Database')

---@class Session: AceModule
local session      = addon:GetModule('Bags.Session')

---@class Utils: AceModule
local utils        = addon:GetModule('Bags.Utils')

-- TODO: Move this to Icon.lua
---@class Icon: Button
---@field Update function
---@field label FontString

---@class CurrencyItem
---@field widget Icon|Button
---@field currencyId number
---@field value number
currency.itemProto = {}

---@class CurrencyFrame
---@field widget Frame
---@field gold FontString
---@field trackedCurrencies table<number, CurrencyItem>
currency.proto     = {}

---@param currencyInfo CurrencyInfo
---@param parent CurrencyFrame
function currency.itemProto:Build(currencyInfo, parent)
    self.currencyId = currencyInfo.currencyID
    self.value = currencyInfo.quantity

    self.widget:SetNormalTexture(currencyInfo.iconFileID)
    self.widget.label:SetText(currencyInfo.quantity)

    self.widget:SetScript('OnEnter', function()
        GameTooltip:SetOwner(self.widget, 'ANCHOR_TOPRIGHT')
        GameTooltip:SetText(currencyInfo.name .. ' (' .. currencyInfo.quantity .. ')', 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)

    self.widget:SetScript('OnLeave', function()
        GameTooltip:Hide()
    end)

    self.widget:SetParent(parent.widget)
    self.widget:SetPoint('LEFT', parent.widget, 'LEFT', 0, 0)

    self.widget:Show()
end

function currency.itemProto:Update(value)
    self.value = value
    self.widget.label:SetText(value)
    self.widget:Show()
end

function currency.itemProto:Clear()
    self.widget:Hide()
    self.widget:SetParent(nil)
    self.widget:ClearAllPoints()

    if currency._pool:IsActive(self) then
        currency._pool:Release(self)
    end
end

function currency.proto:Rebuild()
    local tracked = self.trackedCurrencies

    local index = 0
    for _, frame in pairs(tracked) do
        local iconSize = 24
        local padding = 2

        local xOffset = index * (80 + (iconSize + padding))
        frame.widget:SetPoint('LEFT', self.widget, 'LEFT', xOffset, 0)
        index = index + 1
    end
end

function currency:OnInitialize()
    self._pool = CreateObjectPool(self._DoCreate, self._DoReset)
    if self._pool.SetResetDisallowedIfNew then
        self._pool:SetResetDisallowedIfNew()
    end
end

---@return CurrencyFrame
function currency:CreateFrame(parent)
    local i = setmetatable({}, { __index = self.proto })
    i.trackedCurrencies = {}

    local font = database:GetFont()
    local fontSize = utils:GetFontScale()

    local goldView = parent:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    goldView:SetPoint('TOPLEFT', parent, 'TOPLEFT', 12, 0)
    goldView:SetHeight(session.Settings.Defaults.Sections.Footer)
    goldView:SetJustifyH('LEFT')
    goldView:SetText(C_CurrencyInfo.GetCoinTextureString(GetMoney(), fontSize))
    goldView:SetFont(font.path, fontSize)

    i.gold = goldView

    local currencyFrame = CreateFrame('Frame', nil, parent)
    currencyFrame:SetPoint('TOPLEFT', goldView, 'TOPRIGHT', 24, 0)
    currencyFrame:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', -2, 0)

    i.widget = currencyFrame
    return i
end

---@return CurrencyItem
function currency:Create()
    return self._pool:Acquire()
end

function currency:_DoCreate()
    local i = setmetatable({}, { __index = currency.itemProto })

    local font = database:GetFont()
    local fontSize = utils:GetFontScale()

    ---@type Icon|Button
    local f = CreateFrame('Button', nil, bags.bags.Inventory.widget.currency.widget)
    f:SetSize(24, 24)

    f:RegisterForClicks('LeftButtonUp')

    f:SetScript('OnClick', function()
        ToggleCharacter("TokenFrame")
    end)

    local count = f:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    count:SetPoint('LEFT', f, 'RIGHT', 2, 0)
    count:SetJustifyH('LEFT')
    count:SetFont(font.path, fontSize)

    f.label = count

    i.widget = f

    return i
end

function currency:_DoReset(item)

end

currency:Enable()
