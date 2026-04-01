local addon_name      = ...

---@class CouchMode: AceAddon
local addon           = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Session: AceModule
local session         = addon:NewModule('Bags.Session')

---@class Enums: AceModule
local enums           = addon:GetModule('Bags.Enums')

---@class ViewData
session.viewDataProto = {
    TotalCount = 0,
    Count = 0,
    Resolved = 0
}

---@class BagData
session.bagDataProto  = {
    TotalCount = 0,
    Count = 0
}

function session:OnInitialize()
    ---@type table<number, table<number, Item>>
    self.Items = {}

    ---@type Item[]
    self.InventoryItems = {}
    ---@type Item[]
    self.BankItems = {}
    ---@type Item[]
    self.WarbankItems = {}

    ---@type ViewData
    self.Inventory = setmetatable({}, { __index = self.viewDataProto })
    self.Inventory.Bags = {
        [Enum.BagIndex.Backpack] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.Bag_1] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.Bag_2] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.Bag_3] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.Bag_4] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.ReagentBag] = setmetatable({}, { __index = self.bagDataProto })
    }

    ---@type ViewData
    self.Bank = setmetatable({}, { __index = self.viewDataProto })
    self.Bank.Bags = {
        -- [99] = setmetatable({}, { __index = self.bagDataProto }), -- Enum.BagIndex.Bank
        [Enum.BagIndex.Characterbanktab] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.CharacterBankTab_1] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.CharacterBankTab_2] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.CharacterBankTab_3] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.CharacterBankTab_4] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.CharacterBankTab_5] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.CharacterBankTab_6] = setmetatable({}, { __index = self.bagDataProto }),
        -- [Enum.BagIndex.BankBag_7] = setmetatable({}, { __index = self.bagDataProto }),
        -- [98] = setmetatable({}, { __index = self.bagDataProto }) -- Enum.BagIndex.ReagentBank
    }

    ---@type ViewData
    self.Warbank = setmetatable({}, { __index = self.viewDataProto })
    self.Warbank.Bags = {
        [Enum.BagIndex.AccountBankTab_1] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.AccountBankTab_2] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.AccountBankTab_3] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.AccountBankTab_4] = setmetatable({}, { __index = self.bagDataProto }),
        [Enum.BagIndex.AccountBankTab_5] = setmetatable({}, { __index = self.bagDataProto }),
    }

    ---@type table<number, string>
    self.EquipmentSetItems = {}
    self.ShouldBuildEquipmentSetCache = true

    self.InventoryFilter = nil
    self.BankFilter = nil

    self.BuildingCache = false
    self.BuildingBankCache = false
    self.BuildingWarbankCache = false

    self.InventoryCollapsedCategories = {}
    self.BankCollapsedCategories = {}

    self.Settings = {
        Defaults = {
            Columns = {
                Icon = 32,
                Name = 320,
                Category = 40,
                Ilvl = 50,
                ReqLvl = 50,
                Value = 110
            },
            Sections = {
                Header = 32,
                Filters = 32,
                ListViewHeader = 28,
                ListItemHeight = 28,
                Footer = 32
            }
        },
        HideBags = false
    }
end

---@param inventoryType Enums.InventoryType
---@return ViewData
function session:GetSessionViewDataByType(inventoryType)
    if inventoryType == enums.InventoryType.Inventory then
        return self.Inventory
    end
    if inventoryType == enums.InventoryType.Bank then
        return self.Bank
    end
    if inventoryType == enums.InventoryType.Shared then
        return self.Warbank
    end

    return self.Inventory
end

---@return number
function session:GetItemWidth()
    return self.Settings.Defaults.Columns.Name +
        self.Settings.Defaults.Columns.Icon +
        self.Settings.Defaults.Columns.Category +
        self.Settings.Defaults.Columns.Ilvl +
        self.Settings.Defaults.Columns.ReqLvl +
        self.Settings.Defaults.Columns.Value
end

session:Enable()
