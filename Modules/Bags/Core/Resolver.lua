local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Resolver: AceModule
local resolver = addon:NewModule('Bags.Resolver')

resolver.GetContainerItemInfo = function(bagId, slotId)
    return C_Container.GetContainerItemInfo(bagId, slotId)
end

resolver.GetItemInfo = function(link)
    local _, _, rarity, _, reqLvl, _, _, stackCount, _, texture, sellPrice, classId, subClassId, bindType, xpacId =
        C_Item.GetItemInfo(link)
    return {
        rarity = rarity,
        type = classId,
        subType = subClassId,
        stackCount = stackCount,
        texture = texture,
        sellPrice = sellPrice,
        xpacId = xpacId,
        reqLvl = reqLvl,
        bindType = bindType
    }
end

resolver.GetEffectiveItemLevel = function(link)
    local ilvl = C_Item.GetDetailedItemLevelInfo(link)
    return ilvl
end

resolver.GetInventoryType = function(link)
    return C_Item.GetItemInventoryTypeByID(link)
end

---@param itemLocation ItemLocationMixin
---@return boolean
resolver.GetWarboundStatus = function(bindType, itemLocation)
    if bindType == 2 then -- Bind on equip
        return C_Item.IsBoundToAccountUntilEquip(itemLocation)
    else
        return C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, itemLocation)
    end
end

---@param itemLocation ItemLocationMixin
---@return boolean
resolver.IsAccountBankable = function(itemLocation)
    return C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, itemLocation)
end

---@param classId Enum.ItemClass
---@return boolean
resolver.IsEquippableItem = function(classId)
    return classId == Enum.ItemClass.Weapon or classId == Enum.ItemClass.Armor
end

---@return integer[]
resolver.GetEquipmentSets = function()
    return C_EquipmentSet.GetEquipmentSetIDs()
end

---@param setId integer
---@return string
resolver.GetEquimentSetName = function(setId)
    local name = C_EquipmentSet.GetEquipmentSetInfo(setId)
    return name
end

---@param setId integer
---@return integer[]
resolver.GetItemIdsInEquipmentSet = function(setId)
    return C_EquipmentSet.GetItemIDs(setId)
end

resolver:Enable()
