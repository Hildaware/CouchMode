--[[ ChatPanel.lua
The Chat panel: construction, layout, fading and the controls that drive it.

Builds the CouchMode chat frame, its metal filter bar and input strip, wires the
embedded edit box and Edit Mode integration, and runs the per-frame fade pump for
panel/tab/input opacity. Filter selection and the keybinding-facing controls live
here too because they share the panel's geometry and alpha state.
]]

local addonName, addon = ...

local chat = addon.Chat
local Sources = addon.ChatSources
local Input = addon.ChatInput
local LibEditMode = LibStub('LibEditMode')

--#region ── Constants ────────────────────────────────────────────────────────

local PAD = 8
local FILTER_BAR_H = 32
local INPUT_STRIP_H = 28
local PANEL_CHROME_HEIGHT = (PAD + FILTER_BAR_H + PAD) + (PAD + INPUT_STRIP_H + PAD)
local BORDER_ALPHA = 0.5
local BORDER_INSET = 1

--#endregion

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

--#region ── State ─────────────────────────────────────────────────────────────

chat.panel = nil          ---@type Frame?
chat.feed = nil
chat.filterBtns = {}      ---@type table<string, Button>
chat.returnButton = nil   ---@type Button?
chat.lastActivity = 0
chat.fadeAlpha = 1
chat.tabsAlpha = 0
chat.inputAlpha = 0

--#endregion

--#region ── Panel construction ─────────────────────────────────────────────────

--- Resolved font metrics for the three text fields, passed to the feed.
---@return table
function chat:FontMetrics()
    return {
        msg     = { face = addon.Media.ResolveFont(db().msgFontFace),     size = db().msgFontSize },
        name    = { face = addon.Media.ResolveFont(db().nameFontFace),    size = db().nameFontSize },
        channel = { face = addon.Media.ResolveFont(db().channelFontFace), size = db().channelFontSize },
    }
end

--- Applies the configured panel background, with a temporary hover minimum.
function chat:ApplyPanelBackgroundOpacity()
    if not self.panel or not self.panel.bg then return end
    local opacity = db().backgroundOpacity or 0
    if self.backgroundHovered then opacity = math.max(opacity, 0.25) end
    self.panel.bg:SetColorTexture(0, 0, 0, opacity)
end

--- Applies border opacity independently of message-driven panel fading.
---@param interactive boolean?
function chat:ApplyBorderOpacity(interactive)
    if not self.borderFrame then return end

    if interactive == nil then
        local hovered = self.panel and self.panel.IsMouseOver and self.panel:IsMouseOver()
        interactive = hovered or Input:HasFocus()
    end

    local opacity = db().backgroundOpacity or 0
    if interactive then opacity = 1 end
    self.borderFrame:SetAlpha(BORDER_ALPHA * opacity)
end

function chat:BuildFilterBar(parent)
    local bar = CreateFrame('Frame', nil, parent)
    bar:SetFrameStrata('DIALOG')
    bar:SetPoint('TOPLEFT', parent, 'TOPLEFT', PAD, 0)
    bar:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', -PAD, 0)
    bar:SetHeight(FILTER_BAR_H)
    bar:EnableMouse(true)
    bar:SetAlpha(0)

    addon.Components.Metal.CreateHeader(bar)

    local prev
    for _, filter in ipairs(Sources.FILTERS) do
        -- Plain text buttons keep the atlas header visually continuous.
        local btn = CreateFrame('Button', nil, bar)
        btn:SetSize(60, 22)
        local label = btn:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
        label:SetPoint('CENTER')
        label:SetText(filter.label)
        btn.label = label
        if prev then
            btn:SetPoint('LEFT', prev, 'RIGHT', 2, 0)
        else
            btn:SetPoint('LEFT', bar, 'LEFT', 12, 0)
        end
        btn:RegisterForClicks('LeftButtonUp')
        btn:SetScript('OnClick', function() chat:SetFilter(filter.key) end)
        btn:SetScript('OnEnter', function() label:SetTextColor(1, 1, 1) end)
        btn:SetScript('OnLeave', function() chat:RefreshFilterButtons() end)
        self.filterBtns[filter.key] = btn
        prev = btn
    end
    self.filterBar = bar
    return bar
end

