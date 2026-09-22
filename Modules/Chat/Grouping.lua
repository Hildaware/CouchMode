--[[ Grouping.lua
Pure grouping rules for the Chat feed.

Consecutive accepted messages share one visual group (speaker header + message
lines) only when the speaker identity, channel and direction all match and the
messages arrived within `window` seconds of each other. Messages whose identity
cannot be read safely (secret values) always form anonymous one-message groups.
]]

local addonName, addon = ...
addon = addon or (LibStub and LibStub('AceAddon-3.0'):GetAddon(addonName))

local M = {}

M.DEFAULT_WINDOW = 60

--- Stable identity key for a message's speaker, or nil when unknown/unsafe.
---@param msg ChatMessage
---@return string?
function M.IdentityKey(msg)
    if not msg then return nil end
    if msg.category == 'SYSTEM' then return nil end

    if msg.guid and msg.guid ~= '' then return 'g:' .. msg.guid end
    if msg.sender and msg.sender ~= '' then
        if msg.category == 'NPC' then
            return 'n:' .. (msg.npcId or msg.displayId or msg.sender)
        end
        return 'p:' .. msg.sender
    end
    -- NPC with a known creature but no name.
    if msg.category == 'NPC' and (msg.npcId or msg.displayId) then
        return 'n:' .. (msg.npcId or msg.displayId)
    end
    return nil
end

--- Channel key for a message, or nil when the channel is not safely known.
---@param msg ChatMessage
---@return string?
function M.ChannelKey(msg)
    if not msg then return nil end
    if msg.channelBase and msg.channelBase ~= '' then return 'b:' .. msg.channelBase end
    if msg.channelID then return 'i:' .. msg.channelID end
    return 't:' .. (msg.type or msg.event or '')
end

--- Whether `next` should be appended to the group ending with `prev`.
---@param prev ChatMessage
---@param next ChatMessage
---@param window number?
---@return boolean
function M.ShouldGroup(prev, next, window)
    if not prev or not next then return false end
    if prev.category ~= next.category then return false end
    if (prev.direction or 'in') ~= (next.direction or 'in') then return false end

    local prevId, nextId = M.IdentityKey(prev), M.IdentityKey(next)
    if not prevId or not nextId or prevId ~= nextId then return false end

    local prevChannel, nextChannel = M.ChannelKey(prev), M.ChannelKey(next)
    if prevChannel ~= nextChannel then return false end

    local gap = (next.timestamp or 0) - (prev.timestamp or 0)
    if gap > (window or M.DEFAULT_WINDOW) or gap < 0 then return false end

    return true
end

---@class ChatGroup
---@field messages ChatMessage[]

--- Partitions a flat list of messages into visual groups.
---@param messages ChatMessage[]
---@param window number?
---@return ChatGroup[]
function M.Build(messages, window)
    local groups = {}
    local current
    for i = 1, #messages do
        local msg = messages[i]
        if current and M.ShouldGroup(current.messages[#current.messages], msg, window) then
            current.messages[#current.messages + 1] = msg
        else
            current = { messages = { msg } }
            groups[#groups + 1] = current
        end
    end
    return groups
end

if addon then addon.ChatGrouping = M end
return M
