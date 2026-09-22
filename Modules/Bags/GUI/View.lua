local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local bags = addon:GetModule('Bags')
local view = addon:NewModule('Bags.View')
local enums = addon:GetModule('Bags.Enums')
local utils = addon:GetModule('Bags.Utils')
local database = addon:GetModule('Bags.Database')
local session = addon:GetModule('Bags.Session')
local items = addon:GetModule('Bags.Items')
local filtering = addon:GetModule('Bags.Filtering')
local sorting = addon:GetModule('Bags.Sorting')
local container = addon:GetModule('Bags.BagContainer')
local categoryHeaders = addon:GetModule('Bags.CategoryHeaders')
local itemFrame = addon:GetModule('Bags.ItemFrame')
local bankHeader = addon:GetModule('Bags.BankHeader')
local currency = addon:GetModule('Bags.Currency')

view.proto = {}

local function geometry(type)
    local compact = database:GetViewType() == enums.ViewType.Compact
    local point = type == enums.InventoryType.Inventory and 'TOPRIGHT' or 'TOPLEFT'
    if compact then
        local position = database:GetViewPosition(type)
        return { width = database:GetInventoryViewWidth(), height = database:GetViewHeight(type), point = 'TOPLEFT', relativePoint = 'BOTTOMLEFT', x = position.x, y = position.y }
    end
    return { width = database:GetInventoryViewWidth(), height = math.floor(GetScreenHeight()), point = point, relativePoint = point }
end

local function HasNativeGamepadNavigation()
    return _G.InputUtil
        and InputUtil.IsGamepadUIEnabled
        and InputUtil.IsGamepadUIEnabled()
        and _G.GamepadMode
        and GamepadMode.FrameControlsManager
end

local ITEM_BUTTON_CONTEXT = 'ButtonContext_ContainerFrameItemButton'

local function CurrentItemButton()
    local button = _G.SmartNavigation and SmartNavigation:GetCurrentButton()
    if button and button.buttonContext == ITEM_BUTTON_CONTEXT and button.hasItem then return button end
end

local function IsItemUseBlocked()
    return MerchantFrame:IsShown()
end

local function IsUseItemActionValid()
    local button = SmartNavigation:GetCurrentButton()
    local isItemMoving = CursorHasItem()

    if button and button.hasItem and not InRepairMode() and not isItemMoving and not IsItemUseBlocked() then
        local item = Item:CreateFromBagAndSlot(button:GetBagID(), button:GetID())
        local itemID = item and item:GetItemID()
        if itemID and C_Item.IsUsableItem(itemID) then return true end
    end
    return false
end

local function IsEquipItemActionValid()
    local button = SmartNavigation:GetCurrentButton()
    local isItemMoving = CursorHasItem()

    if button and button.hasItem and not isItemMoving and not IsItemUseBlocked() then
        local item = Item:CreateFromBagAndSlot(button:GetBagID(), button:GetID())
        local itemID = item and item:GetItemID()
        if itemID and C_Item.IsEquippableItem(itemID) then return true end
    end
    return false
end

