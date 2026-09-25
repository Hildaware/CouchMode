local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---A reusable framed, scrollable catalog. Data selection and presentation belong to callers.
---@class CatalogViewOptions
---@field name string
---@field title string|nil
---@field parent Frame|nil
---@field strata string|nil
---@field width number|nil
---@field height number|nil
---@field point string|nil
---@field relativeTo Frame|nil
---@field relativePoint string|nil
---@field x number|nil
---@field y number|nil
---@field minWidth number|nil
---@field minHeight number|nil
---@field maxWidth number|nil
---@field maxHeight number|nil
---@field headerHeight number|nil
---@field toolbarHeight number|nil
---@field columnHeaderHeight number|nil
---@field footerHeight number|nil
---@field rowHeight number|nil
---@field sectionHeight number|nil
---@field scrollTemplate string|nil
---@field smoothScroll boolean|nil
---@field search boolean|nil
---@field onSearch fun(text: string)|nil
---@field onClose fun()|nil
---@field onMove fun(frame: Frame)|nil
---@field onResize fun(frame: Frame)|nil
---@field onShow fun(frame: Frame)|nil
---@field onHide fun(frame: Frame)|nil
---@field onLayoutChanged fun(catalog: CatalogView)|nil
---@field sectionRenderer table|nil
---@field rowRenderer table|nil

---@class CatalogView
---@field frame Frame
---@field headerActions Frame
---@field toolbar Frame
---@field columnHeader Frame
---@field content Frame
---@field footer Frame
---@field scrollFrame ScrollFrame
---@field sectionPool table
---@field rowPool table
---@field activeSections table
---@field activeRows table
---@field scratch table
addon.CatalogView = addon.CatalogView or {}
local catalog = addon.CatalogView
catalog.proto = catalog.proto or {}

local function release(pool, active)
    for index = #active, 1, -1 do
        local component = active[index]
        if component.reset then component:reset() elseif component.frame then component.frame:Hide(); component.frame:ClearAllPoints(); component.frame:SetParent(nil) end
        pool[#pool + 1] = component
        active[index] = nil
    end
end

local function acquire(pool, renderer)
    local component = table.remove(pool)
    if not component then component = renderer.create() end
    return component
end

---Uses the same interpolation approach as ConsolePort's smooth scroll frame,
---without depending on ConsolePort or replacing the caller's frame template.
local function enableSmoothScrolling(scroll)
    local scrollBar = scroll.ScrollBar
    if not scrollBar or not scrollBar.GetPanExtentPercentage or not CreateInterpolator or not InterpolatorUtil then return end

    local interpolator = CreateInterpolator(InterpolatorUtil.InterpolateEaseOut)
    local setScroll = function(value) scroll:SetVerticalScroll(value) end
    scroll:SetScript('OnMouseWheel', function(frame, delta)
        local range = frame:GetVerticalScrollRange()
        if range <= 0 then return end
        local current = frame:GetVerticalScroll()
        local target = interpolator:GetInterpolateTo() or current
        target = math.min(math.max(target - (delta * scrollBar:GetPanExtentPercentage() * range), 0), range)
        interpolator:Interpolate(current, target, 0.075, setScroll)
    end)
end

function catalog:Create(options)
    assert(options and options.name, 'CatalogView requires a frame name')
    local i = setmetatable({ options = options, sectionPool = {}, rowPool = {}, activeSections = {}, activeRows = {}, scratch = {} }, { __index = self.proto })
    local f = CreateFrame('Frame', options.name, options.parent or UIParent, 'BasicFrameTemplateWithInset')
    f:SetFrameStrata(options.strata or 'HIGH')
    f:SetSize(options.width or 600, options.height or 436)
    f:SetPoint(options.point or 'CENTER', options.relativeTo or UIParent, options.relativePoint or options.point or 'CENTER', options.x or 0, options.y or 0)
    f:SetMovable(true); f:SetUserPlaced(true); f:EnableMouse(true); f:SetResizable(true)
    f:SetResizeBounds(options.minWidth or 600, options.minHeight or 436, options.maxWidth or 1200, options.maxHeight or 2000)
    f.TitleText:SetText(options.title or '')
    f.CloseButton:SetScript('OnClick', function() if options.onClose then options.onClose() else f:Hide() end end)
    f:SetScript('OnShow', function(frame) if options.onShow then options.onShow(frame) end end)
    f:SetScript('OnHide', function(frame) if options.onHide then options.onHide(frame) end end)
    f:SetScript('OnSizeChanged', function(frame) i:Relayout(); if options.onResize then options.onResize(frame) end end)

    local header = CreateFrame('Frame', nil, f)
    header:SetPoint('TOPLEFT', f, 'TOPLEFT', 10, -28); header:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -32, -28); header:SetHeight(options.headerHeight or 32)
    header:EnableMouse(true)
    header:RegisterForDrag('LeftButton')
    header:SetScript('OnDragStart', function() f:StartMoving() end)
    header:SetScript('OnDragStop', function() f:StopMovingOrSizing(); if options.onMove then options.onMove(f) end end)
    local toolbar = CreateFrame('Frame', nil, f)
    toolbar:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', -10, 0); toolbar:SetPoint('TOPRIGHT', header, 'BOTTOMRIGHT', 22, 0); toolbar:SetHeight(options.toolbarHeight or 0)
    local columnHeader = CreateFrame('Frame', nil, f)
    columnHeader:SetPoint('TOPLEFT', toolbar, 'BOTTOMLEFT'); columnHeader:SetPoint('TOPRIGHT', toolbar, 'BOTTOMRIGHT'); columnHeader:SetHeight(options.columnHeaderHeight or 0)
    local footer = CreateFrame('Frame', nil, f)
    footer:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 10, 10); footer:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -10, 10); footer:SetHeight(options.footerHeight or 0)
    local scroll = CreateFrame('ScrollFrame', nil, f, options.scrollTemplate or 'UIPanelScrollFrameTemplate')
    -- Blizzard can show the bar again whenever the scroll range changes.
    -- Keep it invisible while preserving its value for wheel and gamepad scrolling.
    if scroll.ScrollBar then
        local scrollBar = scroll.ScrollBar
        scrollBar:Hide()
        scrollBar:SetAlpha(0)
        scrollBar:EnableMouse(false)
        if scrollBar.ScrollUpButton then scrollBar.ScrollUpButton:EnableMouse(false) end
        if scrollBar.ScrollDownButton then scrollBar.ScrollDownButton:EnableMouse(false) end
    end
    scroll:ClearAllPoints()
    scroll:SetPoint('TOPLEFT', f, 'TOPLEFT', 0,
        -(28 + (options.headerHeight or 32) + (options.toolbarHeight or 0) + (options.columnHeaderHeight or 0)))
    scroll:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -10, 10 + (options.footerHeight or 0))
    local content = CreateFrame('Frame', nil, scroll); content:SetSize(1, 1); scroll:SetScrollChild(content)
    if options.smoothScroll ~= false then enableSmoothScrolling(scroll) end
    -- Assign regions before creating resize assets: Blizzard can issue a size
    -- notification while a button texture is being initialized.
    i.frame, i.headerActions, i.toolbar, i.columnHeader, i.footer, i.scrollFrame, i.content = f, header, toolbar, columnHeader, footer, scroll, content
    local grip = CreateFrame('Button', nil, f)
    grip:SetSize(16, 16); grip:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -4, 4)
    grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
    grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
    grip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
    grip:SetScript('OnMouseDown', function() f:StartSizing('BOTTOMRIGHT') end)
    grip:SetScript('OnMouseUp', function() f:StopMovingOrSizing(); if options.onResize then options.onResize(f) end end)
    i.resizeGrip = grip
    if options.search then
        local search = CreateFrame('EditBox', nil, header, 'SearchBoxTemplate'); search:SetSize(200, 16); search:SetPoint('RIGHT', header, 'RIGHT', -4, 0); search:SetAutoFocus(false)
        search:HookScript('OnTextChanged', function(box) if options.onSearch then options.onSearch(box:GetText()) end end)
        i.searchBox = search
    end
    return i
