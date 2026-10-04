local addonName, addon = ...

---@class CouchMode: AceAddon
---@field ToastSources table
---@field ToastFeedProto table
---@field ToastMock table
---@field Toasts ToastsModule
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local EditMode = addon.EditMode

---@class ToastsModule: AceModule
---@field HandleCommand fun(self: ToastsModule, sub: string, arg: string)
local toasts = addon:NewModule('Toasts', 'AceEvent-3.0')

local Sources = addon.ToastSources

--#region ── Constants ────────────────────────────────────────────────────────

local PAD = 8
local PANEL_ORDER = 12
local REFRESH_DELAY = 0.25
local PRESENTATION_PACE = 0.35
local DEFAULT_MAX_ITEMS = 15
local MAX_ITEMS_LIMIT = 20

local DEFAULT_WIDTH = 360
local FADE_DELAY_DESC = 'Maximum seconds a toast remains visible before fading. Toast type and item quality use shorter weighted durations.'

-- Stable palettes for rows that have no item quality of their own.
local NEUTRAL = { r = 0.16, g = 0.16, b = 0.16 }
local MONEY = { r = 0.83, g = 0.68, b = 0.21 }
local REPUTATION = { r = 0.30, g = 0.58, b = 0.95 }
local SYSTEM = { r = 0.46, g = 0.79, b = 0.92 }
local QUEST = { r = 1, g = 0.82, b = 0 }
local QUEST_ICON_ATLAS = 'QuestNormal'
local GOLD_ICON_ID = 901746
local REPUTATION_ICON = 'Interface\\Icons\\achievement_reputation_01'
local SYSTEM_ICON_ID = 4279397
local SYSTEM_EVENT_ICONS = {
    CHAT_MSG_COMBAT_XP_GAIN = 'Interface\\Icons\\XP_Icon',
    CHAT_MSG_COMBAT_HONOR_GAIN = 'Interface\\Icons\\Spell_Misc_HellifrePVPHonorHoldFavor',
    CHAT_MSG_SKILL = 'Interface\\Icons\\INV_Misc_Book_09',
}
local WEAPON_SKILL_ICONS = {
    [43] = 'Interface\\Icons\\INV_Sword_04',
    [44] = 'Interface\\Icons\\INV_Axe_04',
    [45] = 'Interface\\Icons\\INV_Weapon_Bow_05',
    [46] = 'Interface\\Icons\\INV_Weapon_Rifle_01',
    [54] = 'Interface\\Icons\\INV_Mace_01',
    [55] = 'Interface\\Icons\\INV_Sword_07',
    [136] = 'Interface\\Icons\\INV_Staff_08',
    [160] = 'Interface\\Icons\\INV_Mace_04',
    [162] = 'Interface\\Icons\\INV_Gauntlets_04',
    [172] = 'Interface\\Icons\\INV_Axe_09',
    [173] = 'Interface\\Icons\\INV_Weapon_ShortBlade_05',
    [176] = 'Interface\\Icons\\INV_ThrowingKnife_04',
    [226] = 'Interface\\Icons\\INV_Weapon_Crossbow_01',
    [228] = 'Interface\\Icons\\INV_Staff_30',
    [229] = 'Interface\\Icons\\INV_Weapon_Halberd_10',
    [3014] = 'Interface\\Icons\\Ability_Druid_CatForm',
}
local SYSTEM_EVENT_ICON_ATLASES = {
    CHAT_MSG_COLLECTED_APPEARANCE = 'transmog-nav-slot-head',
}

-- Keep junk filtering data-driven so new noisy system lines can be added here.
-- Prefer Blizzard's localized global strings, with English fallbacks for
-- messages whose global-string name differs between client flavors.
local JUNK_SYSTEM_MESSAGES = {
    {
        globals = { 'ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS', 'LE_GAME_ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS' },
        fallbacks = { 'Another action is in progress' },
    },
    {
        globals = { 'ERR_GENERIC_NO_TARGET', 'LE_GAME_ERR_GENERIC_NO_TARGET' },
        fallbacks = { 'You have no target' },
    },
    {
        globals = { 'ERR_INVALID_TARGET', 'ERR_GENERIC_INVALID_TARGET', 'LE_GAME_ERR_GENERIC_NO_VALID_TARGETS' },
        fallbacks = { 'Invalid Target' },
    },
    {
        globals = { 'ERR_OUT_OF_RANGE', 'LE_GAME_ERR_OUT_OF_RANGE' },
        fallbacks = { 'Out of range' },
    },
    {
        globals = { 'ERR_OUT_OF_MANA', 'LE_GAME_ERR_OUT_OF_MANA', 'ERR_SPELL_FAILED_NOT_ENOUGH_MANA' },
        fallbacks = { 'Not enough Mana' },
    },
    {
        globals = { 'ERR_NOT_WHILE_MOVING', 'ERR_CANT_DO_THAT_WHILE_MOVING' },
        fallbacks = { "Can't do that while moving" },
    },
    {
        globals = { 'INTERRUPTED', 'ERR_INTERRUPTED', 'ERR_SPELL_INTERRUPTED' },
        fallbacks = { 'Interrupted' },
    },
}