function chat:BuildPanel()
    if self.panel then
        self.panel:Show()
        if self.borderFrame then self.borderFrame:Show() end
        self:ApplyBorderOpacity()
        return
    end

    local frame = CreateFrame('Frame', 'CouchModeChat', UIParent)
    frame:SetSize(db().width, db().height or chat.DEFAULT_HEIGHT)
    frame:SetScale(db().scale or 1)
    frame:SetFrameStrata('LOW')
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    local borderFrame = CreateFrame('Frame', nil, UIParent)
    borderFrame:SetFrameStrata(frame:GetFrameStrata())
    borderFrame:SetFrameLevel(frame:GetFrameLevel() + 1)
    addon.Components.Metal.PositionBorderFrame(borderFrame, frame, addon.Components.Metal.BORDER_OUTSET)
    borderFrame:SetAlpha(BORDER_ALPHA * (db().backgroundOpacity or 0))
    borderFrame:Hide()
    self.borderFrame = borderFrame

    local borderAnchor = CreateFrame('Frame', nil, frame)
    borderAnchor:SetPoint('TOPLEFT', frame, 'TOPLEFT', BORDER_INSET, 0)
    borderAnchor:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -BORDER_INSET, 0)
    self.borders = addon.Components.Metal.CreateBorderTextures(borderFrame, borderAnchor)

    local bg = frame:CreateTexture(nil, 'BACKGROUND')
    bg:SetPoint('CENTER', frame, 'CENTER', 0, -6)
    bg:SetWidth(frame:GetWidth() - 12)
    bg:SetHeight(frame:GetHeight() - 30)
    bg:SetColorTexture(0, 0, 0, 1)
    frame.bg = bg

    self:BuildFilterBar(frame)

    local scrollArea = CreateFrame('Frame', nil, frame)
    scrollArea:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, -(PAD + FILTER_BAR_H + PAD))
    scrollArea:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PAD, PAD + INPUT_STRIP_H + PAD)
    self.scrollArea = scrollArea

    self.feed = addon.ChatFeedProto.New(scrollArea)
    self.feed:SetFonts(self:FontMetrics())
    self.feed:SetCompactMode(db().compactMode)
    self.feed.onScrollChanged = function() chat:OnFeedChanged() end

    local strip = CreateFrame('Frame', nil, frame)
    strip:SetFrameStrata('DIALOG')
    strip:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', PAD, PAD/2)
    strip:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PAD, PAD/2)
    strip:SetHeight(INPUT_STRIP_H)
    addon.Components.Metal.CreateHeader(strip)
    strip:SetAlpha(0)
    self.inputStrip = strip

    for _, region in ipairs({ frame, scrollArea, strip }) do
        region:EnableMouse(true)
    end

    local returnBtn = CreateFrame('Button', nil, frame)
    returnBtn:SetSize(22, 22)
    returnBtn:SetPoint('BOTTOMRIGHT', scrollArea, 'BOTTOMRIGHT', -4, 4)
    returnBtn:SetFrameLevel(frame:GetFrameLevel() + 20)
    returnBtn:SetNormalTexture('Interface\\ChatFrame\\ChatFrameExpandArrow')
    returnBtn:SetScript('OnClick', function() chat:ScrollToBottom() end)
    returnBtn:Hide()
    self.returnButton = returnBtn

    frame:SetScript('OnUpdate', function(_, dt) chat:UpdateFade(dt) end)

    local eb = Input:Attach(frame, strip)
    if eb and eb.HookScript then
        eb:HookScript('OnEditFocusGained', function()
            chat:Touch()
            chat:ApplyBorderOpacity(true)
        end)
        eb:HookScript('OnEditFocusLost', function()
            chat:Touch()
            chat:ApplyBorderOpacity()
        end)
    end

    LibEditMode:AddFrame(frame, function(_, layoutName, point, x, y)
        -- LibEditMode can dispatch a frame-position callback before it has
        -- resolved the active layout name. There is nowhere valid to persist
        -- that position yet, so wait for a layout-scoped callback instead.
        if not layoutName then return end
        local settings = db()
        settings.positions = settings.positions or {}
        settings.positions[layoutName] = { point = point, x = x, y = y }
    end, { point = 'BOTTOMLEFT', x = 10, y = 120 }, 'CouchMode Chat')

    LibEditMode:AddFrameSettings(frame, {
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Width', desc = 'Panel width in pixels.',
            default = chat.DEFAULT_WIDTH, minValue = 240, maxValue = 1200, valueStep = 10,
            get = function() return db().width end,
            set = function(_, value, fromReset)
                db().width = (fromReset and chat.DEFAULT_WIDTH or value)
                chat:ApplyLayout(true)
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Height', desc = 'Fixed height of the chat panel.',
            default = chat.DEFAULT_HEIGHT, minValue = 200, maxValue = 900, valueStep = 10,
            get = function() return db().height end,
            set = function(_, value, fromReset)
                db().height = (fromReset and chat.DEFAULT_HEIGHT or value)
                chat:ApplyLayout(true)
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Scale', desc = 'Overall panel scale.',
            default = 1, minValue = 0.5, maxValue = 2, valueStep = 0.05,
            get = function() return db().scale end,
            set = function(_, value, fromReset)
                db().scale = (fromReset and 1 or value)
                if chat.panel then chat.panel:SetScale(db().scale) end
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Active Opacity', desc = 'Panel opacity while at least one message is visible.',
            default = 1, minValue = 0.1, maxValue = 1, valueStep = 0.05,
            get = function() return db().activeOpacity end,
            set = function(_, value, fromReset)
                db().activeOpacity = (fromReset and 1 or value)
                chat:Touch()
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Background Opacity', desc = 'Panel opacity after all visible messages fade.',
            default = 0, minValue = 0, maxValue = 1, valueStep = 0.05,
            get = function() return db().backgroundOpacity end,
            set = function(_, value, fromReset)
                db().backgroundOpacity = (fromReset and 0 or value)
                chat:ApplyPanelBackgroundOpacity()
                chat:Touch()
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Fade Delay', desc = 'Seconds each message remains visible before fading.',
            default = 15, minValue = 0, maxValue = 60, valueStep = 1,
            get = function() return db().fadeDelay end,
            set = function(_, value, fromReset)
                db().fadeDelay = (fromReset and 15 or value)
                chat:Touch()
            end,
        },
        {
            kind = LibEditMode.SettingType.Dropdown,
            name = 'Message Font', desc = 'Font used for message text.',
            default = 'Arial Narrow',
            values = (function()
                local values = {}
                for name in pairs(addon.Media.GetFontOptions()) do
                    values[#values + 1] = { text = name, value = name }
                end
                table.sort(values, function(a, b) return a.text < b.text end)
                return values
            end)(),
            get = function() return db().msgFontFace end,
            set = function(_, value, fromReset)
                db().msgFontFace = (fromReset and 'Arial Narrow' or value)
                chat:Recompute()
            end,
        },
    })

    LibEditMode:RegisterCallback('layout', function(layoutName)
        local pos = db().positions[layoutName]
        frame:ClearAllPoints()
        if pos then
            frame:SetPoint(pos.point, pos.x, pos.y)
        else
            frame:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 10, 120)
        end
    end)

    frame:Show()
    borderFrame:Show()
    self.panel = frame
    self:ApplyLayout()
    self:ApplyBorderOpacity()
    self:RefreshFilterButtons()
    self:Recompute()
