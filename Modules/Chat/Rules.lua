--[[ Rules.lua
Locally enforced moderation (player/guild blocking) and cosmetic channel
aliases. Nothing here touches Blizzard's ignore list or channel numbers; rules
live entirely in CouchModeDB so they can be edited and reverted freely.
]]

local addonName, addon = ...
addon = addon or (LibStub and LibStub('AceAddon-3.0'):GetAddon(addonName))

local M = {}

--#region ── Name parsing ──────────────────────────────────────────────────────

--- Splits "Name-Realm" into its base name and realm. Realm may be nil.
---@param name string?
---@return string? base
---@return string? realm
function M.SplitName(name)
    if type(name) ~= 'string' or name == '' then return nil, nil end
    local base, realm = name:match('^(.-)%-(.+)$')
    if not base or base == '' then return name, nil end
    return base, realm
end

--- Lowercases a name/rule for case-insensitive comparisons.
---@param value string?
---@return string?
function M.Key(value)
    if type(value) ~= 'string' or value == '' then return nil end
    local base, realm = M.SplitName(value)
    if not base then return nil end
    if realm then
        return string.lower(base) .. '-' .. string.lower(realm)
    end
    return string.lower(base)
end

--#endregion

--#region ── Blocking ──────────────────────────────────────────────────────────

--- Whether `name` (which may be realm-qualified) matches a stored rule.
--- A rule without a realm matches that base name on any realm; a rule with a
--- realm matches that exact base+realm pair.
---@param rule string
---@param name string
---@return boolean
function M.NameMatchesRule(rule, name)
    local ruleBase, ruleRealm = M.SplitName(rule)
    local nameBase, nameRealm = M.SplitName(name)
    if not ruleBase or not nameBase then return false end
    if string.lower(ruleBase) ~= string.lower(nameBase) then return false end
    if ruleRealm == nil then return true end
    if nameRealm == nil then return false end
    return string.lower(ruleRealm) == string.lower(nameRealm)
end

--- Returns the first matching player rule, or nil.
---@param blocks table  { names = string[], guilds = string[] }
---@param name string?
---@return string?
function M.MatchNameRule(blocks, name)
    if type(name) ~= 'string' or name == '' then return nil end
    local names = blocks and blocks.names
    if not names then return nil end
    for i = 1, #names do
        if M.NameMatchesRule(names[i], name) then return names[i] end
    end
    return nil
end

---@param blocks table
---@param guild string?
---@return boolean
function M.IsGuildBlocked(blocks, guild)
    if type(guild) ~= 'string' or guild == '' then return false end
    local guilds = blocks and blocks.guilds
    if not guilds then return false end
    local key = string.lower(guild)
    for i = 1, #guilds do
        if string.lower(guilds[i]) == key then return true end
    end
    return false
end

--- Whether a normalized message should be dropped before alerts, grouping,
--- filters and session history.
---@param blocks table
---@param msg ChatMessage
---@param guild string?  Known guild name for the sender, when available
---@return boolean
function M.IsBlocked(blocks, msg, guild)
    if not blocks or not msg then return false end
    if M.MatchNameRule(blocks, msg.sender) then return true end
    if M.IsGuildBlocked(blocks, guild) then return true end
    return false
end

--- Adds a name rule if not already present. Returns true when added.
---@param blocks table
---@param name string
---@return boolean
function M.AddName(blocks, name)
    if type(name) ~= 'string' or name == '' then return false end
    blocks.names = blocks.names or {}
    for i = 1, #blocks.names do
        if string.lower(blocks.names[i]) == string.lower(name) then return false end
    end
    blocks.names[#blocks.names + 1] = name
    return true
end

---@param blocks table
---@param name string
---@return boolean
function M.RemoveName(blocks, name)
    local names = blocks and blocks.names
    if not names then return false end
    for i = 1, #names do
        if string.lower(names[i]) == string.lower(name) then
            table.remove(names, i)
            return true
        end
    end
    return false
end

---@param blocks table
---@param guild string
---@return boolean
function M.AddGuild(blocks, guild)
    if type(guild) ~= 'string' or guild == '' then return false end
    blocks.guilds = blocks.guilds or {}
    for i = 1, #blocks.guilds do
        if string.lower(blocks.guilds[i]) == string.lower(guild) then return false end
    end
    blocks.guilds[#blocks.guilds + 1] = guild
    return true
end

---@param blocks table
---@param guild string
---@return boolean
function M.RemoveGuild(blocks, guild)
    local guilds = blocks and blocks.guilds
    if not guilds then return false end
    for i = 1, #guilds do
        if string.lower(guilds[i]) == string.lower(guild) then
            table.remove(guilds, i)
            return true
        end
    end
    return false
end

--#endregion

--#region ── Channel aliases ───────────────────────────────────────────────────

--- Resolves a cosmetic channel alias. Lookups fall back from the canonical
--- chat type to the public-channel base name.
---@param aliases table<string, string>
---@param chatType string?
---@param baseName string?
---@return string?
function M.ResolveAlias(aliases, chatType, baseName)
    if not aliases then return nil end
    if baseName and aliases[baseName] then return aliases[baseName] end
    if chatType and aliases[chatType] then return aliases[chatType] end
    return nil
end

if addon then addon.ChatRules = M end
return M
