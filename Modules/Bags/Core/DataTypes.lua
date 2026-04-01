local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Bags: AceModule
local bags       = addon:GetModule('Bags')

---@class Types: AceModule
local types      = addon:NewModule('Bags.Types')

---@class Utils: AceModule
local utils      = addon:GetModule('Bags.Utils')

---@class Enums: AceModule
local enums      = addon:GetModule('Bags.Enums')


---@class Resolver: AceModule
local resolver = addon:GetModule('Bags.Resolver')

---@class Item
---@field id number
---@field name string
---@field link string
---@field stackCount number
---@field bound boolean
---@field bindType integer
---@field isWarbound boolean
---@field quality Enum.ItemQuality
---@field type Enum.ItemClass
---@field subType number -- This is actually an Enum, but wrong?
---@field equipLocation Enum.InventoryType
---@field texture string|integer
---@field value number
---@field ilvl number
---@field reqLvl number
---@field bag number
---@field slot number
---@field isNew boolean
---@field reqLevel number
---@field isLocked boolean
---@field questInfo ItemQuestInfo
---@field isReadable boolean
---@field isFiltered boolean
---@field hasNoValue boolean
---@field isAccountBankable boolean
---@field category number
---@field location Enums.InventoryType
---@field setName string
local Item = {}

---@param containerItem ContainerItemInfo
---@param itemInfo table
---@param inventoryType Enums.InventoryType
---@param bag integer
---@param slot integer
---@return Item
Item.New = function(containerItem, itemInfo, inventoryType, bag, slot, setName)
    local questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
    local ilvl = resolver.GetEffectiveItemLevel(containerItem.hyperlink)
    local invType = resolver.GetInventoryType(containerItem.hyperlink)
    local isNew = C_NewItems.IsNewItem(bag, slot)

    local itemLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)

    local isWarbound = false
    if resolver.IsEquippableItem(itemInfo.type) then
        isWarbound = resolver.GetWarboundStatus(itemInfo.bindType, itemLocation)
    end

    local accountBankable = resolver.IsAccountBankable(itemLocation)

    ---@type Item
    local self = setmetatable({}, { __index = Item })

    self.id = containerItem.itemID
    self.name = containerItem.itemName
    self.link = containerItem.hyperlink
    self.stackCount = containerItem.stackCount
    self.bound = containerItem.isBound
    self.bindType = itemInfo.bindType
    self.isWarbound = isWarbound
    self.quality = containerItem.quality
    self.type = itemInfo.type
    self.subType = itemInfo.subType
    self.equipLocation = invType
    self.texture = itemInfo.texture or containerItem.iconFileID
    self.value = itemInfo.sellPrice or 0
    self.ilvl = ilvl or 0
    self.bag = bag
    self.slot = slot
    self.isNew = isNew
    self.reqLvl = itemInfo.reqLvl or 0
    self.isLocked = containerItem.isLocked
    self.questInfo = questInfo
    self.isReadable = containerItem.isReadable
    self.isFiltered = containerItem.isFiltered
    self.hasNoValue = containerItem.hasNoValue
    self.category = self:GetCategory()
    self.location = inventoryType
    self.isAccountBankable = accountBankable
    self.setName = setName

    return self
end

---@return integer
function Item:GetCategory()
    if utils.IsEquipmentUnbound(self) then
        return enums.CustomCategory.BindOnEquip
    elseif self.quality == Enum.ItemQuality.Heirloom then
        return enums.CustomCategory.BindOnAccount
    elseif self.isWarbound and not self.bound then
        return enums.CustomCategory.Warbound
    elseif utils.IsJewelry(self) then
        return enums.CustomCategory.Jewelry
    elseif utils.IsTrinket(self) then
        return enums.CustomCategory.Trinket
    elseif self.id == 82800 then
        return Enum.ItemClass.Battlepet
    elseif self.type == nil or not enums.Categories[self.type] then
        return Enum.ItemClass.Miscellaneous
    else
        return self.type
    end
end

types.Item = Item

---@class CategorizedItemSet
---@field items Item[]
---@field count number
---@field hasNew boolean
---@field key integer
---@field name string
---@field order number

---@class SortField
---@field Sort integer
---@field Field integer

types:Enable()
