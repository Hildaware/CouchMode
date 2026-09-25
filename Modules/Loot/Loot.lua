local addonName, addon = ...

---@class CouchMode: AceAddon
---@field LootSources table
---@field LootFeedProto table
---@field LootMock table
---@field Loot LootModule
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local LibEditMode = LibStub('LibEditMode')

---@class LootModule: AceModule
---@field HandleCommand fun(self: LootModule, sub: string, arg: string)
local loot = addon:NewModule('Loot', 'AceEvent-3.0')

local Sources = addon.LootSources

--#region ── Constants ────────────────────────────────────────────────────────

local PAD = 8
local MIN_HEIGHT = 120
local PANEL_ORDER = 12
local REFRESH_DELAY = 0.25

local DEFAULT_WIDTH = 360
local DEFAULT_HEIGHT = 300

-- Stable palettes for rows that have no item quality of their own.
local NEUTRAL = { r = 0.16, g = 0.16, b = 0.16 }
local MONEY = { r = 0.83, g = 0.68, b = 0.21 }
local REPUTATION = { r = 0.30, g = 0.58, b = 0.95 }
local QUEST = { r = 1, g = 0.82, b = 0 }
local QUEST_ICON_ATLAS = 'QuestNormal'
local REPUTATION_ICON = 'Interface\\Icons\\achievement_reputation_01'

-- Row backgrounds are semi-transparent so the feed behind them shows through.
local ROW_BG_ALPHA = 0.5

--#endregion

--#region ── Module state ──────────────────────────────────────────────────────

loot.session = {}       ---@type LootEntry[]
loot.lastMoney = nil    ---@type number?
loot.panel = nil        ---@type Frame?
loot.feed = nil
loot.returnButton = nil ---@type Button?
loot.fadeAlpha = 1
loot.refreshPending = false
loot.filters = nil      ---@type { event: string, callback: fun(...) }[]?
loot.filtersInstalled = false

--#endregion

--#region ── Small helpers ───────────────────────────────────────────────────────

local function db() return addon.db.profile.loot end

local function now()
    return (type(GetTime) == 'function') and GetTime() or 0
end

--- Reads an item quality's RGB from the client, tolerating older clients.
---@param quality any
---@return number? r
---@return number? g
---@return number? b
local function qualityColor(quality)
    if type(quality) ~= 'number' or Sources.isSecret(quality) then return nil end
    if not (C_Item and C_Item.GetItemQualityColor) then return nil end
    local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
    if ok and type(r) == 'number' and type(g) == 'number' and type(b) == 'number' then
        return r, g, b
    end
    return nil
end

--- Blizzard money formatting, preferring the coin-texture markup.
---@param amount any
---@return string
local function moneyString(amount)
    if type(amount) ~= 'number' then return '' end
    if type(GetCoinTextureString) == 'function' then
        local ok, text = pcall(GetCoinTextureString, amount)
        if ok and type(text) == 'string' then return text end
    end
    if type(GetMoneyString) == 'function' then
        local ok, text = pcall(GetMoneyString, amount)
        if ok and type(text) == 'string' then return text end
    end
    return tostring(amount)
end

--- Formats a plain numeric total with Blizzard's thousands separators when available.
---@param value any
---@return string
local function numberString(value)
    if type(value) ~= 'number' then return tostring(value) end
    if type(BreakUpLargeNumbers) == 'function' then
        local ok, text = pcall(BreakUpLargeNumbers, value)
        if ok and type(text) == 'string' then return text end
    end
    return tostring(value)
end

--- Renders a reputation tier as Blizzard's rep bar does, e.g. "1,000 / 6,000"
--- (or "1,000/6,000" when the localized format string is unavailable).
---@param progress number
---@param progressMax number
---@return string
local function reputationProgressString(progress, progressMax)
    local current = numberString(progress)
    local total = numberString(progressMax)
    local format = _G and _G.REPUTATION_PROGRESS_FORMAT
    if type(format) == 'string' and format ~= '' then
        local ok, text = pcall(string.format, format, current, total)
        if ok and type(text) == 'string' then return text end
    end
    return current .. '/' .. total
end

--- Resolves the localized standing label for a reaction index, using the same
--- gender-aware lookup as the reputation frame (FACTION_STANDING_LABEL<reaction>).
---@param reaction any
---@return string?
local function standingLabel(reaction)
    if type(reaction) ~= 'number' then return nil end
    local key = 'FACTION_STANDING_LABEL' .. reaction
    if type(GetText) == 'function' then
        local gender = (type(UnitSex) == 'function') and UnitSex('player') or 2
        local ok, text = pcall(GetText, key, gender)
        if ok and type(text) == 'string' and text ~= '' then return text end
    end
    local fallback = _G and _G[key]
    if type(fallback) == 'string' and fallback ~= '' then return fallback end
    return nil