function view:Create(inventoryType)
    local i = setmetatable({ type = inventoryType, scratch = { categories = {}, all = {}, filtered = {} } }, { __index = self.proto })
    if inventoryType == enums.InventoryType.Bank then i.selectedBankType = enums.BankType.Bank end
    local name = inventoryType == enums.InventoryType.Inventory and 'Inventory' or 'Bank'
    i.usesConsolePort = _G.ConsolePort ~= nil and not HasNativeGamepadNavigation()
    local scrollTemplate = i.usesConsolePort and 'CPSmoothScrollTemplate' or 'UIPanelScrollFrameTemplate'
    if i.usesConsolePort then C_AddOns.LoadAddOn('ConsolePort_Config') end
    local g, sizes = geometry(inventoryType), session.Settings.Defaults.Sections
    i.catalog = addon.CatalogView:Create({
        name = 'CouchModeBags' .. name, title = name, strata = 'HIGH', scrollTemplate = scrollTemplate,
        width = g.width, height = g.height, point = g.point, relativePoint = g.relativePoint, x = g.x, y = g.y,
        minWidth = 600, minHeight = 436, maxWidth = 1200, maxHeight = 2000,
        headerHeight = sizes.Header, toolbarHeight = sizes.Filters + 20, columnHeaderHeight = sizes.ListViewHeader, footerHeight = sizes.Footer,
        sectionHeight = database:GetItemViewHeight(), rowHeight = database:GetItemViewHeight(),
        onClose = function() if inventoryType == enums.InventoryType.Inventory then bags:ToggleAllBags() else bags:CloseBank() end; bags.status.visitingWarbank = false end,
        onResize = function(frame) if database:GetViewType() == enums.ViewType.Compact then database:SetViewHeight(inventoryType, frame:GetHeight()) end end,
        onLayoutChanged = function(catalog) i:LayoutChildren(catalog) end,
        sectionRenderer = categoryHeaders:CreateRenderer(inventoryType == enums.InventoryType.Inventory and session.InventoryCollapsedCategories or session.BankCollapsedCategories, function() i:Update() end),
        rowRenderer = itemFrame:CreateRenderer(),
    })
    local f = i.catalog.frame
    -- Bags-only compatibility aliases. Core never relies on these.
    f.Header, f.ListView, f.scroller, f.footer = i.catalog.headerActions, i.catalog.content, i.catalog.scrollFrame, i.catalog.footer
    f.texture = f:CreateTexture(nil, 'BACKGROUND'); f.texture:SetAllPoints(f); f.texture:SetColorTexture(0, 0, 0, database:GetBackgroundOpacity())
    i.widget = f
    i.filterContainer = filtering:BuildContainer(f, inventoryType)
    i.sortContainer = sorting:Build(f, inventoryType, function() i:Update() end)
    i:ComposeControls()
    if inventoryType == enums.InventoryType.Bank then f.Header.Additions = bankHeader:CreateAdditions(i, f.Header) else i:CreateInventoryHeader(name) end
    container:Build(inventoryType, f)
    if inventoryType == enums.InventoryType.Inventory then f.currency = currency:CreateFrame(f.footer); f.gold = f.currency.gold end
    i:SetupGamepadNavigation()
    i:Hide()
    return i
end

function view.proto:SetupNativeGamepadFooter()
    if self.gamepadFooter or not _G.GamepadSharedUtility then return end

    local select = GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_BOTTOM, GenerateFlatClosure(SmartNavigation.Click, SmartNavigation), ACTION_LABEL_SELECT)
    select:AddButtonContext(ITEM_BUTTON_CONTEXT)
    select:AddCondition(CurrentItemButton)

    local use = GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_LEFT, GenerateFlatClosure(SmartNavigation.RightClick, SmartNavigation), CONTEXT_ACTION_LABEL_USE)
    use:SetVisibilityType(PromptedBindingMixin.VISIBILITY_TYPE.ONLY_IF_USABLE)
    use:AddButtonContext(ITEM_BUTTON_CONTEXT)
    use:AddCondition(IsUseItemActionValid)

    local equip = GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_LEFT, GenerateFlatClosure(SmartNavigation.RightClick, SmartNavigation), CONTEXT_ACTION_LABEL_EQUIP)
    equip:SetVisibilityType(PromptedBindingMixin.VISIBILITY_TYPE.ONLY_IF_USABLE)
    equip:AddButtonContext(ITEM_BUTTON_CONTEXT)
    equip:AddCondition(IsEquipItemActionValid)

    local more = GamepadSharedUtility.CreateMoreActionsPromptedBinding(GAMEPAD_FACE_TOP)
    more:SetVisibilityType(PromptedBindingMixin.VISIBILITY_TYPE.ONLY_IF_USABLE)
    more:AddButtonContext(ITEM_BUTTON_CONTEXT)
    more:AddCondition(CurrentItemButton)
    more:AddMoreActionsEntry(CONTEXT_ACTION_LABEL_SPLIT_ITEM_STACK, function()
        local button = CurrentItemButton()
        local info = button and C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
        if info and not info.isLocked and info.stackCount > 1 then
            button.SplitStack = function(target, count) C_Container.SplitContainerItem(target:GetBagID(), target:GetID(), count) end
            GamepadMode.FrameControlsManager:SuspendFrameWithFooter()
            StackSplitFrame:OpenStackSplitFrame(info.stackCount, button, 'BOTTOMRIGHT', 'TOPRIGHT')
            ShowUIPanel(StackSplitFrame)
        end
    end, function(button)
        local info = button and C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
        return info and not info.isLocked and info.stackCount > 1
    end)
    more:AddMoreActionsEntry(CONTEXT_ACTION_LABEL_DESTROY_ITEM, function()
        local button = CurrentItemButton()
        local item = button and Item:CreateFromBagAndSlot(button:GetBagID(), button:GetID())
        if item then C_Item.ConfirmDeleteItem(item:GetItemGUID()) end
    end)

    local close = GamepadSharedUtility.CreatePromptedBinding(GAMEPAD_FACE_RIGHT, function()
        SmartNavigation:AttemptClose()
        self.gamepadFooter:Refresh()
    end, FRAME_ACTION_CLOSE)

    local footer = GamepadSharedUtility.CreatePromptedBindingFooter(self.widget, 'CouchModeBagsFooter')
    footer:AddPromptedBinding(select)
    footer:AddPromptedBinding(use)
    footer:AddPromptedBinding(equip)
    footer:AddPromptedBinding(more)
    footer:AddStandardFrameControlManagerBindings(self.widget)
    footer:AddPromptedBinding(close)
    footer:Finalize()
    self.gamepadFooter = footer