-- Row backgrounds are semi-transparent so the feed behind them shows through.
local ROW_BG_ALPHA = 0.5

--#endregion

--#region ── Module state ──────────────────────────────────────────────────────

toasts.presentationQueue = {}
toasts.presentationQueueHead = 1
toasts.presentationQueueTail = 0
toasts.presentationQueueScheduled = false
toasts.presentationQueueToken = 0
toasts.lastMoney = nil    ---@type number?
toasts.panel = nil        ---@type Frame?
toasts.feed = nil
toasts.fadeAlpha = 1
toasts.refreshPending = false
toasts.filters = nil      ---@type { event: string, callback: fun(...) }[]?
toasts.filtersInstalled = false
toasts.pendingAppearanceIcons = {}

--#endregion

--#region ── Small helpers ───────────────────────────────────────────────────────

local function db() return addon.db.profile.toasts end

-- The profile delay is the maximum: at 15 seconds, the tiers last 8, 10,
-- 12, and 15 seconds. Item quality can arrive after the initial toast, so
-- resolve the weight from the current entry without changing its timestamp.
local function fadeDuration(entry)
    local weight = 8 / 15
    if entry.kind == 'items' then
        local quality = Sources.SafeNumber(entry.quality)
        if quality and quality >= 4 then
            weight = 1
        elseif quality == 3 then
            weight = 12 / 15
        elseif quality == 2 then
            weight = 10 / 15
        end
    elseif entry.kind == 'currency' then
        weight = 12 / 15
    elseif entry.kind == 'reputation' then
        weight = 10 / 15
    end
    return math.max(db().fadeDelay or 15, 0) * weight
end

local function normalizeSystemMessage(text)
    if Sources.isSecret(text) or type(text) ~= 'string' then return nil end
    return text:lower():gsub('[%p%s]+', '')
end

local function isJunkSystemMessage(text)
    local normalized = normalizeSystemMessage(text)
    if not normalized then return false end

    for _, message in ipairs(JUNK_SYSTEM_MESSAGES) do
        for _, globalName in ipairs(message.globals or {}) do
            local localized = normalizeSystemMessage(_G[globalName])
            if localized and localized == normalized then return true end
        end
        for _, fallback in ipairs(message.fallbacks or {}) do
            if normalizeSystemMessage(fallback) == normalized then return true end
        end
    end
    return false
end

local function isSystemMessageEvent(event)
    return Sources.SYSTEM_EVENT_SET[event] == true or Sources.UI_SYSTEM_EVENT_SET[event] == true
end

local function isQuestProgressMessage(event, text)
    if not isSystemMessageEvent(event) then return false end
    text = Sources.SafeString(text)
    return text ~= nil and text:match('^.+%d+%s*/%s*%d+%s*$') ~= nil
end

local function now()
    return (type(GetTime) == 'function') and GetTime() or 0
end

local function validIcon(icon)
    if Sources.isSecret(icon) then return false end
    return (type(icon) == 'number' and icon > 0)
        or (type(icon) == 'string' and icon ~= '')
end

local function getAppearanceSourceIcon(sourceID)
    local transmog = C_TransmogCollection
    if not (transmog and transmog.GetSourceIcon) then return nil end
    local ok, icon = pcall(transmog.GetSourceIcon, sourceID)
    if ok and validIcon(icon) then return icon end
end

local function latestAppearanceSourceIcon()
    local transmog = C_TransmogCollection
    if not (transmog and transmog.GetLatestAppearance and transmog.GetAllAppearanceSources) then
        return nil
    end

    local ok, appearanceID = pcall(transmog.GetLatestAppearance)
    appearanceID = ok and Sources.SafeNumber(appearanceID) or nil
    if not appearanceID then return nil end

    local sourcesOK, sourceIDs = pcall(transmog.GetAllAppearanceSources, appearanceID)
    if not sourcesOK or type(sourceIDs) ~= 'table' then return nil end
    for _, sourceID in ipairs(sourceIDs) do
        sourceID = Sources.SafeNumber(sourceID)
        if sourceID then
            local icon = getAppearanceSourceIcon(sourceID)
            if icon then return icon end
        end
    end
