local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

-- TODO: BagContainer needs a lot of love. It should be prettier
---@class BagContainer: AceModule
local bags       = addon:NewModule('Bags.BagContainer')

---@class Enums: AceModule
local enums      = addon:GetModule('Bags.Enums')

---@class Session: AceModule
local session    = addon:GetModule('Bags.Session')

---@class Database: AceModule
local database   = addon:GetModule('Bags.Database')

---@class Utils: AceModule
local utils      = addon:GetModule('Bags.Utils')

function bags:Build(type, parent)
    local f = CreateFrame('Frame', nil, parent.Header)
    f:SetSize(32, 32)
    f:SetPoint('RIGHT', parent.Header, 'RIGHT', -40, 0)

    local font = database:GetFont()
    local fontSize = utils:GetFontScale()

    -- Bag Button
    local bagButton = CreateFrame('Button', nil, f)
    bagButton:SetPoint('RIGHT', 0, 'RIGHT')
    bagButton:SetSize(28, 28)

    local btnTex = bagButton:CreateTexture(nil, 'ARTWORK')
    btnTex:SetAllPoints(bagButton)
    btnTex:SetTexture('Interface\\ContainerFrame\\BagSlots2x')
    btnTex:SetAtlas('bag-main')

    CreateContainer(bagButton, type)

    bagButton:SetScript('OnClick', function(self)
        print('Button Click')
        if self.Container:IsShown() then
            self.Container:Hide()
            self:GetParent().ItemCountContainer:Show()
        else
            self.Container:Show()
            self:GetParent().ItemCountContainer:Hide()
        end
    end)

    local itemCountContainer = CreateFrame('Frame', nil, f)
    itemCountContainer:SetPoint('RIGHT', bagButton, 'LEFT', -4, 0)
    itemCountContainer:SetSize(140, 24)

    local itemCountText = itemCountContainer:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    itemCountText:SetAllPoints(itemCountContainer)
    itemCountText:SetText('')
    itemCountText:SetJustifyH('RIGHT')
    itemCountText:SetFont(font.path, fontSize)

    f.ItemCountContainer = itemCountContainer

    parent.Bags = bagButton
    parent.ItemCountText = itemCountText
end

---@param container BagWidget
---@param type Enums.InventoryType
---@param bankType? Enums.BankType
function bags:Update(container, type, bankType)
    if container == nil then return end
    if container.Bags.Container == nil then return end

    local bagStart = 1
    local bagEnd = NUM_TOTAL_EQUIPPED_BAG_SLOTS
    if type == enums.InventoryType.Bank then
        if bankType == enums.BankType.Warbank then
            -- container.Bags.Container.purchase:Hide()

            bagStart = Enum.BagIndex.AccountBankTab_1
            bagEnd = Enum.BagIndex.AccountBankTab_5
        else
            -- local _, full = GetNumBankSlots()
            -- if full then
            --     container.Bags.Container.purchase:Hide()
            -- end

            bagStart = ITEM_INVENTORY_BANK_BAG_OFFSET + 1
            bagEnd = Enum.BagIndex.CharacterBankTab_6 + NUM_BAG_SLOTS + 1
        end
    end

    -- TODO: Max needs to be variable based on Race / etc. Prob an API call we can make
    local max = 16
    if type == enums.InventoryType.Bank then
        if bankType == enums.BankType.Warbank then
            max = 0
        else
            max = 28
        end
    end
    -- local max = type == enums.InventoryType.Bank and 28 or 16
    local reagentCount = 0

    for bag = bagStart, bagEnd do
        local bagID = C_Container.ContainerIDToInventoryID(bag)
        local iconID = GetInventoryItemTexture('player', bagID)
        local link = GetInventoryItemLink('player', bag)
        local maxSlots = C_Container.GetContainerNumSlots(bag)

        local bagIndex = bag
        if type == enums.InventoryType.Bank and bankType == enums.BankType.Bank then
            bagIndex = bagIndex - ITEM_INVENTORY_BANK_BAG_OFFSET
        end

        if type == enums.InventoryType.Inventory and bag == NUM_TOTAL_EQUIPPED_BAG_SLOTS then
            reagentCount = maxSlots
        else
            max = max + maxSlots
        end

        local bagData = {
            bagIndex = bagIndex,
            id = bagID,
            icon = iconID,
            link = link
        }

        -- if type == enums.InventoryType.Bank and bankType == enums.BankType.Bank then
        --     local numSlots, _ = GetNumBankSlots()
        --     bagData.isPurchased = bagIndex <= numSlots
        -- end

        container.Bags.Container.Slots[bagIndex] = UpdateBagSlot(container.Bags.Container.Slots[bagIndex], bagData)
    end

    if bankType == enums.BankType.Warbank then
        container.Bags:SetEnabled(false)
    else
        container.Bags:SetEnabled(true)
    end

    if type == enums.InventoryType.Inventory then
        local invString = session.Inventory.Count .. '/' .. max
        if reagentCount > 0 then
            invString = invString .. '|cff3AA64B (' .. session.Inventory.ReagentCount .. '/' .. reagentCount .. ')|r'
        end
        container.ItemCountText:SetText(invString)
    elseif type == enums.InventoryType.Bank then
        if bankType == enums.BankType.Warbank then
            container.ItemCountText:SetText(session.Warbank.TotalCount .. '/' .. max)
        else
            container.ItemCountText:SetText(session.Bank.TotalCount .. '/' .. max)
        end
    end