end

function chat:ApplyLayout(rebuild)
    local frame = self.panel
    if not frame then return end
    local panelHeight = db().height or chat.DEFAULT_HEIGHT
    frame:SetSize(db().width, panelHeight)
    frame:SetScale(db().scale or 1)
    frame.bg:SetSize(db().width - 12, panelHeight - 30)
    self:ApplyPanelBackgroundOpacity()

    local viewport = panelHeight - PANEL_CHROME_HEIGHT
    self.feed:SetWidth(db().width - PAD * 2)
    self.feed:SetViewportHeight(viewport)

    if rebuild then self:Recompute() end
end

--#endregion

--#region ── Fade / activity ──────────────────────────────────────────────────

function chat:Touch()
    self.lastActivity = (type(GetTime) == 'function') and GetTime() or 0
end

--- Smoothly changes one panel region's local alpha.
---@param region Region?
---@param stateKey string
---@param target number
---@param dt number
function chat:FadeRegion(region, stateKey, target, dt)
    if not region then return end
    local current = self[stateKey] or 0
    local diff = target - current
    if math.abs(diff) < 0.01 then
        current = target
    else
        current = current + diff * math.min(dt * 8, 1)
    end
    if current ~= self[stateKey] then
        self[stateKey] = current
        region:SetAlpha(current)
    end
