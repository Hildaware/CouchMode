local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Bags: AceModule
local bags       = addon:GetModule('Bags')

---@class BankHeader: AceModule
local header     = addon:NewModule('Bags.BankHeader')

---@class Enums: AceModule
local enums      = addon:GetModule('Bags.Enums')

---@class Utils: AceModule
local utils      = addon:GetModule('Bags.Utils')

---@class Session: AceModule
local session    = addon:GetModule('Bags.Session')

---@class Items: AceModule
local items      = addon:GetModule('Bags.Items')

---@class SimpleButton: AceModule
local button     = addon:GetModule('Bags.SimpleButton')

---@class Database: AceModule
local database   = addon:GetModule('Bags.Database')

---@class BankButton: Button
---@field text FontString

header.proto     = {}

---@param parent Frame
---@param type Enums.BankType
---@param width number
---@param onClick function
---@return BankButton|Button
local function CreateBankButton(parent, type, width, onClick)
    local font = database:GetFont()

    ---@type BankButton|Button
    local btn = CreateFrame('Button', nil, parent)
    btn:SetPoint(type == enums.BankType.Bank and 'LEFT' or 'RIGHT')
    btn:SetSize(width, session.Settings.Defaults.Sections.Header - 8)
    btn:SetNormalTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\rectangle')
    btn:GetNormalTexture():SetVertexColor(0, 0, 0, 0.75)
    btn:SetScript('OnClick', onClick)

    btn.text = btn:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    btn.text:SetPoint('CENTER')
    btn.text:SetText(type == enums.BankType.Bank and 'Bank' or 'Warbank')
    btn.text:SetJustifyH('CENTER')
    btn.text:SetFont(font.path, 14)

    local textColor = type == enums.BankType.Bank and { 1, 1, 0 } or { 1, 1, 1 }
    btn.text:SetTextColor(unpack(textColor))

    ---@diagnostic disable-next-line: missing-fields
    utils:CreateRegionalBorder(btn, 'TOP', { 1, 1, 1, 1 })
    ---@diagnostic disable-next-line: missing-fields
    utils:CreateRegionalBorder(btn, 'BOTTOM', { 1, 1, 1, 1 })

    return btn
end