end

--- CHAT_MSG_SKILL has localized text rather than a skill ID. Match its skill
--- name against the skill list, then ask the profession API for its real icon.
local function skillIconFromMessage(text)
    local skillInfo = C_SkillInfo
    local tradeSkills = C_TradeSkillUI
    if not (skillInfo and skillInfo.GetNumSkillLines and skillInfo.GetSkillLineInfo) then return nil end

    local ok, count = pcall(skillInfo.GetNumSkillLines)
    if not ok or type(count) ~= 'number' then return nil end

    for index = 1, count do
        local infoOK, info = pcall(skillInfo.GetSkillLineInfo, index)
        local name = infoOK and type(info) == 'table' and Sources.SafeString(info.name)
        if name and text:find(name, 1, true) then
            if tradeSkills and tradeSkills.GetProfessionInfoBySkillLineID
                and tradeSkills.GetTradeSkillTexture then
                local skillID = Sources.SafeNumber(info.skillID)
                if skillID then
                    local professionOK, profession = pcall(tradeSkills.GetProfessionInfoBySkillLineID, skillID)
                    local professionID = professionOK and type(profession) == 'table'
                        and Sources.SafeNumber(profession.professionID)
                    if professionID then
                        local iconOK, icon = pcall(tradeSkills.GetTradeSkillTexture, professionID)
                        if iconOK and validIcon(icon) then return icon end
                    end
                end
            end
            local skillID = Sources.SafeNumber(info.skillID)
            if skillID then return WEAPON_SKILL_ICONS[skillID] end
            return nil
        end
    end
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
---@param entry ToastEntry
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

function toasts:OnInitialize()
    addon.Toasts = self
end

--- Registers an event only when the running client defines it.
---@param event string
---@param handler string|fun(...)
---@return boolean registered
function toasts:RegisterValidEvent(event, handler)
    return addon.Utils.RegisterEventIfValid(self, event, handler)
end

function toasts:HasQueuedEntries()
    return self.presentationQueueHead <= self.presentationQueueTail
end

function toasts:StopPresentationQueue()
    self.presentationQueueToken = self.presentationQueueToken + 1
    self.presentationQueueScheduled = false
end

function toasts:SchedulePresentationQueue(delay)
    if self.presentationQueueScheduled or not db().enabled then return end

    self.presentationQueueScheduled = true
    self.presentationQueueToken = self.presentationQueueToken + 1
    local token = self.presentationQueueToken
    C_Timer.After(math.max(delay or 0, 0), function()
        if token ~= toasts.presentationQueueToken then return end
        toasts.presentationQueueScheduled = false
        if not db().enabled or not toasts:HasQueuedEntries() then return end
        toasts:ProcessNextQueuedEntry()
    end)
end

function toasts:ProcessNextQueuedEntry()
    if not db().enabled or not self:HasQueuedEntries() then return end

    if self.feed then
        local hidden = self.panel and not self.panel:IsShown()
        local removed = self.feed:RemoveExpiredRows(now(), hidden)
        if removed > 0 then self:ApplyLayout() end
        local maxItems = math.max(1, math.floor(db().maxItems or DEFAULT_MAX_ITEMS))
        if #self.feed.rows >= maxItems then
            self:SchedulePresentationQueue(0.25)
            return
        end
    end

    local entry
    entry = self.presentationQueue[self.presentationQueueHead]
    self.presentationQueue[self.presentationQueueHead] = nil
    self.presentationQueueHead = self.presentationQueueHead + 1

    if not self:HasQueuedEntries() then
        self.presentationQueue = {}
        self.presentationQueueHead = 1
        self.presentationQueueTail = 0
    end

    if entry then
        entry.displayedAt = now()
        if self.feed then
            self.feed:Append(entry)
            self:ApplyLayout()
        end
        self:Touch()
    end

    if entry then
        self:SchedulePresentationQueue(PRESENTATION_PACE)
    end
end

function toasts:ClearPresentationQueue()
    self:StopPresentationQueue()
    self.presentationQueue = {}
    self.presentationQueueHead = 1
    self.presentationQueueTail = 0
end

