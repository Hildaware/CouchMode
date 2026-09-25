local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

addon.MerchantRows = {}
local rows = addon.MerchantRows

local ROW_HEIGHT = 58

local function coinText(amount)
    if amount <= 0 then return '' end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(amount)
    end
    return GetMoneyString(amount)
end

local function costText(index)
    local parts = {}
    for costIndex = 1, (GetMerchantItemCostInfo(index) or 0) do
        local texture, amount = GetMerchantItemCostItem(index, costIndex)
        if texture and amount then
            parts[#parts + 1] = ('|T%s:14:14|t %s'):format(texture, amount)
        end
    end
    return table.concat(parts, '  ')
end

local function createRow(owner)
    local frame = CreateFrame('Frame', nil, UIParent)
    frame:SetHeight(ROW_HEIGHT)
    local background = frame:CreateTexture(nil, 'BACKGROUND')
    background:SetAllPoints(frame)
    background:SetColorTexture(0.1, 0.1, 0.1, 0.55)

    local button = CreateFrame('Button', nil, frame)
    button:SetAllPoints(frame)
    button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    button:RegisterForDrag('LeftButton')
    button.buttonContext = 'ButtonContext_MerchantItemButton'

    local highlight = button:CreateTexture(nil, 'HIGHLIGHT')
    highlight:SetAllPoints(button)
    highlight:SetColorTexture(1, 0.8, 0.25, 0.12)

    local icon = button:CreateTexture(nil, 'ARTWORK')
    icon:SetSize(42, 42)
    icon:SetPoint('LEFT', button, 'LEFT', 8, 0)
    local count = button:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
    count:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT', -1, 1)

    local name = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    name:SetPoint('TOPLEFT', icon, 'TOPRIGHT', 9, -2)
    name:SetPoint('TOPRIGHT', button, 'TOPRIGHT', -170, -7)
    name:SetJustifyH('LEFT')
    name:SetWordWrap(false)

    local detail = button:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    detail:SetPoint('BOTTOMLEFT', icon, 'BOTTOMRIGHT', 9, 4)
    detail:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', -170, 8)
    detail:SetJustifyH('LEFT')
    detail:SetWordWrap(false)

    local price = button:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    price:SetPoint('RIGHT', button, 'RIGHT', -10, 0)
    price:SetWidth(155)
    price:SetJustifyH('RIGHT')

    button:SetScript('OnClick', function(self, mouseButton)
        if IsModifiedClick() then
            MerchantItemButton_OnModifiedClick(self, mouseButton)
        else
            MerchantItemButton_OnClick(self, mouseButton)
            owner:RememberPendingPurchase(self)
        end
    end)
    button:SetScript('OnDragStart', function(self)
        MerchantItemButton_OnClick(self, 'LeftButton')
        owner:RememberPendingPurchase(self)
    end)
    button:SetScript('OnEnter', function(self) MerchantItemButton_OnEnter(self) end)
    button:SetScript('OnLeave', function()
        GameTooltip:Hide()
        ResetCursor()
        MerchantFrame.itemHover = nil
    end)
    button.SplitStack = function(self, quantity)
        if quantity <= 0 then return end
        if self.extendedCost or self.showNonrefundablePrompt then
            MerchantFrame_ConfirmExtendedItemCost(self, quantity)
        else
            BuyMerchantItem(self:GetID(), quantity)
        end
    end

    local row = { frame = frame, button = button, icon = icon, count = count,
        name = name, detail = detail, price = price, height = ROW_HEIGHT }

    function row:resize(width)
        self.frame:SetWidth(width)
    end

    function row:bind(data, offset, parent, width)
        self.frame:SetParent(parent)
        self.frame:ClearAllPoints()
        self.frame:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, -offset)
        self:resize(width)

        local index, buyback = data.index, data.buyback
        local itemName, texture, amount, stackCount, available, purchasable, usable, extended, currencyID
        local link
        if buyback then
            itemName, texture, amount, stackCount, available, usable = GetBuybackItemInfo(index)
            purchasable = true
            link = GetBuybackItemLink(index)
        else
            local info = C_MerchantFrame.GetItemInfo(index)
            if info then
                itemName, texture, amount, stackCount = info.name, info.texture, info.price, info.stackCount
                available, purchasable, usable = info.numAvailable, info.isPurchasable, info.isUsable
                extended, currencyID = info.hasExtendedCost, info.currencyID
                if currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
                    itemName, texture, available = CurrencyContainerUtil.GetCurrencyContainerInfo(currencyID, available, itemName, texture, nil)
                end
                link = GetMerchantItemLink(index)
            end
        end

        if not itemName then
            self.frame:Hide()
            return
        end
        self.frame:Show()
        self.button:SetID(index)
        self.button.hasItem = true
        self.button.count = stackCount or 1
        self.button.price = amount
        self.button.extendedCost = extended
        self.button.showNonrefundablePrompt = not buyback and C_MerchantFrame.IsMerchantItemRefundable
            and not C_MerchantFrame.IsMerchantItemRefundable(index) or false
        self.button.name = itemName
        self.button.link = link
        self.button.texture = texture

        self.icon:SetTexture(texture)
        self.count:SetText((stackCount or 1) > 1 and stackCount or '')
        self.name:SetText(itemName)
        local quality = link and select(3, C_Item.GetItemInfo(link))
        if quality then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            self.name:SetTextColor(r, g, b)
        else
            self.name:SetTextColor(1, 0.82, 0)
        end

        local details = {}
        if available and available > 0 then details[#details + 1] = ('Stock: %s'):format(available) end
        if available == 0 then details[#details + 1] = SOLD_OUT or 'Sold out' end
        if not buyback and extended then details[#details + 1] = costText(index) end
        self.detail:SetText(table.concat(details, '  '))
        self.price:SetText((amount or 0) > 0 and coinText(amount) or (extended and '' or (FREE or 'Free')))
        local canBuy = buyback or (purchasable and available ~= 0 and CanAffordMerchantItem(index))
        self.icon:SetDesaturated(not canBuy)
        self.button:Enable()
        if not usable then self.name:SetTextColor(0.9, 0.25, 0.25) end
    end

    function row:reset()
        if GameTooltip:IsOwned(self.button) then GameTooltip:Hide(); MerchantFrame.itemHover = nil end
        self.button.hasItem = nil
        self.button.link = nil
        self.frame:Hide()
        self.frame:ClearAllPoints()
        self.frame:SetParent(nil)
    end

    return row
end

function rows:CreateRenderer(owner)
    return { create = function() return createRow(owner) end }
end
