--[[ Mock.lua
Representative rewards and system messages for Toasts:

    /cm toasts mock           -- every set
    /cm toasts mock item      -- a single set
    /cm toasts clear          -- wipe the session history

Item entries are emitted as real CHAT_MSG_LOOT lines (built from the client's
own localized format strings when available) so a mock run exercises
recognition and C_Item enrichment exactly like live loot. Money, currency and
reputation entries are built directly, since their live sources are snapshots
and API events rather than chat text.
]]

local addonName, addon = ...
addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)

local M = {}

M.STEP_DELAY = 0.35

--#region ── Format helpers ─────────────────────────────────────────────────────

--- Formats one of Blizzard's runtime strings, falling back to a plain sentence
--- when the client does not expose it.
---@param globalName string
---@param fallback string
---@param ... any
---@return string
local function formatOr(globalName, fallback, ...)
    local format = _G and _G[globalName]
    if type(format) == 'string' and format ~= '' then
        local ok, text = pcall(string.format, format, ...)
        if ok then return text end
    end
    return fallback
end

local function itemLink(itemID, qualityHex, name)
    return ('|cff%s|Hitem:%d::::::::|h[%s]|h|r'):format(qualityHex, itemID, name)
end

local function selfLootText(link)
    return formatOr('LOOT_ITEM_SELF', 'You receive loot: %s.', link)
end

local function selfLootMultipleText(link, count)
    local format = _G and _G.LOOT_ITEM_SELF_MULTIPLE
    if type(format) == 'string' and format ~= '' then
        local ok, text = pcall(string.format, format, link, count)
        if ok then return text end
    end
    return ('You receive loot: %sx%d.'):format(link, count)
end

local function reputationText(faction, amount)
    return formatOr('FACTION_STANDING_INCREASED',
        'Your reputation with %s has increased by %d.', faction, amount)
end

--#endregion

--#region ── Set builders ────────────────────────────────────────────────────────

local function itemSet()
    return {
        { kind = 'items', text = selfLootText(itemLink(6948, 'ffffff', 'Hearthstone')) },
        { kind = 'items', text = selfLootMultipleText(itemLink(12846, '1eff00', 'Argent Dawn Commission'), 5) },
        { kind = 'items', text = selfLootText(itemLink(32837, 'a335ee', "Warglaive of Azzinoth")) },
        { kind = 'items', text = selfLootText(itemLink(19019, 'ff8000', 'Thunderfury, Blessed Blade of the Windseeker')) },
    }
end

local function moneySet()
    return {
        { kind = 'money', amount = 12345, total = 987654 },
        { kind = 'money', amount = 500000, total = 1487654 },
    }
end

local function currencySet()
    return {
        { kind = 'currency', currencyID = 3008, name = 'Valor Points', amount = 25, total = 1350, icon = 236689, quality = 3 },
        { kind = 'currency', currencyID = 1166, name = 'Timewarped Badge', amount = 50, total = 250, icon = 463446, quality = 3 },
    }
end

local function reputationSet()
    return {
        -- Friendly: 1,000 / 6,000.
        { kind = 'reputation', name = 'The Argent Dawn', amount = 250, reaction = 5, progress = 1000, progressMax = 6000 },
        -- Honored: 2,500 / 12,000.
        { kind = 'reputation', name = 'Cenarion Circle', amount = 500, reaction = 6, progress = 2500, progressMax = 12000 },
        { kind = 'reputation', text = reputationText('The Aldor', 75) },
    }
end

local function systemSet()
    return {
        { kind = 'system', event = 'CHAT_MSG_SYSTEM', text = 'You are now AFK.' },
        { kind = 'system', event = 'CHAT_MSG_SYSTEM', text = 'No player named "Ghost" is currently playing.' },
    }
end

--#endregion

--#region ── Scenario registry ──────────────────────────────────────────────────

M.SETS = {
    item = itemSet,
    money = moneySet,
    currency = currencySet,
    reputation = reputationSet,
    system = systemSet,
}

M.ORDER = { 'item', 'money', 'currency', 'reputation', 'system' }

--- Accepted spellings for each set. The plural forms are the natural thing to
--- type from chat (/cm toasts mock items).
---@type table<string, string>
M.ALIASES = {
    items = 'item',
    monies = 'money',
    currencies = 'currency',
    reputations = 'reputation',
}

---@return string[]
function M.Names()
    return M.ORDER
end

--- Resolves a user-supplied set name to a canonical set, 'all', or nil.
---@param setName string?
---@return string?
function M.Resolve(setName)
    if setName == nil or setName == '' then return 'all' end
    setName = tostring(setName):lower()
    local canonical = M.ALIASES[setName] or setName
    if canonical == 'all' or M.SETS[canonical] then return canonical end
    return nil
end

--- Flattens the requested set (or every set for 'all').
---@param setName string?
---@return table[]
function M.Collect(setName)
    local out = {}
    local function addAll(builder)
        local entries = builder()
        for i = 1, #entries do out[#out + 1] = entries[i] end
    end

    local resolved = M.Resolve(setName)
    if resolved == 'all' then
        for _, name in ipairs(M.ORDER) do addAll(M.SETS[name]) end
    elseif resolved then
        addAll(M.SETS[resolved])
    end

    return out
end

--#endregion

--#region ── Firing ─────────────────────────────────────────────────────────────

--- Emits one scenario entry through the Toasts module.
---@param toasts table
---@param spec table
function M.Fire(toasts, spec)
    if toasts.MockEntry then toasts:MockEntry(spec) end
end

--- Fires a set with a staggered delay so fading and scrolling are visible.
---@param toasts table
---@param setName string
---@param stepDelay number?
---@return number fired
function M.Run(toasts, setName, stepDelay)
    local entries = M.Collect(setName)
    stepDelay = stepDelay or M.STEP_DELAY
    for i = 1, #entries do
        local spec = entries[i]
        if C_Timer and C_Timer.After then
            C_Timer.After((i - 1) * stepDelay, function() M.Fire(toasts, spec) end)
        else
            M.Fire(toasts, spec)
        end
    end
    return #entries
end

--#endregion

if addon then addon.ToastMock = M end
return M