function toasts:OnEnable()
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
    if self:HasQueuedEntries() then self:SchedulePresentationQueue(0) end
end

function toasts:OnDisable()
    self:ClearPresentationQueue()
    for _, event in ipairs(Sources.SUPPORT_EVENTS) do
        self:UnregisterEvent(event)
    end
    self:RemoveChatFilters()
    if self.feed then
        self.feed:Clear()
        self:ApplyLayout()
    end
    if self.panel then self.panel:Hide() end
end

--#endregion

--#region ── Money snapshot ────────────────────────────────────────────────────

function toasts:SnapshotMoney()
    if type(GetMoney) ~= 'function' then return end
    local money = GetMoney()
    if money ~= nil and not Sources.isSecret(money) then
        self.lastMoney = money
    end
end

function toasts:OnPlayerEnteringWorld()
    self:SnapshotMoney()
    self:ScheduleRefresh()
end

--#endregion

--#region ── Reward ingestion ──────────────────────────────────────────────────

---@param entry ToastEntry
function toasts:AddEntry(entry)
    if not db().enabled then return end

    self.presentationQueueTail = self.presentationQueueTail + 1
    self.presentationQueue[self.presentationQueueTail] = entry

    if self.presentationQueueHead == self.presentationQueueTail
        and not self.presentationQueueScheduled then
        self:ProcessNextQueuedEntry()
    end
end

--- CHAT_MSG_LOOT: local-player item acquisitions only.
---@param _event string
---@param text any
function toasts:OnLootMessage(_event, text)
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
function toasts:OnPlayerMoney()
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
function toasts:OnCurrencyUpdate(_event, currencyID, quantity, quantityChange)
    if not db().currency then return end
    local entry = Sources.NormalizeCurrency(currencyID, quantity, quantityChange, now())
    if entry then self:AddEntry(entry) end
end

--- CHAT_MSG_COMBAT_FACTION_CHANGE: positive reputation increases only.
---@param _event string
---@param text any
function toasts:OnReputationMessage(_event, text)
    if not db().reputation then return end
    local entry = Sources.NormalizeReputation(text, now())
    if entry then self:AddEntry(entry) end
end

--- TRANSMOG_COLLECTION_SOURCE_ADDED carries the exact item appearance source ID.
function toasts:OnTransmogSourceAdded(_event, sourceID)
    local icon = Sources.SafeNumber(sourceID) and getAppearanceSourceIcon(sourceID)
    if icon then
        self.pendingAppearanceIcons[#self.pendingAppearanceIcons + 1] = {
            icon = icon,
            timestamp = now(),
        }
    end
end

local function takePendingAppearanceIcon(self)
    local queue = self.pendingAppearanceIcons
    local timestamp = now()
    while queue[1] and timestamp - queue[1].timestamp > 5 do
        table.remove(queue, 1)
    end
    local pending = table.remove(queue, 1)
    return pending and pending.icon
end

--- Displays system messages and system-style chat events in the system category.
---@param event string
---@param text any
function toasts:OnSystemMessage(event, text)
    if db().filterJunk and isJunkSystemMessage(text) then return end
    if not db().system then return end
    local entry = Sources.NormalizeSystem(event, text, now())
    if not entry then return end

    if isQuestProgressMessage(event, entry.originalText) then
        entry.iconAtlas = QUEST_ICON_ATLAS
    end

    if event == 'CHAT_MSG_COLLECTED_APPEARANCE' then
        entry.icon = takePendingAppearanceIcon(self) or latestAppearanceSourceIcon()
    elseif event == 'CHAT_MSG_SKILL' then
        entry.icon = skillIconFromMessage(entry.originalText)
    end

    self:AddEntry(entry)
end

--- Whether this system line will be presented by Toasts instead of Chat.
---@param event string
---@param text any
---@return boolean
function toasts:ShouldSuppressSystemMessageFromChat(event, text)
    if db().enabled ~= true then return false end
    if db().filterJunk and isSystemMessageEvent(event) and isJunkSystemMessage(text) then
        return true
    end
    return db().system == true and Sources.NormalizeSystem(event, text, 0) ~= nil
end

--- UI_ERROR_MESSAGE/UI_INFO_MESSAGE provide (messageType, text); the message
--- is the second event argument. SYSMSG already uses OnSystemMessage directly.
function toasts:OnUIMessage(event, _messageType, text)
    self:OnSystemMessage(event, text)
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