end

function view.proto:SetupGamepadNavigation()
    local f = self.widget
    if self.usesConsolePort then
        f.scroller.ScrollBar:Hide()
        f.scroller.ScrollBar:EnableMouse(false)
        _G.ConsolePort:AddInterfaceCursorFrame(f)
        f:SetPropagateKeyboardInput(true)
        f:SetScript('OnGamePadButtonDown', function(_, key)
            if not HasNativeGamepadNavigation() then self:OnGamePadButton(key) end
        end)
    end

    f:HookScript('OnShow', function(frame)
        if self.usesConsolePort and not InCombatLockdown() and _G.ConsolePortInputHandler then
            _G.ConsolePortInputHandler:SetCommand('PADRSHOULDER', frame, true, 'LeftButton', 'UIControl', nil)
            _G.ConsolePortInputHandler:SetCommand('PADLSHOULDER', frame, true, 'LeftButton', 'UIControl', nil)
            if _G.Scrap then _G.ConsolePortInputHandler:SetCommand('PAD3', frame, true, 'LeftButton', 'UIControl', nil) end
        end
        if HasNativeGamepadNavigation() and _G.SmartNavigation then
            SmartNavigation:SetSmartNavPanelInfoAddedCallback(frame, GenerateClosure(self.SmartNavPanelInfoAdded, self))
            EventRegistry:RegisterCallback('Gamepad.RefreshFrameFocus', self.RefreshNativeGamepadFocus, self)
        end
    end)
    f:HookScript('OnHide', function(frame)
        if self.usesConsolePort and _G.ConsolePortInputHandler then
            _G.ConsolePortInputHandler:Release(frame)
        end
        EventRegistry:UnregisterCallback('Gamepad.RefreshFrameFocus', self)
        if self.gamepadFooter then
            securecallfunction(self.gamepadFooter.HideAndDeactivateBindings, self.gamepadFooter)
        end
    end)
    f.SmartNavigationCloseHandler = function()
        if CursorHasItem() then
            ClearCursor()
        elseif self.type == enums.InventoryType.Inventory then
            bags:CloseAllBags()
        else
            bags:CloseBank()
        end
        return true
    end
end

function view.proto:RefreshNativeGamepadFocus()
    -- FrameControlsManager invokes a frame's FocusGamepad and UnfocusGamepad
    -- methods directly, then continues into protected binding updates. Keep
    -- addon callbacks behind EventRegistry's secure callback boundary instead.
    local manager = GamepadMode.FrameControlsManager
    local isFocused = manager.isUIFocused and manager:GetActiveFrame() == self.widget

    if isFocused then
        self:SetupNativeGamepadFooter()
        securecallfunction(self.gamepadFooter.ShowAndActivateBindings, self.gamepadFooter)
    elseif self.gamepadFooter then
        securecallfunction(self.gamepadFooter.HideAndDeactivateBindings, self.gamepadFooter)
    end
