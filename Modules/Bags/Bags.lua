local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Bags: AceModule
local bags       = addon:GetModule('Bags')
---@cast bags +AceHook-3.0
---@cast bags +AceEvent-3.0

---@class Session: AceModule
local session    = addon:GetModule('Bags.Session')

---@class Enums: AceModule
local enums      = addon:GetModule('Bags.Enums')

---@class Events: AceModule
local events     = addon:GetModule('Bags.Events')

---@class Utils: AceModule
local utils      = addon:GetModule('Bags.Utils')

---@class Items: AceModule
local items      = addon:GetModule('Bags.Items')

---@class View: AceModule
local view       = addon:GetModule('Bags.View')

---@class ItemFrame: AceModule
local itemFrame  = addon:GetModule('Bags.ItemFrame')

---@class ConsoleBagsStatus
---@field backpackShouldOpen boolean
---@field backpackShouldClose boolean
---@field visitingBank boolean
---@field visitingWarbank boolean
bags.status      = {}

---@class Bags
---@field Inventory BagView
---@field Bank BagView
---@field FocusedNode Enums.InventoryType?
bags.bags        = {}

function bags:OnInitialize()
    bags.status = {
        backpackShouldOpen = false,
        backpackShouldClose = false,
        visitingBank = false,
        visitingWarbank = false,
        bankTimerPending = false
    }

    local frame = CreateFrame('Frame')
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("UPDATE_BINDINGS")
    frame:SetScript("OnEvent", function()
        ClearOverrideBindings(frame)
        local bindings = {
            "TOGGLEBACKPACK",
            "TOGGLEREAGENTBAG",
            "TOGGLEBAG1",
            "TOGGLEBAG2",
            "TOGGLEBAG3",
            "TOGGLEBAG4",
            "OPENALLBAGS"
        }
        for _, binding in pairs(bindings) do
            local key, otherkey = GetBindingKey(binding)
            if key ~= nil then
                SetOverrideBinding(frame, true, key, function() bags:ToggleAllBags() end)
            end
            if otherkey ~= nil then
                SetOverrideBinding(frame, true, otherkey, function() bags:ToggleAllBags() end)
            end
        end
    end)
end

function bags:OnDisable()
    if bags.bags.Inventory then
        bags.bags.Inventory:Hide()
        bags.bags.Inventory = nil
    end
    if bags.bags.Bank then
        bags.bags.Bank:Hide()
        bags.bags.Bank = nil
    end
    self:UnhookAll()
end

function bags:OnEnable()
    if not addon.db.profile.bags.enabled then self:Disable(); return end

    bags.bags.Inventory = view:Create(enums.InventoryType.Inventory)
    bags.bags.Bank = view:Create(enums.InventoryType.Bank)
    bags.bags.FocusedNode = nil
    bags.bags.Inventory:UpdateGUI(enums.InventoryType.Inventory)
    bags.bags.Bank:UpdateGUI(enums.InventoryType.Bank)

    table.insert(UISpecialFrames, bags.bags.Inventory:GetName())
    table.insert(UISpecialFrames, bags.bags.Bank:GetName())

    self:SecureHook('ToggleAllBags')
    self:SecureHook('ToggleBackpack')
    self:SecureHook('CloseSpecialWindows')
    self:SecureHook('OpenAllBags')
    self:SecureHook('CloseAllBags')

    -- Triggers when currency is Watch toggled
    self:SecureHook(TokenFrame, 'SetTokenWatched', bags.UpdateCurrencyTracking)

    ---@diagnostic disable-next-line: undefined-field
    events:RegisterEvent('BANKFRAME_OPENED', function()
        bags.status.visitingBank = true
        events:Send('ConsoleBagsBankToggle')
    end)

    ---@diagnostic disable-next-line: undefined-field
    events:RegisterEvent('BANKFRAME_CLOSED', function()
        bags.status.visitingBank = false
        events:Send('ConsoleBagsBankToggle')
    end)

    events:Register('ConsoleBagsBankToggle', bags.OnBankUpdate)
    events:Register('ConsoleBagsToggle', bags.OnUpdate)
end

function bags.OnBankUpdate()
    if not bags.status.visitingBank then
        bags.bags.Bank:Hide()

        bags.bags.Bank:SetAsBank()

        if bags.bags.Inventory:IsShown() then
            bags:ToggleAllBags()
        end

        return
    end

    if bags.bags.Bank:IsShown() then return end

    if session.Settings.HideBags == true then return end

    items.GetEquipmentSetData()

    if not session.BuildingBankCache then
        items.BuildBankCache()
    end

    if not bags.bags.Inventory:IsShown() then
        bags:ToggleAllBags()
    end

    if session.Bank.Resolved >= session.Bank.TotalCount then
        bags.bags.Bank:Update()
        bags.bags.Bank:Show()

        items.BuildWarbankCache()
    elseif not bags.status.bankTimerPending then
        bags.status.bankTimerPending = true
        C_Timer.After(0.1, function()
            bags.status.bankTimerPending = false
            bags.OnBankUpdate()
        end)
    end
