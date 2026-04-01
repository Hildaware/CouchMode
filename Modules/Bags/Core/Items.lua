local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Items: AceModule
local items      = addon:NewModule('Bags.Items')

---@class Resolver: AceModule
local resolver   = addon:GetModule('Bags.Resolver')

---@class Types: AceModule
local types      = addon:GetModule('Bags.Types')

---@class Utils: AceModule
local utils      = addon:GetModule('Bags.Utils')

---@class Enums: AceModule
local enums      = addon:GetModule('Bags.Enums')

---@class Session: AceModule
local session    = addon:GetModule('Bags.Session')

---@class Database: AceModule
local database   = addon:GetModule('Bags.Database')


---@param bag integer
---@param slot integer
---@param inventoryType? Enums.InventoryType
---@return Item?
local function GetItemData(bag, slot, inventoryType, equipmentSetItems)
    local containerItem = resolver.GetContainerItemInfo(bag, slot)
    if containerItem ~= nil then
        local itemInfo = resolver.GetItemInfo(containerItem.hyperlink)

        local setName = ''
        if equipmentSetItems then
            setName = equipmentSetItems[containerItem.itemID] or ''
        end

        local item = types.Item.New(containerItem, itemInfo, inventoryType, bag, slot, setName)
        return item
    end
    return nil
end