end

--- Builds the parenthetical reputation detail: "Friendly 1,000 / 6,000", the
--- label alone for capped factions, the progress alone when no label is known,
--- or nil when nothing can be resolved.
---@param entry LootEntry
---@return string?
local function reputationDetail(entry)
    local label = standingLabel(entry.reaction)
    local progress
    if entry.progress and entry.progressMax and entry.progressMax > 0 then
        progress = reputationProgressString(entry.progress, entry.progressMax)
    end
    if label and progress then return label .. ' ' .. progress end
    return label or progress
end

--#endregion

--#region ── Lifecycle ─────────────────────────────────────────────────────────

function loot:OnInitialize()
    addon.Loot = self
end

--- Registers an event only when the running client defines it.
---@param event string
---@param handler string|fun(...)
---@return boolean registered
function loot:RegisterValidEvent(event, handler)
    return addon.Utils.RegisterEventIfValid(self, event, handler)
end

function loot:OnEnable()
    if not db().enabled then
        self:Disable()
        return
    end

    self:BuildPanel()
    self:SnapshotMoney()
    self:InstallChatFilters()

    for _, event in ipairs(Sources.SUPPORT_EVENTS) do
        local handler = self.EVENT_HANDLERS[event]
        if handler then
            self:RegisterValidEvent(event, handler)
        end
    end

    self:Touch()
end

function loot:OnDisable()
    for _, event in ipairs(Sources.SUPPORT_EVENTS) do
        self:UnregisterEvent(event)
    end
    self:RemoveChatFilters()
    if self.panel then self.panel:Hide() end
end

--#endregion

--#region ── Money snapshot ────────────────────────────────────────────────────

function loot:SnapshotMoney()
    if type(GetMoney) ~= 'function' then return end
    local money = GetMoney()
    if money ~= nil and not Sources.isSecret(money) then
        self.lastMoney = money
    end
end

function loot:OnPlayerEnteringWorld()
    self:SnapshotMoney()
    self:ScheduleRefresh()
end

--#endregion

--#region ── Reward ingestion ──────────────────────────────────────────────────

---@param entry LootEntry
function loot:AddEntry(entry)
    if not db().enabled then return end

    self.session[#self.session + 1] = entry

    local cap = db().historyCap or 200
    local overflow = #self.session - cap
    local atBottom = self.feed and self.feed:IsAtBottom()
    if atBottom then self.feed:ResumeLive() end

    if overflow > 0 then
        for _ = 1, overflow do table.remove(self.session, 1) end
        if self.feed then self.feed:Rebuild(self.session) end
    elseif self.feed then
        self.feed:Append(entry)
    end

    if self.feed then
        if atBottom ~= false then self.feed:ScrollToBottom() end
        self:OnFeedChanged()
    end
    self:Touch()
end

--- CHAT_MSG_LOOT: local-player item acquisitions only.
---@param _event string
---@param text any
function loot:OnLootMessage(_event, text)
    if not db().items then return end
    local entry = Sources.NormalizeItem(text, now())
    if not entry then return end

    -- Name comes from the hyperlink; quality/icon may need the client to load
    -- item data, and the carried count is deferred until bags settle.
    Sources.EnrichItem(entry, { withCount = false })
    entry.needsRefresh = true

    self:AddEntry(entry)
    self:ScheduleRefresh()
end

--- PLAYER_MONEY: consume positive deltas of the GetMoney() snapshot.
function loot:OnPlayerMoney()
    if not db().money then return end
    if type(GetMoney) ~= 'function' then return end

    local current = GetMoney()
    if current == nil or Sources.isSecret(current) then return end

    local previous = self.lastMoney
    self.lastMoney = current
    if previous == nil then return end
    if current <= previous then return end

    local entry = Sources.NormalizeMoney(current - previous, current, now())
    if entry then self:AddEntry(entry) end
end

--- CURRENCY_DISPLAY_UPDATE: positive currency changes only.
---@param _event string
---@param currencyID any
---@param quantity any
---@param quantityChange any
function loot:OnCurrencyUpdate(_event, currencyID, quantity, quantityChange)
    if not db().currency then return end
    local entry = Sources.NormalizeCurrency(currencyID, quantity, quantityChange, now())
    if entry then self:AddEntry(entry) end
end

--- CHAT_MSG_COMBAT_FACTION_CHANGE: positive reputation increases only.
---@param _event string
---@param text any
function loot:OnReputationMessage(_event, text)
    if not db().reputation then return end
    local entry = Sources.NormalizeReputation(text, now())
    if entry then self:AddEntry(entry) end
end

--#endregion

--#region ── Item data refresh ─────────────────────────────────────────────────

--- Re-resolves uncached item rows (data load) and refreshes carried counts.
local function getQuestItemIDsInBags()
    local questItemIDs = {}
    local containers = C_Container
    if not containers or type(containers.GetContainerNumSlots) ~= 'function'
        or type(containers.GetContainerItemInfo) ~= 'function'
        or type(containers.GetContainerItemQuestInfo) ~= 'function' then
        return questItemIDs
    end

    local firstBag = BACKPACK_CONTAINER or 0
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = firstBag, lastBag do
        local ok, slotCount = pcall(containers.GetContainerNumSlots, bag)
        if ok and type(slotCount) == 'number' then
            for slot = 1, slotCount do
                local itemOk, itemInfo = pcall(containers.GetContainerItemInfo, bag, slot)
                local itemID = itemOk and itemInfo and itemInfo.itemID
                if type(itemID) == 'number' and not Sources.isSecret(itemID) then
                    local questOk, questInfo = pcall(containers.GetContainerItemQuestInfo, bag, slot)
                    if questOk and questInfo and questInfo.isQuestItem == true then
                        questItemIDs[itemID] = true
                    end
                end
            end
        end
    end
    return questItemIDs
end

function loot:RefreshItems()
    if not db().enabled then return end
    local changed = false
    local questItemIDs
    for i = 1, #self.session do
        local entry = self.session[i]
        if entry.kind == 'items' and entry.needsRefresh then
            questItemIDs = questItemIDs or getQuestItemIDsInBags()
            local itemID = entry.itemID
            if type(itemID) == 'number' and not Sources.isSecret(itemID)
                and questItemIDs[itemID] and not entry.isQuestItem then
                entry.isQuestItem = true
                changed = true
            end
            if Sources.EnrichItem(entry, { withCount = true }) then changed = true end
            if Sources.IsItemResolved(entry) then entry.needsRefresh = nil end
        end
    end
    if changed and self.feed then self.feed:Rebuild(self.session) end
end

function loot:ScheduleRefresh()
    if not (C_Timer and C_Timer.After) or self.refreshPending then return end
    self.refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        self.refreshPending = false
        self:RefreshItems()
    end)
