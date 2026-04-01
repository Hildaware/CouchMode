local addon_name      = ...

---@class CouchMode: AceAddon
local addon           = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Bags: AceModule
local bags            = addon:GetModule('Bags')

---@class View: AceModule
local view            = addon:NewModule('Bags.View')

---@class Enums: AceModule
local enums           = addon:GetModule('Bags.Enums')

---@class Utils: AceModule
local utils           = addon:GetModule('Bags.Utils')

---@class Database: AceModule
local database        = addon:GetModule('Bags.Database')

---@class Session: AceModule
local session         = addon:GetModule('Bags.Session')

---@class Events: AceModule
local events          = addon:GetModule('Bags.Events')

---@class Items: AceModule
local items           = addon:GetModule('Bags.Items')

---@class Filtering: AceModule
local filtering       = addon:GetModule('Bags.Filtering')

---@class Sorting: AceModule
local sorting         = addon:GetModule('Bags.Sorting')

---@class BagContainer: AceModule
local container       = addon:GetModule('Bags.BagContainer')

---@class CategoryHeaders: AceModule
local categoryHeaders = addon:GetModule('Bags.CategoryHeaders')

---@class ItemFrame: AceModule
local itemFrame       = addon:GetModule('Bags.ItemFrame')

---@class BankHeader: AceModule
local bankHeader      = addon:GetModule('Bags.BankHeader')

---@class Currency: AceModule
local currency        = addon:GetModule('Bags.Currency')

---@class Header: Frame
---@field texture Texture
---@field Additions BankHeaderFrame

---@class BagWidget: Frame
---@field Header Header
---@field ListView Frame
---@field gold FontString
---@field currency CurrencyFrame

---@class (exact) BagView
---@field items ListItem[]
---@field filterContainer FilterContainer
---@field sortContainer SortContainer
---@field categoryHeaders CategoryHeader[]
---@field widget BagWidget
---@field type Enums.InventoryType
---@field viewType Enums.ViewType
---@field selectedBankType? Enums.BankType
view.proto            = {}

