local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Bags: AceModule
local bagsModule = addon:GetModule('Bags')

---@class Database: AceModule
local database = addon:NewModule('Bags.Database')

---@class Enums: AceModule
local enums = addon:GetModule('Bags.Enums')

local ACCIDENTAL_PRESIDENCY_FONT_PATH = 'Interface\\AddOns\\CouchMode\\Resources\\Fonts\\AccidentalPresidency.ttf'
local LEGACY_FONT_PATH = 'Interface\\AddOns\\Bags\\Fonts\\AccidentalPresidency.ttf'

---@class databaseOptions
local defaults = {
    bags = {
        enabled = true,
        Characters = {},
        ViewType = enums.ViewType.Full,
        BackgroundOpacity = 0.75,
        Font = {
            Name = 'Accidental Presidency',
            Path = ACCIDENTAL_PRESIDENCY_FONT_PATH,
            Size = 12
        },
        InventoryFrame = {
            Size = {
                X = 600,
                Y = 436,
            },
            Position = {
                X = 500,
                Y = 500
            },
            Columns = {
                Icon = 32,
                Name = 320,
                Category = 40,
                Ilvl = 50,
                ReqLvl = 50,
                Value = 110
            },
            ItemHeight = 28,
            SortField = { ---@type SortField
                Field = enums.SortField.Name,
                Sort = enums.SortOrder.Desc
            }
        },
        BankFrame = {
            Size = {
                X = 600,
                Y = 436,
            },
            Position = {
                X = 20,
                Y = 500
            },
            Columns = {
                Icon = 32,
                Name = 280,
                Category = 40,
                Ilvl = 50,
                ReqLvl = 50,
                Value = 110
            },
            SortField = { ---@type SortField
                Field = enums.SortField.Name,
                Sort = enums.SortOrder.Desc
            }
        }
    }
}

function database:GetDefaults()
    return defaults
end

function database:OnInitialize()
    database.internal = addon.db.profile.bags
    if database.internal.Font.Path == LEGACY_FONT_PATH then
        database.internal.Font.Path = ACCIDENTAL_PRESIDENCY_FONT_PATH
    end
end

---@return SortField
function database:GetInventorySortField()
    return self.internal.InventoryFrame.SortField
end

---@return SortField
function database:GetBankSortField()
    return database.internal.BankFrame.SortField
end

function database:GetInventoryViewPositionY()
    return database.internal.InventoryFrame.Position.Y or 200
end

function database:GetInventoryViewPositionX()
    return database.internal.InventoryFrame.Position.X or 500
end

function database:GetInventoryViewHeight()
    return database.internal.InventoryFrame.Size.Y or 396
end

function database:SetInventoryPosition(x, y)
    database.internal.InventoryFrame.Position = { X = x, Y = y }
end

function database:SetInventoryViewHeight(height)
    database.internal.InventoryFrame.Size.Y = height
    bagsModule.Inventory:UpdateGUI(enums.InventoryType.Inventory)
end

function database:SetInventoryViewWidth(width)
    database.internal.InventoryFrame.Size.X = width
    bagsModule.Inventory:UpdateGUI(enums.InventoryType.Inventory)
end

function database:GetInventoryViewWidth()
    return database.internal.InventoryFrame.Size.X or 600
end

function database:GetItemViewHeight()
    return database.internal.InventoryFrame.ItemHeight or 28
end

function database:SetItemViewHeight(height)
    database.internal.InventoryFrame.ItemHeight = height
    bagsModule.Inventory:UpdateGUI(enums.InventoryType.Inventory)
end

---@return { name: string, path: string, size: number }
function database:GetFont()
    local font = database.internal.Font
    return { name = font.Name, path = font.Path, size = font.Size }
end

---@param name string
---@param path string
function database:SetFont(name, path)
    local font = database.internal.Font
    font.Name = name
    font.Path = path

    bagsModule.Inventory:UpdateGUI(enums.InventoryType.Inventory)
    bagsModule.Bank:UpdateGUI(enums.InventoryType.Bank)
end

function database:GetBankViewPositionY()
    return database.internal.BankFrame.Position.Y or 200
end

function database:GetBankViewPositionX()
    return database.internal.BankFrame.Position.X or 500
end

function database:GetBankViewHeight()
    return database.internal.BankFrame.Size.Y or 396
end

function database:SetBankPosition(x, y)
    database.internal.BankFrame.Position = { X = x, Y = y }
end

function database:SetBankViewHeight(height)
    database.internal.BankFrame.Size.Y = height
end

---@param inventoryType Enums.InventoryType
function database:GetViewHeight(inventoryType)
    if inventoryType == enums.InventoryType.Inventory then
        return database:GetInventoryViewHeight()
    elseif inventoryType == enums.InventoryType.Bank then
        return database:GetBankViewHeight()
    end
end

---@param inventoryType Enums.InventoryType
---@param height integer
function database:SetViewHeight(inventoryType, height)
    if inventoryType == enums.InventoryType.Inventory then
        database:SetInventoryViewHeight(height)
    elseif inventoryType == enums.InventoryType.Bank then
        database:SetBankViewHeight(height)
    end
end

---@param inventoryType Enums.InventoryType
---@return {x: integer, y: integer}
function database:GetViewPosition(inventoryType)
    local position = { x = 0, y = 0 }
    if inventoryType == enums.InventoryType.Inventory then
        position.x, position.y = database:GetInventoryViewPositionX(), database:GetInventoryViewPositionY()
    elseif inventoryType == enums.InventoryType.Bank then
        position.x, position.y = database:GetBankViewPositionX(), database:GetBankViewPositionY()
    end

    return position
end

---@param inventoryType Enums.InventoryType
---@param x integer
---@param y integer
function database:SetViewPosition(inventoryType, x, y)
    if inventoryType == enums.InventoryType.Inventory then
        database:SetInventoryPosition(x, y)
    elseif inventoryType == enums.InventoryType.Bank then
        database:SetBankPosition(x, y)
    end
end

---@param inventoryType Enums.InventoryType
---@return SortField
function database:GetSortField(inventoryType)
    if inventoryType == enums.InventoryType.Bank then
        return database:GetBankSortField()
    else
        return database:GetInventorySortField()
    end
end

---@return Enums.ViewType
function database:GetViewType()
    return database.internal.ViewType
end

---@param type Enums.ViewType
function database:SetViewType(type)
    database.internal.ViewType = type
    bagsModule.Inventory:UpdateGUI(enums.InventoryType.Inventory)
end

---@param opacity number
function database:SetBackgroundOpacity(opacity)
    database.internal.BackgroundOpacity = opacity
    bagsModule.Inventory:UpdateGUI(enums.InventoryType.Inventory)
end

---@return number
function database:GetBackgroundOpacity()
    return database.internal.BackgroundOpacity
end

database:Enable()
