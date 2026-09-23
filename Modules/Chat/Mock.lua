--[[ Mock.lua
Fires representative chat events for every source CouchMode understands.

The messages are pushed through the real ChatRouter (not injected directly into
the feed), so a mock run exercises event normalization, deduplication, category
mapping, grouping, filters, blocking and identity resolution exactly like live
chat would.

Driven from chat:
    /cm chat mock            -- every set
    /cm chat mock npc        -- a single set
    /cm chat mock rich       -- links, emoji and long wrapping text
    /cm chat clear           -- wipe the session history
]]

local addonName, addon = ...
addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)

local M = {}

M.STEP_DELAY = 0.35

--#region ── Identity helpers ────────────────────────────────────────────────────

local function playerIdentity()
    return UnitName('player'), UnitGUID('player')
end

--- Returns a real group member's name/GUID when available, otherwise the
--- player's own. Falls back to a synthetic GUID when nothing is accessible.
---@param index number
---@return string? name
---@return string? guid
local function groupIdentity(index)
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    if count > 0 then
        local token = (IsInRaid and IsInRaid()) and ('raid' .. index) or ('party' .. index)
        local name, guid = UnitName(token), UnitGUID(token)
        if name and guid then return name, guid end
    end
    local name, guid = playerIdentity()
    if name and guid and index == 1 then return name, guid end
    local synthetic = ('Player-1-%08X'):format(0x0A0B0C00 + index)
    return ('Mock%d'):format(index), synthetic
end

--#endregion

--#region ── Set builders ────────────────────────────────────────────────────────

local function npcSet()
    return {
        { event = 'CHAT_MSG_MONSTER_SAY', sender = 'Worg Pup', text = 'Stay a while, and listen.' },
        { event = 'CHAT_MSG_MONSTER_YELL', sender = 'Mocha', text = 'For the Horde!' },
        { event = 'CHAT_MSG_MONSTER_WHISPER', sender = 'Bebe', text = 'You carry such a fragile little world.' },
        { event = 'CHAT_MSG_MONSTER_PARTY', sender = 'Panda Cub', text = 'The road ahead is dark, but we walk it together.' },
        { event = 'CHAT_MSG_MONSTER_EMOTE', sender = 'Weevil K. Neevil', text = 'pauses to consider his words.' },
        { event = 'CHAT_MSG_RAID_BOSS_EMOTE', sender = 'Sinister Squashling', text = 'The sky tears open above you.' },
        { event = 'CHAT_MSG_RAID_BOSS_WHISPER', sender = 'Baby Crocolisk', text = 'You were never meant to win this.' },
    }
end

local function whisperSet()
    local meName = playerIdentity()
    return {
        { event = 'CHAT_MSG_WHISPER', sender = 'Anon', sender2 = 'Anon-Tichondrius', text = 'hey, got a sec?' },
        { event = 'CHAT_MSG_WHISPER_INFORM', sender = meName, sender2 = meName, text = 'sure, one moment' },
        { event = 'CHAT_MSG_BN_WHISPER', sender = 'BattleTag', sender2 = 'BattleTag', bnSender = 90210, text = 'want to run a key?' },
        { event = 'CHAT_MSG_BN_WHISPER_INFORM', sender = meName, sender2 = meName, bnSender = 90210, text = 'sure!' },
    }
end

local function groupSet()
    local n1, g1 = groupIdentity(1)
    local n2, g2 = groupIdentity(2)
    local n3, g3 = groupIdentity(3)
    return {
        { event = 'CHAT_MSG_PARTY', sender = n1, guid = g1, text = 'incoming pull' },
        { event = 'CHAT_MSG_PARTY', sender = n2, guid = g2, text = 'kicking the caster' },
        { event = 'CHAT_MSG_PARTY_LEADER', sender = n3, guid = g3, text = 'stack up on me' },
        { event = 'CHAT_MSG_RAID', sender = n2, guid = g2, text = 'tank swap at 50%' },
        { event = 'CHAT_MSG_RAID_LEADER', sender = n1, guid = g1, text = 'lust on pull' },
        { event = 'CHAT_MSG_INSTANCE_CHAT', sender = n3, guid = g3, text = 'need a portal out' },
        { event = 'CHAT_MSG_PARTY_GUIDE', sender = n1, guid = g1, text = 'welcome, follow the markers' },
    }
end

local function guildSet()
    local n1, g1 = groupIdentity(1)
    local n2, g2 = groupIdentity(2)
    return {
        { event = 'CHAT_MSG_GUILD', sender = n1, guid = g1, text = 'gm tonight?' },
        { event = 'CHAT_MSG_GUILD', sender = n2, guid = g2, text = 'yep, 8pm server' },
        { event = 'CHAT_MSG_OFFICER', sender = n1, guid = g1, text = 'officer note updated' },
    }
end