---@param inventoryType Enums.InventoryType
---@return BagView
function view:Create(inventoryType)
    local i = setmetatable({}, { __index = self.proto })
    i.items = {}
    i.categoryHeaders = {}
    i.type = inventoryType

    local viewType = database:GetViewType()
    i.viewType = viewType

    if i.type == enums.InventoryType.Bank then
        i.selectedBankType = enums.BankType.Bank
    end

    local viewName = (inventoryType == enums.InventoryType.Inventory and 'Inventory') or 'Bank'

    local fullHeight = math.floor(GetScreenHeight())
    local width = database:GetInventoryViewWidth()

    local font = database:GetFont()
    local fontSize = utils:GetFontScale()

    ---@class BagWidget
    local f = CreateFrame('Frame', 'CouchModeBags' .. viewName, UIParent)
    f:SetFrameStrata('HIGH')

    if viewType == enums.ViewType.Full then
        f:SetSize(width, fullHeight)

        local setPoint = inventoryType == enums.InventoryType.Inventory and 'TOPRIGHT' or 'TOPLEFT'
        f:SetPoint(setPoint, UIParent, setPoint)
    else
        f:SetSize(width, database:GetViewHeight(inventoryType))
        local position = database:GetViewPosition(inventoryType)
        f:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', position.x, position.y)
    end

    f:SetMovable(true)
    f:SetUserPlaced(true)
    f:EnableMouse(true)
    f:SetResizable(true)
    f:SetResizeBounds(600, 436, 1200, 2000)

    f.texture = f:CreateTexture(nil, 'BACKGROUND')
    f.texture:SetAllPoints(f)
    f.texture:SetColorTexture(0, 0, 0, database:GetBackgroundOpacity())

    if _G['ConsolePort'] then
        -- Stop ConsolePort from reading buttons
        f:SetScript('OnShow', function(frame)
            if InCombatLockdown() then return end
            if _G['ConsolePortInputHandler'] then
                _G['ConsolePortInputHandler']:SetCommand('PADRSHOULDER', frame, true, 'LeftButton', 'UIControl', nil)
                _G['ConsolePortInputHandler']:SetCommand('PADLSHOULDER', frame, true, 'LeftButton', 'UIControl', nil)

                if _G['Scrap'] then
                    _G['ConsolePortInputHandler']:SetCommand('PAD3', frame, true, 'LeftButton', 'UIControl', nil)
                end
            end
        end)

        -- Re-allow ConsolePort Input handling
        f:SetScript('OnHide', function(frame)
            if _G['ConsolePortInputHandler'] then
                _G['ConsolePortInputHandler']:Release(frame)
            end
        end)

        f:SetPropagateKeyboardInput(true)

        f:SetScript('OnGamePadButtonDown', function(_, key)
            if InCombatLockdown() then return end

            if _G['Scrap'] and key == 'PAD3' then -- Square
                local item = GameTooltip:IsVisible() and select(2, GameTooltip:GetItem())
                if item then
                    _G['Scrap']:ToggleJunk(tonumber(item:match('item:(%d+)')))
                end
                return
            end

            -- set focus
            local node = _G['ConsolePort'].GetCursorNode()
            -- Get the most parented that isn't UIParent
            if node ~= nil then
                local parentest = utils:GetParentMostNode(node)
                if parentest ~= nil then
                    if parentest:GetName() == f:GetName() then
                        bags.bags.FocusedNode = inventoryType
                    end
                end
            end

            if bags.bags.FocusedNode ~= inventoryType then return end

            if key ~= 'PADRSHOULDER' and key ~= 'PADLSHOULDER' then return end

            if key == 'PADRSHOULDER' then     -- Right
                i.filterContainer:ScrollRight()
            elseif key == 'PADLSHOULDER' then -- Left
                i.filterContainer:ScrollLeft()
            end
        end)
    end

    -- Frame Header
    ---@class Header
    local header = CreateFrame('Frame', nil, f)
    header:SetSize(f:GetWidth() - 2, session.Settings.Defaults.Sections.Header)
    header:SetPoint('TOPLEFT', f, 'TOPLEFT', 1, -1)
    header:EnableMouse(true)

    utils:CreateRegionalBorder(header, 'BOTTOM')

    header.texture = header:CreateTexture(nil, 'BACKGROUND')
    header.texture:SetAllPoints(header)
    header.texture:SetColorTexture(0, 0, 0, 0.5)

    if inventoryType == enums.InventoryType.Bank then
        header.Additions = bankHeader:CreateAdditions(i, header)
    else
        local configButton = CreateFrame('Button', nil, header)
        configButton:SetSize(24, 24)
        configButton:SetPoint('LEFT', header, 'LEFT', 12, 0)
        configButton:SetNormalTexture('Interface\\Buttons\\UI-OptionsButton')
        configButton:GetNormalTexture():SetDesaturated(true)

        configButton:SetScript('OnEnter', function()
            GameTooltip:SetOwner(configButton, 'ANCHOR_TOPLEFT')
            GameTooltip:SetText('Open Options', 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        configButton:SetScript('OnLeave', function()
            GameTooltip:Hide()
        end)

        configButton:SetScript('OnClick', function()
            LibStub("AceConfigDialog-3.0"):Open(addon_name)
        end)

        local text = header:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
        text:SetPoint('LEFT', configButton, 'RIGHT', 12, 0)
        text:SetJustifyH('LEFT')
        text:SetText(viewName)
        text:SetFont(font.path, fontSize)

        header.label = text

        local searchBox = CreateFrame('EditBox', nil, header, 'SearchBoxTemplate')
        searchBox:SetPoint('LEFT', text, 'RIGHT', 24, 0)
        searchBox:SetSize(200, 16)
        searchBox:SetAutoFocus(false)
        searchBox:SetFrameLevel(5)
        searchBox:HookScript('OnTextChanged', function()
            local searchText = searchBox:GetText()

            local cb = function()
                i:Update(searchText)
            end

            i.filterContainer:OnSearch(cb)
        end)
    end

    local close = CreateFrame('Button', nil, header)
    close:SetSize(24, 24)
    close:SetPoint('RIGHT', header, 'RIGHT', -6, 0)
    close:SetNormalTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Close_Normal')
    close:SetPushedTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Close_Normal')
    close:GetPushedTexture():SetVertexColor(1, 1, 0, 0.5)
    close:SetScript('OnEnter', function()
        close:GetNormalTexture():SetVertexColor(1, 1, 0, 1)
    end)
    close:SetScript('OnLeave', function()
        close:GetNormalTexture():SetVertexColor(1, 1, 1, 1)
    end)
    close:SetScript('OnClick', function()
        if inventoryType == enums.InventoryType.Inventory then
            bags:ToggleAllBags()
        elseif inventoryType == enums.InventoryType.Bank then
            bags:CloseBank()
        end

        bags.status.visitingWarbank = false
    end)

    if viewType ~= enums.ViewType.Full then
        header:RegisterForDrag('LeftButton')
        header:SetScript('OnDragStart', function(self, button)
            self:GetParent():StartMoving()
        end)
        header:SetScript('OnDragStop', function(self)
            self:GetParent():StopMovingOrSizing()
            local x = self:GetParent():GetLeft()
            local y = self:GetParent():GetTop()
            database:SetViewPosition(inventoryType, x, y)
        end)
    end

    header.UpdateGUI = function()
        local updatedFont = database:GetFont()
        local updatedFontSize = utils:GetFontScale()
        local updatedItemWidth = database:GetInventoryViewWidth()
        f.Header:SetWidth(updatedItemWidth)

        if (f.Header.label ~= nil) then
            f.Header.label:SetFont(updatedFont.path, updatedFontSize)
        end

        f.ItemCountText:SetFont(updatedFont.path, updatedFontSize)
    end

    f.Header = header

    -- Filters
    local filterContainer = filtering:BuildContainer(f, inventoryType)

    local sortContainer = sorting:Build(f, inventoryType, function() i:Update() end)

    local offset = session.Settings.Defaults.Sections.Header + (session.Settings.Defaults.Sections.Filters + 20)
        + session.Settings.Defaults.Sections.ListViewHeader

    local scrollType = 'UIPanelScrollFrameTemplate'
    if _G['ConsolePort'] then
        C_AddOns.LoadAddOn('ConsolePort_Config')
        scrollType = 'CPSmoothScrollTemplate'
    end

    local scroller = CreateFrame('ScrollFrame', nil, f, scrollType)
    scroller:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -offset)
    scroller:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', 0, session.Settings.Defaults.Sections.Footer + 2)
    scroller:SetWidth(f:GetWidth())

    if _G['ConsolePort'] then
        scroller.ScrollBar:Hide()
        scroller.ScrollBar:EnableMouse(false)
    end

    local scrollChild = CreateFrame('Frame', nil, scroller)
    scroller:SetScrollChild(scrollChild)
    scrollChild:SetSize(scroller:GetWidth(), 1)

    local footer = CreateFrame('Frame', nil, f)
    footer:SetSize(f:GetWidth() - 2, session.Settings.Defaults.Sections.Footer)
    footer:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 1, 1)

    footer.texture = footer:CreateTexture(nil, 'BACKGROUND')
    footer.texture:SetAllPoints(footer)
    footer.texture:SetColorTexture(0, 0, 0, 0.5)

    if inventoryType == enums.InventoryType.Inventory then
        local currencyFrame = currency:CreateFrame(footer)

        f.currency = currencyFrame
        f.gold = f.currency.gold
    end

    -- Drag Bar
    if viewType == enums.ViewType.Compact then
        local drag = CreateFrame('Button', nil, f)
        drag:SetSize(64, 12)
        drag:SetPoint('BOTTOM', f, 'BOTTOM', 0, -6)

        drag:SetScript('OnMouseDown', function(self)
            self:GetParent():StartSizing('BOTTOM')
        end)

        drag:SetScript('OnMouseUp', function(self)
            self:GetParent():StopMovingOrSizing('BOTTOM')
            database:SetViewHeight(inventoryType, self:GetParent():GetHeight())
        end)

        local dragTex = drag:CreateTexture(nil, 'BACKGROUND')
        dragTex:SetAllPoints(drag)
        dragTex:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Handlebar')

        f.DragBag = drag
    end

    f.scroller = scroller
    f.ListView = scrollChild
    f.footer = footer
    f:Hide()

    utils:CreateBorder(f)

    container:Build(inventoryType, f)

    if _G['ConsolePort'] then
        _G['ConsolePort']:AddInterfaceCursorFrame(f)
    end

    i.widget = f
    i.filterContainer = filterContainer
    i.sortContainer = sortContainer

    -- Reusable tables at class level
    if not view.proto._catTable then
        view.proto._catTable = {}
        view.proto._allCategories = {}
        view.proto._filteredCategories = {}
        view.proto._orderedCategories = {}
        view.proto._orderedAllCategories = {}
    end

    return i
