local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local merchant = addon:NewModule('Merchant', 'AceEvent-3.0')
local utils = addon.Utils

local defaults = { merchant = { enabled = true, width = 600, height = 500 } }
local REFRESH_EVENTS = {
    'MERCHANT_UPDATE', 'MERCHANT_FILTER_ITEM_UPDATE', 'PLAYER_MONEY', 'BAG_UPDATE',
    'CURRENCY_DISPLAY_UPDATE', 'GUILDBANK_UPDATE_MONEY', 'GUILDBANK_UPDATE_WITHDRAWMONEY',
    'UPDATE_INVENTORY_DURABILITY', 'GET_ITEM_INFO_RECEIVED', 'UNIT_INVENTORY_CHANGED',
}

local function nativeGamepadEnabled()
    return _G.InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
        and _G.GamepadMode and GamepadMode.FrameControlsManager and _G.SmartNavigation
end

local function addButton(parent, label, width, anchor, relative, x, y, onClick)
    local button = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    button:SetSize(width, 24)
    button:SetPoint(anchor, relative, anchor, x, y)
    button:SetText(label)
    button:SetScript('OnClick', onClick)
    return button
end

local function addIconButton(parent, atlas, tooltip, point, relative, relativePoint, x, y, onClick)
    local button = CreateFrame('Button', nil, parent)
    button:SetSize(36, 36)
    button:SetPoint(point, relative, relativePoint, x, y)

    local background = button:CreateTexture(nil, 'BACKGROUND')
    background:SetTexture('Interface\\Buttons\\UI-EmptySlot')
    background:SetSize(64, 64)
    background:SetPoint('TOPLEFT', button, 'TOPLEFT', -13, 14)

    button.icon = button:CreateTexture(nil, 'BORDER')
    button.icon:SetAtlas(atlas)
    button.icon:SetPoint('CENTER')
    button.icon:SetSize(32, 32)

    button:SetPushedTexture('Interface\\Buttons\\UI-Quickslot-Depress')
    button:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square', 'ADD')
    button:SetScript('OnClick', onClick)
    button:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_TOP')
        GameTooltip:SetText(tooltip)
        GameTooltip:Show()
    end)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    return button
end