---@param view BagView
---@param parent Frame
---@return BankHeader
function header:CreateAdditions(view, parent)
    local i = setmetatable({}, { __index = header.proto })

    ---@class BankHeaderToggles
    local togglerContainer = CreateFrame('Frame', nil, parent)
    togglerContainer:SetPoint('TOPLEFT', parent, 'TOPLEFT', 12, 0)
    togglerContainer:SetSize(150, session.Settings.Defaults.Sections.Header)

    local bank = CreateBankButton(togglerContainer, enums.BankType.Bank, 60,
        function(btn)
            btn.text:SetTextColor(1, 1, 0)
            btn:GetParent().warbank.text:SetTextColor(1, 1, 1)

            view.selectedBankType = enums.BankType.Bank
            bags.status.visitingWarbank = false

            if not session.BuildingBankCache then
                items.BuildBankCache()
            end

            bags.bags.Inventory:Update()

            BankFrame.selectedTab = 1
            BankFrame.activeTabIndex = 1
            -- AccountBankPanel.selectedTabID = nil

            if session.Bank.Resolved >= session.Bank.TotalCount then
                bags.bags.Bank:Update()
            end

            i:UpdateState(enums.BankType.Bank)
        end)

    local warbank = CreateBankButton(togglerContainer, enums.BankType.Warbank, 80,
        function(btn)
            btn.text:SetTextColor(1, 1, 0)
            btn:GetParent().bank.text:SetTextColor(1, 1, 1)

            view.selectedBankType = enums.BankType.Warbank
            bags.status.visitingWarbank = true

            if not session.BuildingWarbankCache then
                items.BuildWarbankCache()
            end

            bags.bags.Inventory:Update()

            BankFrame.selectedTab = 1
            BankFrame.activeTabIndex = 3
            -- local tabData = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)
            -- for _, data in pairs(tabData) do
            --     if data.ID ~= nil then
            --         AccountBankPanel.selectedTabID = data.ID
            --         break
            --     end
            -- end

            if session.Warbank.Resolved >= session.Warbank.TotalCount then
                bags.bags.Bank:Update()
            end

            i:UpdateState(enums.BankType.Warbank)
        end)

    togglerContainer.bank = bank
    togglerContainer.warbank = warbank

    i.toggles = togglerContainer

    local searchBox = CreateFrame('EditBox', nil, parent, 'SearchBoxTemplate')
    searchBox:SetPoint('LEFT', togglerContainer, 'RIGHT', 8, 0)
    searchBox:SetSize(120, 16)
    searchBox:SetAutoFocus(false)
    searchBox:SetFrameLevel(5)
    searchBox:HookScript('OnTextChanged', function()
        local searchText = searchBox:GetText()

        local cb = function()
            bags.bags.Bank:Update(searchText)
        end

        bags.bags.Bank.filterContainer:OnSearch(cb)
    end)

    ---@class NewBankHeader
    local headerContainer = CreateFrame('Frame', nil, parent)
    headerContainer:SetPoint('TOPLEFT', searchBox, 'TOPRIGHT', 0, 8)
    headerContainer:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', -200, 0)

    --#region Actions

    ---@type Size
    local baseButtonSize = { width = 30, height = 30 }

    local purchase = button:Create(headerContainer, 'Interface\\Garrison\\GarrisonBuildingUI',
        'Garr_Building-AddFollowerPlus', baseButtonSize)

    purchase:SetPoint('LEFT', headerContainer, 'LEFT', 8, 0)

    -- Warbank Only

    local depositIconSize = { width = 20, height = 24 }
    local deposit = button:Create(headerContainer, 'Interface\\Minimap\\ObjectIconsAtlas',
        'poi-traveldirections-arrow2', baseButtonSize, depositIconSize)

    local setPoint = purchase.base:IsShown() and purchase.base or headerContainer
    local relativeTo = purchase.base:IsShown() and 'RIGHT' or 'LEFT'
    deposit:SetPoint('LEFT', setPoint, relativeTo, 8, 0)
    deposit:OnClick(function()
        C_Bank.AutoDepositItemsIntoBank(2)
    end)
    deposit:SetTooltip('Deposit All Warbound Items')


    ---@class CheckButton
    local reagentCheck = CreateFrame('CheckButton', nil, headerContainer, 'UICheckButtonTemplate')
    reagentCheck:SetPoint('TOPLEFT', deposit.base, 'TOPRIGHT', 2, 0)
    reagentCheck:SetSize(20, 20)
    reagentCheck:SetText('Include Reagents')
    reagentCheck:SetChecked(GetCVarBool('bankAutoDepositReagents'))
    reagentCheck:SetScript('OnEnter', function()
        GameTooltip:SetOwner(reagentCheck, 'ANCHOR_TOPRIGHT')
        GameTooltip:SetText('Also include tradeable reagents', 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    reagentCheck:SetScript('OnLeave', function()
        GameTooltip:Hide()
    end)
    reagentCheck:SetScript('OnClick', function()
        SetCVar('bankAutoDepositReagents', reagentCheck:GetChecked())
    end)


    local moneyDeposit = button:Create(headerContainer, 'Interface\\MainMenuBar\\MainMenuBar',
        'hud-MainMenuBar-arrowdown-up', baseButtonSize)

    moneyDeposit:SetPoint('TOPLEFT', reagentCheck, 'TOPRIGHT', 8, 0)
    moneyDeposit:OnClick(function()
        StaticPopup_Show("BANK_MONEY_DEPOSIT", nil, nil, { bankType = 2 })
    end)
    moneyDeposit:SetTooltip(BANK_DEPOSIT_MONEY_BUTTON_LABEL)

    local moneyWithdraw = button:Create(headerContainer, 'Interface\\MainMenuBar\\MainMenuBar',
        'hud-MainMenuBar-arrowup-up', baseButtonSize)

    moneyWithdraw:SetPoint('LEFT', moneyDeposit.base, 'RIGHT', 2, 0)
    moneyWithdraw:OnClick(function()
        StaticPopup_Show("BANK_MONEY_WITHDRAW", nil, nil, { bankType = 2 })
    end)
    moneyWithdraw:SetTooltip(BANK_WITHDRAW_MONEY_BUTTON_LABEL)

    local goldView = headerContainer:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    goldView:SetPoint('LEFT', moneyWithdraw.base, 'RIGHT', 8, 0)
    goldView:SetWidth(140)
    goldView:SetJustifyH('LEFT')
    goldView:SetText(C_CurrencyInfo.GetCoinTextureString(C_Bank.FetchDepositedMoney(2)))

    headerContainer.purchase = purchase
    headerContainer.deposit = deposit
    headerContainer.reagentCheck = reagentCheck
    headerContainer.money = goldView
    headerContainer.moneyDeposit = moneyDeposit
    headerContainer.moneyWithdraw = moneyWithdraw

    headerContainer.deposit.base:Hide()
    headerContainer.reagentCheck:Hide()
    headerContainer.money:Hide()
    headerContainer.moneyDeposit.base:Hide()
    headerContainer.moneyWithdraw.base:Hide()

    i.newBankHeader = headerContainer

    return i
end

---@param bankType Enums.BankType
function header.proto:Update(bankType)
    local type = bankType == enums.BankType.Bank and Enum.BankType.Character or Enum.BankType.Account

    local purchase = self.newBankHeader.purchase

    if C_Bank.HasMaxBankTabs(type) then
        purchase.base:Hide()
    else
        purchase.base:Show()
        purchase:OnClick(function()
            StaticPopup_Show("CONFIRM_BUY_BANK_TAB", nil, nil, { bankType = type })
        end)
        local bankTabData = C_Bank.FetchNextPurchasableBankTabData(type)
        local purchaseCost = "Unknown"
        if bankTabData ~= nil then
            purchaseCost = utils.FormatMoney(bankTabData.tabCost)
        end
        purchase:SetTooltip(string.format('Purchase a Tab for %s', purchaseCost))
    end

    local setPoint = purchase.base:IsShown() and purchase.base or self.newBankHeader
    local relativeTo = purchase.base:IsShown() and 'RIGHT' or 'LEFT'
    self.newBankHeader.deposit.base:SetPoint('LEFT', setPoint, relativeTo, 8, 0)


    self.newBankHeader.money:SetText(C_CurrencyInfo.GetCoinTextureString(C_Bank.FetchDepositedMoney(type)))
end

---@param bankType Enums.BankType
function header.proto:UpdateState(bankType)
    if bankType == enums.BankType.Bank then
        self.newBankHeader.deposit.base:Hide()
        self.newBankHeader.reagentCheck:Hide()
        self.newBankHeader.money:Hide()
        self.newBankHeader.moneyDeposit.base:Hide()
        self.newBankHeader.moneyWithdraw.base:Hide()
    else
        self.newBankHeader.deposit.base:Show()
        self.newBankHeader.reagentCheck:Show()
        self.newBankHeader.money:Show()
        self.newBankHeader.moneyDeposit.base:Show()
        self.newBankHeader.moneyWithdraw.base:Show()
    end
end

function header.proto:SetAsBank()
    self.toggles.bank.text:SetTextColor(1, 1, 0)
    self.toggles.warbank.text:SetTextColor(1, 1, 1)

    bags.bags.Bank.selectedBankType = enums.BankType.Bank
    bags.status.visitingWarbank = false
    bags.bags.Inventory:Update()
end

header:Enable()