function toasts:RefreshItems()
    if not db().enabled then return end
    local changed = false
    local questItemIDs
    local function refreshEntry(entry)
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

    if self.feed then
        for i = 1, #self.feed.rows do
            refreshEntry(self.feed.rows[i]._entry)
        end
    end
    for i = self.presentationQueueHead, self.presentationQueueTail do
        local entry = self.presentationQueue[i]
        if entry then refreshEntry(entry) end
    end
    if changed and self.feed then
        self.feed:Rebuild(self.feed:GetEntries())
        self:ApplyLayout()
    end
end

function toasts:ScheduleRefresh()
    if not (C_Timer and C_Timer.After) or self.refreshPending then return end
    self.refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        self.refreshPending = false
        self:RefreshItems()
    end)
end

function toasts:OnItemInfoReceived()
    self:ScheduleRefresh()
end

toasts.OnBagUpdate = toasts.OnItemInfoReceived

--#endregion

--#region ── Native chat filters ───────────────────────────────────────────────

--- Rewards that can be recognized from a chat line. Each entry maps a chat
--- event to the profile category and the predicate that recognizes a local
--- player's gain.
---@type { event: string, kind: ToastKind, recognize: fun(text:any):boolean }[]
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
for _, event in ipairs(Sources.SYSTEM_EVENTS) do
    CHAT_SOURCES[#CHAT_SOURCES + 1] = {
        event = event,
        kind = 'system',
        recognize = function(text) return Sources.SafeString(text) ~= nil end,
    }
end

function toasts:IsRecognizedChatLine(event, text)
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
function toasts:FilterChatMessage(event, text)
    if not db().enabled then return nil end
    if db().filterJunk and isSystemMessageEvent(event) and isJunkSystemMessage(text) then
        return true
    end
    if self:IsRecognizedChatLine(event, text) then return true end
    return nil
end