end

function loot:OnItemInfoReceived()
    self:ScheduleRefresh()
end

loot.OnBagUpdate = loot.OnItemInfoReceived

--#endregion

--#region ── Native chat filters ───────────────────────────────────────────────

--- Rewards that can be recognized from a chat line. Each entry maps a chat
--- event to the profile category and the predicate that recognizes a local
--- player's gain.
---@type { event: string, kind: LootKind, recognize: fun(text:any):boolean }[]
local CHAT_SOURCES = {
    {
        event = 'CHAT_MSG_LOOT',
        kind = 'items',
        recognize = function(text) return Sources.ParseSelfLoot(text) ~= nil end,
    },
    {
        event = 'CHAT_MSG_MONEY',
        kind = 'money',
        recognize = function(text) return Sources.IsSelfMoneyLine(text) end,
    },
    {
        event = 'CHAT_MSG_CURRENCY',
        kind = 'currency',
        recognize = function(text) return Sources.ParseCurrencyGain(text) ~= nil end,
    },
    {
        event = 'CHAT_MSG_COMBAT_FACTION_CHANGE',
        kind = 'reputation',
        recognize = function(text) return Sources.ParseReputationGain(text) ~= nil end,
    },
}

function loot:IsRecognizedRewardLine(event, text)
    local spec = self.chatSourceByEvent and self.chatSourceByEvent[event]
    if not spec then return false end
    if not db()[spec.kind] then return false end
    if Sources.isSecret(text) then return false end
    return spec.recognize(text) == true
end

--- Message-event filter callback. Returns true to remove the line from
--- Blizzard chat; anything else leaves it untouched.
---@param event string
---@param text any
---@return boolean?
function loot:FilterChatMessage(event, text)
    if not db().enabled then return nil end
    if self:IsRecognizedRewardLine(event, text) then return true end
    return nil
end

