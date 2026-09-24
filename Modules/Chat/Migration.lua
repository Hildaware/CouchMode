--[[ Migration.lua
Idempotent profile migration from the old single "Banter" module to the split
Chat / Chat Bubbles modules.

Old shape (profile.banter):
    enabled, reskinBubbles, hideScrollLog, positions, itemWidth,
    nameFont*, msgFont*, styleByType, revealText, revealSpeed, disableTalkingHead

New shape:
    profile.chat.*        -> scrolling chat replacement (enabled for everyone)
    profile.chatBubbles.* -> overhead NPC bubble replacement
    profile.schemaVersion -> bumped to M.CURRENT_VERSION once migrated
]]

local addonName, addon = ...
addon = addon or (LibStub and LibStub('AceAddon-3.0'):GetAddon(addonName))

local M = {}

M.CURRENT_VERSION = 5
local DEFAULT_CHAT_HEIGHT = 260

--- Computes the routing/enablement decisions for Chat Bubbles.
---@param old table  the legacy `profile.banter` table
---@return { bubblesEnabled: boolean, bubblesMode: string }
function M.Compute(old)
    old = old or {}
    local reskins = old.reskinBubbles == true
    -- A profile only gets overhead replacement when it previously enabled the
    -- module *and* asked for reskinned bubbles.
    local bubblesEnabled = (old.enabled ~= false) and reskins
    -- hideScrollLog(true) means "only show world-anchored bants" -> fallback-only.
    -- Anything else (or no reskinning at all) records NPC chat unconditionally.
    local bubblesMode = (reskins and old.hideScrollLog == true) and 'fallback' or 'always'
    return { bubblesEnabled = bubblesEnabled, bubblesMode = bubblesMode }
end

local function migrateFromBanter(profile, old)
    local decision = M.Compute(old)

    local chat = profile.chat
    chat.enabled = true
    if old.positions then chat.positions = old.positions end
    if old.msgFontFace then chat.msgFontFace = old.msgFontFace end
    if old.msgFontSize then chat.msgFontSize = old.msgFontSize end

    local bubbles = profile.chatBubbles
    bubbles.enabled = decision.bubblesEnabled
    bubbles.mode = decision.bubblesMode
    if old.disableTalkingHead ~= nil then bubbles.disableTalkingHead = old.disableTalkingHead end
    if old.reskinBubbles ~= nil then bubbles.reskinBubbles = old.reskinBubbles end
    if old.itemWidth then bubbles.itemWidth = old.itemWidth end

    -- Bubble visual settings move across verbatim.
    for _, key in ipairs({
        'nameFontFace', 'nameFontSize', 'nameFontColor',
        'msgFontFace', 'msgFontSize', 'msgFontColor',
        'styleByType', 'revealText', 'revealSpeed',
    }) do
        if old[key] ~= nil then bubbles[key] = old[key] end
    end
end

--- v2 -> v3: the single chat font is split into per-field fonts. The old
--- `fontFace`/`fontSize` seeded the message field, so they carry over there.
---@param profile table
local function splitChatFonts(profile)
    local chat = profile.chat
    if not chat then return end
    if chat.fontFace then chat.msgFontFace = chat.fontFace end
    if chat.fontSize then chat.msgFontSize = chat.fontSize end
    chat.fontFace = nil
    chat.fontSize = nil
end

--- v3 -> v4: browsing height and the compact live-feed cap are independent.
--- Only migrate a physically stored legacy value; profiles that used the old
--- implicit default receive the new 400px defaults from AceDB.
---@param profile table
local function splitChatHeights(profile)
    local chat = profile.chat
    if not chat then return end
    local oldHeight = rawget(chat, 'height')
    if oldHeight ~= nil then
        if rawget(chat, 'historyHeight') == nil then chat.historyHeight = oldHeight end
        if rawget(chat, 'maxHeight') == nil then chat.maxHeight = oldHeight end
    end
    chat.height = nil
end

--- v4 -> v5: the chat panel now has one fixed height setting.
--- This is an unreleased layout change, so old experimental height values are
--- discarded and the new control starts at its default.
---@param profile table
local function resetChatHeight(profile)
    local chat = profile.chat
    if not chat then return end
    chat.height = DEFAULT_CHAT_HEIGHT
    chat.historyHeight = nil
    chat.maxHeight = nil
end

--- Runs the migration against an AceDB instance. Safe to call repeatedly.
---@param db table  AceDB instance (must expose `.profile`)
---@return boolean migrated  whether any change was applied
function M.Run(db)
    local profile = db and db.profile
    if not profile then return false end

    local version = profile.schemaVersion or 0
    if version >= M.CURRENT_VERSION then return false end

    if version < 2 then
        local old = profile.banter
        if old and profile.chat and profile.chatBubbles then
            migrateFromBanter(profile, old)
        elseif old then
            -- Defensive: defaults missing (shouldn't happen once modules register).
            profile.chat = profile.chat or {}
            profile.chat.enabled = true
            profile.chatBubbles = profile.chatBubbles or {}
            migrateFromBanter(profile, old)
        else
            -- Fresh profile: the module defaults already describe the new shape.
            if profile.chat then profile.chat.enabled = true end
        end
        -- Obsolete storage is discarded only after a successful migration.
        profile.banter = nil
    end

    if version < 3 then
        splitChatFonts(profile)
    end

    if version < 4 then
        splitChatHeights(profile)
    end

    if version < 5 then
        resetChatHeight(profile)
    end

    profile.schemaVersion = M.CURRENT_VERSION
    return true
end

if addon then addon.ChatMigration = M end
return M