end

function view.proto:SmartNavPanelInfoAdded(_)
    local firstItemButton
    for _, row in ipairs(self.catalog.activeRows) do
        local button = row.widget and row.widget.itemButton
        if button and button:IsVisible() then
            firstItemButton = button
            break
        end
    end

    if firstItemButton then
        SmartNavigation:SetTargetButtonForFrame(self.widget, firstItemButton)
    end
end

function view.proto:RefreshNativeGamepadNavigation()
    if HasNativeGamepadNavigation() and self.widget:IsShown() and _G.SmartNavigation then
        SmartNavigation:RefreshButtonGroups(self.widget)
    end
end

function view.proto:CreateInventoryHeader(name)
    local f = self.widget
    local button = CreateFrame('Button', nil, f.Header); button:SetSize(24, 24); button:SetPoint('LEFT', f.Header, 4, 0); button:SetNormalTexture('Interface\\Buttons\\UI-OptionsButton'); button:GetNormalTexture():SetDesaturated(true)
    button:SetScript('OnClick', function() LibStub('AceConfigDialog-3.0'):Open(addonName) end)
    local label = f.Header:CreateFontString(nil, 'ARTWORK', 'GameFontNormal'); label:SetPoint('LEFT', button, 'RIGHT', 8, 0); label:SetText(name); f.Header.label = label
    local search = CreateFrame('EditBox', nil, f.Header, 'SearchBoxTemplate'); search:SetPoint('LEFT', label, 'RIGHT', 24, 0); search:SetSize(200, 16); search:SetAutoFocus(false)
    search:HookScript('OnTextChanged', function(box) self.filterContainer:OnSearch(function() self:Update(box:GetText(), true) end) end)
end

function view.proto:LayoutChildren(catalog)
    local f, width = self.widget, catalog.frame:GetWidth()
    if f == nil then return end
    f.Header:SetWidth(width - 42); f.scroller:SetWidth(width); f.ListView:SetWidth(width); f.footer:SetWidth(width - 20)
    if f.gold then f.gold:SetFont(database:GetFont().path, utils:GetFontScale()) end
end

function view.proto:ComposeControls()
    local filter = self.filterContainer.widget
    filter:SetParent(self.catalog.toolbar); filter:ClearAllPoints(); filter:SetPoint('TOPLEFT'); filter:SetPoint('BOTTOMRIGHT')
    local sort = self.sortContainer.widget
    sort:SetParent(self.catalog.columnHeader); sort:ClearAllPoints(); sort:SetPoint('TOPLEFT'); sort:SetPoint('BOTTOMRIGHT')
end

