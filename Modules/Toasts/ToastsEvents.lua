local addonName, addon = ...
addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)
local toasts = addon.Toasts
local Sources = addon.ToastSources

local function db() return addon.db.profile.toasts end
local function now() return (type(GetTime) == 'function') and GetTime() or 0 end
local REFRESH_DELAY = 0.25
local QUEST_ICON_ATLAS = toasts.QUEST_ICON_ATLAS

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