function toasts:InstallChatFilters()
    if self.filtersInstalled then return end

    -- Modern clients expose ChatFrameUtil; older ones only the legacy function.
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if type(add) ~= 'function' then return end
    local remove = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter

    self.chatSourceByEvent = {}
    self.filters = {}

    for _, spec in ipairs(CHAT_SOURCES) do
        if addon.Utils.EventExists(spec.event) ~= false then
            self.chatSourceByEvent[spec.event] = spec
            local callback = function(_, event, ...)
                return toasts:FilterChatMessage(event, ...)
            end
            add(spec.event, callback)
            self.filters[#self.filters + 1] = { event = spec.event, callback = callback }
        end
    end

    self.filterRemove = remove
    self.filtersInstalled = true
end

function toasts:RemoveChatFilters()
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
---@param entry ToastEntry
---@return table
function toasts:PresentEntry(entry)
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
            icon = GOLD_ICON_ID,
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
    elseif entry.kind == 'system' then
        return {
            text = entry.originalText or '',
            icon = entry.icon or SYSTEM_EVENT_ICONS[entry.event] or SYSTEM_ICON_ID,
            iconAtlas = not entry.icon and (entry.iconAtlas or SYSTEM_EVENT_ICON_ATLASES[entry.event]) or nil,
            wrap = true,
            bg = { 0.07, 0.16, 0.21, 0.72 },
            border = { SYSTEM.r, SYSTEM.g, SYSTEM.b },
            textColor = { 0.86, 0.96, 1 },
        }
    end
    return { text = entry.originalText or '' }
end

--- Resolved font metrics for the feed label field.
---@return table
function toasts:FontMetrics()
    return {
        label = { face = addon.Media.ResolveFont(db().fontFace), size = db().fontSize },
    }
end

--#endregion

--#region ── Panel construction ─────────────────────────────────────────────────

function toasts:BuildPanel()
    if self.panel then
        self.panel:Show()
        return
    end

    local frame = CreateFrame('Frame', 'CouchModeToasts', UIParent)
    frame:SetSize(db().width or DEFAULT_WIDTH, PAD * 2 + 1)
    frame:SetFrameStrata('LOW')
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    local scrollArea = CreateFrame('Frame', nil, frame)
    scrollArea:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, -PAD)
    scrollArea:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PAD, PAD)
    self.scrollArea = scrollArea

    self.feed = addon.ToastFeedProto.New(scrollArea)
    self.feed.presenter = function(entry) return toasts:PresentEntry(entry) end
    self.feed.durationForEntry = fadeDuration

    -- Rows enable the mouse for tooltips, so hover is tracked on the padding
    -- regions here and per-row inside the feed.
    local function onEnter() self.feed:NoteHover(1) end
    local function onLeave() self.feed:NoteHover(-1) end
    for _, region in ipairs({ frame, scrollArea }) do
        region:EnableMouse(true)
        region:SetScript('OnEnter', onEnter)
        region:SetScript('OnLeave', onLeave)
    end

    frame:SetScript('OnUpdate', function(_, dt) toasts:UpdateFade(dt) end)

    EditMode:RegisterFrame(frame, function(_, layoutName, point, x, y)
        -- Position callbacks cannot be persisted until the active layout is known.
        if not layoutName then return end
        local settings = db()
        settings.positions = settings.positions or {}
        settings.positions[layoutName] = { point = point, x = x, y = y }
    end, { point = 'BOTTOMRIGHT', x = -40, y = 40 }, 'CouchMode Toasts')

    EditMode:RegisterFrameSettings(frame, {
        {
            kind = EditMode.SettingType.Slider,
            name = 'Width', desc = 'Feed width in pixels.',
            default = DEFAULT_WIDTH, minValue = 200, maxValue = 900, valueStep = 10,
            get = function() return db().width end,
            set = function(_, value, fromReset)
                db().width = (fromReset and DEFAULT_WIDTH or value)
                toasts:ApplyLayout()
            end,
        },
        {
            kind = EditMode.SettingType.Slider,
            name = 'Max Items', desc = 'Maximum number of active toast rows shown at once. Additional rewards wait in the queue.',
            default = DEFAULT_MAX_ITEMS, minValue = 1, maxValue = MAX_ITEMS_LIMIT, valueStep = 1,
            get = function() return db().maxItems or DEFAULT_MAX_ITEMS end,
            set = function(_, value, fromReset)
                db().maxItems = (fromReset and DEFAULT_MAX_ITEMS or value)
                if toasts.feed then toasts.feed:TrimToCount(db().maxItems) end
                toasts:ApplyLayout()
                if toasts:HasQueuedEntries() then toasts:SchedulePresentationQueue(0) end
            end,
        },
        {
            kind = EditMode.SettingType.Slider,
            name = 'Active Opacity', desc = 'Feed opacity while at least one reward is visible.',
            default = 1, minValue = 0.1, maxValue = 1, valueStep = 0.05,
            get = function() return db().activeOpacity end,
            set = function(_, value, fromReset)
                db().activeOpacity = (fromReset and 1 or value)
                toasts:Touch()
            end,
        },
        {
            kind = EditMode.SettingType.Slider,
            name = 'Fade Delay', desc = FADE_DELAY_DESC,
            default = 15, minValue = 0, maxValue = 120, valueStep = 1,
            get = function() return db().fadeDelay end,
            set = function(_, value, fromReset)
                db().fadeDelay = (fromReset and 15 or value)
                toasts:Touch()
            end,
        },
        {
            kind = EditMode.SettingType.Dropdown,
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
                toasts:ApplyFont()
            end,
        },
    })

    EditMode:RegisterCallback('layout', function(layoutName)
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
end

function toasts:ApplyFont()
    if not self.feed then return end
    self.feed:SetFonts(self:FontMetrics())
    self:ApplyLayout()
end

--#endregion

--#region ── Layout ─────────────────────────────────────────────────────────────

function toasts:ApplyLayout()
    local frame = self.panel
    if not frame then return end

    local width = db().width or DEFAULT_WIDTH

    if self.feed then
        self.feed:SetWidth(width - PAD * 2)
        local viewportHeight = self.feed:GetTailHeight(db().maxItems or DEFAULT_MAX_ITEMS)
        frame:SetSize(width, viewportHeight + PAD * 2)
        self.feed:SetViewportHeight(viewportHeight)
    else
        frame:SetSize(width, PAD * 2 + 1)
    end
end

--#endregion

--#region ── Fade / activity ──────────────────────────────────────────────────

function toasts:Touch()
    self.lastActivity = now()
end

function toasts:UpdateFade(dt)
    if not self.panel then return end

    local currentTime = now()
    local hasVisible = true
    if self.feed then
        hasVisible = self.feed:UpdateRowFade(currentTime)
        if self.feed:RemoveExpiredRows(currentTime) > 0 then
            self:ApplyLayout()
            if self:HasQueuedEntries() then self:SchedulePresentationQueue(0) end
        end
    end

    local hovered = self.feed and self.feed.hovering
    local target = db().activeOpacity or 1
    if not hovered and not hasVisible then
        target = 0
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

--#endregion

--#region ── Panel controls ─────────────────────────────────────────────────────

function toasts:Toggle()
    if not self.panel then return end
    if self.panel:IsShown() then
        self.panel:Hide()
    else
        self.panel:Show()
        self:Touch()
    end
end

function toasts:ClosePanel()
    if self.panel then self.panel:Hide() end
end

function toasts:ClearToasts()
    self:ClearPresentationQueue()
    if self.feed then self.feed:Clear() end
    self:ApplyLayout()
end

--#endregion

--#region ── Defaults ─────────────────────────────────────────────────────────

function toasts:GetDefaults()
    return {
        toasts = {
            enabled = true,
            -- Position (per Edit Mode layout)
            positions = {},
            -- Sizing / appearance
            width = DEFAULT_WIDTH,
            maxItems = DEFAULT_MAX_ITEMS,
            activeOpacity = 1,
            fadeDelay = 15,
            fontFace = 'Arial Narrow',
            fontSize = 14,
            -- Reward categories
            items = true,
            money = true,
            currency = true,
            reputation = true,
            system = true,
            filterJunk = true,
        },
    }
end

--#endregion

--#region ── Options ──────────────────────────────────────────────────────────

function toasts:NotifyChange()
    local registry = LibStub('AceConfigRegistry-3.0', true)
    if registry then registry:NotifyChange(addonName) end
end

function toasts:BuildArgs()
    return {
        description = {
            name = 'A live feed for rewards and system messages. Recognized lines are removed '
                .. 'from Blizzard chat while their Toasts category is enabled. System messages are '
                .. 'also removed from CouchMode Chat when both Toasts and this category are enabled.',
            type = 'description',
            order = 1,
        },
        enabled = {
            name = 'Enable',
            desc = 'Show Toasts and hide recognized lines from Blizzard chat.',
            type = 'toggle',
            order = 2,
            get = function() return db().enabled end,
            set = function(_, value)
                db().enabled = value
                if value then toasts:Enable() else toasts:Disable() end
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
        system = {
            name = 'System Messages',
            desc = 'Show system messages in a distinct toast style instead of duplicating them in CouchMode Chat.',
            type = 'toggle', order = 11,
            get = function() return db().system end,
            set = function(_, value) db().system = value end,
        },
        filterJunk = {
            name = 'Filter Junk',
            desc = 'Hide repetitive action errors such as “Out of range” and “You have no target.”',
            type = 'toggle', order = 12,
            get = function() return db().filterJunk end,
            set = function(_, value) db().filterJunk = value end,
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
                    set = function(_, value) db().width = value; toasts:ApplyLayout() end,
                },
                maxItems = {
                    name = 'Max Items',
                    desc = 'Maximum number of active toast rows shown at once. Additional rewards wait in the queue.',
                    type = 'range', min = 1, max = MAX_ITEMS_LIMIT, step = 1, order = 2,
                    get = function() return db().maxItems or DEFAULT_MAX_ITEMS end,
                    set = function(_, value)
                        db().maxItems = value
                        if toasts.feed then toasts.feed:TrimToCount(value) end
                        toasts:ApplyLayout()
                        if toasts:HasQueuedEntries() then toasts:SchedulePresentationQueue(0) end
                    end,
                },
                activeOpacity = {
                    name = 'Active Opacity', desc = 'Feed opacity while at least one reward is visible.',
                    type = 'range', min = 0.1, max = 1, step = 0.05, order = 4,
                    get = function() return db().activeOpacity end,
                    set = function(_, value) db().activeOpacity = value; toasts:Touch() end,
                },
                fadeDelay = {
                    name = 'Fade Delay', desc = FADE_DELAY_DESC,
                    type = 'range', min = 0, max = 120, step = 1, order = 6,
                    get = function() return db().fadeDelay end,
                    set = function(_, value) db().fadeDelay = value; toasts:Touch() end,
                },
                fontFace = {
                    name = 'Font', desc = 'Font used for reward text.',
                    type = 'select', style = 'dropdown', order = 8,
                    values = addon.Media.GetFontOptions(),
                    get = function() return db().fontFace end,
                    set = function(_, value) db().fontFace = value; toasts:ApplyFont() end,
                },
                fontSize = {
                    name = 'Font Size', desc = 'Reward text size.',
                    type = 'range', min = 8, max = 28, step = 1, order = 9,
                    get = function() return db().fontSize end,
                    set = function(_, value) db().fontSize = value; toasts:ApplyFont() end,
                },
            },
        },
        misc = {
            name = 'Misc',
            type = 'group',
            inline = true,
            order = 99,
            args = {
                testRewards = {
                    name = 'Test Rewards',
                    desc = 'Fire mock toasts for every category.\n\nAlso available as /cm toasts mock.',
                    type = 'execute', order = 1,
                    func = function() toasts:RunMock('all') end,
                },
            },
        },
    }