end

function CreateContainer(parent, type)
    local container = CreateFrame('Frame', nil, parent)
    container:SetPoint('RIGHT', parent, 'LEFT', -4, 0)
    container:SetSize(1, parent:GetHeight())

    container.Slots = {}

    local bagStart = 1
    local bagEnd = NUM_TOTAL_EQUIPPED_BAG_SLOTS
    if type == enums.InventoryType.Bank then
        bagStart = ITEM_INVENTORY_BANK_BAG_OFFSET + 1
        bagEnd = Enum.BagIndex.CharacterBankTab_6 + NUM_BAG_SLOTS + 1
    end

    for bag = bagStart, bagEnd do
        local bagID = C_Container.ContainerIDToInventoryID(bag)
        local iconID = GetInventoryItemTexture('player', bagID)
        local link = GetInventoryItemLink('player', bag)

        local bagIndex = bag
        if type == enums.InventoryType.Bank then
            bagIndex = bagIndex - ITEM_INVENTORY_BANK_BAG_OFFSET
        end

        local bagData = {
            bagIndex = bagIndex,
            id = bagID,
            icon = iconID,
            link = link
        }

        if type == enums.InventoryType.Bank then
            -- local numSlots, _ = GetNumBankSlots()
            local numSlots = C_Bank.FetchNumPurchasedBankTabs(0) -- 0 = Character
            bagData.isPurchased = bagIndex <= numSlots
        end

        local f = CreateBagSlot(container, bagData)
        container.Slots[bagIndex] = f
    end

    if type == enums.InventoryType.Bank then
        local purchaseBagButton = CreateFrame('Button', nil, container)
        purchaseBagButton:SetSize(28, 28)
        purchaseBagButton:SetPoint('LEFT', container.Slots[#container.Slots], 'RIGHT', 12, 0)
        purchaseBagButton:SetNormalTexture(133784)

        purchaseBagButton:SetScript('OnEnter', function(self)
            GameTooltip:SetOwner(self, 'ANCHOR_NONE')
            ContainerFrameItemButton_CalculateItemTooltipAnchors(self, GameTooltip)

            local num, _ = GetNumBankSlots()
            local cost = GetBankSlotCost(num)
            GameTooltip:SetText('Purchase Bag Slot: ' .. GetCoinTextureString(cost))
            GameTooltip:Show()
        end)

        purchaseBagButton:SetScript('OnLeave', function(self)
            GameTooltip:Hide()
        end)

        purchaseBagButton:SetScript('OnClick', function()
            local _, fullBank = GetNumBankSlots()
            if fullBank then return end
            local cost = GetBankSlotCost(fullBank)
            BankFrame.nextSlotCost = cost
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
            StaticPopup_Show('CONFIRM_BUY_BANK_SLOT')
        end)

        container:SetWidth(container:GetWidth() + 40)

        container.purchase = purchaseBagButton
    end

    parent.Container = container
    container:Hide()
end

function CreateBagSlot(parent, bagData)
    local f = CreateFrame('Button', nil, parent)
    f:SetPoint('RIGHT', parent, 'LEFT', (bagData.bagIndex * 30), 0)
    f:SetSize(28, 28)

    f.bagID = bagData.id

    f:SetID(bagData.id)
    f:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    f:RegisterForDrag('LeftButton')

    local btnTex = f:CreateTexture(nil, 'ARTWORK')
    btnTex:SetAllPoints(f)

    if bagData.icon ~= nil then
        btnTex:SetTexture(bagData.icon)
        btnTex:SetVertexColor(1, 1, 1, 1)
    else
        btnTex:SetTexture('Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag')

        if bagData.isPurchased ~= nil then
            if not bagData.isPurchased then
                btnTex:SetVertexColor(1, 0, 0, 1)
            else
                btnTex:SetVertexColor(1, 1, 1, 1)
            end
        end
    end

    f.texture = btnTex

    f:SetScript('OnClick', function(self, button, down)
        if button == 'LeftButton' then
            PickupInventoryItem(self.bagID)
        end
    end)

    f:SetScript('OnDragStart', function(self)
        PickupInventoryItem(self.bagID)
    end)

    f:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_NONE')
        ContainerFrameItemButton_CalculateItemTooltipAnchors(self, GameTooltip)
        GameTooltip:SetInventoryItem('player', self.bagID)
        GameTooltip:Show()
    end)

    f:SetScript('OnLeave', function(self)
        GameTooltip:Hide()
    end)

    parent:SetWidth(parent:GetWidth() + 30)

    return f
end

function UpdateBagSlot(self, bagData)
    if self == nil then return end

    self.bagID = bagData.id
    self:SetID(bagData.id)

    if bagData.icon ~= nil then
        self.texture:SetTexture(bagData.icon)
        self.texture:SetVertexColor(1, 1, 1, 1)
    else
        self.texture:SetTexture('Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag')

        if bagData.isPurchased ~= nil then
            if not bagData.isPurchased then
                self.texture:SetVertexColor(1, 0, 0, 1)
            else
                self.texture:SetVertexColor(1, 1, 1, 1)
            end
        end
    end

    return self
end