end

function view.proto:Update(searchText)
    -- Clear existing tables instead of recreating
    wipe(self._catTable)
    wipe(self._allCategories)
    wipe(self._filteredCategories)
    wipe(self._orderedCategories)
    wipe(self._orderedAllCategories)

    for _, row in pairs(self.items) do
        row:Empty()
    end

    for index, row in pairs(self.categoryHeaders) do
        row:Clear()
        self.categoryHeaders[index] = nil
    end

    local sessionFilter = nil
    local sessionCats = {}
    if self.type == enums.InventoryType.Inventory then
        sessionFilter = session.InventoryFilter
        sessionCats = session.InventoryCollapsedCategories
    elseif self.type == enums.InventoryType.Bank then
        sessionFilter = session.BankFilter
        sessionCats = session.BankCollapsedCategories
    end

    local invType, bankType = enums.InventoryType, enums.BankType
    local searchTextLower = searchText and searchText:lower() or nil

    local locationItems
    if self.type == invType.Inventory then
        locationItems = session.InventoryItems
    elseif self.selectedBankType == bankType.Warbank then
        locationItems = session.WarbankItems
    else
        locationItems = session.BankItems
    end

    for _, item in ipairs(locationItems) do
        if searchTextLower then
            if item.name:lower():find(searchTextLower, 1, true) then
                utils.AddItemToCategory(item, self._catTable)
            end
        else
            utils.AddItemToCategory(item, self._catTable)
        end
    end

    items:SortItems(self._catTable, database:GetSortField(self.type))

    local iter = 1
    for key, value in pairs(self._catTable) do
        value.key = key
        value.order = enums.Categories[key].order
        value.name = enums.Categories[key].name
        self._allCategories[iter] = value
        if not sessionFilter or key == sessionFilter then
            self._filteredCategories[#self._filteredCategories + 1] = value
        end
        iter = iter + 1
    end

    -- Single sort pass for filtered categories
    if #self._filteredCategories > 0 then
        table.sort(self._filteredCategories, function(a, b) return a.order < b.order end)
        for i = 1, #self._filteredCategories do
            self._orderedCategories[i] = self._filteredCategories[i]
        end
    end

    -- Single sort pass for all categories
    if #self._allCategories > 0 then
        table.sort(self._allCategories, function(a, b) return a.order < b.order end)
        for i = 1, #self._allCategories do
            self._orderedAllCategories[i] = self._allCategories[i]
        end
    end

    local offset, catIndex, itemIndex = 1, 1, 1

    for _, categoryData in ipairs(self._orderedCategories) do
        if #categoryData.items > 0 then
            local categoryFrame = categoryHeaders:Create()
            categoryFrame:Build(categoryData, offset, self.widget.ListView, sessionCats,
                function() self:Update() end)
            tinsert(self.categoryHeaders, categoryFrame)

            offset = offset + 1
            catIndex = catIndex + 1

            if not sessionCats[categoryData.key] then
                for _, item in ipairs(categoryData.items) do
                    local frame = self.items[itemIndex] or itemFrame:Create()
                    frame:Build(item, offset, self.widget.ListView)
                    if not self.items[itemIndex] then
                        tinsert(self.items, frame)
                    end

                    offset = offset + 1
                    itemIndex = itemIndex + 1
                end
            end
        end
    end

    -- Cleanup Unused
    for index, row in pairs(self.items) do
        if not row.item then
            row:Clear()
            self.items[index] = nil
        end
    end

    local function onFilterSelectCallback(key)
        if self.type == enums.InventoryType.Inventory then
            session.InventoryFilter = key
        elseif self.type == enums.InventoryType.Bank then
            session.BankFilter = key
        end

        self:Update()
    end

    self.filterContainer:Update(self.type, self._orderedAllCategories, onFilterSelectCallback)
    container:Update(self.widget, self.type, self.selectedBankType)

    if self.widget.Header.Additions then
        self.widget.Header.Additions:Update(self.selectedBankType)
    end
end

---@param inventoryType Enums.InventoryType
function view.proto:UpdateGUI(inventoryType)
    local viewType = database:GetViewType()

    local width = database:GetInventoryViewWidth()
    local font = database:GetFont()
    local fontSize = utils:GetFontScale()

    self.viewType = viewType

    if viewType == enums.ViewType.Full then
        local fullHeight = math.floor(GetScreenHeight())
        local scale = 100

        -- TODO: Test use scale
        if GetCVar('useUiScale') == '1' then
            scale = math.floor(UIParent:GetEffectiveScale() * 100)
        end

        if inventoryType == enums.InventoryType.Inventory then
            -- Sizing
            self.widget:SetSize(width, fullHeight)
            self.widget:ClearAllPoints()
            self.widget:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', 0, 0)

            -- Remove Drag Handlers
            self.widget.Header:SetScript('OnDragStart', function() end)
            self.widget.Header:SetScript('OnDragStop', function() end)

            -- Hide vertical Drag Bar
            if self.widget.DragBag then
                self.widget.DragBag:Hide()
            end
        end
    else -- Compact
        local viewHeight = database:GetViewHeight(inventoryType)
        -- Sizing
        self.widget:SetSize(width, viewHeight)
        local position = database:GetViewPosition(inventoryType)
        self.widget:ClearAllPoints()
        self.widget:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', position.x, position.y)

        -- Add Drag Handlers
        self.widget.Header:RegisterForDrag('LeftButton')
        self.widget.Header:SetScript('OnDragStart', function(self)
            self:GetParent():StartMoving()
        end)
        self.widget.Header:SetScript('OnDragStop', function(self)
            self:GetParent():StopMovingOrSizing()
            local x = self:GetParent():GetLeft()
            local y = self:GetParent():GetTop()
            database:SetViewPosition(inventoryType, x, y)
        end)

        -- Show vertical Drag Bar
        if self.widget.DragBag then
            self.widget.DragBag:Show()
        else
            local drag = CreateFrame('Button', nil, self.widget)
            drag:SetSize(64, 12)
            drag:SetPoint('BOTTOM', self.widget, 'BOTTOM', 0, -6)

            drag:SetScript('OnMouseDown', function(self)
                self:GetParent():StartSizing('BOTTOM')
            end)

            drag:SetScript('OnMouseUp', function(self)
                self:GetParent():StopMovingOrSizing('BOTTOM')
                database:SetViewHeight(inventoryType, self:GetParent():GetHeight())
            end)

            local dragTex = drag:CreateTexture(nil, 'BACKGROUND')
            dragTex:SetAllPoints(drag)
            dragTex:SetTexture('Interface\\Addons\\CouchMode\\Modules\\Bags\\Media\\Handlebar')

            self.widget.DragBag = drag
        end
    end

    self.widget.texture:SetColorTexture(0, 0, 0, database:GetBackgroundOpacity())

    -- Update the width of the rest of the elements
    self.widget.Header:UpdateGUI()
    self.filterContainer:UpdateGUI()

    self.sortContainer.widget:Hide()
    self.sortContainer.widget:SetParent(nil)
    self.sortContainer = sorting:Build(self.widget, inventoryType, function() self:Update() end)

    self.widget.scroller:SetWidth(width)
    self.widget.ListView:SetWidth(width)
    self.widget.footer:SetWidth(width - 2)
    self.widget.gold:SetFont(font.path, fontSize)
    self:Update()
end

---@return boolean
function view.proto:IsShown()
    return self.widget:IsShown()
end

function view.proto:Show()
    self.widget:Show()
end

function view.proto:Hide()
    self.widget:Hide()
end

function view.proto:GetName()
    return self.widget:GetName()
end

function view.proto:UpdateMoney()
    if self.type == enums.InventoryType.Inventory then
        local money = GetMoney()
        if money == nil then return end
        local str = C_CurrencyInfo.GetCoinTextureString(money)
        if str == nil or str == '' then return end
        self.widget.gold:SetText(str)
        return
    end

    if self.type == enums.InventoryType.Bank then
        self.widget.Header.Additions:Update(enums.BankType.Bank)
    end
end

---@param currencyId number?
---@param value number?
function view.proto:UpdateCurrency(currencyId, value)
    -- Generic Update
    if not currencyId and not value then
        local index = 1
        local trackedCurrencies = {}
        repeat
            local currencyInfo = C_CurrencyInfo.GetCurrencyListInfo(index)
            if currencyInfo.isShowInBackpack then
                if not self.widget.currency.trackedCurrencies[currencyInfo.currencyID] then
                    -- Create
                    local frame = currency:Create()
                    self.widget.currency.trackedCurrencies[currencyInfo.currencyID] = frame
                    frame:Build(currencyInfo, self.widget.currency)
                else
                    -- Update
                    self.widget.currency.trackedCurrencies[currencyInfo.currencyID]:Update(currencyInfo.quantity)
                end
                tinsert(trackedCurrencies, currencyInfo.currencyID)
            end
            index = index + 1
        until index > C_CurrencyInfo.GetCurrencyListSize()


        -- Remove untracked
        for currencyId, frame in pairs(self.widget.currency.trackedCurrencies) do
            if not tContains(trackedCurrencies, currencyId) then
                frame:Clear()
                self.widget.currency.trackedCurrencies[currencyId] = nil
            end
        end

        -- Re-org frame
        self.widget.currency:Rebuild()
        return
    end

    if not self.widget.currency.trackedCurrencies[currencyId] then return end
    self.widget.currency.trackedCurrencies[currencyId]:Update(value)
end

view:Enable()