---@param item Item
---@param sessionData ViewData
---@param locationItems Item[]
local function AddItemToSession(item, sessionData, locationItems)
    session.Items[utils.ReplaceBagSlot(item.bag)][item.slot] = item
    sessionData.Resolved = sessionData.Resolved + 1
    locationItems[#locationItems + 1] = item
end

---@param bag integer
---@param slot integer
---@param inventoryType Enums.InventoryType
---@param sessionData ViewData
---@param locationItems Item[]
local function CreateItem(bag, slot, inventoryType, sessionData, equipmentSetItems, locationItems)
    local itemObj = Item:CreateFromBagAndSlot(bag, slot)
    if itemObj:IsItemEmpty() then
        return false
    end

    local function processItem()
        local item = GetItemData(bag, slot, inventoryType, equipmentSetItems)
        if item then
            AddItemToSession(item, sessionData, locationItems)
            return true
        end
        return false
    end

    if itemObj:IsItemDataCached() then
        return processItem()
    else
        itemObj:ContinueOnItemLoad(function()
            processItem()
        end)
        return false
    end
end

---@param bag integer
---@param sessionData ViewData
local function CreateBagData(bag, sessionData)
    local bagSize = C_Container.GetContainerNumSlots(bag)
    local freeSlots = C_Container.GetContainerNumFreeSlots(bag)
    local itemCount = bagSize - freeSlots

    local replacedBagSlot = utils.ReplaceBagSlot(bag)
    local sessionBag = sessionData.Bags[replacedBagSlot]

    -- Set total count once
    sessionBag.TotalCount = itemCount

    -- Check inventory bag type once
    if enums.PlayerInventoryBagIndex[bag] then
        -- Use direct comparison instead of table lookup for ReagentBag
        if bag == REAGENTBANK_CONTAINER then
            sessionBag.ReagentCount = itemCount
        else
            sessionBag.Count = itemCount
        end
    end

    -- Use direct table assignment instead of or operator
    if not session.Items[replacedBagSlot] then
        session.Items[replacedBagSlot] = {}
    end

    return bagSize
end

---@param bag integer
---@param bagSize integer
---@param slots table
local function CleanupSessionItems(bag, bagSize, slots)
    for i = 1, bagSize do
        if slots[i] == false then
            session.Items[bag][i] = nil
        end
    end
end

function items.GetEquipmentSetData()
    if not session.ShouldBuildEquipmentSetCache then return end
    session.EquipmentSetItems = {}
    local setData = resolver.GetEquipmentSets()
    for _, setId in pairs(setData) do
        local itemIds = resolver.GetItemIdsInEquipmentSet(setId)
        for _, itemId in pairs(itemIds) do
            session.EquipmentSetItems[itemId] = resolver.GetEquimentSetName(setId)
        end
    end
    session.ShouldBuildEquipmentSetCache = false
end

function items.BuildItemCache()
    local invType = enums.InventoryType.Inventory
    session.BuildingCache = true
    session.Inventory.TotalCount = 0
    session.Inventory.Count = 0
    session.Inventory.ReagentCount = 0
    session.Inventory.Resolved = 0

    wipe(session.InventoryItems)

    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        session.Inventory.Bags[bag].TotalCount = 0
        session.Inventory.Bags[bag].Count = 0

        local bagSize = CreateBagData(bag, session.Inventory)
        local requiresCleanup = {}
        for slot = 1, bagSize do
            local created = CreateItem(bag, slot, invType, session.Inventory, session.EquipmentSetItems,
                session.InventoryItems)
            requiresCleanup[slot] = created
        end

        CleanupSessionItems(bag, bagSize, requiresCleanup)
    end

    -- Recalculate totals
    for index, bag in pairs(session.Inventory.Bags) do
        session.Inventory.TotalCount = session.Inventory.TotalCount + bag.TotalCount
        session.Inventory.Count = session.Inventory.Count + bag.Count
        session.Inventory.Resolved = session.Inventory.Resolved + bag.Count

        if index == Enum.BagIndex.ReagentBag then
            session.Inventory.ReagentCount = bag.TotalCount
        end
    end

    session.BuildingCache = false
end

function items.BuildBankCache()
    local invType = enums.InventoryType.Bank
    session.BuildingBankCache = true
    session.Bank.TotalCount = 0
    session.Bank.Count = 0
    session.Bank.ReagentCount = 0
    session.Bank.Resolved = 0

    wipe(session.BankItems)

    -- Bank Container
    local replacedBagSlot = utils.ReplaceBagSlot(enums.BANK_CONTAINER)
    session.Bank.Bags[replacedBagSlot].TotalCount = 0
    session.Bank.Bags[replacedBagSlot].Count = 0

    local bagSize = CreateBagData(enums.BANK_CONTAINER, session.Bank)
    local requiresCleanup = {}
    for slot = 1, bagSize do
        local created = CreateItem(enums.BANK_CONTAINER, slot, invType, session.Bank, session.EquipmentSetItems,
            session.BankItems)
        requiresCleanup[slot] = created
    end

    CleanupSessionItems(replacedBagSlot, bagSize, requiresCleanup)

    -- Bank Bags
    for bag, _ in pairs(enums.BankBagIndex) do
        session.Bank.Bags[bag].TotalCount = 0
        session.Bank.Bags[bag].Count = 0

        local bankBagSize = CreateBagData(bag, session.Bank)
        requiresCleanup = {}
        for slot = 1, bankBagSize do
            local created = CreateItem(bag, slot, invType, session.Bank, session.EquipmentSetItems, session.BankItems)
            requiresCleanup[slot] = created
        end

        CleanupSessionItems(bag, bankBagSize, requiresCleanup)
    end

    -- Bank Reagent Container
    -- local replacedReagentBagSlot = utils.ReplaceBagSlot(REAGENTBANK_CONTAINER)
    -- session.Bank.Bags[replacedReagentBagSlot].TotalCount = 0
    -- session.Bank.Bags[replacedReagentBagSlot].Count = 0

    -- local reagentContainerSize = CreateBagData(REAGENTBANK_CONTAINER, session.Bank)
    -- requiresCleanup = {}
    -- for slot = 1, reagentContainerSize do
    --     local created = CreateItem(REAGENTBANK_CONTAINER, slot, invType, session.Bank)
    --     requiresCleanup[slot] = created
    -- end

    -- CleanupSessionItems(replacedReagentBagSlot, reagentContainerSize, requiresCleanup)

    -- Recalculate totals
    for _, bag in pairs(session.Bank.Bags) do
        session.Bank.TotalCount = session.Bank.TotalCount + bag.TotalCount
        session.Bank.Count = session.Bank.Count + bag.Count
        session.Bank.Resolved = session.Bank.Resolved + bag.Count
    end

    session.BuildingBankCache = false
end

function items.BuildWarbankCache()
    -- Cache frequently accessed values
    local warbank = session.Warbank
    local invType = enums.InventoryType.Shared
    local equipmentSetItems = session.EquipmentSetItems

    session.BuildingWarbankCache = true

    -- Initialize counters once
    warbank.TotalCount = 0
    warbank.Count = 0
    warbank.Resolved = 0

    wipe(session.WarbankItems)

    -- Pre-cache warbank bags reference
    local warbankBags = warbank.Bags
    local totalCount = 0

    -- Process warbank tabs
    for bag = Enum.BagIndex.AccountBankTab_1, Enum.BagIndex.AccountBankTab_5 do
        local currentBag = warbankBags[bag]
        currentBag.TotalCount = 0
        currentBag.Count = 0

        local bagSize = CreateBagData(bag, warbank)
        local requiresCleanup = {}
        for slot = 1, bagSize do
            requiresCleanup[slot] = CreateItem(bag, slot, invType, warbank, equipmentSetItems, session.WarbankItems)
        end

        CleanupSessionItems(bag, bagSize, requiresCleanup)
        totalCount = totalCount + currentBag.TotalCount
    end

    -- Set final totals (for warbank, TotalCount = Count)
    warbank.TotalCount = totalCount
    warbank.Count = totalCount
    warbank.Resolved = totalCount

    session.BuildingWarbankCache = false
end

---@param bagId integer
---@param inventoryType Enums.InventoryType
---@return ViewData
function items:UpdateBag(bagId, inventoryType)
    -- Cache frequently accessed values
    local buildingFlag
    if inventoryType == enums.InventoryType.Inventory then
        buildingFlag = 'BuildingCache'
    elseif inventoryType == enums.InventoryType.Bank then
        buildingFlag = 'BuildingBankCache'
    else
        buildingFlag = 'BuildingWarbankCache'
    end
    session[buildingFlag] = true

    -- Get and cache session data
    local sessionData = session:GetSessionViewDataByType(inventoryType)
    local equipmentSetItems = session.EquipmentSetItems

    -- Initialize counters
    sessionData.TotalCount = 0
    sessionData.Count = 0
    sessionData.ReagentCount = 0
    sessionData.Resolved = 0

    -- Process bag
    local replacedBagSlot = utils.ReplaceBagSlot(bagId)
    local currentBag = sessionData.Bags[replacedBagSlot]
    currentBag.TotalCount = 0
    currentBag.Count = 0

    -- Determine the flat list for this location type
    local locationItems
    if inventoryType == enums.InventoryType.Inventory then
        locationItems = session.InventoryItems
    elseif inventoryType == enums.InventoryType.Bank then
        locationItems = session.BankItems
    else
        locationItems = session.WarbankItems
    end

    local bagSize = CreateBagData(bagId, sessionData)
    local requiresCleanup = {}

    -- Process slots
    for slot = 1, bagSize do
        requiresCleanup[slot] = CreateItem(bagId, slot, inventoryType, sessionData, equipmentSetItems, locationItems)
    end

    CleanupSessionItems(replacedBagSlot, bagSize, requiresCleanup)

    -- Rebuild the full flat list for this location type from all bags
    wipe(locationItems)
    for bagIndex in pairs(sessionData.Bags) do
        local slots = session.Items[bagIndex]
        if slots then
            for _, item in pairs(slots) do
                locationItems[#locationItems + 1] = item
            end
        end
    end

    -- Calculate totals during bag processing
    local totalCount = 0
    local regularCount = 0
    for index, bag in pairs(sessionData.Bags) do
        local bagTotal = bag.TotalCount
        totalCount = totalCount + bagTotal

        if index == REAGENTBANK_CONTAINER then
            sessionData.ReagentCount = bagTotal
        else
            regularCount = regularCount + bag.Count
        end
    end

    -- Set final totals
    sessionData.TotalCount = totalCount
    sessionData.Count = regularCount
    sessionData.Resolved = totalCount

    -- Reset building flag
    session[buildingFlag] = false

    return sessionData
end

---@param categories CategorizedItemSet[]
---@param sortField SortField
function items:SortItems(categories, sortField)
    local type = sortField.Field
    local order = sortField.Sort

    local comparators = {
        [enums.SortField.Name] = 'name',
        [enums.SortField.Icon] = 'quality',
        [enums.SortField.Ilvl] = 'ilvl',
        [enums.SortField.ReqLvl] = 'reqLvl',
        [enums.SortField.Value] = 'value',
    }

    local function Sort(itemSet, comparator, sortOrder)
        table.sort(itemSet, function(a, b)
            if a.isNew ~= b.isNew then
                return a.isNew
            end

            if sortOrder == enums.SortOrder.Desc then
                return a[comparator] > b[comparator]
            else
                return a[comparator] < b[comparator]
            end
        end)
    end


    for _, cat in pairs(categories) do
        Sort(cat.items, comparators[type], order)
    end
end

items:Enable()