function view.proto:BuildSections(searchText)
    local s = self.scratch; wipe(s.categories); wipe(s.all); wipe(s.filtered)
    local collapsed = self.type == enums.InventoryType.Inventory and session.InventoryCollapsedCategories or session.BankCollapsedCategories
    local selected = self.type == enums.InventoryType.Inventory and session.InventoryFilter or session.BankFilter
    local source = self.type == enums.InventoryType.Inventory and session.InventoryItems or (self.selectedBankType == enums.BankType.Warbank and session.WarbankItems or session.BankItems)
    local needle = searchText and searchText:lower() or nil
    for _, item in ipairs(source) do if not needle or item.name:lower():find(needle, 1, true) then utils.AddItemToCategory(item, s.categories) end end
    items:SortItems(s.categories, database:GetSortField(self.type))
    for key, data in pairs(s.categories) do data.key = key; data.order = enums.Categories[key].order; data.name = enums.Categories[key].name; s.all[#s.all + 1] = data; if not selected or key == selected then s.filtered[#s.filtered + 1] = data end end
    table.sort(s.all, function(a,b) return a.order < b.order end); table.sort(s.filtered, function(a,b) return a.order < b.order end)
    local sections = {}
    for _, data in ipairs(s.filtered) do if #data.items > 0 then sections[#sections + 1] = { key = data.key, data = data, expanded = not collapsed[data.key], rows = data.items } end end
    return sections, s.all
end

function view.proto:Update(searchText, resetScroll)
    local sections, all = self:BuildSections(searchText)
    self.catalog:Render(sections, resetScroll)
    self.filterContainer:Update(self.type, all, function(key) if self.type == enums.InventoryType.Inventory then session.InventoryFilter = key else session.BankFilter = key end; self:Update(nil, true) end)
    container:Update(self.widget, self.type, self.selectedBankType)
    if self.widget.Header.Additions then self.widget.Header.Additions:Update(self.selectedBankType) end
    self:RefreshNativeGamepadNavigation()
end

function view.proto:UpdateGUI(inventoryType)
    self.viewType = database:GetViewType(); self.catalog:SetGeometry(geometry(inventoryType)); self.widget.texture:SetColorTexture(0, 0, 0, database:GetBackgroundOpacity())
    local compact = self.viewType == enums.ViewType.Compact
    self.catalog.headerActions:EnableMouse(compact)
    self.catalog.resizeGrip:SetShown(compact)
    self.filterContainer:UpdateGUI(); self.sortContainer.widget:Hide(); self.sortContainer.widget:SetParent(nil); self.sortContainer = sorting:Build(self.widget, inventoryType, function() self:Update() end); self:ComposeControls()
    self:Update()
end
function view.proto:IsShown() return self.catalog:IsShown() end
function view.proto:Show()
    if HasNativeGamepadNavigation() then
        securecallfunction(ShowUIPanel, self.widget)
    else
        self.catalog:Show()
    end
end
function view.proto:Hide()
    if HasNativeGamepadNavigation() then
        securecallfunction(HideUIPanel, self.widget)
    else
        self.catalog:Hide()
    end
end
function view.proto:GetName() return self.catalog:GetName() end
function view.proto:SetAsBank() if self.widget.Header.Additions then self.widget.Header.Additions:SetAsBank() end end
function view.proto:UpdateMoney()
    if self.type == enums.InventoryType.Inventory then local money = GetMoney(); if money and self.widget.gold then self.widget.gold:SetText(C_CurrencyInfo.GetCoinTextureString(money)) end elseif self.widget.Header.Additions then self.widget.Header.Additions:Update(enums.BankType.Bank) end
end
function view.proto:UpdateCurrency(currencyId, value)
    if self.type ~= enums.InventoryType.Inventory then return end
    if currencyId then local frame = self.widget.currency.trackedCurrencies[currencyId]; if frame then frame:Update(value) end; return end
    local tracked = {}; for index = 1, C_CurrencyInfo.GetCurrencyListSize() or 0 do local info = C_CurrencyInfo.GetCurrencyListInfo(index); if info and info.currencyID and info.isShowInBackpack then local frame = self.widget.currency.trackedCurrencies[info.currencyID]; if not frame then frame = currency:Create(); self.widget.currency.trackedCurrencies[info.currencyID] = frame; frame:Build(info, self.widget.currency) else frame:Update(info.quantity) end; tracked[info.currencyID] = true end end
    for id, frame in pairs(self.widget.currency.trackedCurrencies) do if not tracked[id] then frame:Clear(); self.widget.currency.trackedCurrencies[id] = nil end end; self.widget.currency:Rebuild()
end
function view.proto:OnGamePadButton(key)
    if InCombatLockdown() then return end
    if _G.Scrap and key == 'PAD3' then local item = GameTooltip:IsVisible() and select(2, GameTooltip:GetItem()); if item then _G.Scrap:ToggleJunk(tonumber(item:match('item:(%d+)'))) end; return end
    local node = _G.ConsolePort.GetCursorNode(); if node then local parent = utils:GetParentMostNode(node); if parent and parent:GetName() == self.widget:GetName() then bags.bags.FocusedNode = self.type end end
    if bags.bags.FocusedNode ~= self.type then return end
    if key == 'PADRSHOULDER' then self.filterContainer:ScrollRight() elseif key == 'PADLSHOULDER' then self.filterContainer:ScrollLeft() end
end
view:Enable()