end

function toasts:GetOptions()
    self.optionsArgs = self.optionsArgs or self:BuildArgs()
    return 'toasts', {
        name = 'Toasts',
        type = 'group',
        order = PANEL_ORDER,
        args = self.optionsArgs,
    }
end

--#endregion

--#region ── Testing / mock ───────────────────────────────────────────────────

function toasts:Notify(text)
    print('CouchMode: ' .. tostring(text))
end

--- Applies one mock reward through the same paths live rewards use.
---@param spec table
function toasts:MockEntry(spec)
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
    elseif spec.kind == 'system' then
        local event = spec.event or 'CHAT_MSG_SYSTEM'
        if event == 'UI_ERROR_MESSAGE' or event == 'UI_INFO_MESSAGE' then
            self:OnUIMessage(event, nil, spec.text)
        else
            self:OnSystemMessage(event, spec.text)
        end
        return
    end

    if entry then self:AddEntry(entry) end
end

function toasts:RunMock(setName)
    local mock = addon.ToastMock
    if not mock then return end
    if not db().enabled then
        self:Notify('enable Toasts before running the mock.')
        return
    end

    local resolved = mock.Resolve(setName)
    if not resolved then
        self:Notify(('Unknown mock set "%s". Available: %s, all.')
            :format(tostring(setName), table.concat(mock.Names(), ', ')))
        return
    end

    local count = mock.Run(self, resolved)
    self:Notify(('Toasts mock: fired %d messages from "%s".'):format(count, resolved))
