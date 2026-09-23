--[[ Sources.lua
Flavor-safe event sources and normalization for CouchMode's Loot module.

This file is intentionally free of Ace/Lib dependencies so it can be loaded by
the pure Lua test suite:
    local chunk = assert(loadfile('Modules/Loot/Sources.lua'))
    local Sources = chunk('CouchMode', fakeAddon)

It owns three responsibilities:
  * describe which Blizzard events carry each reward kind,
  * recognize/normalize accepted rewards (items, money, currency, reputation),
  * enrich accepted items through C_Item without ever touching secret values.

Recognition is driven entirely by Blizzard's localized runtime format strings
(`LOOT_ITEM_SELF`, `FACTION_STANDING_INCREASED`, ...). When a client does not
expose one of those globals the corresponding line is simply not recognized, so
native chat keeps displaying it rather than the addon guessing.
]]

local addonName, addon = ...
addon = addon or (LibStub and LibStub('AceAddon-3.0'):GetAddon(addonName))

local M = {}

--#region ── Safe value helpers ───────────────────────────────────────────────

-- WoW's "secret" values cannot be compared, hashed, measured or concatenated.
-- Every helper treats a secret value as unknown instead of touching it.
local function isSecret(value)
    local fn = issecretvalue
    return fn ~= nil and fn(value)
end
M.isSecret = isSecret

--- Whether a value is safe to compare, index, hash or concatenate.
---@param value any
---@return boolean
function M.isSafe(value)
    return value ~= nil and not isSecret(value)
end

---@param value any
---@return string?
function M.SafeString(value)
    if isSecret(value) then return nil end
    if type(value) ~= 'string' or value == '' then return nil end
    return value
end

---@param value any
---@return number?
function M.SafeNumber(value)
    if isSecret(value) then return nil end
    if type(value) ~= 'number' then return nil end
    return value
end

--#endregion

--#region ── Reward kinds and events ──────────────────────────────────────────

--- The four reward categories the Loot feed understands.
---@alias LootKind 'items'|'money'|'currency'|'reputation'

---@type LootKind[]
M.KINDS = { 'items', 'money', 'currency', 'reputation' }

--- The Blizzard chat event that carries each reward category's text.
---@type table<LootKind, string>
M.KIND_EVENT = {
    items = 'CHAT_MSG_LOOT',
    money = 'CHAT_MSG_MONEY',
    currency = 'CHAT_MSG_CURRENCY',
    reputation = 'CHAT_MSG_COMBAT_FACTION_CHANGE',
}

--- Reverse lookup: chat event -> reward category.
---@type table<string, LootKind>
M.EVENT_KIND = {}
for kind, event in pairs(M.KIND_EVENT) do
    M.EVENT_KIND[event] = kind
end

--- Every chat event the native-chat filters care about.
---@type string[]
M.EVENTS = { 'CHAT_MSG_LOOT', 'CHAT_MSG_MONEY', 'CHAT_MSG_CURRENCY', 'CHAT_MSG_COMBAT_FACTION_CHANGE' }

--- Events the module registers for reward ingestion and item refresh. They are
--- registered through addon.Utils.RegisterEventIfValid so an unknown event can
--- never throw.
---@type string[]
M.SUPPORT_EVENTS = {
    'PLAYER_MONEY',
    'CURRENCY_DISPLAY_UPDATE',
    -- Chat events that feed rows (money/currency come from the API events above;
    -- their chat lines are only filtered).
    'CHAT_MSG_LOOT',
    'CHAT_MSG_COMBAT_FACTION_CHANGE',
    -- Item data / bag settling, used to refresh uncached rows and carried counts.
    'GET_ITEM_INFO_RECEIVED',
    'ITEM_DATA_LOAD_RESULT',
    'BAG_UPDATE_DELAYED',
    'PLAYER_ENTERING_WORLD',
}

--#endregion

--#region ── Localized format matchers ─────────────────────────────────────────

