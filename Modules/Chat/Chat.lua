local addonName, addon = ...

---@class CouchMode: AceAddon
---@field ChatRouter table
---@field ChatSources table
---@field ChatRules table
---@field ChatGrouping table
---@field ChatInput table
---@field ChatFeedProto table
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local LibEditMode = LibStub('LibEditMode')
local LSM = LibStub('LibSharedMedia-3.0')

---@class ChatModule: AceModule
local chat = addon:NewModule('Chat', 'AceEvent-3.0')

local Sources = addon.ChatSources
local Rules = addon.ChatRules
local Grouping = addon.ChatGrouping
local Input = addon.ChatInput

--#region ── Constants ────────────────────────────────────────────────────────

local FALLBACK_FONT = 'Interface/AddOns/CouchMode/Resources/Fonts/BebasNeue-Regular.ttf'
local PAD = 8
local FILTER_BAR_H = 22
local INPUT_STRIP_H = 28
local PANEL_ORDER = 10
local PANEL_CHROME_HEIGHT = (PAD + FILTER_BAR_H + PAD) + (PAD + INPUT_STRIP_H + PAD)
local MIN_LIVE_PANEL_HEIGHT = PANEL_CHROME_HEIGHT + 20
local DEFAULT_HISTORY_HEIGHT = 400
local DEFAULT_MAX_HEIGHT = 400

local DEFAULT_TEXT_COLOR = { r = 1, g = 0.82, b = 0 }

--#endregion

--#region ── State ─────────────────────────────────────────────────────────────

chat.session = {}         ---@type ChatMessage[] accepted this login
chat.groups = {}          ---@type ChatGroup[]
chat.lastGroup = nil      ---@type ChatGroup?
chat.lastVisible = nil    ---@type ChatMessage?

chat.identByGuid = {}     ---@type table<string, table>
chat.unitByGuid = {}      ---@type table<string, string>
chat.guildByName = {}     ---@type table<string, string>
chat.guildRosterBuilt = false
chat.inspectingGuid = nil ---@type string?
chat.inspectQueue = {}    ---@type {unit:string, guid:string}[]

chat.panel = nil          ---@type Frame?
chat.feed = nil
chat.filterBtns = {}      ---@type table<string, Button>
chat.returnButton = nil   ---@type Button?
chat.lastActivity = 0
chat.fadeAlpha = 1
chat.tabsAlpha = 0
chat.inputAlpha = 0
chat.hovering = false
chat.suppressed = nil     ---@type table<Frame, table>?

--#endregion

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

--#region ── Lifecycle ─────────────────────────────────────────────────────────

function chat:OnInitialize()
    addon.Chat = self
end

function chat:IsSubscriberEnabled()
    return db().enabled == true
end

--- Registers an event only when the running client defines it, so flavor-
--- specific events never throw from RegisterEvent.
---@param event string
---@param handler string|fun(...)
function chat:RegisterValidEvent(event, handler)
    local Utils = addon.Utils
    if Utils and Utils.EventExists and Utils.EventExists(event) == false then return end
    self:RegisterEvent(event, handler)
end

function chat:OnEnable()
    if not db().enabled then
        self:Disable(); return
    end

    self:BuildPanel()
    addon.ChatRouter:Subscribe(self)

    self:RegisterValidEvent('UPDATE_CHAT_WINDOWS', 'ApplyBlizzardSuppression')
    self:RegisterValidEvent('PLAYER_ENTERING_WORLD', 'OnPlayerEnteringWorld')
    self:RegisterValidEvent('GUILD_ROSTER_UPDATE', function() self.guildRosterBuilt = false end)
    self:RegisterValidEvent('INSPECT_READY', 'OnInspectReady')
    self:RegisterValidEvent('PLAYER_REGEN_ENABLED', 'ProcessInspectQueue')
    self:RegisterValidEvent('PLAYER_LOGOUT', 'OnLogout')

    self:SuppressBlizzard()
    Input:Attach(self.panel, self.inputStrip)
    self.blockCheck = function(msg) return chat:ApplyBlockFilter(msg) end
    addon.ChatRouter.blockCheck = self.blockCheck
    self:InstallSuppressionHooks()
    -- Blizzard may (re)show frames during login; re-apply once the UI settles.
    C_Timer.After(1, function()
        if db().enabled then chat:SuppressBlizzard() end
    end)
    self:Touch()
end

--- Reapplies suppression whenever Blizzard pops up a new chat window.
function chat:InstallSuppressionHooks()
    if self.suppressionHooked then return end
    self.suppressionHooked = true
    if FCF_OpenTemporaryWindow then
        hooksecurefunc('FCF_OpenTemporaryWindow', function()
            C_Timer.After(0, function()
                if db().enabled then chat:SuppressBlizzard() end
            end)
        end)
    end
end

--- Restores Blizzard's UI when the addon is unloaded (logout/reload).
function chat:OnLogout()
    Input:Detach()
    self:RestoreBlizzard()
end

function chat:OnDisable()
    addon.ChatRouter:Unsubscribe(self)
    self:UnregisterEvent('UPDATE_CHAT_WINDOWS')
    self:UnregisterEvent('PLAYER_ENTERING_WORLD')
    self:UnregisterEvent('GUILD_ROSTER_UPDATE')
    self:UnregisterEvent('INSPECT_READY')
    self:UnregisterEvent('PLAYER_REGEN_ENABLED')
    self:UnregisterEvent('PLAYER_LOGOUT')

    Input:Detach()
    self:RestoreBlizzard()
    if addon.ChatRouter.blockCheck == self.blockCheck then
        addon.ChatRouter.blockCheck = nil
    end
    self.blockCheck = nil
    if self.panel then self.panel:Hide() end
end

function chat:OnPlayerEnteringWorld()
    self:ClearSession()
    if db().enabled then self:SuppressBlizzard() end
end

--#endregion

--#region ── Blizzard suppression ───────────────────────────────────────────────