end

--- Entry point for `/cm toasts ...`.
---@param sub string
---@param arg string
function toasts:HandleCommand(sub, arg)
    sub = (sub or ''):lower()
    if sub == 'mock' or sub == 'test' then
        toasts:RunMock(arg)
    elseif sub == 'items' or sub == 'item' then
        -- Convenience shortcut for the item reward set.
        toasts:RunMock('item')
    elseif sub == 'clear' then
        toasts:ClearToasts()
        toasts:Notify('Active Toasts and queued rewards cleared.')
    elseif sub == 'sets' then
        toasts:Notify('Toasts mock sets: ' .. table.concat(addon.ToastMock.Names(), ', ') .. ', all')
    else
        toasts:Notify('CouchMode Toasts: /cm toasts items | /cm toasts mock [set] | /cm toasts sets | /cm toasts clear')
    end
end

--#endregion

--#region ── Event routing table ────────────────────────────────────────────────

--- Maps the support events in ToastSources to module handlers.
toasts.EVENT_HANDLERS = {
    PLAYER_MONEY = 'OnPlayerMoney',
    CURRENCY_DISPLAY_UPDATE = 'OnCurrencyUpdate',
    CHAT_MSG_LOOT = 'OnLootMessage',
    CHAT_MSG_COMBAT_FACTION_CHANGE = 'OnReputationMessage',
    GET_ITEM_INFO_RECEIVED = 'OnItemInfoReceived',
    ITEM_DATA_LOAD_RESULT = 'OnItemInfoReceived',
    BAG_UPDATE_DELAYED = 'OnItemInfoReceived',
    PLAYER_ENTERING_WORLD = 'OnPlayerEnteringWorld',
    TRANSMOG_COLLECTION_SOURCE_ADDED = 'OnTransmogSourceAdded',
    SYSMSG = 'OnSystemMessage',
    UI_ERROR_MESSAGE = 'OnUIMessage',
    UI_INFO_MESSAGE = 'OnUIMessage',
}
for _, event in ipairs(Sources.SYSTEM_EVENTS) do
    toasts.EVENT_HANDLERS[event] = 'OnSystemMessage'
end

--#endregion

--#region ── Bindings ──────────────────────────────────────────────────────────

function CouchMode_ToastsToggle() addon.Toasts:Toggle() end
function CouchMode_ToastsClose() addon.Toasts:ClosePanel() end

BINDING_NAME_COUCHMODE_TOASTS_TOGGLE = 'Toggle Toasts'
BINDING_NAME_COUCHMODE_TOASTS_CLOSE = 'Close Toasts'

--#endregion

toasts:Enable()