local function disableMouseRecursively(frame, saved)
    if frame.EnableMouse and frame.IsMouseEnabled then
        if not saved.mouseStateByFrame[frame] then
            saved.mouse[#saved.mouse + 1] = { frame, frame:IsMouseEnabled() }
            saved.mouseStateByFrame[frame] = true
        end
        frame:EnableMouse(false)
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        disableMouseRecursively(child, saved)
    end
end

function merchant:GetDefaults()
    return defaults
end

function merchant:GetOptions()
    return 'merchant', {
        name = 'Merchant', type = 'group', order = 1.5,
        args = {
            enabled = {
                name = 'Enable', desc = 'Use the custom merchant view on retail and WoW: Forever.',
                type = 'toggle', order = 1,
                get = function() return addon.db.profile.merchant.enabled end,
                set = function(_, value)
                    addon.db.profile.merchant.enabled = value
                    if value then self:Enable() else self:Disable() end
                end,
            },
        },
    }
end

function merchant:OnEnable()
    self.profile = addon.db.profile.merchant
    if not self.profile.enabled or (utils.FLAVOR ~= 'retail' and utils.FLAVOR ~= 'forever') then
        self:Disable()
        return
    end
    if not _G.MerchantFrame or not C_MerchantFrame or not C_MerchantFrame.GetItemInfo
        or not _G.MerchantItemButton_OnClick then
        self:Disable()
        return
    end

    if not self.catalog then self:CreateView() end
    if not self.hooked then
        MerchantFrame:HookScript('OnShow', function() if self:IsEnabled() then self:Open() end end)
        MerchantFrame:HookScript('OnHide', function() if self:IsEnabled() then self:CloseFromNative() end end)
        if _G.MerchantFrame_UpdateCurrencies then
            hooksecurefunc('MerchantFrame_UpdateCurrencies', function()
                if self.active then self:ConcealNative() end
            end)
        end
        self.hooked = true
    end
    for _, event in ipairs(REFRESH_EVENTS) do
        utils.RegisterEventIfValid(self, event, 'OnRefreshEvent')
    end
    if MerchantFrame:IsShown() then self:Open() end
end

function merchant:OnDisable()
    self:UnregisterAllEvents()
    self.active = false
    self.pendingPurchase = nil
    if self.catalog then
        self.closingFromNative = true
        self.catalog:Hide()
        self.closingFromNative = false
    end
    self:RestoreNative()
end

function merchant:RememberPendingPurchase(button)
    if MerchantFrame.extendedCost ~= button and MerchantFrame.highPrice ~= button then return end
    local proxy = {
        index = button:GetID(), count = button.count, price = button.price,
        name = button.name, link = button.link, texture = button.texture,
        extendedCost = button.extendedCost,
        showNonrefundablePrompt = button.showNonrefundablePrompt,
    }
    function proxy:GetID() return self.index end
    if MerchantFrame.extendedCost == button then MerchantFrame.extendedCost = proxy end
    if MerchantFrame.highPrice == button then MerchantFrame.highPrice = proxy end
    self.pendingPurchase = proxy
end

function merchant:ClearPendingPurchase()
    if not _G.MerchantFrame then return end
    MerchantFrame.extendedCost = nil
    MerchantFrame.highPrice = nil
    self.pendingPurchase = nil
end

function merchant:ConcealNative()
    local frame = MerchantFrame
    local saved = self.nativeState
    if not saved then
        saved = { alpha = frame:GetAlpha(), mouse = {}, mouseStateByFrame = {}, ignored = frame.smartNavigationIgnored }
        self.nativeState = saved
    end
    disableMouseRecursively(frame, saved)
    frame:SetAlpha(0)
    frame.smartNavigationIgnored = true
end

function merchant:RestoreNative()
    local saved = self.nativeState
    if not saved then return end
    MerchantFrame:SetAlpha(saved.alpha)
    MerchantFrame.smartNavigationIgnored = saved.ignored
    for _, state in ipairs(saved.mouse) do state[1]:EnableMouse(state[2]) end
    self.nativeState = nil
end

function merchant:SaveGeometry()
    if not self.catalog or not self.catalog.frame:IsShown() then return end
    local frame = self.catalog.frame
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    self.profile.width = math.floor(frame:GetWidth() + 0.5)
    self.profile.height = math.floor(frame:GetHeight() + 0.5)
    self.profile.x = math.floor(left + 0.5)
    self.profile.y = math.floor(top - UIParent:GetTop() + 0.5)
end

function merchant:PlaceView()
    if not self.catalog then return end
    local frame = self.catalog.frame
    frame:ClearAllPoints()
    if self.profile.x and self.profile.y then
        local maxX = math.max(0, UIParent:GetWidth() - frame:GetWidth())
        local minY = math.min(0, frame:GetHeight() - UIParent:GetHeight())
        frame:SetPoint('TOPLEFT', UIParent, 'TOPLEFT',
            math.min(math.max(self.profile.x, 0), maxX), math.max(math.min(self.profile.y, 0), minY))
        return
    end
    local bags = addon:GetModule('Bags', true)
    local inventory = bags and bags.bags and bags.bags.Inventory
    local inventoryFrame = inventory and inventory.widget
    if inventoryFrame and inventoryFrame:IsShown() then
        frame:SetPoint('TOPRIGHT', inventoryFrame, 'TOPLEFT', -10, 0)
        if frame:GetLeft() and frame:GetLeft() < 0 then
            frame:ClearAllPoints()
            frame:SetPoint('TOPLEFT', inventoryFrame, 'TOPRIGHT', 10, 0)
        end
        if frame:GetRight() and frame:GetRight() > UIParent:GetWidth() then
            frame:ClearAllPoints()
            frame:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', 0, 0)
        end
    else
        frame:SetPoint('CENTER', UIParent, 'CENTER', -250, 0)
    end
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then
        local x = math.min(math.max(left, 0), math.max(0, UIParent:GetWidth() - frame:GetWidth()))
        local y = math.max(math.min(top - UIParent:GetTop(), 0),
            math.min(0, frame:GetHeight() - UIParent:GetHeight()))
        if x ~= left or y ~= top - UIParent:GetTop() then
            frame:ClearAllPoints()
            frame:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', x, y)
        end
    end
end

function merchant:RequestClose()
    if MerchantFrame:IsShown() then HideUIPanel(MerchantFrame) end
end

function merchant:Open()
    if self.active then return end
    self.active = true
    self.mode = 'merchant'
    self.searchText = ''
    self:ConcealNative()
    if self.catalog.searchBox then
        self.settingSearchText = true
        self.catalog.searchBox:SetText('')
        self.settingSearchText = false
    end
    self:PlaceView()
    self.catalog:Show()
    self:Refresh()
    C_Timer.After(0, function()
        if self.active and not self.profile.x then self:PlaceView() end
        if self.active then self:ConcealNative(); self:Refresh() end
    end)
end

function merchant:CloseFromNative()
    self.active = false
    if self.catalog then
        self.closingFromNative = true
        self.catalog:Hide()
        self.closingFromNative = false
    end
    if InRepairMode() then
        HideRepairCursor()
        if nativeGamepadEnabled() then SmartNavigation:ClearOverrideIconAtlas() end
    end
    self:ClearPendingPurchase()
    self:RestoreNative()
end

function merchant:SetTab(mode)
    if not self.active or self.mode == mode then return end
    if CursorHasItem() then ClearCursor() end
    self:ClearPendingPurchase()
    self.mode = mode
    local tab = mode == 'buyback' and 2 or 1
    PanelTemplates_SetTab(MerchantFrame, tab)
    if _G.MerchantFrame_Update then MerchantFrame_Update() end
    if _G.EventRegistry then
        EventRegistry:TriggerEvent(mode == 'buyback' and 'MerchantFrame.BuyBackTabShow' or 'MerchantFrame.MerchantTabShow')
    end
    StackSplitFrame:Hide()
    self:Refresh(true)
end

function merchant:BuildRows()
    local found = {}
    local buyback = self.mode == 'buyback'
    local count = buyback and GetNumBuybackItems() or GetMerchantNumItems()
    local needle = not buyback and self.searchText and self.searchText:lower()
    for index = 1, count do
        local name
        if buyback then
            name = GetBuybackItemInfo(index)
        else
            local info = C_MerchantFrame.GetItemInfo(index)
            name = info and info.name
            if info and info.currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
                name = CurrencyContainerUtil.GetCurrencyContainerInfo(info.currencyID, info.numAvailable,
                    info.name, info.texture, nil)
            end
        end
        if name and (not needle or needle == '' or name:lower():find(needle, 1, true)) then
            local price
            if buyback then
                local _, _, buybackPrice = GetBuybackItemInfo(index)
                price = buybackPrice
            else
                local info = C_MerchantFrame.GetItemInfo(index)
                price = info and info.price
            end
            found[#found + 1] = { index = index, buyback = buyback, name = name, price = price or 0 }
        end
    end
    local sortField = self.sortField or 'name'
    local descending = self.sortDescending == true
    table.sort(found, function(a, b)
        local left, right
        if sortField == 'cost' then
            left, right = a.price, b.price
        else
            left, right = a.name:lower(), b.name:lower()
        end
        if left == right then return a.index < b.index end
        if descending then return left > right end
        return left < right
    end)
    return found
end

function merchant:UpdateSortHeader()
    if not self.sortButtons then return end
    for field, button in pairs(self.sortButtons) do
        local selected = self.sortField == field
        button.text:SetTextColor(selected and 1 or 0.85, selected and 0.82 or 0.85, selected and 0 or 0.85)
        button.arrow:SetShown(selected)
        if selected then
            button.arrow:SetTexture(self.sortDescending
                and 'Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Arrow_Down'
                or 'Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Arrow_Up')
        end
    end
end

function merchant:SortBy(field)
    if self.sortField == field then
        self.sortDescending = not self.sortDescending
    else
        self.sortField = field
        self.sortDescending = false
    end
    self:UpdateSortHeader()
    self:Refresh(true)
end

function merchant:OnRefreshEvent()
    self:Refresh()
end

function merchant:Refresh(resetScroll)
    if not self.active or not self.catalog then return end
    self:ConcealNative()
    local pending = self.pendingPurchase
    if pending then
        local info = C_MerchantFrame.GetItemInfo(pending.index)
        local currentName = info and info.name
        if info and info.currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
            currentName = CurrencyContainerUtil.GetCurrencyContainerInfo(info.currencyID, info.numAvailable,
                info.name, info.texture, nil)
        end
        if not info or currentName ~= pending.name or GetMerchantItemLink(pending.index) ~= pending.link then
            if CursorHasItem() then ClearCursor() end
            self:ClearPendingPurchase()
        end
    end
    local title = self.mode == 'buyback' and (MERCHANT_BUYBACK or 'Buyback') or (UnitName('npc') or MERCHANT or 'Merchant')
    self.catalog.frame.TitleText:SetText(title)
    PanelTemplates_SetTab(self.catalog.headerActions, self.mode == 'buyback' and 2 or 1)
    self.catalog.searchBox:SetShown(self.mode == 'merchant')
    self.filterDropdown:SetShown(self.mode == 'merchant' and self:HasMerchantFilter())
    if self.filterDropdown:IsShown() then self.filterDropdown:Update() end
    self.catalog:Render({ { rows = self:BuildRows() } }, resetScroll)
    self:RefreshFooter()
    if self.gamepadFooter then self.gamepadFooter:Refresh() end
    self:RefreshGamepadNavigation()
end

function merchant:HasMerchantFilter()
    if not self.filterDropdown or not SetMerchantFilter or not GetMerchantFilter then return false end
    if C_GameRules and C_GameRules.IsGameRuleActive and Enum.GameRule and Enum.GameRule.MerchantFilterDisabled then
        return not C_GameRules.IsGameRuleActive(Enum.GameRule.MerchantFilterDisabled)
    end
    return true
end

function merchant:LayoutCurrencies()
    if not self.money or not self.currencies then return end
    local currencyCount = self.currencyCount or 0
    local currencyStart = 12 + self.money:GetStringWidth() + 24
    local availableWidth = math.max(50, self.catalog.footer:GetWidth() - currencyStart - 12)
    local spacing = currencyCount > 1
        and math.min(56, math.max(50, (availableWidth - 50) / (currencyCount - 1))) or 56
    for index, slot in ipairs(self.currencies) do
        slot:ClearAllPoints()
        slot:SetPoint('TOPLEFT', self.catalog.footer, 'TOPLEFT', currencyStart + (index - 1) * spacing, -4)
    end
end

function merchant:RefreshFooter()
    local canRepair = CanMerchantRepair()
    local repairCost, hasRepairs = GetRepairAllCost()
    self.repairAll:Show()
    self.repairSingle:Show()
    local canRepairAll = canRepair and hasRepairs and repairCost <= GetMoney()
    self.repairAll:SetEnabled(canRepairAll)
    self.repairAll.icon:SetDesaturated(not canRepairAll)
    self.repairSingle:SetEnabled(canRepair)
    self.repairSingle.icon:SetDesaturated(false)
    if InRepairMode() then self.repairSingle:LockHighlight() else self.repairSingle:UnlockHighlight() end
    local canGuildRepair = canRepair and CanGuildBankRepair and CanGuildBankRepair()
    self.repairGuild:SetShown(canGuildRepair and true or false)
    self.repairGuild:SetEnabled(canGuildRepair and hasRepairs)
    local sellJunkEnabled = C_MerchantFrame.GetNumJunkItems
        and C_MerchantFrame.GetNumJunkItems() > 0 or false
    self.sellJunk:SetShown(self.mode == 'merchant' and C_MerchantFrame.IsSellAllJunkEnabled
        and C_MerchantFrame.IsSellAllJunkEnabled() or false)
    self.sellJunk:SetEnabled(sellJunkEnabled)
    self.sellJunk.icon:SetDesaturated(not sellJunkEnabled)
    self.money:SetText(C_CurrencyInfo.GetCoinTextureString(GetMoney()))

    local currencies = C_MerchantFrame.GetMerchantCurrencies and C_MerchantFrame.GetMerchantCurrencies() or {}
    self.currencyCount = #currencies
    for index, slot in ipairs(self.currencies) do
        local currencyID = currencies[index]
        local info = currencyID and C_CurrencyInfo.GetCurrencyInfo(currencyID)
        slot:SetShown(info ~= nil)
        slot.currencyID = currencyID
        if info then
            slot.icon:SetTexture(info.iconFileID)
            slot.count:SetText(tostring(info.quantity))
        end
    end
    self:LayoutCurrencies()
end

function merchant:CreateView()
    local scrollTemplate = _G.ConsolePort and not nativeGamepadEnabled() and 'CPSmoothScrollTemplate' or 'UIPanelScrollFrameTemplate'
    if scrollTemplate == 'CPSmoothScrollTemplate' and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn('ConsolePort_Config')
    end
    self.catalog = addon.CatalogView:Create({
        name = 'CouchModeMerchant', title = MERCHANT or 'Merchant', strata = 'HIGH',
        width = self.profile.width, height = self.profile.height,
        minWidth = 480, minHeight = 360, maxWidth = 1200, maxHeight = 1200,
        headerHeight = 32, toolbarHeight = 34, columnHeaderHeight = 24, footerHeight = 76,
        rowHeight = addon.MerchantRows:GetHeight(), scrollTemplate = scrollTemplate, search = true,
        onSearch = function(text)
            if self.settingSearchText then return end
            if CursorHasItem() then ClearCursor() end
            self:ClearPendingPurchase()
            self.searchText = text
            self:Refresh(true)
        end,
        onClose = function() self:RequestClose() end,
        onHide = function() if self.active and not self.closingFromNative then self:RequestClose() end end,
        onMove = function() self:SaveGeometry() end,
        onResize = function() self:SaveGeometry() end,
        onLayoutChanged = function(catalog)
            for _, row in ipairs(catalog.activeRows) do row:resize(catalog.content:GetWidth()) end
            if self.money then self:LayoutCurrencies() end
        end,
        rowRenderer = addon.MerchantRows:CreateRenderer(self),
    })
    local frame = self.catalog.frame
    frame:Hide()
    local shade = frame:CreateTexture(nil, 'BACKGROUND')
    shade:SetAllPoints(frame)
    shade:SetColorTexture(0, 0, 0, 0.8)

    local tabs = self.catalog.headerActions
    tabs.Tabs = {}
    tabs.tabPadding = 12
    self.buyTab = CreateFrame('Button', nil, tabs, 'PanelTabButtonTemplate')
    self.buyTab:SetID(1)
    self.buyTab:SetText(MERCHANT or 'Merchant')
    self.buyTab:SetPoint('TOPLEFT', tabs, 'TOPLEFT', 0, 0)
    self.buyTab:SetScript('OnClick', function() self:SetTab('merchant') end)
    tabs.Tabs[1] = self.buyTab

    self.buybackTab = CreateFrame('Button', nil, tabs, 'PanelTabButtonTemplate')
    self.buybackTab:SetID(2)
    self.buybackTab:SetText(MERCHANT_BUYBACK or 'Buyback')
    tabs.Tabs[2] = self.buybackTab
    PanelTemplates_SetNumTabs(tabs, 2)
    PanelTemplates_SetTab(tabs, 1)
    self.buybackTab:SetScript('OnClick', function() self:SetTab('buyback') end)

    local columnHeader = self.catalog.columnHeader
    local underline = columnHeader:CreateTexture(nil, 'BACKGROUND')
    underline:SetPoint('BOTTOMLEFT', columnHeader, 'BOTTOMLEFT', 0, 2)
    underline:SetPoint('BOTTOMRIGHT', columnHeader, 'BOTTOMRIGHT', 0, 2)
    underline:SetHeight(1)
    underline:SetColorTexture(1, 1, 1, 0.4)
    self.sortButtons = {}
    local function createSortButton(field, label, anchor, relative, x, width)
        local button = CreateFrame('Button', nil, columnHeader)
        button:SetSize(width, 22)
        button:SetPoint(anchor, relative, anchor, x, 0)
        button.text = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
        button.text:SetPoint(field == 'name' and 'LEFT' or 'RIGHT', button, field == 'name' and 'LEFT' or 'RIGHT', 0, 0)
        button.text:SetText(label)
        button.arrow = button:CreateTexture(nil, 'ARTWORK')
        button.arrow:SetSize(8, 12)
        button.arrow:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Arrow_Up')
        if field == 'name' then
            button.arrow:SetPoint('LEFT', button.text, 'RIGHT', 3, 0)
        else
            button.arrow:SetPoint('RIGHT', button.text, 'LEFT', -3, 0)
        end
        button:SetScript('OnClick', function() self:SortBy(field) end)
        button:SetScript('OnEnter', function()
            GameTooltip:SetOwner(button, 'ANCHOR_TOP')
            GameTooltip:SetText((SORT_BY or 'Sort by') .. ' ' .. label)
            GameTooltip:Show()
        end)
        button:SetScript('OnLeave', function() GameTooltip:Hide() end)
        self.sortButtons[field] = button
    end
    createSortButton('name', NAME or 'Name', 'LEFT', columnHeader, 48, 220)
    createSortButton('cost', COST or 'Cost', 'RIGHT', columnHeader, -8, 155)
    self.sortField = self.sortField or 'name'
    if self.sortDescending == nil then self.sortDescending = false end
    self:UpdateSortHeader()

    local filter = CreateFrame('DropdownButton', nil, self.catalog.toolbar, 'WowStyle1DropdownTemplate')
    filter:SetPoint('LEFT', self.catalog.toolbar, 'LEFT', 10, 0)
    filter:SetWidth(190)
    filter:SetupMenu(function(_, root)
        local function selected(value) return GetMerchantFilter() == value end
        local function choose(value)
            if CursorHasItem() then ClearCursor() end
            self:ClearPendingPurchase()
            SetMerchantFilter(value)
            self:Refresh(true)
        end
        if GetNumSpecializations and (C_SpecializationInfo or GetSpecializationInfo) and LE_LOOT_FILTER_SPEC1 then
            for index = 1, GetNumSpecializations() do
                local specName
                if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
                    specName = select(2, C_SpecializationInfo.GetSpecializationInfo(index, false, false, nil, UnitSex('player')))
                else
                    specName = select(2, GetSpecializationInfo(index))
                end
                if specName then root:CreateRadio(specName, selected, choose, LE_LOOT_FILTER_SPEC1 + index - 1) end
            end
        end
        if LE_LOOT_FILTER_CLASS then root:CreateRadio(ALL_SPECS or 'All Specializations', selected, choose, LE_LOOT_FILTER_CLASS) end
        root:CreateDivider()
        if LE_LOOT_FILTER_BOE then root:CreateRadio(ITEM_BIND_ON_EQUIP or 'Bind on Equip', selected, choose, LE_LOOT_FILTER_BOE) end
        if LE_LOOT_FILTER_ALL then root:CreateRadio(ALL or 'All', selected, choose, LE_LOOT_FILTER_ALL) end
    end)
    self.filterDropdown = filter

    local footer = self.catalog.footer
    self.repairSingle = addIconButton(footer, 'SpellIcon-256x256-Repair', REPAIR_AN_ITEM or 'Repair',
        'RIGHT', footer, 'BOTTOMRIGHT', -66, 32, function()
            if InRepairMode() then
                HideRepairCursor()
                if nativeGamepadEnabled() then SmartNavigation:ClearOverrideIconAtlas() end
            else
                ShowRepairCursor()
                if nativeGamepadEnabled() then
                    SmartNavigation:SetOverrideIconAtlas('gamepad-repairhammercursor-vendor')
                    ToggleCharacter('PaperDollFrame', true)
                end
            end
            self:RefreshFooter()
        end)
    self.repairAll = addIconButton(footer, 'SpellIcon-256x256-RepairAll', REPAIR_ALL_ITEMS or 'Repair all items',
        'RIGHT', footer, 'BOTTOMRIGHT', -24, 32, function()
            RepairAllItems()
            PlaySound(SOUNDKIT.ITEM_REPAIR)
            self:RefreshFooter()
        end)
    self.repairGuild = addButton(footer, GUILDBANK_REPAIR or 'Guild repair', 105,
        'TOPLEFT', footer, 0, -9, function()
            RepairAllItems(true)
            PlaySound(SOUNDKIT.ITEM_REPAIR)
            self:RefreshFooter()
        end)
    self.sellJunk = addIconButton(footer, 'SpellIcon-256x256-SellJunk', SELL_ALL_JUNK_ITEMS or 'Sell all junk',
        'RIGHT', self.repairSingle, 'LEFT', -20, 0, function() MerchantFrame_OnSellAllJunkButtonClicked() end)
    self.repairGuild:ClearAllPoints()
    self.repairGuild:SetPoint('RIGHT', self.sellJunk, 'LEFT', -20, 0)
    self.money = footer:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    self.money:SetPoint('LEFT', footer, 'BOTTOMLEFT', 12, 32)
    self.money:SetJustifyH('LEFT')

    self.currencies = {}
    for index = 1, 6 do
        local slot = CreateFrame('Button', nil, footer)
        slot:SetSize(50, 22)
        slot:SetPoint('TOPLEFT', footer, 'TOPLEFT', 156 + (index - 1) * 56, -4)
        slot.icon = slot:CreateTexture(nil, 'ARTWORK')
        slot.icon:SetSize(18, 18)
        slot.icon:SetPoint('LEFT', slot, 'LEFT', 0, 0)
        slot.count = slot:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
        slot.count:SetPoint('LEFT', slot.icon, 'RIGHT', 3, 0)
        slot:SetScript('OnEnter', function(button)
            if not button.currencyID then return end
            GameTooltip:SetOwner(button, 'ANCHOR_RIGHT')
            GameTooltip:SetCurrencyByID(button.currencyID)
            GameTooltip:Show()
        end)
        slot:SetScript('OnLeave', function() GameTooltip:Hide() end)
        self.currencies[index] = slot
    end

    frame.SmartNavigationCloseHandler = function() self:RequestClose(); return true end
    table.insert(UISpecialFrames, frame:GetName())
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript('OnGamePadButtonDown', function(_, key)
        if key == 'PADLSHOULDER' then self:SetTab('merchant')
        elseif key == 'PADRSHOULDER' then self:SetTab('buyback') end
    end)
    frame:HookScript('OnShow', function() self:ActivateGamepad() end)
    frame:HookScript('OnHide', function() self:DeactivateGamepad() end)
    if scrollTemplate == 'CPSmoothScrollTemplate' then
        ConsolePort:AddInterfaceCursorFrame(frame)
    end
end

function merchant:CreateNativeGamepadFooter()
    if self.gamepadFooter or not _G.GamepadSharedUtility then return end
    local current = function()
        local button = SmartNavigation:GetCurrentButton()
        if button and button.buttonContext == 'ButtonContext_MerchantItemButton' and button.hasItem then
            return button
        end
    end
    local buy = GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_BOTTOM,
        function() SmartNavigation:RightClick() end, CONTEXT_ACTION_LABEL_BUY)
    buy:AddButtonContext('ButtonContext_MerchantItemButton')
    buy:AddCondition(current)
    local multiple = GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_LEFT, function()
        local button = current()
        if button and self.mode == 'merchant' then MerchantItemButton_BuyMultipleStacks(button) end
    end, CONTEXT_ACTION_LABEL_MULTI_BUY)
    multiple:AddButtonContext('ButtonContext_MerchantItemButton')
    multiple:AddCondition(function()
        local button = current()
        return button and self.mode == 'merchant' and GetMerchantItemMaxStack(button:GetID()) > 1
    end)
    local close = GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_RIGHT,
        function() self:RequestClose() end, FRAME_ACTION_CLOSE)
    local footer = GamepadSharedUtility.CreatePromptedBindingFooter(self.catalog.frame, 'CouchModeMerchantFooter')
    footer:AddPromptedBinding(buy)
    footer:AddPromptedBinding(multiple)
    footer:AddStandardFrameControlManagerBindings(self.catalog.frame)
    footer:AddPromptedBinding(close)
    footer:Finalize()
    self.gamepadFooter = footer