end

function catalog.proto:ReleaseContent() release(self.sectionPool, self.activeSections); release(self.rowPool, self.activeRows); self.content:SetHeight(1) end
function catalog.proto:Render(sections, resetScroll)
    local position = resetScroll and 0 or self.scrollFrame:GetVerticalScroll()
    self:ReleaseContent()
    local y, width = 0, math.max(self.scrollFrame:GetWidth(), self.content:GetWidth(), 1)
    self.content:SetWidth(width)
    for _, section in ipairs(sections or {}) do
        if self.options.sectionRenderer then
            local header = acquire(self.sectionPool, self.options.sectionRenderer)
            self.activeSections[#self.activeSections + 1] = header
            header:bind(section, y, self.content, width)
            y = y + (header.height or self.options.sectionHeight or 1)
        end
        if section.expanded ~= false then
            for _, rowData in ipairs(section.rows or {}) do
                local row = acquire(self.rowPool, self.options.rowRenderer)
                self.activeRows[#self.activeRows + 1] = row
                row:bind(rowData, y, self.content, width)
                y = y + (row.height or self.options.rowHeight or 1)
            end
        end
    end
    self.content:SetHeight(math.max(y, 1)); self.scrollFrame:SetVerticalScroll(position); self:Relayout()
end
function catalog.proto:SetGeometry(geometry)
    self.frame:SetSize(geometry.width, geometry.height); self.frame:ClearAllPoints(); self.frame:SetPoint(geometry.point or 'CENTER', geometry.relativeTo or UIParent, geometry.relativePoint or geometry.point or 'CENTER', geometry.x or 0, geometry.y or 0); self:Relayout()
end
function catalog.proto:Relayout()
    self.content:SetWidth(self.scrollFrame:GetWidth())
    if self.options.onLayoutChanged then self.options.onLayoutChanged(self) end
end
function catalog.proto:Show() self.frame:Show() end
function catalog.proto:Hide() self.frame:Hide() end
function catalog.proto:IsShown() return self.frame:IsShown() end
function catalog.proto:GetName() return self.frame:GetName() end
