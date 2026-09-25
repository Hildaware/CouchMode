local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

addon.MerchantRows = {}
local rows = addon.MerchantRows
local database = addon:GetModule('Bags.Database')
local rowStyle = addon.Components.ItemRow

local COMPACT_HEIGHT = 44

local function coinText(amount)
    if amount <= 0 then return '' end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(amount)
    end
    return GetMoneyString(amount)
end

local function costText(index, canAfford)
    local parts = {}
    for costIndex = 1, (GetMerchantItemCostInfo(index) or 0) do
        local texture, amount = GetMerchantItemCostItem(index, costIndex)
        if texture and amount then
            local amountText = tostring(amount)
            if canAfford == false then
                amountText = DISABLED_FONT_COLOR:WrapTextInColorCode(amountText)
            end
            parts[#parts + 1] = ('|T%s:14:14|t %s'):format(texture, amountText)
        end
    end
    return table.concat(parts, '  ')
end

local function priceText(amount, extended)
    if (amount or 0) > 0 then return coinText(amount) end
    if extended then return '' end
    return FREE or 'Free'
end

local function createRow(owner)
    local frame = rowStyle.Create(UIParent, { plainButton = true })
    local button = frame.itemButton
    -- The bag slot template leaves its store-item glow visible by default.
    -- Merchant rows never use the bag-only BattlePay/new-item decoration.
    frame.icon.BattlepayItemTexture:Hide()
    button:RegisterForDrag('LeftButton')
    button.buttonContext = 'ButtonContext_MerchantItemButton'
    button.UpdateTooltip = MerchantItemButton_OnEnter

    local name = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    name:SetJustifyH('LEFT')
    name:SetWordWrap(false)

    local detail = button:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    detail:SetJustifyH('LEFT')
    detail:SetWordWrap(false)

    local price = button:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    price:SetJustifyH('RIGHT')
    price:SetWordWrap(false)

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
    button:SetScript('OnEnter', function(self)
        self.HighlightTexture:Show()
        MerchantItemButton_OnEnter(self)
    end)
    button:SetScript('OnLeave', function(self)
        self.HighlightTexture:Hide()
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

    local row = {
        frame = frame, button = button, icon = frame.icon,
        name = name, detail = detail, price = price,
        height = database:GetItemViewHeight(), compact = false,
    }

    function row:resize(width)
        local height = database:GetItemViewHeight()
        local iconSize = math.max(1, height - 6)
        local iconColumnWidth = math.max(32, iconSize)
        local font = database:GetFont()
        local fontSize = rowStyle.GetFontSize(width, height, 20)

        self.height = height
        self.compact = height < COMPACT_HEIGHT
        rowStyle.SetGeometry(self.frame, width, height, iconColumnWidth)
        self.name:SetFont(font.path, fontSize)
        self.detail:SetFont(font.path, fontSize)
        self.price:SetFont(font.path, fontSize)

        self.name:ClearAllPoints()
        self.detail:ClearAllPoints()
        self.price:ClearAllPoints()
        if self.compact then
            local contentWidth = math.max(1, width - iconColumnWidth - 22)
            self.detail:SetPoint('RIGHT', self.button, 'RIGHT', -10, 0)
            self.detail:SetWidth(math.floor(contentWidth / 2))
            self.detail:SetJustifyH('RIGHT')
            self.name:SetPoint('LEFT', self.frame.iconContainer, 'RIGHT', 8, 0)
            self.name:SetPoint('RIGHT', self.detail, 'LEFT', -8, 0)
            self.price:Hide()
        else
            self.name:SetPoint('TOPLEFT', self.frame.iconContainer, 'TOPRIGHT', 8, -4)
            self.name:SetPoint('TOPRIGHT', self.button, 'TOPRIGHT', -170, -4)
            self.detail:SetPoint('BOTTOMLEFT', self.frame.iconContainer, 'BOTTOMRIGHT', 8, 4)
            self.detail:SetPoint('BOTTOMRIGHT', self.button, 'BOTTOMRIGHT', -170, 4)
            self.detail:SetJustifyH('LEFT')
            self.price:SetPoint('RIGHT', self.button, 'RIGHT', -10, 0)
            self.price:SetWidth(155)
            self.price:Show()
        end
    end

    function row:bind(data, offset, parent, width)
        self.frame:SetParent(parent)
        self.frame:ClearAllPoints()
        self.frame:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, -offset)
        self:resize(width)

        local index, buyback = data.index, data.buyback
        local itemName, texture, amount, stackCount, available, usable, extended, currencyID
        local link, quality
        if buyback then
            itemName, texture, amount, stackCount, available, usable = GetBuybackItemInfo(index)
            link = GetBuybackItemLink(index)
        else
            local info = C_MerchantFrame.GetItemInfo(index)
            if info then
                itemName, texture, amount, stackCount = info.name, info.texture, info.price, info.stackCount
                available, usable = info.numAvailable, info.isUsable
                extended, currencyID = info.hasExtendedCost, info.currencyID
                if currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
                    itemName, texture, available, quality = CurrencyContainerUtil.GetCurrencyContainerInfo(
                        currencyID, available, itemName, texture, nil)
                end
                link = GetMerchantItemLink(index)
            end
        end

        if not itemName then
            self.frame:Hide()
            return
        end

        if quality == nil and link then quality = select(3, C_Item.GetItemInfo(link)) end
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

        ClearItemButtonOverlay(self.icon)
        self.icon:SetHasItem(texture)
        self.icon:SetItemButtonTexture(texture)
        SetItemButtonCount(self.icon, stackCount or 1)
        local r, g, b = rowStyle.SetQuality(self.frame, quality, link)

        local knownHeirloom = false
        if not buyback and GetMerchantItemID and C_Heirloom and C_Heirloom.IsItemHeirloom
            and C_Heirloom.PlayerHasHeirloom then
            local itemID = GetMerchantItemID(index)
            knownHeirloom = itemID and C_Heirloom.IsItemHeirloom(itemID)
                and C_Heirloom.PlayerHasHeirloom(itemID) or false
        end
        SetItemButtonDesaturated(self.icon, knownHeirloom)
        self.name:SetText(itemName)
        self.name:SetTextColor(r, g, b)
        if not usable then self.name:SetTextColor(0.9, 0.25, 0.25) end

        local details = {}
        if available and available > 0 then details[#details + 1] = ('Stock: %s'):format(available) end
        if available == 0 then details[#details + 1] = SOLD_OUT or 'Sold out' end
        local canAfford = buyback or CanAffordMerchantItem(index)
        if not buyback and extended then details[#details + 1] = costText(index, canAfford) end
        local priceValue = priceText(amount, extended)
        local priceColor = canAfford == false and DISABLED_FONT_COLOR or HIGHLIGHT_FONT_COLOR
        self.price:SetTextColor(priceColor:GetRGB())
        if self.compact then
            if priceValue ~= '' then
                details[#details + 1] = canAfford == false
                    and DISABLED_FONT_COLOR:WrapTextInColorCode(priceValue) or priceValue
            end
            self.detail:SetText(table.concat(details, '  '))
            self.price:SetText('')
        else
            self.detail:SetText(table.concat(details, '  '))
            self.price:SetText(priceValue)
        end

        self.frame.itemButton.Desaturate:Hide()
        self.button:Enable()
        self.icon:Show()
        self.frame:Show()
        self.button:Show()
    end

    function row:reset()
        if GameTooltip:IsOwned(self.button) then
            GameTooltip:Hide()
            MerchantFrame.itemHover = nil
        end
        self.button.hasItem = nil
        self.button.count = nil
        self.button.price = nil
        self.button.extendedCost = nil
        self.button.showNonrefundablePrompt = nil
        self.button.name = nil
        self.button.link = nil
        self.button.texture = nil
        self.name:SetText('')
        self.detail:SetText('')
        self.price:SetText('')
        rowStyle.Reset(self.frame)
    end

    return row
end

function rows:GetHeight()
    return database:GetItemViewHeight()
end

function rows:CreateRenderer(owner)
    return { create = function() return createRow(owner) end }
end