end

function chat:UpdateFade(dt)
    if not self.panel then return end
    local now = (type(GetTime) == 'function') and GetTime() or 0
    local panelHovered = self.panel.IsMouseOver and self.panel:IsMouseOver() or false
    local feedHovered = self.scrollArea and self.scrollArea.IsMouseOver
        and self.scrollArea:IsMouseOver() or false
    if self.feed then self.feed:SetHoverHistory(feedHovered) end
    local historyVisible = self.feed and self.feed:IsHistoryVisible()
    local backgroundHovered = panelHovered
    if backgroundHovered ~= self.backgroundHovered then
        self.backgroundHovered = backgroundHovered
        self:ApplyPanelBackgroundOpacity()
    end
    local inputFocused = Input:HasFocus()
    local gamepadFocused = false
    local gamepadMode = _G.GamepadMode
    local focusManager = gamepadMode and gamepadMode.FrameControlsManager
    if focusManager and focusManager.isUIFocused and focusManager.GetActiveFrame then
        gamepadFocused = focusManager:GetActiveFrame() == self.panel
    end
    local engaged = historyVisible or panelHovered or inputFocused or gamepadFocused
    if self.feed then self.feed:SetFadePaused(engaged, now) end
    local hasVisibleMessages = self.feed and self.feed:UpdateMessageFade(
        now, db().fadeDelay or 15,
        db().fadeEnabled == true
    ) or false

    -- The filter controls are discoverable from their own hover region, while
    -- the input strip only exists while Blizzard's edit box is active.
    self:FadeRegion(self.filterBar, 'tabsAlpha', panelHovered and 1 or 0, dt)
    self:FadeRegion(self.inputStrip, 'inputAlpha', inputFocused and 1 or 0, dt)

    -- Individual lines expire from their own display times. The panel remains
    -- active while a line, tab interaction, or focused input is visible.
    local target = db().activeOpacity
    if db().fadeEnabled and not engaged and not hasVisibleMessages then
        target = db().backgroundOpacity
    end
    local current = self.fadeAlpha
    local diff = target - current
    local nextAlpha
    if math.abs(diff) < 0.01 then
        nextAlpha = target
    else
        nextAlpha = current + diff * math.min(dt * 6, 1)
    end
    if nextAlpha ~= current then
        self.fadeAlpha = nextAlpha
        self.panel:SetAlpha(nextAlpha)
    end
    self:ApplyBorderOpacity(engaged)
end

--#endregion

--#region ── Filters ─────────────────────────────────────────────────────────

function chat:SetFilter(filter)
    if not Sources.FILTER_KEYS[filter] then return end
    db().filter = filter
    self:RefreshFilterButtons()
    self:Recompute()
    self:Touch()
end

function chat:CycleFilter(delta)
    self:SetFilter(Sources.CycleFilter(db().filter, delta))
end

function chat:RefreshFilterButtons()
    for key, btn in pairs(self.filterBtns) do
        local active = key == (db().filter or 'ALL')
        if active then
            btn.label:SetTextColor(1, 0.82, 0, 1)
        else
            btn.label:SetTextColor(0.65, 0.65, 0.65, 1)
        end
    end
end

--#endregion

--#region ── Panel controls ─────────────────────────────────────────────────────

function chat:Toggle()
    if not db().enabled then return end
    if not self.panel then return end
    if Input:HasFocus() then
        Input:Deactivate()
        self:Touch()
    else
        Input:Focus()
        self:Touch()
    end
end

function chat:FocusInput()
    if self.panel then Input:Focus(); self:Touch() end
end

function chat:ClosePanel()
    Input:Deactivate()
    self.fadeAlpha = db().backgroundOpacity
    if self.panel then self.panel:SetAlpha(self.fadeAlpha) end
    self:ApplyBorderOpacity()
end

function chat:ScrollUp()
    if self.feed then self.feed:ScrollBy(60) end
    self:Touch()
end

function chat:ScrollDown()
    if self.feed then self.feed:ScrollBy(-60) end
    self:Touch()
end

--#endregion