function loot:InstallChatFilters()
    if self.filtersInstalled then return end

    -- Modern clients expose ChatFrameUtil; older ones only the legacy function.
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if type(add) ~= 'function' then return end
    local remove = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter

    self.chatSourceByEvent = {}
    self.filters = {}

    for _, spec in ipairs(CHAT_SOURCES) do
        self.chatSourceByEvent[spec.event] = spec
        local callback = function(_, event, ...)
            return loot:FilterChatMessage(event, ...)
        end
        add(spec.event, callback)
        self.filters[#self.filters + 1] = { event = spec.event, callback = callback }
    end

    self.filterRemove = remove
    self.filtersInstalled = true
end

function loot:RemoveChatFilters()
    if not self.filtersInstalled then return end
    local remove = self.filterRemove
        or (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter)
        or ChatFrame_RemoveMessageEventFilter
    if type(remove) == 'function' and self.filters then
        for i = 1, #self.filters do
            remove(self.filters[i].event, self.filters[i].callback)
        end
    end
    self.filters = nil
    self.filtersInstalled = false
end

--#endregion

--#region ── Presentation ──────────────────────────────────────────────────────

--- Builds the feed's styling for one entry. Styling lives here (not in the
--- feed) so colors and labels stay in one place, mirroring the Chat module.
---@param entry LootEntry
---@return table
function loot:PresentEntry(entry)
    if entry.kind == 'items' then
        local quality = entry.quality
        local r, g, b = qualityColor(quality)
        if not r or not quality or quality < 2 then
            r, g, b = NEUTRAL.r, NEUTRAL.g, NEUTRAL.b
        end
        local isQuestItem = entry.isQuestItem == true
        if isQuestItem then
            r, g, b = QUEST.r, QUEST.g, QUEST.b
        end
        local text = entry.name or 'Item'
        if entry.count and entry.count > 0 then
            text = ('%s (%d)'):format(text, entry.count)
        end
        return {
            text = text,
            icon = entry.icon,
            questIconAtlas = isQuestItem and QUEST_ICON_ATLAS or nil,
            hyperlink = entry.hyperlink,
            bg = { r * 0.35, g * 0.35, b * 0.35, ROW_BG_ALPHA },
            border = { r, g, b },
            textColor = { 1, 1, 1 },
        }
    elseif entry.kind == 'money' then
        local text = '+' .. moneyString(entry.amount)
        if entry.total then text = text .. '   (' .. moneyString(entry.total) .. ')' end
        return {
            text = text,
            bg = { 0.20, 0.15, 0.03, ROW_BG_ALPHA },
            border = { MONEY.r, MONEY.g, MONEY.b },
            textColor = { 1, 0.93, 0.62 },
        }
    elseif entry.kind == 'currency' then
        local r, g, b = qualityColor(entry.quality)
        if not r then r, g, b = 0.20, 0.60, 0.40 end
        local text = ('%s +%s'):format(entry.name or 'Currency', tostring(entry.amount))
        if entry.total then text = text .. (' (%s)'):format(tostring(entry.total)) end
        return {
            text = text,
            icon = entry.icon,
            hyperlink = entry.hyperlink,
            bg = { r * 0.30, g * 0.30, b * 0.30, ROW_BG_ALPHA },
            border = { r, g, b },
            textColor = { 1, 1, 1 },
        }
    elseif entry.kind == 'reputation' then
        local text
        if entry.name and entry.amount then
            text = ('%s +%d'):format(entry.name, entry.amount)
            local detail = reputationDetail(entry)
            if detail then text = text .. (' (%s)'):format(detail) end
        else
            -- Fall back to the original localized line when parsing is partial.
            text = entry.originalText or 'Reputation'
        end
        return {
            text = text,
            icon = REPUTATION_ICON,
            bg = { 0.06, 0.13, 0.26, ROW_BG_ALPHA },
            border = { REPUTATION.r, REPUTATION.g, REPUTATION.b },
            textColor = { 0.82, 0.91, 1 },
        }
    end
    return { text = entry.originalText or '' }
end

--- Resolved font metrics for the feed label field.
---@return table
function loot:FontMetrics()
    return {
        label = { face = addon.Media.ResolveFont(db().fontFace), size = db().fontSize },
    }
end

--#endregion

--#region ── Panel construction ─────────────────────────────────────────────────

