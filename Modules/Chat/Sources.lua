--[[ Sources.lua
Shared, dependency-light description of every chat source CouchMode's Chat
module understands.

This file is intentionally free of Ace/Lib dependencies so it can be loaded by
the pure Lua test suite:
    local chunk = assert(loadfile('Modules/Chat/Sources.lua'))
    local Sources = chunk('CouchMode', fakeAddon)
]]

local addonName, addon = ...
addon = addon or (LibStub and LibStub('AceAddon-3.0'):GetAddon(addonName))

local M = {}

--#region ── Safe value helpers ───────────────────────────────────────────────

-- WoW's "secret" values cannot be compared, hashed, measured or concatenated.
-- Every helper below treats a secret value as "unknown" instead of touching it.
local function isSecret(value)
    local fn = issecretvalue
    return fn ~= nil and fn(value)
end
M.isSecret = isSecret

--- Whether a value is safe to compare/hash/store.
---@param value any
---@return boolean
function M.isSafe(value)
    return value ~= nil and not isSecret(value)
end

--#endregion

--#region ── Categories ───────────────────────────────────────────────────────

---@alias ChatSourceCategory
---| 'NPC'
---| 'WHISPER'
---| 'GROUP'
---| 'GUILD'
---| 'PUBLIC'
---| 'SYSTEM'

---@type table<string, string[]>
M.EVENTS_BY_CATEGORY = {
    NPC = {
        'CHAT_MSG_MONSTER_SAY',
        'CHAT_MSG_MONSTER_YELL',
        'CHAT_MSG_MONSTER_WHISPER',
        'CHAT_MSG_MONSTER_PARTY',
        'CHAT_MSG_MONSTER_EMOTE',
        'CHAT_MSG_RAID_BOSS_EMOTE',
        'CHAT_MSG_RAID_BOSS_WHISPER',
    },
    WHISPER = {
        'CHAT_MSG_WHISPER',
        'CHAT_MSG_WHISPER_INFORM',
        'CHAT_MSG_BN_WHISPER',
        'CHAT_MSG_BN_WHISPER_INFORM',
    },
    GROUP = {
        'CHAT_MSG_PARTY',
        'CHAT_MSG_PARTY_LEADER',
        'CHAT_MSG_PARTY_GUIDE',
        'CHAT_MSG_RAID',
        'CHAT_MSG_RAID_LEADER',
        'CHAT_MSG_RAID_WARNING',
        'CHAT_MSG_INSTANCE_CHAT',
        'CHAT_MSG_INSTANCE_CHAT_LEADER',
    },
    GUILD = {
        'CHAT_MSG_GUILD',
        'CHAT_MSG_OFFICER',
    },
    PUBLIC = {
        'CHAT_MSG_SAY',
        'CHAT_MSG_YELL',
        'CHAT_MSG_EMOTE',
        'CHAT_MSG_TEXT_EMOTE',
        'CHAT_MSG_CHANNEL',
        'CHAT_MSG_COMMUNITIES_CHANNEL',
    },
    SYSTEM = {
        'CHAT_MSG_SYSTEM',
        'CHAT_MSG_CHANNEL_NOTICE',
        'CHAT_MSG_CHANNEL_NOTICE_USER',
        'CHAT_MSG_IGNORED',
        'CHAT_MSG_FILTERED',
        'CHAT_MSG_RESTRICTED',
        'CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE',
        'CHAT_MSG_BN_INLINE_TOAST_ALERT',
        'CHAT_MSG_BN_INLINE_TOAST_BROADCAST',
    },
}

---@type table<string, ChatSourceCategory>
M.CATEGORY_BY_EVENT = {}
for category, events in pairs(M.EVENTS_BY_CATEGORY) do
    for _, event in ipairs(events) do
        M.CATEGORY_BY_EVENT[event] = category
    end
end

--- Events that only ship on a subset of clients. Registering an event the
--- running client does not know throws a hard error, so the router consults
--- this map (and then the client itself via C_EventUtils.IsEventValid) before
--- it touches the event system.
---@type table<string, WowFlavor>
M.FLAVOR_SPECIFIC = {
    ['CHAT_MSG_PARTY_GUIDE'] = 'retail',
}