--- Global format strings that describe a reward line. Only formats available on
--- the running client are compiled, so recognition automatically degrades to
--- "keep the line in native chat" on trimmed-down clients.
---@type table<string, string[]>
local PATTERN_NAMES = {
    -- Local-player item acquisitions ("You receive loot: ..."). Multiple-item
    -- formats are listed first: the single-item pattern would otherwise swallow
    -- the trailing "xN" as part of the item link.
    itemSelf = {
        'LOOT_ITEM_SELF_MULTIPLE',
        'LOOT_ITEM_PUSHED_SELF_MULTIPLE',
        'LOOT_ITEM_CREATED_SELF_MULTIPLE',
        'LOOT_ITEM_SELF',
        'LOOT_ITEM_PUSHED_SELF',
        'LOOT_ITEM_CREATED_SELF',
    },
    -- Other players' acquisitions, kept in native chat on purpose.
    itemGroup = {
        'LOOT_ITEM_MULTIPLE',
        'LOOT_ITEM_PUSHED_MULTIPLE',
        'LOOT_ITEM_CREATED_MULTIPLE',
        'LOOT_ITEM',
        'LOOT_ITEM_PUSHED',
        'LOOT_ITEM_CREATED',
    },
    -- Money the local player loots.
    moneySelf = {
        'LOOT_MONEY_SELF',
    },
    currency = {
        'CURRENCY_GAINED',
        'CURRENCY_GAINED_MULTIPLE',
        'CURRENCY_GAINED_MULTIPLE_BONUS',
        'CURRENCY_GAINED_BONUS',
    },
    -- Positive reputation changes only; decreases are deliberately excluded.
    reputation = {
        'FACTION_STANDING_INCREASED',
        'FACTION_STANDING_INCREASED_ACCOUNT_WIDE',
        'FACTION_STANDING_INCREASED_BY',
    },
}

--- Escapes one literal character for use inside a Lua pattern.
---@param char string
---@return string
local function escapePatternChar(char)
    if char:match('[%^%$%(%)%%%.%[%]%*%+%-%?]') then
        return '%' .. char
    end
    return char
end