function loot:BuildPanel()
    if self.panel then
        self.panel:Show()
        return
    end

    local frame = CreateFrame('Frame', 'CouchModeLoot', UIParent)
    frame:SetSize(db().width, db().height)
    frame:SetScale(db().scale or 1)
    frame:SetFrameStrata('LOW')
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    local bg = frame:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, db().backgroundOpacity)
    frame.bg = bg

    local scrollArea = CreateFrame('Frame', nil, frame)
    scrollArea:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, -PAD)
    scrollArea:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PAD, PAD)
    self.scrollArea = scrollArea

    self.feed = addon.LootFeedProto.New(scrollArea)
    self.feed.presenter = function(entry) return loot:PresentEntry(entry) end
    self.feed.onScrollChanged = function() loot:OnFeedChanged() end

    -- Rows enable the mouse for tooltips, so hover is tracked on the padding
    -- regions here and per-row inside the feed.
    local function onEnter() self.feed:NoteHover(1) end
    local function onLeave() self.feed:NoteHover(-1) end
    for _, region in ipairs({ frame, scrollArea }) do
        region:EnableMouse(true)
        region:SetScript('OnEnter', onEnter)
        region:SetScript('OnLeave', onLeave)
    end

    local returnBtn = CreateFrame('Button', nil, frame)
    returnBtn:SetSize(22, 22)
    returnBtn:SetPoint('BOTTOMRIGHT', scrollArea, 'BOTTOMRIGHT', -4, 4)
    returnBtn:SetFrameLevel(frame:GetFrameLevel() + 20)
    returnBtn:SetNormalTexture('Interface\\ChatFrame\\ChatFrameExpandArrow')
    returnBtn:SetScript('OnClick', function() loot:ScrollToBottom() end)
    returnBtn:Hide()
    self.returnButton = returnBtn

    frame:SetScript('OnUpdate', function(_, dt) loot:UpdateFade(dt) end)

    LibEditMode:AddFrame(frame, function(_, layoutName, point, x, y)
        -- LibEditMode can dispatch a frame-position callback before it has
        -- resolved the active layout name. There is nowhere valid to persist
        -- that position yet, so wait for a layout-scoped callback instead.
        if not layoutName then return end
        local settings = db()
        settings.positions = settings.positions or {}
        settings.positions[layoutName] = { point = point, x = x, y = y }
    end, { point = 'BOTTOMRIGHT', x = -40, y = 40 }, 'CouchMode Loot')

    LibEditMode:AddFrameSettings(frame, {
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Width', desc = 'Feed width in pixels.',
            default = DEFAULT_WIDTH, minValue = 200, maxValue = 900, valueStep = 10,
            get = function() return db().width end,
            set = function(_, value, fromReset)
                db().width = (fromReset and DEFAULT_WIDTH or value)
                loot:ApplyLayout()
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Height', desc = 'Feed height in pixels.',
            default = DEFAULT_HEIGHT, minValue = MIN_HEIGHT, maxValue = 900, valueStep = 10,
            get = function() return db().height end,
            set = function(_, value, fromReset)
                db().height = (fromReset and DEFAULT_HEIGHT or value)
                loot:ApplyLayout()
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Scale', desc = 'Overall feed scale.',
            default = 1, minValue = 0.5, maxValue = 2, valueStep = 0.05,
            get = function() return db().scale end,
            set = function(_, value, fromReset)
                db().scale = (fromReset and 1 or value)
                if loot.panel then loot.panel:SetScale(db().scale) end
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Active Opacity', desc = 'Feed opacity while at least one reward is visible.',
            default = 1, minValue = 0.1, maxValue = 1, valueStep = 0.05,
            get = function() return db().activeOpacity end,
            set = function(_, value, fromReset)
                db().activeOpacity = (fromReset and 1 or value)
                loot:Touch()
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Background Opacity', desc = 'Feed opacity after all rewards fade.',
            default = 0, minValue = 0, maxValue = 1, valueStep = 0.05,
            get = function() return db().backgroundOpacity end,
            set = function(_, value, fromReset)
                db().backgroundOpacity = (fromReset and 0 or value)
                if loot.panel and loot.panel.bg then
                    loot.panel.bg:SetColorTexture(0, 0, 0, db().backgroundOpacity)
                end
                loot:Touch()
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Fade Delay', desc = 'Seconds each reward remains visible before fading.',
            default = 15, minValue = 0, maxValue = 120, valueStep = 1,
            get = function() return db().fadeDelay end,
            set = function(_, value, fromReset)
                db().fadeDelay = (fromReset and 15 or value)
                loot:Touch()
            end,
        },
        {
            kind = LibEditMode.SettingType.Dropdown,
            name = 'Font', desc = 'Font used for reward text.',
            default = 'Arial Narrow',
            values = (function()
                local values = {}
                for name in pairs(addon.Media.GetFontOptions()) do
                    values[#values + 1] = { text = name, value = name }
                end
                table.sort(values, function(a, b) return a.text < b.text end)
                return values
            end)(),
            get = function() return db().fontFace end,
            set = function(_, value, fromReset)
                db().fontFace = (fromReset and 'Arial Narrow' or value)
                loot:ApplyFont()
            end,
        },
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'History Cap', desc = 'Rewards retained for the current login.',
            default = 200, minValue = 20, maxValue = 1000, valueStep = 20,
            get = function() return db().historyCap end,
            set = function(_, value, fromReset)
                db().historyCap = (fromReset and 200 or value)
                loot:TrimSession()
            end,
        },
    })

    LibEditMode:RegisterCallback('layout', function(layoutName)
        local pos = db().positions[layoutName]
        frame:ClearAllPoints()
        if pos then
            frame:SetPoint(pos.point, pos.x, pos.y)
        else
            frame:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', -40, 40)
        end
    end)

    frame:Show()
    self.panel = frame
    self:ApplyFont()
    self:ApplyLayout()
    self:OnFeedChanged()
