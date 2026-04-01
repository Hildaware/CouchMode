local addon_name          = ...

---@class CouchMode: AceAddon
local addon               = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class CategoryHeaders: AceModule
local categoryHeaders     = addon:NewModule('Bags.CategoryHeaders')

---@class Session: AceModule
local session             = addon:GetModule('Bags.Session')

---@class Enums: AceModule
local enums               = addon:GetModule('Bags.Enums')

---@class Utils: AceModule
local utils               = addon:GetModule('Bags.Utils')

---@class Database: AceModule
local database            = addon:GetModule('Bags.Database')

---@class CategoryHeaderItem: Button
---@field type Texture
---@field typeContainer Frame
---@field name FontString
---@field nameContainer Frame
---@field isHeader boolean

---@class CategoryHeader
---@field widget CategoryHeaderItem|Button
categoryHeaders.itemProto = {}

function categoryHeaders:OnInitialize()
    self._pool = CreateObjectPool(self._DoCreate, self._DoReset)
    if self._pool.SetResetDisallowedIfNew then
        self._pool:SetResetDisallowedIfNew()
    end

    ---@type CategoryHeader[]
    local frames = {}
    for i = 1, 40 do
        frames[i] = self:Create()
    end
    for _, frame in pairs(frames) do
        frame:Clear()
    end
end

function categoryHeaders:Create()
    return self._pool:Acquire()
end

---@param data CategorizedItemSet
---@param offset number
---@param parent Frame
---@param collapsedCategories table
---@param callback function
function categoryHeaders.itemProto:Build(data, offset, parent, collapsedCategories, callback)
    local frame = self.widget

    local font = database:GetFont()
    local itemHeight = database:GetItemViewHeight()
    local itemWidth = database:GetInventoryViewWidth()
    local columnScale = utils:GetColumnScale()
    local fontSize = utils:GetFontScale()

    frame:SetParent(parent)
    frame:SetSize(itemWidth, itemHeight)
    frame:ClearAllPoints()
    frame:SetPoint('TOP', 0, -((offset - 1) * itemHeight))

    if collapsedCategories[data.key] then
        frame:GetNormalTexture():SetVertexColor(1, 0, 0, 1)
    else
        frame:GetNormalTexture():SetVertexColor(1, 1, 1, 0.35)
    end

    frame.typeContainer:SetSize(session.Settings.Defaults.Columns.Icon * columnScale, itemHeight)
    frame.type:SetTexture(utils.GetCategoyIcon(data.key))
    frame.type:SetSize(24 * columnScale, 24 * columnScale)

    frame.nameContainer:SetSize(session.Settings.Defaults.Columns.Name * columnScale, itemHeight)
    frame.name:SetText(data.name .. ' (' .. data.count .. ')')
    frame.name:SetFont(font.path, fontSize)

    frame:SetScript('OnClick', function(self, button, down)
        if button == 'LeftButton' then
            local isCollapsed = collapsedCategories[data.key] and
                collapsedCategories[data.key] == true

            if isCollapsed then
                collapsedCategories[data.key] = false
            else
                collapsedCategories[data.key] = true
            end

            callback()
        end
    end)

    frame:Show()
end

function categoryHeaders.itemProto:Clear()
    self.widget:Hide()
    self.widget:SetParent(nil)
    self.widget:ClearAllPoints()

    if categoryHeaders._pool:IsActive(self) then
        categoryHeaders._pool:Release(self)
    end
end

---@return CategoryHeader
function categoryHeaders:_DoCreate()
    local i = setmetatable({}, { __index = categoryHeaders.itemProto })

    local font = database:GetFont()
    local itemHeight = database:GetItemViewHeight()
    local itemWidth = database:GetInventoryViewWidth()
    local columnScale = utils:GetColumnScale()
    local fontSize = utils:GetFontScale()

    ---@type CategoryHeaderItem|Button
    local f = CreateFrame('Button')
    f:SetSize(itemWidth, itemHeight)

    f:RegisterForClicks('LeftButtonUp')

    f:SetNormalTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Item_Highlight_Solid')
    f:GetNormalTexture():SetVertexColor(1, 1, 0, 0.5)
    f:SetHighlightTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Item_Highlight_Solid')
    f:GetHighlightTexture():SetVertexColor(1, 1, 0, 0.25)

    -- type
    local type = CreateFrame('Frame', nil, f)
    type:SetPoint('LEFT', f, 'LEFT', 8, 0)
    type:SetHeight(itemHeight)
    type:SetWidth(session.Settings.Defaults.Columns.Icon * columnScale)

    local typeTex = type:CreateTexture(nil, 'ARTWORK')
    typeTex:SetPoint('CENTER', type, 'CENTER')
    typeTex:SetSize(24 * columnScale, 24 * columnScale)

    f.typeContainer = type
    f.type = typeTex

    -- Name
    local name = CreateFrame('Frame', nil, f)
    name:SetPoint('LEFT', type, 'RIGHT', 8, 0)
    name:SetHeight(itemHeight)
    name:SetWidth(session.Settings.Defaults.Columns.Name * columnScale)
    local nameText = name:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    nameText:SetAllPoints(name)
    nameText:SetJustifyH('LEFT')
    nameText:SetFont(font.path, fontSize)

    f.nameContainer = name
    f.name = nameText

    f.isHeader = true

    i.widget = f

    return i
end

function categoryHeaders:_DoReset(item)
    -- if categoryHeaders._pool:IsActive(item) then
    --     categoryHeaders._pool:Release(item)
    -- end
end

categoryHeaders:Enable()