--- All supported events that exist on the given flavor. Pass nil to skip flavor
--- filtering (used by tests and by callers that handle validity separately).
---@param flavor WowFlavor?
---@return string[]
function M.EventsForFlavor(flavor)
    local out = {}
    for _, events in pairs(M.EVENTS_BY_CATEGORY) do
        for _, event in ipairs(events) do
            local required = M.FLAVOR_SPECIFIC[event]
            if not required or flavor == nil or required == flavor then
                out[#out + 1] = event
            end
        end
    end
    table.sort(out)
    return out
end

-- NPC dialogue is the only source eligible for overhead bubble replacement.
M.NPC_EVENTS = {}
for _, event in ipairs(M.EVENTS_BY_CATEGORY.NPC) do
    M.NPC_EVENTS[event] = true
end

M.WHISPER_EVENTS = {}
for _, event in ipairs(M.EVENTS_BY_CATEGORY.WHISPER) do
    M.WHISPER_EVENTS[event] = true
end

--- Returns the category for an event name, or nil when the event is unsupported.
---@param event string
---@return ChatSourceCategory?
function M.GetCategory(event)
    return M.CATEGORY_BY_EVENT[event]
end

---@param event string
---@return boolean
function M.IsNpc(event)
    return M.NPC_EVENTS[event] == true
end

--- Whether the speech is addressed to the group rather than the open world.
---@param event string
---@return boolean
function M.IsGroupNpc(event)
    return event == 'CHAT_MSG_MONSTER_PARTY' or event == 'CHAT_MSG_MONSTER_WHISPER'
        or event == 'CHAT_MSG_RAID_BOSS_WHISPER'
end

--#endregion

--#region ── Fixed filters ─────────────────────────────────────────────────────

--- Ordered list of fixed filters shown in the panel.
---@type { key: string, label: string }[]
M.FILTERS = {
    { key = 'ALL',     label = 'All' },
    { key = 'NPC',     label = 'NPC' },
    { key = 'WHISPER', label = 'Whispers' },
    { key = 'GROUP',   label = 'Group' },
    { key = 'GUILD',   label = 'Guild' },
    { key = 'PUBLIC',  label = 'Public' },
    { key = 'SYSTEM',  label = 'System' },
}

M.FILTER_KEYS = {}
for i, filter in ipairs(M.FILTERS) do
    M.FILTER_KEYS[filter.key] = i
end

---@param msg ChatMessage
---@param filter string
---@return boolean
function M.MatchesFilter(msg, filter)
    if not filter or filter == 'ALL' then return true end
    return msg.category == filter
end

---@param filter string
---@return string
function M.FilterLabel(filter)
    local index = M.FILTER_KEYS[filter]
    return index and M.FILTERS[index].label or (filter or 'All')
end

--- Cycles through the fixed filters, wrapping around.
---@param filter string?
---@param delta number
---@return string
function M.CycleFilter(filter, delta)
    local index = M.FILTER_KEYS[filter or 'ALL'] or 1
    local count = #M.FILTERS
    index = ((index - 1 + (delta or 1)) % count + count) % count + 1
    return M.FILTERS[index].key
end

--#endregion

--#region ── Type helpers ──────────────────────────────────────────────────────

--- Strips the CHAT_MSG_ prefix and normalizes leader variants.
---@param event string
---@return string
function M.ShortType(event)
    local short = event:gsub('^CHAT_MSG_', ''):gsub('_LEADER$', ''):gsub('^MONSTER_', '')
    if short == 'INSTANCE_CHAT' then short = 'INSTANCE' end
    if short == 'BN_WHISPER_INFORM' then short = 'WHISPER_INFORM' end
    if short == 'BN_WHISPER' then short = 'WHISPER' end
    return short
end

--- Human-readable fallback for sources that do not provide a channel base.
--- Event names stay internal; headers use title-cased, space-separated labels.
---@param event string
---@return string
function M.DisplayType(event)
    local labels = {
        BN_WHISPER = 'Battle.net Whisper',
        WHISPER_INFORM = 'Whisper',
        TEXT_EMOTE = 'Emote',
        RAID_BOSS_EMOTE = 'Boss Emote',
        RAID_BOSS_WHISPER = 'Boss Whisper',
        RAID_WARNING = 'Raid Warning',
        INSTANCE = 'Instance',
        CHANNEL_NOTICE = 'Channel Notice',
        CHANNEL_NOTICE_USER = 'Channel Notice',
        BN_WHISPER_PLAYER_OFFLINE = 'Battle.net',
        BN_INLINE_TOAST_ALERT = 'Battle.net',
        BN_INLINE_TOAST_BROADCAST = 'Battle.net',
    }
    local short = M.ShortType(event)
    if labels[short] then return labels[short] end
    return short:gsub('_', ' '):gsub('(%a)([%a]*)', function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

--- Maps a chat event to its ChatTypeInfo key (exact event suffix).
---@param event string
---@return string
function M.ChatTypeKey(event)
    return (event:gsub('^CHAT_MSG_', ''))
end

---@param event string
---@return boolean
function M.IsOutgoingEvent(event)
    return event == 'CHAT_MSG_WHISPER_INFORM' or event == 'CHAT_MSG_BN_WHISPER_INFORM'
end

--#endregion

--#region ── Normalization ─────────────────────────────────────────────────────

---@class ChatMessage
---@field event       string   Raw CHAT_MSG_* event
---@field type        string   Short type, e.g. 'SAY'
---@field category    string   Source category (NPC/WHISPER/GROUP/GUILD/PUBLIC/SYSTEM)
---@field direction   string   'in'|'out'
---@field timestamp   number   GetTime() when received
---@field displayedAt number? GetTime() when shown in the Chat feed
---@field clock       string   Wall-clock HH:MM:SS
---@field lineID      number?  Blizzard line id (nil when unavailable/secret)
---@field text        string   Raw display text (may be a secret value)
---@field sender      string?  Sender display name
---@field guid        string?  Sender GUID
---@field channelName string?  Raw channel name (e.g. "1. General")
---@field channelBase string?  Channel base name (arg9)
---@field channelID   number?  Channel index (arg8)
---@field zoneChannelID number?
---@field language    string?  Language name
---@field languageID  number?
---@field flags       string?  special flags (GM/AFK/DND/DEV/BOSS)
---@field bnSenderID  number?
---@field isBN        boolean
---@field npcId       number?
---@field displayId   number?
---@field unitToken   string?
---@field blocked     boolean?

local function safeNumber(value)
    if isSecret(value) then return nil end
    if type(value) ~= 'number' or value == 0 then return nil end
    return value
end

local function safeString(value)
    if isSecret(value) then return nil end
    if type(value) ~= 'string' or value == '' then return nil end
    return value
end

--- Builds a normalized message record from a CHAT_MSG_* payload.
--- Pure: only reads globals that exist in both WoW and the test harness.
---@param event string
---@param timestamp number
---@param clock string
---@param ... any  Raw Blizzard arguments
---@return ChatMessage?
function M.Normalize(event, timestamp, clock, ...)
    local category = M.CATEGORY_BY_EVENT[event]
    if not category then return nil end

    local text, sender, language, channelName, sender2, flags, zoneChannelID,
        channelID, channelBase, languageID, lineID, guid, bnSenderID, isMobile,
        isSubtitle, hideInLetterbox = ...

    if isSecret(hideInLetterbox) then hideInLetterbox = nil end
    if hideInLetterbox == true then return nil end

    local direction = M.IsOutgoingEvent(event) and 'out' or 'in'
    if direction == 'in' and guid and not isSecret(guid) then
        local playerGUID = UnitGUID and UnitGUID('player')
        if playerGUID and not isSecret(playerGUID) and playerGUID == guid then
            direction = 'out'
        end
    end
    if direction == 'in' and sender and not isSecret(sender) and UnitName then
        local playerName = UnitName('player')
        if playerName and not isSecret(playerName) and playerName == sender then
            direction = 'out'
        end
    end

    local record = {
        event = event,
        type = M.ShortType(event),
        category = category,
        direction = direction,
        timestamp = timestamp,
        clock = clock,
        lineID = safeNumber(lineID),
        text = text,
        sender = safeString(sender),
        guid = safeString(guid),
        channelName = safeString(channelName),
        channelBase = safeString(channelBase),
        channelID = safeNumber(channelID),
        zoneChannelID = safeNumber(zoneChannelID),
        language = safeString(language),
        languageID = safeNumber(languageID),
        flags = safeString(flags),
        bnSenderID = safeNumber(bnSenderID),
        isBN = (bnSenderID ~= nil and not isSecret(bnSenderID) and bnSenderID ~= 0) or false,
    }

    -- Whisper display name: prefer the realm-qualified "playerName2" when present.
    if record.category == 'WHISPER' then
        record.sender = safeString(sender2) or record.sender
    end

    return record
end

--#endregion

if addon then addon.ChatSources = M end
return M