end

function merchant:RefreshNativeGamepadFocus()
    if not nativeGamepadEnabled() then return end
    local manager = GamepadMode.FrameControlsManager
    local focused = manager.isUIFocused and manager:GetActiveFrame() == self.catalog.frame
    if focused then
        self:CreateNativeGamepadFooter()
        if self.gamepadFooter then securecallfunction(self.gamepadFooter.ShowAndActivateBindings, self.gamepadFooter) end
    elseif self.gamepadFooter then
        securecallfunction(self.gamepadFooter.HideAndDeactivateBindings, self.gamepadFooter)
    end
end

function merchant:ActivateGamepad()
    if _G.ConsolePortInputHandler and _G.ConsolePort and not nativeGamepadEnabled() and not InCombatLockdown() then
        ConsolePortInputHandler:SetCommand('PADLSHOULDER', self.catalog.frame, true, 'LeftButton', 'UIControl', nil)
        ConsolePortInputHandler:SetCommand('PADRSHOULDER', self.catalog.frame, true, 'LeftButton', 'UIControl', nil)
    end
    if nativeGamepadEnabled() then
        SmartNavigation:SetSmartNavPanelInfoAddedCallback(self.catalog.frame, function()
            self:SetFirstGamepadTarget()
        end)
        EventRegistry:RegisterCallback('Gamepad.RefreshFrameFocus', self.RefreshNativeGamepadFocus, self)
        local manager = GamepadMode.FrameControlsManager
        if manager.FocusFrame then securecallfunction(manager.FocusFrame, manager, self.catalog.frame) end
        self:RefreshNativeGamepadFocus()
    end
end

function merchant:DeactivateGamepad()
    if _G.ConsolePortInputHandler then ConsolePortInputHandler:Release(self.catalog.frame) end
    if _G.EventRegistry then EventRegistry:UnregisterCallback('Gamepad.RefreshFrameFocus', self) end
    if self.gamepadFooter then securecallfunction(self.gamepadFooter.HideAndDeactivateBindings, self.gamepadFooter) end
end

function merchant:SetFirstGamepadTarget()
    if not nativeGamepadEnabled() or not self.catalog:IsShown() then return end
    local target
    for _, row in ipairs(self.catalog.activeRows) do
        if row.frame:IsShown() and row.button:IsEnabled() then
            target = row.button
            break
        end
    end
    SmartNavigation:SetTargetButtonForFrame(self.catalog.frame, target)
end

function merchant:RefreshGamepadNavigation()
    if not nativeGamepadEnabled() or not self.catalog:IsShown() then return end
    self:SetFirstGamepadTarget()
    SmartNavigation:RefreshButtonGroups(self.catalog.frame)
end

merchant:Enable()