--- Converts a Blizzard printf-style format string into an anchored Lua pattern.
--- `%s` captures a non-greedy span, `%d` captures an integer, `%%` a literal
--- percent; every other character is escaped. Positional specifiers (`%1$s`)
--- are not understood and therefore never match, which is the safe outcome.
---@param format string
---@return string
function M.FormatToPattern(format)
    local out = {}
    local i = 1
    local n = #format
    while i <= n do
        local char = format:sub(i, i)
        if char == '%' then
            local spec = format:sub(i + 1, i + 1)
            if spec == '%' then
                out[#out + 1] = '%%'
                i = i + 2
            elseif spec == 's' or spec == 'S' then
                out[#out + 1] = '(.-)'
                i = i + 2
            elseif spec == 'd' or spec == 'D' or spec == 'i' or spec == 'u' then
                out[#out + 1] = '(%-?%d+)'
                i = i + 2
            else
                -- Unknown specifier: keep a literal percent and continue.
                out[#out + 1] = '%%'
                i = i + 1
            end
        else
            out[#out + 1] = escapePatternChar(char)
            i = i + 1
        end
    end
    return '^' .. table.concat(out) .. '$'
end

local patternCache = {}

--- Clears the compiled-format cache. Tests call this after installing fake
--- global format strings.
function M.ResetPatternCache()
    patternCache = {}
end

--- Compiles (and caches) the patterns for one format set.
---@param setName string
---@return string[]
function M.Patterns(setName)
    local cached = patternCache[setName]
    if cached then return cached end

    local patterns = {}
    local names = PATTERN_NAMES[setName] or {}
    for i = 1, #names do
        local format = _G and _G[names[i]]
        if type(format) == 'string' and format ~= '' and format:find('%%[sdSDiu]') then
            patterns[#patterns + 1] = M.FormatToPattern(format)
        end
    end

    patternCache[setName] = patterns
    return patterns
end

--- Tries each pattern in turn and returns the first set of captures.
---@param text any
---@param patterns string[]
---@return string[]? captures
function M.MatchFormat(text, patterns)
    if not M.isSafe(text) or type(text) ~= 'string' or text == '' then return nil end
    for i = 1, #patterns do
        local captures = { text:match(patterns[i]) }
        if captures[1] ~= nil then return captures end
    end
    return nil
end

--- Extracts display text from an inline markup link, falling back to the whole
--- value when there is no `|h[Name]|h` span.
---@param value any
---@return string?
function M.DisplayFromMarkup(value)
    if type(value) ~= 'string' then return nil end
    local text = value:match('|h%[(.-)%]|h')
    return text or value
end

--#endregion

--#region ── Item hyperlinks ───────────────────────────────────────────────────

--- Splits an item hyperlink into its numeric id, display name and the intact
--- hyperlink (color codes included) for tooltips.
---@param link any
---@return number? itemID
---@return string? name
---@return string? hyperlink
function M.ExtractItemIdentity(link)
    if not M.isSafe(link) or type(link) ~= 'string' or link == '' then return nil end
    local itemID = tonumber(link:match('|Hitem:(%d+)'))
    local name = link:match('|h%[(.-)%]|h')
    return itemID, name or link, link
end

--#endregion

--#region ── Local-player recognition ──────────────────────────────────────────

--- Recognizes a local-player item acquisition.
---@param text any
---@return { itemID: number?, name: string?, hyperlink: string, count: number }?
function M.ParseSelfLoot(text)
    local captures = M.MatchFormat(text, M.Patterns('itemSelf'))
    if not captures then return nil end

    local link = captures[1]
    local count = 1
    if captures[2] then
        local n = tonumber(captures[2])
        if n then count = n end
    end

    local itemID, name, hyperlink = M.ExtractItemIdentity(link)
    return {
        itemID = itemID,
        name = name,
        hyperlink = hyperlink or link,
        count = count,
    }
end

--- Whether a loot line belongs to another player (and must stay in native chat).
---@param text any
---@return boolean
function M.IsGroupLoot(text)
    return M.MatchFormat(text, M.Patterns('itemGroup')) ~= nil
end

--- Whether a money line is the local player's own loot.
---@param text any
---@return boolean
function M.IsSelfMoneyLine(text)
    return M.MatchFormat(text, M.Patterns('moneySelf')) ~= nil
end

--- Parses a positive reputation gain into its faction name and amount.
---@param text any
---@return { name: string?, amount: number }?
function M.ParseReputationGain(text)
    local captures = M.MatchFormat(text, M.Patterns('reputation'))
    if not captures then return nil end

    local name, amount
    for i = 1, #captures do
        local value = captures[i]
        if type(value) == 'string' and value ~= '' then
            if value:match('^%-?%d+$') then
                if not amount then amount = tonumber(value) end
            elseif not name then
                name = M.DisplayFromMarkup(value)
            end
        end
    end

    if not amount or amount <= 0 then return nil end
    return { name = name, amount = amount }
end

--- Parses a currency gain line for its display name and amount (when present).
---@param text any
---@return { name: string?, amount: number? }?
function M.ParseCurrencyGain(text)
    local captures = M.MatchFormat(text, M.Patterns('currency'))
    if not captures then return nil end

    local name, amount
    for i = 1, #captures do
        local value = captures[i]
        if type(value) == 'string' and value ~= '' then
            if value:match('^%-?%d+$') then
                if not amount then amount = tonumber(value) end
            elseif not name then
                name = M.DisplayFromMarkup(value)
            end
        end
    end

    return { name = name, amount = amount }
end

--#endregion

--#region ── Entry normalization ───────────────────────────────────────────────

---@class LootEntry
---@field kind        LootKind  Reward category
---@field timestamp   number    GetTime() when received
---@field originalText string?  Raw line, retained for fallback rendering
---@field name        string?   Display name (item/faction/currency)
---@field icon        number?   Texture fileID
---@field hyperlink   string?   Item hyperlink, retained for tooltips
---@field quality     number?   ItemQuality, when known
---@field amount      number?   Gained amount (money/currency/reputation)
---@field total       number?   Resulting total (money/currency)
---@field reaction    number?   Reputation reaction index (5 = Friendly, ...)
---@field progress    number?   Reputation tier progress (currentStanding - currentReactionThreshold)
---@field progressMax number?   Reputation tier width (nextReactionThreshold - currentReactionThreshold)
---@field count       number?   Carried item count
---@field itemID      number?   Item id
---@field isQuestItem boolean? Whether the item is flagged as a quest item in the bags
---@field currencyID  number?   Currency id
---@field needsRefresh boolean? Item data or count still pending

--- Builds an item entry from a raw CHAT_MSG_LOOT line.
---@param text any
---@param timestamp number
---@return LootEntry?
function M.NormalizeItem(text, timestamp)
    local info = M.ParseSelfLoot(text)
    if not info then return nil end
    return {
        kind = 'items',
        timestamp = timestamp,
        originalText = text,
        itemID = info.itemID,
        name = info.name,
        hyperlink = info.hyperlink,
        count = info.count,
    }
end

--- Builds a money entry from a positive GetMoney() delta.
---@param delta any
---@param total any
---@param timestamp number
---@return LootEntry?
function M.NormalizeMoney(delta, total, timestamp)
    if isSecret(delta) or type(delta) ~= 'number' or delta <= 0 then return nil end
    return {
        kind = 'money',
        timestamp = timestamp,
        amount = delta,
        total = M.SafeNumber(total),
    }
end

--- Reads a currency's display info, tolerating clients without the API.
---@param currencyID any
---@return table?
function M.GetCurrencyInfo(currencyID)
    if isSecret(currencyID) or type(currencyID) ~= 'number' then return nil end
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if ok then return info end
    return nil
end

local function resolveCurrencyLink(currencyID, amount)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink) then return nil end
    local ok, link = pcall(C_CurrencyInfo.GetCurrencyLink, currencyID, amount)
    if ok and M.isSafe(link) and type(link) == 'string' and link ~= '' then return link end
    return nil
end

--- Builds a currency entry from a positive CURRENCY_DISPLAY_UPDATE change.
---@param currencyID any
---@param quantity any
---@param quantityChange any
---@param timestamp number
---@return LootEntry?
function M.NormalizeCurrency(currencyID, quantity, quantityChange, timestamp)
    if isSecret(currencyID) or type(currencyID) ~= 'number' then return nil end
    if isSecret(quantityChange) or type(quantityChange) ~= 'number' or quantityChange <= 0 then return nil end

    local info = M.GetCurrencyInfo(currencyID)
    local total = M.SafeNumber(quantity)
    if not total and info then total = M.SafeNumber(info.quantity) end

    return {
        kind = 'currency',
        timestamp = timestamp,
        currencyID = currencyID,
        name = info and M.SafeString(info.name) or nil,
        icon = info and M.SafeNumber(info.iconFileID) or nil,
        quality = info and M.SafeNumber(info.quality) or nil,
        hyperlink = resolveCurrencyLink(currencyID, quantityChange),
        amount = quantityChange,
        total = total,
    }
end

--- Normalizes a faction name for tolerant matching (drops a leading "The ").
---@param name string
---@return string
local function normalizeFactionName(name)
    return (name:lower():gsub('^the%s+', ''))
end

--- The reaction value at which a faction is capped (Exalted). Mirrors
--- MAX_REPUTATION_REACTION from ReputationFrame.lua.
---@return number
local function maxReaction()
    local value = _G and _G.MAX_REPUTATION_REACTION
    if type(value) == 'number' then return value end
    return 8
end

--- Computes the current tier's progress for a faction, mirroring Blizzard's
--- reputation bar (ReputationFrame.InitializeBarForStandardReputation):
---
---     progress    = currentStanding          - currentReactionThreshold
---     progressMax = nextReactionThreshold    - currentReactionThreshold
---
--- The faction's `reaction` is always returned so callers can render its
--- standing label (Friendly, Honored, ...). Capped (Exalted) factions have no
--- progress bar and return nil progress values.
---@param data table  C_Reputation FactionData
---@return { reaction: number?, progress: number?, progressMax: number? }?
function M.InterpretFactionData(data)
    if type(data) ~= 'table' or data.isHeader == true then return nil end

    local reaction = M.SafeNumber(data.reaction)
    local current = M.SafeNumber(data.currentStanding)
    local threshold = M.SafeNumber(data.currentReactionThreshold)
    local nextThreshold = M.SafeNumber(data.nextReactionThreshold)

    local result = { reaction = reaction }
    if reaction == maxReaction() then return result end
    if current == nil or threshold == nil or nextThreshold == nil then return result end

    local size = nextThreshold - threshold
    if size <= 0 then return result end

    result.progress = current - threshold
    result.progressMax = size
    return result
end

--- Resolves a faction's current tier progress by name through C_Reputation. The
--- reputation chat line only carries the display name, so this is a best-effort
--- lookup: when no faction matches, nil is returned and no standing is shown.
---@param factionName any
---@return { reaction: number?, progress: number?, progressMax: number? }?
function M.GetFactionReputation(factionName)
    if not M.SafeString(factionName) then return nil end
    if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then
        return nil
    end

    local ok, count = pcall(C_Reputation.GetNumFactions)
    if not ok or type(count) ~= 'number' then return nil end

    local wanted = normalizeFactionName(factionName)
    for i = 1, count do
        local ok2, data = pcall(C_Reputation.GetFactionDataByIndex, i)
        if ok2 and type(data) == 'table' and data.isHeader ~= true
            and M.isSafe(data.name) and type(data.name) == 'string' then
            if data.name == factionName or normalizeFactionName(data.name) == wanted then
                return M.InterpretFactionData(data)
            end
        end
    end
    return nil
end

--- Builds a reputation entry from a raw CHAT_MSG_COMBAT_FACTION_CHANGE line.
---@param text any
---@param timestamp number
---@return LootEntry?
function M.NormalizeReputation(text, timestamp)
    local gain = M.ParseReputationGain(text)
    if not gain then return nil end
    local entry = M.NormalizeReputationFromParts(gain.name, gain.amount, timestamp, text)
    if entry then
        local info = M.GetFactionReputation(gain.name)
        if info then
            entry.reaction = info.reaction
            entry.progress = info.progress
            entry.progressMax = info.progressMax
        end
    end
    return entry
end

--- Builds a reputation entry from already-known parts (used by mock data).
---@param name string?
---@param amount number?
---@param timestamp number
---@param text string?
---@return LootEntry?
function M.NormalizeReputationFromParts(name, amount, timestamp, text)
    if isSecret(amount) or type(amount) ~= 'number' or amount <= 0 then return nil end
    return {
        kind = 'reputation',
        timestamp = timestamp,
        originalText = text,
        name = name,
        amount = amount,
    }
end

--#endregion

--#region ── Enrichment ─────────────────────────────────────────────────────────

--- Resolves an item's name, icon and quality through C_Item, and optionally its
--- carried-bag count. Secret return values are ignored rather than compared.
---@param entry LootEntry
---@param options? { GetItemInfo?: fun(id:number):any, GetItemIconByID?: fun(id:number):any, GetItemCount?: fun(id:number):any, withCount?: boolean }
---@return boolean changed
function M.EnrichItem(entry, options)
    if type(entry) ~= 'table' or entry.kind ~= 'items' then return false end
    local itemID = entry.itemID
    if isSecret(itemID) or type(itemID) ~= 'number' then return false end

    options = options or {}
    local getInfo = options.GetItemInfo or (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    local getIcon = options.GetItemIconByID or (C_Item and C_Item.GetItemIconByID)
    local getCount = options.GetItemCount or (C_Item and C_Item.GetItemCount)

    local changed = false
    local resolved = M.SafeNumber(entry.quality) ~= nil

    if type(getInfo) == 'function' then
        local ok, name, link, quality = pcall(getInfo, itemID)
        if ok then
            if M.isSafe(name) and type(name) == 'string' and name ~= '' and name ~= entry.name then
                entry.name = name
                changed = true
            end
            if M.isSafe(link) and type(link) == 'string' and link ~= '' and link ~= entry.hyperlink then
                entry.hyperlink = link
                changed = true
            end
            if M.isSafe(quality) and type(quality) == 'number' then
                resolved = true
                if entry.quality ~= quality then
                    entry.quality = quality
                    changed = true
                end
            end
        end
    end

    if type(getIcon) == 'function' then
        local ok, icon = pcall(getIcon, itemID)
        if ok and M.isSafe(icon) and type(icon) == 'number' and entry.icon ~= icon then
            entry.icon = icon
            changed = true
        end
    end

    -- The count is a snapshot taken once the item data is known, so it is only
    -- read when the item itself resolved (avoids storing a placeholder 0).
    if options.withCount and resolved and type(getCount) == 'function' then
        local ok, count = pcall(getCount, itemID)
        if ok and M.isSafe(count) and type(count) == 'number' and entry.count ~= count then
            entry.count = count
            changed = true
        end
    end

    return changed
end

--- Whether the client has supplied the item's cached data (quality and icon).
--- The carried count is refreshed separately once bags settle, so it is not
--- part of the resolution check.
---@param entry LootEntry
---@return boolean
function M.IsItemResolved(entry)
    return M.SafeNumber(entry.quality) ~= nil and M.SafeNumber(entry.icon) ~= nil
end

--#endregion

if addon then addon.LootSources = M end
return M