local function iterSuppressedFrames()
    local frames = {}
    local count = NUM_CHAT_WINDOWS or 10
    for i = 1, count do
        local frame = _G['ChatFrame' .. i]
        if frame then
            frames[#frames + 1] = frame
            frames[#frames + 1] = _G['ChatFrame' .. i .. 'Tab']
            frames[#frames + 1] = _G['ChatFrame' .. i .. 'ButtonFrame']
            frames[#frames + 1] = _G['ChatFrame' .. i .. 'Minimized']
            frames[#frames + 1] = _G['ChatFrame' .. i .. 'ScrollToBottomButton']
        end
    end
    frames[#frames + 1] = _G['GeneralDockManager']
    frames[#frames + 1] = _G['ChatFrameMenuButton']
    frames[#frames + 1] = _G['QuickJoinToastButton']
    frames[#frames + 1] = _G['ChatMenu']

    local filtered = {}
    for i = 1, #frames do
        if frames[i] then filtered[#filtered + 1] = frames[i] end
    end
    return filtered
end

--- Hides Blizzard's visible chat without touching its saved window settings.
function chat:SuppressBlizzard()
    self.suppressed = self.suppressed or {}
    for _, frame in ipairs(iterSuppressedFrames()) do
        if not self.suppressed[frame] then
            self.suppressed[frame] = {
                alpha = frame:GetAlpha(),
                mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or false,
            }
        end
        frame:SetAlpha(0)
        if frame.EnableMouse then frame:EnableMouse(false) end
    end
end
chat.ApplyBlizzardSuppression = chat.SuppressBlizzard

--- Restores every frame previously suppressed to its saved state.
function chat:RestoreBlizzard()
    if not self.suppressed then return end
    for frame, state in pairs(self.suppressed) do
        if frame.SetAlpha then frame:SetAlpha(state.alpha) end
        if frame.EnableMouse then frame:EnableMouse(state.mouse) end
    end
    self.suppressed = nil
end

--#endregion

--#region ── Panel construction ─────────────────────────────────────────────────

local function fetchFont(face)
    return LSM:Fetch(LSM.MediaType.FONT, face) or FALLBACK_FONT
end

--- Resolved font metrics for the three text fields, passed to the feed.
---@return table
function chat:FontMetrics()
    return {
        msg     = { face = fetchFont(db().msgFontFace),     size = db().msgFontSize },
        name    = { face = fetchFont(db().nameFontFace),    size = db().nameFontSize },
        channel = { face = fetchFont(db().channelFontFace), size = db().channelFontSize },
    }
end

function chat:BuildFilterBar(parent)
    local bar = CreateFrame('Frame', nil, parent)
    bar:SetPoint('TOPLEFT', parent, 'TOPLEFT', PAD, -PAD)
    bar:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', -PAD, -PAD)
    bar:SetHeight(FILTER_BAR_H)
    bar:EnableMouse(true)
    bar:SetAlpha(0)

    local prev
    for _, filter in ipairs(Sources.FILTERS) do
        local btn = CreateFrame('Button', nil, bar, 'UIPanelButtonTemplate')
        btn:SetSize(64, 20)
        btn:SetText(filter.label)
        if prev then
            btn:SetPoint('LEFT', prev, 'RIGHT', 4, 0)
        else
            btn:SetPoint('LEFT', bar, 'LEFT', 0, 0)
        end
        btn:RegisterForClicks('LeftButtonUp')
        btn:SetScript('OnClick', function() chat:SetFilter(filter.key) end)
        self.filterBtns[filter.key] = btn
        prev = btn
    end
    self.filterBar = bar
    return bar
end

function chat:BuildPanel()
    if self.panel then
        self.panel:Show()
        return
    end

    local frame = CreateFrame('Frame', 'CouchModeChat', UIParent)
    frame:SetSize(db().width, db().historyHeight or DEFAULT_HISTORY_HEIGHT)
    frame:SetScale(db().scale or 1)
    frame:SetFrameStrata('LOW')
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    local bg = frame:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    frame.bg = bg

    self:BuildFilterBar(frame)

    local scrollArea = CreateFrame('Frame', nil, frame)
    scrollArea:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, -(PAD + FILTER_BAR_H + PAD))
    scrollArea:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PAD, PAD + INPUT_STRIP_H + PAD)
    self.scrollArea = scrollArea

    self.feed = addon.ChatFeedProto.New(scrollArea)
    self.feed:SetFonts(self:FontMetrics())
    self.feed.onScrollChanged = function() chat:OnFeedChanged() end

    local strip = CreateFrame('Frame', nil, frame)
    strip:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', PAD, PAD)
    strip:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PAD, PAD)
    strip:SetHeight(INPUT_STRIP_H)
    local stripBg = strip:CreateTexture(nil, 'BACKGROUND')
    stripBg:SetAllPoints()
    stripBg:SetColorTexture(0, 0, 0, 0.4)
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
        eb:HookScript('OnEditFocusGained', function() chat:Touch() end)
        eb:HookScript('OnEditFocusLost', function() chat:Touch() end)
    end

    LibEditMode:AddFrame(frame, function(_, layoutName, point, x, y)
        db().positions[layoutName] = { point = point, x = x, y = y }
    end, { point = 'BOTTOMLEFT', x = 40, y = 220 }, 'CouchMode Chat')

    LibEditMode:AddFrameSettings(frame, {
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Width', desc = 'Panel width in pixels.',
            default = 520, minValue = 240, maxValue = 1200, valueStep = 10,
            get = function() return db().width end,
            set = function(_, value, fromReset)
                db().width = (fromReset and 520 or value)
                chat:ApplyLayout(true)
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'History Height', desc = 'Panel height while hovering or scrolling through history.',
            default = DEFAULT_HISTORY_HEIGHT, minValue = 300, maxValue = 900, valueStep = 10,
            get = function() return db().historyHeight end,
            set = function(_, value, fromReset)
                db().historyHeight = (fromReset and DEFAULT_HISTORY_HEIGHT or value)
                chat:ApplyLayout(true)
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Live Maximum Height', desc = 'Largest automatic height of the live message feed.',
            default = DEFAULT_MAX_HEIGHT, minValue = 150, maxValue = 900, valueStep = 10,
            get = function() return db().maxHeight end,
            set = function(_, value, fromReset)
                db().maxHeight = (fromReset and DEFAULT_MAX_HEIGHT or value)
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
                if chat.panel then chat.panel.bg:SetColorTexture(0, 0, 0, db().backgroundOpacity) end
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
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'History Cap', desc = 'Messages retained for the current login.',
            default = 500, minValue = 50, maxValue = 2000, valueStep = 50,
            get = function() return db().historyCap end,
            set = function(_, value, fromReset)
                db().historyCap = (fromReset and 500 or value)
                while #chat.session > db().historyCap do table.remove(chat.session, 1) end
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
            frame:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 40, 220)
        end
    end)

    frame:Show()
    self.panel = frame
    self:ApplyLayout()
    self:RefreshFilterButtons()
    self:Recompute()
end

function chat:ApplyLayout(rebuild, panelHeight, animate)
    local frame = self.panel
    if not frame then return end
    panelHeight = math.max(panelHeight or db().historyHeight or DEFAULT_HISTORY_HEIGHT, MIN_LIVE_PANEL_HEIGHT)
    frame:SetSize(db().width, panelHeight)
    frame:SetScale(db().scale or 1)
    frame.bg:SetColorTexture(0, 0, 0, db().backgroundOpacity)

    local viewport = panelHeight - PANEL_CHROME_HEIGHT
    self.feed:SetWidth(db().width - PAD * 2)
    self.feed:SetLiveContentLimit(math.max(
        (db().maxHeight or DEFAULT_MAX_HEIGHT) - PANEL_CHROME_HEIGHT - PAD * 2, 0))
    self.feed:SetViewportHeight(math.max(viewport, 20), animate)

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
    self[stateKey] = current
    region:SetAlpha(current)
end

--- Applies either the fixed history height or the content-sized live height.
function chat:UpdatePanelSize()
    if self.updatingPanelSize or not self.panel or not self.feed then return end

    local historyVisible = self.feed:IsHistoryVisible()
    local contentHeight = self.feed:GetVisibleContentHeight()
    local targetHeight = historyVisible and (db().historyHeight or DEFAULT_HISTORY_HEIGHT)
        or math.max(MIN_LIVE_PANEL_HEIGHT, contentHeight + PANEL_CHROME_HEIGHT + PAD * 2)
    local currentHeight = self.panel:GetHeight() or 0
    if math.abs(currentHeight - targetHeight) < 0.5 then
        self.feed:FinishLayoutTransaction()
        return
    end

    self.updatingPanelSize = true
    self:ApplyLayout(false, targetHeight, not historyVisible)
    if not historyVisible then self.feed:ScrollToBottom(true) end
    self.updatingPanelSize = false
end

function chat:UpdateFade(dt)
    if not self.panel then return end
    local hovering = self.panel.IsMouseOver and self.panel:IsMouseOver() or false
    if hovering ~= self.hovering then
        self.hovering = hovering
        self.feed:SetHistoryPreview(hovering)
        if hovering and not self.feed:IsBrowsingHistory() then self.feed:ScrollToBottom(true) end
        self:Touch()
    end
    local now = (type(GetTime) == 'function') and GetTime() or 0
    local historyVisible = self.feed and self.feed:IsHistoryVisible()
    local hasVisibleMessages = self.feed and self.feed:UpdateMessageFade(
        now, db().fadeDelay or 15, db().fadeEnabled == true and not historyVisible
    ) or false
    self:UpdatePanelSize()
    local tabsHovered = self.filterBar and self.filterBar:IsMouseOver()
    local inputFocused = Input:HasFocus()

    -- The filter controls are discoverable from their own hover region, while
    -- the input strip only exists while Blizzard's edit box is active.
    self:FadeRegion(self.filterBar, 'tabsAlpha', tabsHovered and 1 or 0, dt)
    self:FadeRegion(self.inputStrip, 'inputAlpha', inputFocused and 1 or 0, dt)

    -- Individual lines expire from their own receive times. The panel remains
    -- active while a line, tab interaction, or focused input is visible.
    local target = db().activeOpacity
    if db().fadeEnabled and not historyVisible and not hasVisibleMessages and not tabsHovered and not inputFocused then
        target = db().backgroundOpacity
    end
    local current = self.fadeAlpha
    local diff = target - current
    if math.abs(diff) < 0.01 then
        self.fadeAlpha = target
    else
        self.fadeAlpha = current + diff * math.min(dt * 6, 1)
    end
    self.panel:SetAlpha(self.fadeAlpha)
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
        btn:GetFontString():SetTextColor(active and 1 or 0.55, active and 1 or 0.55, active and 1 or 0.55, 1)
        if active then btn:LockHighlight() else btn:UnlockHighlight() end
    end
end

--#endregion

--#region ── Identity ──────────────────────────────────────────────────────────

local function isSecret(value)
    local fn = issecretvalue
    return fn ~= nil and fn(value)
end

local function findUnitTokenByGUID(guid)
    if not guid then return nil end
    if UnitGUID('player') == guid then return 'player' end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local isRaid = IsInRaid and IsInRaid()
    for i = 1, n do
        local token = isRaid and ('raid' .. i) or ('party' .. i)
        if UnitGUID(token) == guid then return token end
    end
end

function chat:ResolveUnit(msg)
    if not msg.guid then return nil end
    local cached = self.unitByGuid[msg.guid]
    if cached ~= nil and cached ~= false then return cached end
    local token = findUnitTokenByGUID(msg.guid) or (UnitTokenFromGUID and UnitTokenFromGUID(msg.guid))
    self.unitByGuid[msg.guid] = token or false
    return token
end

function chat:ResolveIdentity(msg)
    if not msg.guid or isSecret(msg.guid) then return nil end
    local id = self.identByGuid[msg.guid]
    if id then return id end

    local localizedClass, classFile, localizedRace, raceFile, sex = GetPlayerInfoByGUID(msg.guid)
    if (issecretvalue and issecretvalue(localizedClass)) then return nil end
    if not classFile then return nil end

    id = {
        class = localizedClass,
        classFile = classFile,
        race = localizedRace,
        raceFile = raceFile,
        sex = sex,
    }
    self.identByGuid[msg.guid] = id
    return id
end

function chat:BuildGuildRoster()
    if self.guildRosterBuilt then return end
    self.guildRosterBuilt = true
    if not (GetNumGuildMembers and GetGuildInfo) then return end
    local guild = GetGuildInfo('player')
    if not guild then return end
    local count = GetNumGuildMembers() or 0
    for i = 1, count do
        local name = GetGuildRosterInfo(i)
        if name then
            local base = Rules.SplitName(name)
            if base then self.guildByName[string.lower(base)] = guild end
        end
    end
end

--- Best-effort guild lookup for a message sender.
---@param msg ChatMessage
---@param unit string?
---@return string?
function chat:ResolveGuild(msg, unit)
    if unit and unit ~= 'player' and UnitIsPlayer and UnitIsPlayer(unit) and GetGuildInfo then
        local guild = GetGuildInfo(unit)
        if guild and not isSecret(guild) then return guild end
    end
    if not msg.sender or isSecret(msg.sender) then return nil end
    self:BuildGuildRoster()
    local base = Rules.SplitName(msg.sender)
    if base then return self.guildByName[string.lower(base)] end
end

--#endregion

--#region ── Enrichment / inspect ────────────────────────────────────────────────

local function safeCall(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end

function chat:Enrich(msg)
    if Sources.IsNpc(msg.event) then
        if not msg.npcId and msg.sender and not isSecret(msg.sender) and addon.BanterData then
            local id, displayId = addon.BanterData.GetByName(msg.sender)
            msg.npcId, msg.displayId = id, displayId
        end
        if not msg.displayId and msg.guid then
            msg.unitToken = self:ResolveUnit(msg)
        end
        return
    end

    if msg.guid then
        local id = self:ResolveIdentity(msg)
        if id then
            msg.classFile = id.classFile
            msg.class = id.class
            msg.raceFile = id.raceFile
            msg.sex = id.sex
        end
        msg.unitToken = self:ResolveUnit(msg)
    end
end

function chat:CanInspect(unit)
    if not unit then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    if CanInspect and not CanInspect(unit) then return false end
    return true
end

function chat:EnqueueInspect(unit, guid)
    if not db().specEnrichment or not unit or not guid then return end
    if not (NotifyInspect and GetInspectSpecialization) then return end
    local id = self.identByGuid[guid]
    if id and id.spec then return end
    if not self:CanInspect(unit) then return end
    if self.inspectingGuid then
        self.inspectQueue[#self.inspectQueue + 1] = { unit = unit, guid = guid }
        return
    end
    self.inspectingGuid = guid
    NotifyInspect(unit)
end

function chat:ProcessInspectQueue()
    if self.inspectingGuid then return end
    if not NotifyInspect then return end
    local nextEntry = table.remove(self.inspectQueue, 1)
    if nextEntry and self:CanInspect(nextEntry.unit) then
        self.inspectingGuid = nextEntry.guid
        NotifyInspect(nextEntry.unit)
    end
end

function chat:OnInspectReady(event, guid)
    if isSecret(guid) then self.inspectingGuid = nil; return end
    local unit = self.unitByGuid[guid] or (UnitTokenFromGUID and UnitTokenFromGUID(guid))
    if unit and guid == UnitGUID(unit) and GetInspectSpecialization and GetSpecializationInfoByID then
        local specID = GetInspectSpecialization(unit)
        local _, name, _, icon = GetSpecializationInfoByID(specID)
        if icon then
            local id = self.identByGuid[guid]
            if id then
                id.spec = { name = name, icon = icon }
                -- Class colors remain authoritative; only the badge refreshes.
                self:RefreshVisibleIcons()
            end
        end
    end
    self.inspectingGuid = nil
    C_Timer.After(0.1, function() self:ProcessInspectQueue() end)
end

--#endregion

--#region ── Text reveal ────────────────────────────────────────────────────────

--- Cancels any in-flight reveal animation on a FontString.
---@param fs FontString
function chat:CancelReveal(fs)
    if fs and fs._revealTicker then
        fs._revealTicker:Cancel()
        fs._revealTicker = nil
    end
end

--- Cancels a header fade in flight.
---@param fs FontString
function chat:CancelTextFade(fs)
    if fs and fs._fadeTicker then
        fs._fadeTicker:Cancel()
        fs._fadeTicker = nil
    end
end

--- Fades a channel/name label in over `duration` seconds. Gated by the same
--- setting as message reveal; skips text that has already been faded in so
--- re-renders (appending to a group) never replay the animation.
---@param fs FontString
---@param duration number?
function chat:FadeInText(fs, duration)
    if not fs then return end
    self:CancelTextFade(fs)

    local text = fs:GetText() or ''
    if not db().revealText then
        fs._fadedText = text
        fs:SetAlpha(1)
        return
    end
    if fs._fadedText == text then return end
    fs._fadedText = text

    duration = duration or 0.25
    local step = 0.02
    local elapsed = 0
    fs:SetAlpha(0)
    fs._fadeTicker = C_Timer.NewTicker(step, function()
        elapsed = elapsed + step
        local t = math.min(elapsed / duration, 1)
        fs:SetAlpha(t)
        if t >= 1 then
            chat:CancelTextFade(fs)
            fs:SetAlpha(1)
        end
    end)
end

--- Sets a FontString's full text immediately, cancelling any reveal in flight.
---@param fs FontString
---@param text string?
function chat:SetTextPlain(fs, text)
    self:CancelReveal(fs)
    fs:SetText(text or '')
end

--- Returns the byte position at which the next reveal step may safely end.
--- Hyperlinks contain WoW markup (for example `|c...|Hitem:...|h[name]|h|r`)
--- that only renders as a link when FontString receives the complete sequence.
--- Keep that sequence in one reveal step so partial markup is never displayed.
---@param text string
---@param start number  first byte of the next reveal step
---@return number
local function nextRevealEnd(text, start)
    local linkStart = start

    -- A standard hyperlink is usually wrapped in a 10-byte |cAARRGGBB code.
    -- Treat the wrapper as part of its link so the color control code is never
    -- revealed by itself.
    local prefix = text:sub(start, start + 9)
    if prefix:match('^|[cC]%x%x%x%x%x%x%x%x') then
        linkStart = start + 10
    end

    if text:sub(linkStart, linkStart + 1) ~= '|H' then
        return start
    end

    local firstClose = text:find('|h', linkStart + 2, true)
    if not firstClose then return start end
    local secondClose = text:find('|h', firstClose + 2, true)
    if not secondClose then return start end

    local linkEnd = secondClose + 1
    if text:sub(linkEnd + 1, linkEnd + 2):lower() == '|r' then
        linkEnd = linkEnd + 2
    end
    return linkEnd
end

--- Reveals `text` character-by-character when the setting is on. Fonts and
--- width must already be applied; callers measure the returned/current height
--- with the full text before calling this. Hyperlinks are revealed atomically.
---@param fs FontString
---@param text string?
function chat:Reveal(fs, text)
    if not fs then return end
    self:CancelReveal(fs)
    text = text or ''

    if not db().revealText or isSecret(text) then
        fs._revealedText = text
        fs:SetText(text)
        return
    end

    -- Already fully revealed: leave it alone (rebuilds must not re-animate).
    if fs._revealedText == text and fs:GetText() == text then return end
    fs._revealedText = text

    local total = #text
    if total == 0 then
        fs:SetText('')
        return
    end

    local speed = math.max(db().revealSpeed or 44, 1)
    local shown = 0
    fs:SetText('')
    fs._revealTicker = C_Timer.NewTicker(1 / speed, function()
        shown = nextRevealEnd(text, shown + 1)
        if shown >= total then
            chat:CancelReveal(fs)
            fs:SetText(text)
        else
            fs:SetText(text:sub(1, shown))
        end
    end)
end

--#endregion

--#region ── Styling (called by the feed) ────────────────────────────────────────

---@param group ChatGroup
---@return boolean
function chat:GroupShowsIdentity(group)
    return true
end

local function chatTypeColor(event)
    local key = Sources.ChatTypeKey(event)
    local info = ChatTypeInfo and ChatTypeInfo[key]
    if info then return info.r, info.g, info.b, 1 end
    local d = DEFAULT_TEXT_COLOR
    return d.r, d.g, d.b, 1
end

local function classColor(classFile)
    if not classFile then return nil end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
end

local function raceAtlas(raceFile, sex)
    if not raceFile or not GetRaceAtlas then return nil end
    local race = string.lower(raceFile):gsub('[^%a]', '')
    local gender = (sex == 3) and 'female' or 'male'
    local ok, atlas = pcall(GetRaceAtlas, race, gender, true)
    if ok then return atlas end
end

local function classAtlasCoords(classFile)
    if not classFile or not CLASS_ICON_TCOORDS then return nil end
    return CLASS_ICON_TCOORDS[classFile]
end

--- Applies the group's identity (name, channel, icon).
---@param g Frame
---@param msg ChatMessage
---@return boolean hasIcon  whether an icon was drawn
function chat:StyleIdentity(g, msg)
    local name = msg.sender or (msg.category == 'SYSTEM' and 'System') or msg.type or ''
    self:SetTextPlain(g.name, name)
    g.name:SetFont(fetchFont(db().nameFontFace), db().nameFontSize, 'OUTLINE')

    local class = msg.classFile or (msg.guid and self:ResolveIdentity(msg) and self.identByGuid[msg.guid].classFile)
    local cc = classColor(class)
    if cc then
        g.name:SetTextColor(cc.r, cc.g, cc.b, 1)
    else
        local r, gg, b = chatTypeColor(msg.event)
        g.name:SetTextColor(r, gg, b, 1)
    end

    local alias = Rules.ResolveAlias(db().aliases, Sources.ChatTypeKey(msg.event), msg.channelBase)
    local r, gg, b = chatTypeColor(msg.event)
    self:SetTextPlain(g.channel, alias or (msg.category == 'SYSTEM' and ''
        or (msg.channelBase or Sources.DisplayType(msg.event))))
    g.channel:SetFont(fetchFont(db().channelFontFace), db().channelFontSize, 'OUTLINE')
    g.channel:SetTextColor(r, gg, b, 0.85)

    -- 2D icon selection only: no 3D models in the feed.
    g.icon:Hide()
    g.iconBorder:Hide()
    g.spec:Hide()

    local unit = msg.unitToken or (msg.guid and self:ResolveUnit(msg))
    local displayId = msg.displayId

    -- Resolve which 2D image to show, and a cache key so repeated rebuilds do
    -- not re-render the same portrait every time.
    local iconKey, apply
    if msg.category == 'NPC' then
        if displayId and displayId > 0 and SetPortraitTextureFromCreatureDisplayID then
            iconKey = 'd:' .. displayId
            apply = function() SetPortraitTextureFromCreatureDisplayID(g.icon, displayId) end
        elseif unit and SetPortraitTexture then
            iconKey = 'u:' .. unit
            apply = function() SetPortraitTexture(g.icon, unit) end
        end
    elseif msg.category == 'SYSTEM' then
        iconKey = ('c:%d:%d:%d'):format(math.floor(r * 100), math.floor(gg * 100), math.floor(b * 100))
        apply = function()
            g.icon:SetTexture(nil)
            g.icon:SetColorTexture(r, gg, b, 0.9)
        end
    elseif unit and SetPortraitTexture then
        iconKey = 'u:' .. unit
        apply = function() SetPortraitTexture(g.icon, unit) end
    else
        local atlas = raceAtlas(msg.raceFile or (self:ResolveIdentity(msg) or {}).raceFile, msg.sex)
        local coords = classAtlasCoords(class)
        if atlas then
            iconKey = 'a:' .. atlas
            apply = function() g.icon:SetAtlas(atlas) end
        elseif coords then
            iconKey = 'k:' .. tostring(class)
            apply = function()
                g.icon:SetTexture('Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes')
                g.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
        end
    end

    local shown = false
    if iconKey then
        if g._iconKey ~= iconKey then
            apply()
            g._iconKey = iconKey
        end
        g.icon:Show()
        g.iconBorder:Show()
        shown = true
    else
        g._iconKey = nil
    end

    -- Specialization badge.
    local id = msg.guid and self.identByGuid[msg.guid]
    if shown and id and id.spec and id.spec.icon then
        g.spec:SetTexture(id.spec.icon)
        g.spec:Show()
    end

    if unit then
        self:EnqueueInspect(unit, msg.guid)
    end

    return shown
end

---@param fs FontString
---@param msg ChatMessage
---@param isFirst boolean
function chat:StyleLine(fs, msg, isFirst)
    local r, g, b = chatTypeColor(msg.event)
    fs:SetTextColor(r, g, b, 1)
end

function chat:RefreshVisibleIcons()
    if self.panel and self.feed then self:Recompute() end
end

--#endregion

--#region ── Session / routing ──────────────────────────────────────────────────

--- Enriches a message and applies local blocking rules.
--- Returns true when the message should be dropped entirely.
---@param msg ChatMessage
---@return boolean blocked
function chat:ApplyBlockFilter(msg)
    self:Enrich(msg)
    local unit = msg.unitToken or (msg.guid and self:ResolveUnit(msg)) or nil
    local guild = self:ResolveGuild(msg, unit)
    if Rules.IsBlocked(db().blocks, msg, guild) then
        msg.blocked = true
        return true
    end
    msg.guild = guild
    return false
end

function chat:ClearSession()
    wipe(self.session)
    self.groups = {}
    self.lastGroup = nil
    self.lastVisible = nil
    if self.feed then self.feed:Clear() end
end

---@param msg ChatMessage
function chat:ChatMessage(msg)
    if not db().enabled then return end

    if self:ApplyBlockFilter(msg) then return end

    -- Alerts (Talking Head suppression and similar) happen after blocking.
    self.session[#self.session + 1] = msg

    local cap = db().historyCap or 500
    if #self.session > cap then
        local overflow = #self.session - cap
        for _ = 1, overflow do table.remove(self.session, 1) end
        self:Recompute()
        self:Touch()
        return
    end

    if not Sources.MatchesFilter(msg, db().filter) then
        return
    end

    local followBottom = self.feed and not self.feed:IsBrowsingHistory()
    if self.lastVisible and Grouping.ShouldGroup(self.lastVisible, msg, db().groupWindow) and self.lastGroup then
        self.lastGroup.messages[#self.lastGroup.messages + 1] = msg
        if self.feed then self.feed:RefreshLastGroup(self.lastGroup) end
    else
        local group = { messages = { msg } }
        self.groups[#self.groups + 1] = group
        self.lastGroup = group
        if self.feed then self.feed:AppendGroup(group) end
    end
    self.lastVisible = msg

    if self.feed then
        if followBottom then self.feed:ScrollToBottom(true) end
        self:OnFeedChanged()
    end
    self:Touch()
end

function chat:Recompute()
    local preserveBrowse = self.feed and self.feed:IsBrowsingHistory()
    local previousOffset = preserveBrowse and self.feed:GetScrollOffset() or 0
    local previousContentHeight = preserveBrowse and self.feed:GetContentHeight() or 0
    local filtered = {}
    for i = 1, #self.session do
        local msg = self.session[i]
        if Sources.MatchesFilter(msg, db().filter) then
            filtered[#filtered + 1] = msg
        end
    end
    local groups = Grouping.Build(filtered, db().groupWindow)
    self.groups = groups
    self.lastGroup = groups[#groups]
    self.lastVisible = filtered[#filtered]
    if self.feed then
        self.feed:SetFonts(self:FontMetrics())
        self.feed.showDividers = db().dividers ~= false
        self.feed:Rebuild(groups)
        if preserveBrowse then
            local removedHeight = math.max(previousContentHeight - self.feed:GetContentHeight(), 0)
            self.feed:RestoreScrollOffset(math.max(previousOffset - removedHeight, 0))
        else
            self.feed:ScrollToBottom()
        end
    end
    self:OnFeedChanged()
end

function chat:OnFeedChanged()
    self:UpdatePanelSize()
    if not self.returnButton or not self.feed then return end
    if not self.feed:IsBrowsingHistory() or self.feed:IsAtBottom() then
        self.returnButton:Hide()
    else
        self.returnButton:Show()
    end
end

function chat:ScrollToBottom()
    if self.feed then self.feed:ScrollToBottom() end
    self:OnFeedChanged()
    self:Touch()
end

--#endregion

--#region ── Moderation actions ─────────────────────────────────────────────────

function chat:BlockName(name)
    if Rules.AddName(db().blocks, name) then
        self:Recompute()
        self:NotifyChange()
    end
end

function chat:BlockGuild(guild)
    if Rules.AddGuild(db().blocks, guild) then
        self:Recompute()
        self:NotifyChange()
    end
end

local function safeText(text)
    if isSecret(text) then return '' end
    return text or ''
end

function chat:ShowCopyDialog(text)
    if not self.copyDialog then
        local f = CreateFrame('Frame', 'CouchModeChatCopy', UIParent, 'BasicFrameTemplateWithInset')
        f:SetSize(440, 220)
        f:SetPoint('CENTER')
        f:SetFrameStrata('DIALOG')
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag('LeftButton')
        f:SetScript('OnDragStart', f.StartMoving)
        f:SetScript('OnDragStop', f.StopMovingOrSizing)
        f.TitleText:SetText('Copy Message')

        local eb = CreateFrame('EditBox', nil, f, 'InputBoxTemplate')
        eb:SetMultiLine(true)
        eb:SetSize(410, 165)
        eb:SetPoint('TOPLEFT', f, 'TOPLEFT', 14, -40)
        eb:SetAutoFocus(true)
        eb:SetScript('OnChar', function() end) -- read-only: block edits, allow selection
        eb:SetScript('OnEscapePressed', function() f:Hide() end)
        f.edit = eb
        self.copyDialog = f
    end
    self.copyDialog.edit:SetText(safeText(text))
    self.copyDialog.edit:HighlightText()
    self.copyDialog:Show()
end

---@param g Frame
function chat:ShowGroupMenu(g)
    local group = g.groupData
    if not group or not MenuUtil then return end
    local msg = group.messages[1]
    local name = msg.sender
    MenuUtil.CreateContextMenu(g, function(_, root)
        root:CreateTitle(name or Sources.FilterLabel(msg.category))
        root:CreateButton('Copy message', function() chat:ShowCopyDialog(msg.text) end)
        if name and msg.category ~= 'SYSTEM' then
            root:CreateButton('Whisper', function()
                if ChatFrameUtil and ChatFrameUtil.OpenChat then
                    ChatFrameUtil.OpenChat(SLASH_SMART_WHISPER1 .. ' ' .. name .. ' ')
                else
                    chat:FocusInput()
                end
            end)
            root:CreateButton('Block ' .. name, function() chat:BlockName(name) end)
            if C_FriendList and C_FriendList.AddIgnore then
                root:CreateButton('Ignore ' .. name, function() C_FriendList.AddIgnore(name) end)
            end
        end
        local guild = msg.guild or chat:ResolveGuild(msg, msg.unitToken)
        if guild then
            root:CreateButton('Block guild ' .. guild, function() chat:BlockGuild(guild) end)
        end
    end)
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

--#region ── Defaults ─────────────────────────────────────────────────────────

function chat:GetDefaults()
    return {
        chat = {
            enabled = true,
            -- Position (per Edit Mode layout)
            positions = {},
            -- Sizing / appearance
            width = 520,
            historyHeight = DEFAULT_HISTORY_HEIGHT,
            maxHeight = DEFAULT_MAX_HEIGHT,
            scale = 1,
            activeOpacity = 1,
            backgroundOpacity = 0,
            fadeEnabled = true,
            fadeDelay = 15,
            -- Text (each field is independently configurable)
            channelFontFace = 'Arial Narrow',
            channelFontSize = 11,
            nameFontFace = 'Arial Narrow',
            nameFontSize = 14,
            msgFontFace = 'Arial Narrow',
            msgFontSize = 14,
            -- Character-by-character reveal (same behaviour as Chat Bubbles)
            revealText = true,
            revealSpeed = 44,
            -- Divider between messages
            dividers = true,
            -- History
            historyCap = 500,
            groupWindow = 60,
            filter = 'ALL',
            -- Identity
            specEnrichment = true,
            -- Moderation / cosmetics
            blocks = { names = {}, guilds = {} },
            aliases = {},
        },
        -- Bumped by ChatMigration; a value below CURRENT_VERSION runs migration.
        schemaVersion = 1,
    }
end

--#endregion

--#region ── Options ──────────────────────────────────────────────────────────

function chat:NotifyChange()
    local registry = LibStub('AceConfigRegistry-3.0', true)
    if registry then registry:NotifyChange(addonName) end
end

function chat:BuildBlockedList()
    local values = {}
    local blocks = db().blocks
    for i = 1, #(blocks.names or {}) do
        local name = blocks.names[i]
        values['name:' .. name] = 'Unblock ' .. name
    end
    for i = 1, #(blocks.guilds or {}) do
        local guild = blocks.guilds[i]
        values['guild:' .. guild] = 'Unblock guild ' .. guild
    end
    if next(values) == nil then
        values['__none'] = 'No blocked players or guilds'
    end
    return values
end

function chat:ApplyBlockedList(_)
    -- (Re)build the dynamic dropdown entries.
    if not self.optionsArgs or not self.optionsArgs.moderation then return end
    local args = self.optionsArgs.moderation.args
    args.blocked.values = function() return chat:BuildBlockedList() end
    args.blocked.get = function() return '__none' end
    args.blocked.set = function(_, value)
        local kind, key = value:match('^(%a+):(.+)$')
        if kind == 'name' then
            Rules.RemoveName(db().blocks, key)
        elseif kind == 'guild' then
            Rules.RemoveGuild(db().blocks, key)
        end
        chat:Recompute()
        chat:NotifyChange()
    end
end

function chat:BuildAliasList()
    local values = {}
    local aliases = db().aliases
    local any = false
    for key, alias in pairs(aliases) do
        values[key] = alias .. '  (' .. key .. ')'
        any = true
    end
    if not any then values['__none'] = 'No channel aliases' end
    return values
end

function chat:BuildArgs()
    local args = {
        description = {
            name = 'A full chat replacement: scrollback, filters, identity icons, moderation and channel aliases. '
                .. 'Disabling restores Blizzard chat exactly as it was.',
            type = 'description',
            order = 1,
        },
        enabled = {
            name = 'Enable',
            desc = 'Replace Blizzard chat with the CouchMode Chat feed.',
            type = 'toggle',
            order = 2,
            get = function() return db().enabled end,
            set = function(_, value)
                db().enabled = value
                if value then chat:Enable() else chat:Disable() end
            end,
        },
        open = {
            name = 'Open Chat',
            desc = 'Focus the CouchMode chat input.',
            type = 'execute',
            order = 3,
            func = function() chat:FocusInput() end,
        },
        appearance = {
            name = 'Appearance',
            type = 'group',
            inline = true,
            order = 10,
            args = {
                width = {
                    name = 'Width', desc = 'Panel width in pixels.',
                    type = 'range', min = 240, max = 1200, step = 10, order = 1,
                    get = function() return db().width end,
                    set = function(_, v) db().width = v; chat:ApplyLayout(true) end,
                },
                historyHeight = {
                    name = 'History Height', desc = 'Panel height while hovering or scrolling through history.',
                    type = 'range', min = 300, max = 900, step = 10, order = 2,
                    get = function() return db().historyHeight end,
                    set = function(_, v) db().historyHeight = v; chat:ApplyLayout(true) end,
                },
                maxHeight = {
                    name = 'Live Maximum Height', desc = 'Largest automatic height of the live message feed.',
                    type = 'range', min = 150, max = 900, step = 10, order = 2.5,
                    get = function() return db().maxHeight end,
                    set = function(_, v) db().maxHeight = v; chat:ApplyLayout(true) end,
                },
                scale = {
                    name = 'Scale', desc = 'Overall panel scale.',
                    type = 'range', min = 0.5, max = 2, step = 0.05, order = 3,
                    get = function() return db().scale end,
                    set = function(_, v) db().scale = v; chat:ApplyLayout() end,
                },
                activeOpacity = {
                    name = 'Active Opacity', desc = 'Panel opacity while at least one message is visible.',
                    type = 'range', min = 0.1, max = 1, step = 0.05, order = 4,
                    get = function() return db().activeOpacity end,
                    set = function(_, v) db().activeOpacity = v; chat:Touch() end,
                },
                backgroundOpacity = {
                    name = 'Background Opacity', desc = 'Panel opacity after all visible messages fade.',
                    type = 'range', min = 0, max = 1, step = 0.05, order = 5,
                    get = function() return db().backgroundOpacity end,
                    set = function(_, v) db().backgroundOpacity = v; chat:ApplyLayout() end,
                },
                fadeEnabled = {
                    name = 'Auto-fade', desc = 'Fade each message after its delay, then fade the panel when none remain.',
                    type = 'toggle', order = 6,
                    get = function() return db().fadeEnabled end,
                    set = function(_, v) db().fadeEnabled = v; chat:Touch() end,
                },
                fadeDelay = {
                    name = 'Fade Delay', desc = 'Seconds each message remains visible before fading.',
                    type = 'range', min = 0, max = 60, step = 1, order = 7,
                    get = function() return db().fadeDelay end,
                    set = function(_, v) db().fadeDelay = v; chat:Touch() end,
                },
                channelHeader = { name = 'Channel', type = 'header', order = 8 },
                channelFont = {
                    name = 'Font', desc = 'Font for the channel label.',
                    type = 'select', style = 'dropdown', order = 9,
                    values = addon.Media.GetFontOptions(),
                    get = function() return db().channelFontFace end,
                    set = function(_, v) db().channelFontFace = v; chat:Recompute() end,
                },
                channelSize = {
                    name = 'Font Size', desc = 'Channel label size.',
                    type = 'range', min = 6, max = 28, step = 1, order = 10,
                    get = function() return db().channelFontSize end,
                    set = function(_, v) db().channelFontSize = v; chat:Recompute() end,
                },
                nameHeader = { name = 'Name', type = 'header', order = 11 },
                nameFont = {
                    name = 'Font', desc = 'Font for the speaker name.',
                    type = 'select', style = 'dropdown', order = 12,
                    values = addon.Media.GetFontOptions(),
                    get = function() return db().nameFontFace end,
                    set = function(_, v) db().nameFontFace = v; chat:Recompute() end,
                },
                nameSize = {
                    name = 'Font Size', desc = 'Speaker name size.',
                    type = 'range', min = 6, max = 32, step = 1, order = 13,
                    get = function() return db().nameFontSize end,
                    set = function(_, v) db().nameFontSize = v; chat:Recompute() end,
                },
                msgHeader = { name = 'Message', type = 'header', order = 14 },
                msgFont = {
                    name = 'Font', desc = 'Font for message text.',
                    type = 'select', style = 'dropdown', order = 15,
                    values = addon.Media.GetFontOptions(),
                    get = function() return db().msgFontFace end,
                    set = function(_, v) db().msgFontFace = v; chat:Recompute() end,
                },
                msgSize = {
                    name = 'Font Size', desc = 'Message text size.',
                    type = 'range', min = 8, max = 28, step = 1, order = 16,
                    get = function() return db().msgFontSize end,
                    set = function(_, v) db().msgFontSize = v; chat:Recompute() end,
                },
                revealText = {
                    name = 'Reveal Text',
                    desc = 'Message text reveals character-by-character; the channel and name fade in.',
                    type = 'toggle', order = 17,
                    get = function() return db().revealText end,
                    set = function(_, v) db().revealText = v; chat:Recompute() end,
                },
                revealSpeed = {
                    name = 'Reveal Speed', desc = 'Characters revealed per second.',
                    type = 'range', min = 5, max = 120, step = 1, order = 18,
                    disabled = function() return not db().revealText end,
                    get = function() return db().revealSpeed end,
                    set = function(_, v) db().revealSpeed = v; chat:Recompute() end,
                },
                dividers = {
                    name = 'Dividers', desc = 'Draw an ornamental divider between messages.',
                    type = 'toggle', order = 19,
                    get = function() return db().dividers ~= false end,
                    set = function(_, v) db().dividers = v; chat:Recompute() end,
                },
                historyCap = {
                    name = 'History Cap', desc = 'Maximum messages kept for the current login (not saved).',
                    type = 'range', min = 50, max = 2000, step = 50, order = 20,
                    get = function() return db().historyCap end,
                    set = function(_, v)
                        db().historyCap = v
                        while #chat.session > v do table.remove(chat.session, 1) end
                        chat:Recompute()
                    end,
                },
            },
        },
        identity = {
            name = 'Identity',
            type = 'group',
            inline = true,
            order = 20,
            args = {
                specEnrichment = {
                    name = 'Specialization Badges',
                    desc = 'Throttled, out-of-combat inspects add a specialization badge to player icons.',
                    type = 'toggle',
                    order = 1,
                    get = function() return db().specEnrichment end,
                    set = function(_, v) db().specEnrichment = v end,
                },
            },
        },
        moderation = {
            name = 'Moderation & Aliases',
            type = 'group',
            inline = true,
            order = 30,
            args = {
                blocked = {
                    name = 'Blocked', desc = 'Locally blocked players and guilds.',
                    type = 'select', style = 'dropdown', order = 1,
                    values = function() return chat:BuildBlockedList() end,
                    get = function() return '__none' end,
                    set = function() end,
                },
                blockName = {
                    name = 'Block Player', desc = 'Name or Name-Realm. A bare name matches any realm.',
                    type = 'input', order = 2,
                    get = function() return '' end,
                    set = function(_, v)
                        if v and v ~= '' then chat:BlockName(v) end
                    end,
                },
                blockGuild = {
                    name = 'Block Guild', desc = 'Guild name. Best effort: requires known membership.',
                    type = 'input', order = 3,
                    get = function() return '' end,
                    set = function(_, v)
                        if v and v ~= '' then chat:BlockGuild(v) end
                    end,
                },
                aliasKey = {
                    name = 'Alias Channel', desc = 'Canonical chat type or public channel base name.',
                    type = 'input', order = 4,
                    get = function() return '' end,
                    set = function(_, v) db()._pendingAliasKey = v end,
                },
                aliasName = {
                    name = 'Alias Name', desc = 'Cosmetic label to show for that channel.',
                    type = 'input', order = 5,
                    get = function() return '' end,
                    set = function(_, v)
                        local key = db()._pendingAliasKey
                        if key and key ~= '' and v and v ~= '' then
                            db().aliases[key] = v
                            chat:NotifyChange()
                        end
                    end,
                },
                aliasList = {
                    name = 'Aliases', desc = 'Configured cosmetic channel aliases.',
                    type = 'select', style = 'dropdown', order = 6,
                    values = function() return chat:BuildAliasList() end,
                    get = function() return '__none' end,
                    set = function(_, value)
                        if db().aliases[value] then
                            db().aliases[value] = nil
                            chat:NotifyChange()
                        end
                    end,
                },
            },
        },
        misc = {
            name = 'Misc',
            type = 'group',
            inline = true,
            order = 99,
            args = {
                clear = {
                    name = 'Clear History', desc = 'Clear the current login\'s message history.',
                    type = 'execute', order = 1,
                    func = function() chat:ClearSession() end,
                },
                testMessages = {
                    name = 'Test Messages',
                    desc = 'Fire mock messages for every source into the feed.\n\nAlso available in chat as /cm chat mock [set] and /cm chat sets.',
                    type = 'execute', order = 2,
                    func = function() chat:RunMock('all') end,
                },
            },
        },
    }
    return args
end

function chat:GetOptions()
    self.optionsArgs = self.optionsArgs or self:BuildArgs()
    return 'chat', {
        name = 'Chat',
        type = 'group',
        order = PANEL_ORDER,
        args = self.optionsArgs,
    }
end

function chat:RebuildOptions()
    self:ApplyBlockedList()
end

--#endregion

--#region ── Testing / mock ──────────────────────────────────────────────────────

--- Pushes a message through the router so it lands in the feed like a real
--- system line. Used for feedback that would otherwise be hidden by the
--- Blizzard chat suppression.
---@param text string
function chat:Notify(text)
    if not db().enabled then print('CouchMode: ' .. tostring(text)); return end
    addon.ChatRouter:OnEvent('CHAT_MSG_SYSTEM', text, '', '', '', '', '', 0, 0, '', 0, nil, nil)
end

--- Fires a set of representative mock messages through the real router.
---@param setName string?  'all' or one of addon.ChatMock.Names()
function chat:RunMock(setName)
    if not db().enabled then
        print('CouchMode: enable Chat before running the mock.')
        return
    end
    local mock = addon.ChatMock
    if not mock then return end

    setName = (setName == nil or setName == '') and 'all' or setName
    if setName ~= 'all' and not mock.SETS[setName] then
        chat:Notify(('Unknown mock set "%s". Available: %s, all.')
            :format(setName, table.concat(mock.Names(), ', ')))
        return
    end

    local count = mock.Run(addon.ChatRouter, setName)
    chat:Notify(('Chat mock: fired %d messages from "%s".'):format(count, setName))
end

--- Entry point for `/cm chat ...`.
---@param sub string
---@param arg string
function chat:HandleCommand(sub, arg)
    sub = (sub or ''):lower()
    if sub == 'mock' or sub == 'test' then
        chat:RunMock(arg)
    elseif sub == 'clear' then
        chat:ClearSession()
        chat:Notify('Chat history cleared.')
    elseif sub == 'sets' then
        chat:Notify('Chat mock sets: ' .. table.concat(addon.ChatMock.Names(), ', ') .. ', all')
    else
        chat:Notify('CouchMode Chat: /cm chat mock [set] | /cm chat sets | /cm chat clear')
    end
end

--#endregion

--#region ── Bindings ──────────────────────────────────────────────────────────

function CouchMode_ChatToggle() addon.Chat:Toggle() end
function CouchMode_ChatFocus() addon.Chat:FocusInput() end
function CouchMode_ChatFilterNext() addon.Chat:CycleFilter(1) end
function CouchMode_ChatFilterPrev() addon.Chat:CycleFilter(-1) end
function CouchMode_ChatScrollUp() addon.Chat:ScrollUp() end
function CouchMode_ChatScrollDown() addon.Chat:ScrollDown() end
function CouchMode_ChatBottom() addon.Chat:ScrollToBottom() end
function CouchMode_ChatClose() addon.Chat:ClosePanel() end

--#endregion

chat:Enable()