end

function loot:ApplyFont()
    if not self.feed then return end
    self.feed:SetFonts(self:FontMetrics())
end

--#endregion

--#region ── Layout ─────────────────────────────────────────────────────────────

function loot:ApplyLayout()
    local frame = self.panel
    if not frame then return end

    local height = math.max(db().height or DEFAULT_HEIGHT, MIN_HEIGHT)
    frame:SetSize(db().width or DEFAULT_WIDTH, height)
    frame:SetScale(db().scale or 1)
    if frame.bg then frame.bg:SetColorTexture(0, 0, 0, db().backgroundOpacity or 0) end

    if self.feed then
        self.feed:SetWidth((db().width or DEFAULT_WIDTH) - PAD * 2)
        self.feed:SetViewportHeight(height - PAD * 2)
    end
end

function loot:TrimSession()
    local cap = db().historyCap or 200
    local overflow = #self.session - cap
    if overflow > 0 then
        for _ = 1, overflow do table.remove(self.session, 1) end
        if self.feed then self.feed:Rebuild(self.session) end
        self:OnFeedChanged()
    end
end

--#endregion

--#region ── Fade / activity ──────────────────────────────────────────────────

function loot:Touch()
    self.lastActivity = now()
end

function loot:UpdateFade(dt)
    if not self.panel then return end

    local browsing = self.feed and self.feed:IsBrowsingHistory()
    local fadeEnabled = db().fadeEnabled == true
    local hasVisible = true
    if self.feed then
        hasVisible = self.feed:UpdateRowFade(now(), db().fadeDelay or 15, fadeEnabled and not browsing)
    end

    local hovered = self.feed and self.feed.hovering
    local target = db().activeOpacity or 1
    if fadeEnabled and not hasVisible and not hovered then
        target = db().backgroundOpacity or 0
    end

    local current = self.fadeAlpha or 0
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
end

function loot:OnFeedChanged()
    if not self.returnButton or not self.feed then return end
    if self.feed:IsAtBottom() then
        self.returnButton:Hide()
    else
        self.returnButton:Show()
    end
end

--#endregion

--#region ── Panel controls ─────────────────────────────────────────────────────

function loot:Toggle()
    if not self.panel then return end
    if self.panel:IsShown() then
        self.panel:Hide()
    else
        self.panel:Show()
        self:OnFeedChanged()
        self:Touch()
    end
end

function loot:ClosePanel()
    if self.feed then
        self.feed:ResumeLive()
        self.feed:ScrollToBottom()
    end
    if self.panel then self.panel:Hide() end
end

function loot:ScrollUp()
    if self.feed then self.feed:ScrollBy(60) end
    self:Touch()
end

function loot:ScrollDown()
    if self.feed then self.feed:ScrollBy(-60) end
    self:Touch()
end

function loot:ScrollToBottom()
    if self.feed then
        -- An explicit return to the bottom resumes live fading.
        self.feed:ResumeLive()
        self.feed:ScrollToBottom()
    end
    self:OnFeedChanged()
    self:Touch()
end

function loot:ClearSession()
    wipe(self.session)
    if self.feed then self.feed:Clear() end
    self:OnFeedChanged()
end

--#endregion

--#region ── Defaults ─────────────────────────────────────────────────────────

function loot:GetDefaults()
    return {
        loot = {
            enabled = true,
            -- Position (per Edit Mode layout)
            positions = {},
            -- Sizing / appearance
            width = DEFAULT_WIDTH,
            height = DEFAULT_HEIGHT,
            scale = 1,
            activeOpacity = 1,
            backgroundOpacity = 0,
            fadeEnabled = true,
            fadeDelay = 15,
            fontFace = 'Arial Narrow',
            fontSize = 14,
            -- Reward categories
            items = true,
            money = true,
            currency = true,
            reputation = true,
            -- History
            historyCap = 200,
        },
    }
end

--#endregion

--#region ── Options ──────────────────────────────────────────────────────────

function loot:NotifyChange()
    local registry = LibStub('AceConfigRegistry-3.0', true)
    if registry then registry:NotifyChange(addonName) end
end