local function publicSet()
    local meName, meGuid = playerIdentity()
    return {
        { event = 'CHAT_MSG_SAY', sender = meName, guid = meGuid, text = 'Hello world!' },
        { event = 'CHAT_MSG_YELL', sender = 'Advertiser', text = 'WTS boosts, pst' },
        { event = 'CHAT_MSG_TEXT_EMOTE', sender = 'Anon', text = 'waves at everyone.' },
        { event = 'CHAT_MSG_EMOTE', sender = 'Anon', text = 'dances.' },
        { event = 'CHAT_MSG_CHANNEL', sender = 'Trader', channelName = '2. Trade', channelID = 2, channelBase = 'Trade', text = 'WTS [Thunderfury] 500g' },
        { event = 'CHAT_MSG_CHANNEL', sender = 'Trader', channelName = '2. Trade', channelID = 2, channelBase = 'Trade', text = 'also buying mats' },
        { event = 'CHAT_MSG_COMMUNITIES_CHANNEL', sender = 'Community Friend', channelName = 'My Community', channelBase = 'My Community', text = 'anyone up for keys?' },
    }
end

local function systemSet()
    return {
        { event = 'CHAT_MSG_SYSTEM', text = 'You are now AFK.' },
        { event = 'CHAT_MSG_SYSTEM', text = 'No player named "Ghost" is currently playing.' },
        { event = 'CHAT_MSG_IGNORED', text = 'Anon is ignoring you.' },
        { event = 'CHAT_MSG_FILTERED', text = '[filtered]' },
        { event = 'CHAT_MSG_RESTRICTED', text = 'Trial accounts cannot use this channel.' },
        { event = 'CHAT_MSG_CHANNEL_NOTICE', text = 'Joined channel: Trade' },
        { event = 'CHAT_MSG_CHANNEL_NOTICE_USER', text = 'Anon has joined the channel.' },
        { event = 'CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE', text = 'BattleTag is offline.' },
        { event = 'CHAT_MSG_BN_INLINE_TOAST_ALERT', text = 'BattleTag has come online.' },
        { event = 'CHAT_MSG_BN_INLINE_TOAST_BROADCAST', text = 'BattleTag: anyone around?' },
    }
end

local function richSet()
    local meName, meGuid = playerIdentity()
    return {
        { event = 'CHAT_MSG_SAY', sender = 'Linker', text = 'check out |cff0070dd|Hitem:19019::::::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r' },
        { event = 'CHAT_MSG_SAY', sender = 'Mage', text = 'casting |cff71d5ff|Hspell:133|h[Fireball]|h|r next' },
        { event = 'CHAT_MSG_PARTY', sender = meName, guid = meGuid, text = 'whisper |cff33ff99|Hplayer:Anon|h[Anon]|h|r for the invite' },
        { event = 'CHAT_MSG_SAY', sender = 'Chatty', text = 'This is a deliberately long line of chatter meant to wrap across several rows so the feed layout, indentation and bottom-anchored scrolling can be checked with a realistic paragraph of text.' },
        { event = 'CHAT_MSG_SAY', sender = 'Chatty', text = 'Second paragraph from the same speaker, which should group under the existing header.' },
    }
end

--#endregion

--#region ── Scenario registry ──────────────────────────────────────────────────

M.SETS = {
    npc = npcSet,
    whisper = whisperSet,
    group = groupSet,
    guild = guildSet,
    public = publicSet,
    system = systemSet,
    rich = richSet,
}

M.ORDER = { 'npc', 'whisper', 'group', 'guild', 'public', 'system', 'rich' }

---@return string[]
function M.Names()
    return M.ORDER
end

--- Flattens the requested set (or every set for 'all').
---@param setName string
---@return table[] entries
function M.Collect(setName)
    local Utils = addon and addon.Utils
    local out = {}

    local function addAll(builder)
        for _, entry in ipairs(builder()) do
            -- Never fire an event this client does not know about.
            local exists = Utils and Utils.EventExists and Utils.EventExists(entry.event)
            if exists ~= false then out[#out + 1] = entry end
        end
    end

    if setName == 'all' or setName == '' or setName == nil then
        for _, name in ipairs(M.ORDER) do addAll(M.SETS[name]) end
    elseif M.SETS[setName] then
        addAll(M.SETS[setName])
    end

    return out
end

--#endregion

--#region ── Firing ─────────────────────────────────────────────────────────────

--- Emits one scenario entry as a raw Blizzard chat event.
---@param router table
---@param entry table
function M.Fire(router, entry)
    router:OnEvent(entry.event,
        entry.text,           -- arg1  text
        entry.sender,         -- arg2  playerName
        entry.language or '', -- arg3  languageName
        entry.channelName or '', -- arg4  channelName
        entry.sender2 or entry.sender, -- arg5 playerName2
        entry.flags or '',    -- arg6  specialFlags
        entry.zone or 0,      -- arg7  zoneChannelID
        entry.channelID or 0, -- arg8  channelIndex
        entry.channelBase or '', -- arg9 channelBaseName
        entry.languageID or 0, -- arg10 languageID
        nil,                  -- arg11 lineID (nil: never deduplicated)
        entry.guid,           -- arg12 guid
        entry.bnSender)       -- arg13 bnSenderID
end

--- Fires a set with a staggered delay so grouping/fade behaviour is visible.
---@param router table
---@param setName string
---@param stepDelay number?
---@return number fired
function M.Run(router, setName, stepDelay)
    local entries = M.Collect(setName)
    stepDelay = stepDelay or M.STEP_DELAY
    for i = 1, #entries do
        local entry = entries[i]
        C_Timer.After((i - 1) * stepDelay, function()
            M.Fire(router, entry)
        end)
    end
    return #entries
end

if addon then addon.ChatMock = M end
return M