end

function bags.OnUpdate()
    if bags.status.backpackShouldOpen then
        if session.Settings.HideBags == true then return end

        items.GetEquipmentSetData()

        if not session.BuildingCache then
            items.BuildItemCache()
        end

        if session.Inventory.Resolved >= session.Inventory.TotalCount then
            bags.status.backpackShouldOpen = false
            bags.status.backpackShouldClose = false

            bags.bags.Inventory:UpdateCurrency()
            bags.bags.Inventory:UpdateMoney()
            bags.bags.Inventory:Update()

            PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
            bags.bags.Inventory:Show()
        end
    elseif bags.status.backpackShouldClose then
        bags.status.backpackShouldClose = false

        PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
        bags.bags.Inventory:Hide()

        bags:CloseBank()
    end
end

function bags:ToggleAllBags()
    if bags.bags.Inventory:IsShown() then
        bags.status.backpackShouldClose = true
    else
        bags.status.backpackShouldOpen = true
    end

    events:Send('ConsoleBagsToggle')
end

function bags:ToggleBackpack()
    bags:ToggleAllBags()
end

function bags:OpenAllBags()
    if bags.bags.Inventory:IsShown() then return end
    bags.status.backpackShouldOpen = true

    events:Send('ConsoleBagsToggle')
end

function bags:CloseAllBags()
    if not bags.bags.Inventory:IsShown() then return end
    bags.status.backpackShouldClose = true

    events:Send('ConsoleBagsToggle')
end

function bags:CloseSpecialWindows()
    bags.status.backpackShouldClose = true
    bags.bags.Bank:Hide()
    if C_Bank then
        C_Bank.CloseBankFrame()
    else
        CloseBankFrame()
    end
end

function bags:CloseBank()
    bags:CloseSpecialWindows()
end

function bags:UpdateCurrencyTracking()
    bags.bags.Inventory:UpdateCurrency()
end

--#region Events

function events:PLAYER_MONEY()
    bags.bags.Inventory:UpdateMoney()
end

function events:ACCOUNT_MONEY()
    bags.bags.Bank:UpdateMoney()
end

function events:BAG_CONTAINER_UPDATE()
    items.BuildItemCache()
    if bags.bags.Inventory and bags.bags.Inventory:IsShown() then
        bags.bags.Inventory:Update()
    end
end

---@param bagId number
function events:BAG_UPDATE(_, bagId)
    local bagType = utils:GetBagType(bagId)
    if bagType == nil then
        return
    end

    local sessionData = items:UpdateBag(bagId, bagType)
    if sessionData.Resolved < sessionData.TotalCount then
        return
    end

    local bag = bagType == enums.InventoryType.Inventory and
        bags.bags.Inventory or bags.bags.Bank

    if bag and bag:IsShown() then
        items.BuildItemCache()
        bag:Update()
    end
end

function events:PLAYERBANKSLOTS_CHANGED()
    items.BuildBankCache()
    bags.bags.Bank:Update()
    items.BuildItemCache()
    bags.bags.Inventory:Update()
end

-- function events:PLAYERBANKBAGSLOTS_CHANGED()
--     items.BuildBankCache()
--     bags.bags.Bank:Update()
--     items.BuildItemCache()
--     bags.bags.Inventory:Update()
-- end

function events:EQUIPMENT_SETS_CHANGED()
    session.ShouldBuildEquipmentSetCache = true
    items.GetEquipmentSetData()
    if bags.bags.Inventory and bags.bags.Inventory:IsShown() then
        items.BuildItemCache()
        bags.bags.Inventory:Update()
    end
end

function events:PLAYER_REGEN_DISABLED()
    if _G['ConsolePortInputHandler'] then
        _G['ConsolePortInputHandler']:Release(bags.bags.Inventory)
    end
end

-- function events:PLAYERREAGENTBANKSLOTS_CHANGED()
--     items.BuildBankCache()
--     bags.bags.Bank:Update()
-- end

function events:CURRENCY_DISPLAY_UPDATE(_, currencyId, newValue)
    if not bags.bags.Inventory then return end
    bags.bags.Inventory:UpdateCurrency(currencyId, newValue)
end

--#endregion

if _G['Scrap'] then
    local original = _G['Scrap'].ToggleJunk
    ---@param self any
    ---@param id number
    _G['Scrap'].ToggleJunk = function(self, id)
        original(self, id)

        for _, iFrame in pairs(bags.bags.Inventory.items) do
            if iFrame.itemId == id then
                iFrame:Update()
            end
        end
    end
end


bags:Enable()