function loot:BuildArgs()
    return {
        description = {
            name = 'A scrolling feed of rewards you gain: looted items, money, currency and reputation. '
                .. 'Reward lines are removed from Blizzard chat only while Loot is enabled and recognized.',
            type = 'description',
            order = 1,
        },
        enabled = {
            name = 'Enable',
            desc = 'Show the Loot feed and hide recognized reward lines from Blizzard chat.',
            type = 'toggle',
            order = 2,
            get = function() return db().enabled end,
            set = function(_, value)
                db().enabled = value
                if value then loot:Enable() else loot:Disable() end
            end,
        },
        rewards = {
            name = 'Rewards',
            type = 'group',
            inline = true,
            order = 10,
            args = {
                items = {
                    name = 'Items', desc = 'Items looted by you.',
                    type = 'toggle', order = 1,
                    get = function() return db().items end,
                    set = function(_, value) db().items = value end,
                },
                money = {
                    name = 'Money', desc = 'Money you gain.',
                    type = 'toggle', order = 2,
                    get = function() return db().money end,
                    set = function(_, value) db().money = value end,
                },
                currency = {
                    name = 'Currency', desc = 'Currency you gain.',
                    type = 'toggle', order = 3,
                    get = function() return db().currency end,
                    set = function(_, value) db().currency = value end,
                },
                reputation = {
                    name = 'Reputation', desc = 'Reputation increases.',
                    type = 'toggle', order = 4,
                    get = function() return db().reputation end,
                    set = function(_, value) db().reputation = value end,
                },
            },
        },
        appearance = {
            name = 'Appearance',
            type = 'group',
            inline = true,
            order = 20,
            args = {
                width = {
                    name = 'Width', desc = 'Feed width in pixels.',
                    type = 'range', min = 200, max = 900, step = 10, order = 1,
                    get = function() return db().width end,
                    set = function(_, value) db().width = value; loot:ApplyLayout() end,
                },
                height = {
                    name = 'Height', desc = 'Feed height in pixels.',
                    type = 'range', min = MIN_HEIGHT, max = 900, step = 10, order = 2,
                    get = function() return db().height end,
                    set = function(_, value) db().height = value; loot:ApplyLayout() end,
                },
                scale = {
                    name = 'Scale', desc = 'Overall feed scale.',
                    type = 'range', min = 0.5, max = 2, step = 0.05, order = 3,
                    get = function() return db().scale end,
                    set = function(_, value) db().scale = value; loot:ApplyLayout() end,
                },
                activeOpacity = {
                    name = 'Active Opacity', desc = 'Feed opacity while at least one reward is visible.',
                    type = 'range', min = 0.1, max = 1, step = 0.05, order = 4,
                    get = function() return db().activeOpacity end,
                    set = function(_, value) db().activeOpacity = value; loot:Touch() end,
                },
                backgroundOpacity = {
                    name = 'Background Opacity', desc = 'Feed opacity after all rewards fade.',
                    type = 'range', min = 0, max = 1, step = 0.05, order = 5,
                    get = function() return db().backgroundOpacity end,
                    set = function(_, value) db().backgroundOpacity = value; loot:ApplyLayout() end,
                },
                fadeEnabled = {
                    name = 'Auto-fade', desc = 'Fade each reward after its delay.',
                    type = 'toggle', order = 6,
                    get = function() return db().fadeEnabled end,
                    set = function(_, value) db().fadeEnabled = value; loot:Touch() end,
                },
                fadeDelay = {
                    name = 'Fade Delay', desc = 'Seconds each reward remains visible before fading.',
                    type = 'range', min = 0, max = 120, step = 1, order = 7,
                    get = function() return db().fadeDelay end,
                    set = function(_, value) db().fadeDelay = value; loot:Touch() end,
                },
                fontFace = {
                    name = 'Font', desc = 'Font used for reward text.',
                    type = 'select', style = 'dropdown', order = 8,
                    values = addon.Media.GetFontOptions(),
                    get = function() return db().fontFace end,
                    set = function(_, value) db().fontFace = value; loot:ApplyFont() end,
                },
                fontSize = {
                    name = 'Font Size', desc = 'Reward text size.',
                    type = 'range', min = 8, max = 28, step = 1, order = 9,
                    get = function() return db().fontSize end,
                    set = function(_, value) db().fontSize = value; loot:ApplyFont() end,
                },
                historyCap = {
                    name = 'History Cap', desc = 'Maximum rewards kept for the current login (not saved).',
                    type = 'range', min = 20, max = 1000, step = 20, order = 10,
                    get = function() return db().historyCap end,
                    set = function(_, value) db().historyCap = value; loot:TrimSession() end,
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
                    name = 'Clear History', desc = 'Clear the current login\'s reward history.',
                    type = 'execute', order = 1,
                    func = function() loot:ClearSession() end,
                },
                testRewards = {
                    name = 'Test Rewards',
                    desc = 'Fire mock rewards for every category.\n\nAlso available in chat as /cm loot mock.',
                    type = 'execute', order = 2,
                    func = function() loot:RunMock('all') end,
                },
            },
        },
    }
end

function loot:GetOptions()
    self.optionsArgs = self.optionsArgs or self:BuildArgs()
    return 'loot', {
        name = 'Loot',
        type = 'group',
        order = PANEL_ORDER,
        args = self.optionsArgs,
    }
end

--#endregion

--#region ── Testing / mock ───────────────────────────────────────────────────

function loot:Notify(text)
    print('CouchMode: ' .. tostring(text))
end

--- Applies one mock reward through the same paths live rewards use.
---@param spec table
function loot:MockEntry(spec)
    local timestamp = now()
    local entry

    if spec.kind == 'items' then
        self:OnLootMessage('CHAT_MSG_LOOT', spec.text)
        return
    elseif spec.kind == 'money' then
        entry = Sources.NormalizeMoney(spec.amount, spec.total, timestamp)
    elseif spec.kind == 'currency' then
        entry = Sources.NormalizeCurrency(spec.currencyID, spec.total, spec.amount, timestamp)
        if entry then
            entry.name = spec.name or entry.name
            entry.icon = spec.icon or entry.icon
            entry.quality = spec.quality or entry.quality
        end
    elseif spec.kind == 'reputation' then
        if spec.name and spec.amount then
            entry = Sources.NormalizeReputationFromParts(spec.name, spec.amount, timestamp, spec.text)
            if entry then
                local info = Sources.GetFactionReputation(spec.name)
                entry.reaction = spec.reaction or (info and info.reaction)
                entry.progress = spec.progress or (info and info.progress)
                entry.progressMax = spec.progressMax or (info and info.progressMax)
            end
        elseif spec.text and Sources.ParseReputationGain(spec.text) then
            self:OnReputationMessage('CHAT_MSG_COMBAT_FACTION_CHANGE', spec.text)
            return
        end
    end

    if entry then self:AddEntry(entry) end
end

function loot:RunMock(setName)
    local mock = addon.LootMock
    if not mock then return end
    if not db().enabled then
        self:Notify('enable Loot before running the mock.')
        return
    end

    local resolved = mock.Resolve(setName)
    if not resolved then
        self:Notify(('Unknown mock set "%s". Available: %s, all.')
            :format(tostring(setName), table.concat(mock.Names(), ', ')))
        return
    end

    local count = mock.Run(self, resolved)
    self:Notify(('Loot mock: fired %d rewards from "%s".'):format(count, resolved))
end

--- Entry point for `/cm loot ...`.
---@param sub string
---@param arg string
function loot:HandleCommand(sub, arg)
    sub = (sub or ''):lower()
    if sub == 'mock' or sub == 'test' then
        loot:RunMock(arg)
    elseif sub == 'items' or sub == 'item' then
        -- Convenience shortcut for the item reward set.
        loot:RunMock('item')
    elseif sub == 'clear' then
        loot:ClearSession()
        loot:Notify('Loot history cleared.')
    elseif sub == 'sets' then
        loot:Notify('Loot mock sets: ' .. table.concat(addon.LootMock.Names(), ', ') .. ', all')
    else
        loot:Notify('CouchMode Loot: /cm loot items | /cm loot mock [set] | /cm loot sets | /cm loot clear')
    end
end

--#endregion

--#region ── Event routing table ────────────────────────────────────────────────

--- Maps the support events in LootSources to module handlers.
loot.EVENT_HANDLERS = {
    PLAYER_MONEY = 'OnPlayerMoney',
    CURRENCY_DISPLAY_UPDATE = 'OnCurrencyUpdate',
    CHAT_MSG_LOOT = 'OnLootMessage',
    CHAT_MSG_COMBAT_FACTION_CHANGE = 'OnReputationMessage',
    GET_ITEM_INFO_RECEIVED = 'OnItemInfoReceived',
    ITEM_DATA_LOAD_RESULT = 'OnItemInfoReceived',
    BAG_UPDATE_DELAYED = 'OnItemInfoReceived',
    PLAYER_ENTERING_WORLD = 'OnPlayerEnteringWorld',
}

--#endregion

--#region ── Bindings ──────────────────────────────────────────────────────────

function CouchMode_LootToggle() addon.Loot:Toggle() end
function CouchMode_LootScrollUp() addon.Loot:ScrollUp() end
function CouchMode_LootScrollDown() addon.Loot:ScrollDown() end
function CouchMode_LootBottom() addon.Loot:ScrollToBottom() end
function CouchMode_LootClose() addon.Loot:ClosePanel() end

--#endregion

loot:Enable()
