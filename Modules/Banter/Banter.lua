local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local LSM = LibStub('LibSharedMedia-3.0')

---@class BanterModule: AceModule, AceEvent-3.0
local banter = addon:NewModule('Banter', 'AceEvent-3.0')
---@cast banter +AceEvent-3.0

--#region ── Constants ────────────────────────────────────────────────────────

local FONT_PATH = 'Interface/AddOns/CouchMode/Modules/Banter/Resources/Fonts/BebasNeue-Regular.ttf'

local EVENT_SAY = 'CHAT_MSG_MONSTER_SAY'
local EVENT_YELL = 'CHAT_MSG_MONSTER_YELL'
local EVENT_WHISPER = 'CHAT_MSG_MONSTER_WHISPER'
local EVENT_PARTY = 'CHAT_MSG_MONSTER_PARTY'

-- Expose event name constants so BanterGabber can use them for styleByType.
banter.EVENT_SAY = EVENT_SAY
banter.EVENT_YELL = EVENT_YELL
banter.EVENT_WHISPER = EVENT_WHISPER
banter.EVENT_PARTY = EVENT_PARTY

local TEST_ARGS = {
    { name = 'Lorewalker Cho',            id = 54961, message = 'Stay a while, and listen.' },
    { name = 'Highlord Bolvar Fordragon', id = 1748,  message = 'Power can be easily taken, but should not be given lightly. Those who lead through fear only stay in power while those they govern lack courage.' },
    { name = 'Lorewalker Cho',            id = 54961, message = 'Parents cannot always be assured of the legacy that they will leave behind, especially when the parents are gods and their children are monsters.' },
    { name = 'Highlord Bolvar Fordragon', id = 1748,  message = 'As such, knowledge is my armor, and I carry a quill in place of a sword.' },
}

--#endregion

--#region ── Utilities (from Gab Core/Utils.lua) ──────────────────────────────

local function CalculateDisplayDuration(message)
    local baseDuration = 3
    local charsPerSecond = 20
    local duration = baseDuration + (#message / charsPerSecond)
    return math.min(duration, 20)
end

-- Expose so BanterFrame can use it.
banter.CalculateDisplayDuration = CalculateDisplayDuration

--#endregion

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.banter end

--#endregion

--#region ── Defaults ─────────────────────────────────────────────────────────

function banter:GetDefaults()
    return {
        banter = {
            enabled = true,
            -- Blizzard UI suppression
            disableTalkingHead = true,
            disableChatLog = false,
            disableChatBubble = false,
            -- Position
            x = 0,
            y = 0,
            -- Sizing
            itemWidth = 512,
            maxItems = 5,
            growUpwards = true,
            portraitSize = 80,
            -- Name font
            nameFontFace = 'Bebas Neue',
            nameFontSize = 28,
            nameFontColor = { r = 1, g = 1, b = 1, a = 1 },
            -- Message font
            msgFontFace = 'Bebas Neue',
            msgFontSize = 16,
            msgFontColor = { r = 1, g = 1, b = 0, a = 1 },
            styleByType = true,
        }
    }
end

--#endregion

--#region ── Options ──────────────────────────────────────────────────────────

function banter:GetOptions()
    return 'banter', {
        name = 'Banter',
        type = 'group',
        order = 20,
        args = {
            description = {
                name = 'Displays NPC monster dialogue in a styled overlay with portraits and animated message stacks.',
                type = 'description',
                order = 1,
            },
            enabled = {
                name = 'Enable',
                desc = 'Show NPC dialogue overlays.',
                type = 'toggle',
                order = 2,
                get = function() return db().enabled end,
                set = function(_, value)
                    db().enabled = value
                    if value then banter:Enable() else banter:Disable() end
                end,
            },
            sizing = {
                name = 'Sizing & Positioning',
                type = 'group',
                inline = true,
                order = 3,
                args = {
                    unlock = {
                        name = 'Unlock/Lock',
                        desc = 'Unlocks the Banter window for repositioning.',
                        type = 'execute',
                        order = 1,
                        func = function()
                            addon:GetModule('BanterFrame'):ToggleLock()
                        end,
                    },
                    test = {
                        name = 'Test',
                        desc = 'Fire sample NPC messages to preview the display.',
                        type = 'execute',
                        order = 2,
                        func = function()
                            local delay = 0
                            for _, args in ipairs(TEST_ARGS) do
                                C_Timer.After(delay, function()
                                    local fakeGuid = "Creature-0-0-0-0-" .. args.id .. "-0"
                                    banter:OnMonsterMessage(EVENT_SAY, args.message, args.name, nil, nil, nil, nil, nil,
                                        nil, nil, nil, nil, fakeGuid)
                                end)
                                delay = delay + 3
                            end
                        end,
                    },
                    width = {
                        name = 'Window Width',
                        desc = 'Width of each gabber frame in pixels.',
                        type = 'range',
                        order = 3,
                        min = 200,
                        max = 1200,
                        step = 10,
                        get = function() return db().itemWidth end,
                        set = function(_, val)
                            db().itemWidth = val
                            addon:GetModule('BanterFrame'):Refresh()
                        end,
                    },
                    maxItems = {
                        name = 'Max Gabbers',
                        desc = 'Maximum number of NPC dialogue frames shown at once.',
                        type = 'range',
                        order = 4,
                        min = 1,
                        max = 20,
                        step = 1,
                        get = function() return db().maxItems end,
                        set = function(_, val)
                            db().maxItems = val
                        end,
                    },
                },
            },
            control = {
                name = 'Controls',
                type = 'group',
                inline = true,
                order = 4,
                args = {
                    disableTalkingHead = {
                        name = 'Hide Talking Head',
                        desc = 'Hide the Blizzard Talking Head frame when Banter is active.',
                        type = 'toggle',
                        order = 1,
                        get = function() return db().disableTalkingHead end,
                        set = function(_, val)
                            db().disableTalkingHead = val
                            applyTalkingHeadSuppression(val)
                        end,
                    },
                    disableChatBubble = {
                        name = 'Hide Chat Bubbles',
                        desc = 'Hide Blizzard NPC chat bubbles.',
                        type = 'toggle',
                        order = 2,
                        get = function() return db().disableChatBubble end,
                        set = function(_, val)
                            db().disableChatBubble = val
                        end,
                    },
                },
            },
            styling = {
                name = 'Styling',
                type = 'group',
                inline = true,
                order = 5,
                args = {
                    nameHeader = { name = 'Name', type = 'header', order = 1 },
                    nameFont = {
                        name = 'Font',
                        desc = 'Font for the NPC name.',
                        type = 'select',
                        order = 2,
                        style = 'dropdown',
                        dialogControl = 'LSM30_Font',
                        values = LSM:HashTable(LSM.MediaType.FONT),
                        get = function() return db().nameFontFace end,
                        set = function(_, val)
                            db().nameFontFace = val
                            addon:GetModule('BanterFrame'):Refresh()
                        end,
                    },
                    nameSize = {
                        name = 'Size',
                        desc = 'Font size for the NPC name.',
                        type = 'range',
                        order = 3,
                        min = 8,
                        max = 48,
                        step = 1,
                        get = function() return db().nameFontSize end,
                        set = function(_, val)
                            db().nameFontSize = val
                            addon:GetModule('BanterFrame'):Refresh()
                        end,
                    },
                    nameColor = {
                        name = 'Color',
                        desc = 'Color of the NPC name text.',
                        type = 'color',
                        order = 4,
                        hasAlpha = true,
                        get = function()
                            local c = db().nameFontColor
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            local c = db().nameFontColor
                            c.r, c.g, c.b, c.a = r, g, b, a
                            addon:GetModule('BanterFrame'):Refresh()
                        end,
                    },
                    msgHeader = { name = 'Message', type = 'header', order = 5 },
                    msgFont = {
                        name = 'Font',
                        desc = 'Font for message text.',
                        type = 'select',
                        order = 6,
                        style = 'dropdown',
                        dialogControl = 'LSM30_Font',
                        values = LSM:HashTable(LSM.MediaType.FONT),
                        get = function() return db().msgFontFace end,
                        set = function(_, val)
                            db().msgFontFace = val
                            addon:GetModule('BanterFrame'):Refresh()
                        end,
                    },
                    msgSize = {
                        name = 'Size',
                        desc = 'Font size for message text.',
                        type = 'range',
                        order = 7,
                        min = 8,
                        max = 36,
                        step = 1,
                        get = function() return db().msgFontSize end,
                        set = function(_, val)
                            db().msgFontSize = val
                            addon:GetModule('BanterFrame'):Refresh()
                        end,
                    },
                    msgColor = {
                        name = 'Color',
                        desc = 'Default color of message text (used when Style by Type is off).',
                        type = 'color',
                        order = 8,
                        hasAlpha = true,
                        disabled = function() return db().styleByType end,
                        get = function()
                            local c = db().msgFontColor
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            local c = db().msgFontColor
                            c.r, c.g, c.b, c.a = r, g, b, a
                            addon:GetModule('BanterFrame'):Refresh()
                        end,
                    },
                    styleByType = {
                        name = 'Style by Type',
                        desc = 'Automatically color messages by chat type (yells red, whispers pink, etc.).',
                        type = 'toggle',
                        order = 9,
                        get = function() return db().styleByType end,
                        set = function(_, val)
                            db().styleByType = val
                        end,
                    },
                },
            },
        },
    }
end

--#endregion

--#region ── Blizzard UI suppression ──────────────────────────────────────────

local talkingHeadHooked = false

function applyTalkingHeadSuppression(suppress)
    if suppress then
        if not talkingHeadHooked then
            if TalkingHeadFrame then
                hooksecurefunc(TalkingHeadFrame, 'Show', function(f)
                    if db().disableTalkingHead then f:Hide() end
                end)
                talkingHeadHooked = true
            end
        end
    end
end

--#endregion

--#region ── Event handling ───────────────────────────────────────────────────

---@param event string  e.g. 'CHAT_MSG_MONSTER_YELL'
---@param message string
---@param name string
function banter:OnMonsterMessage(event, message, name, lang, channel, player2, specialFlags, zoneChannelID, channelIndex,
                                 baseChannelName, langID, lineID, guid)
    if not guid or guid == "" then return end

    local guidType, _, _, _, _, npcIDStr = strsplit("-", guid)
    if guidType ~= "Creature" and guidType ~= "Vehicle" then return end

    local npcID = tonumber(npcIDStr)
    local displayId = addon.BanterData.GetDisplayId(npcID)
    if not displayId then return end

    ---@type BanterGabberData
    local data = {
        id = npcID,
        displayId = displayId,
        name = name,
        message = message,
        type = event,
        duration = CalculateDisplayDuration(message),
    }

    addon:GetModule('BanterFrame'):AddBants(data)
end

--#endregion

--#region ── Lifecycle ────────────────────────────────────────────────────────

function banter:OnEnable()
    if not db().enabled then self:Disable(); return end

    -- Register custom font with LSM so it appears in the font picker.
    if not LSM:IsValid(LSM.MediaType.FONT, 'Bebas Neue') then
        LSM:Register(LSM.MediaType.FONT, 'Bebas Neue', FONT_PATH)
    end

    self:RegisterEvent(EVENT_SAY, 'OnMonsterMessage')
    self:RegisterEvent(EVENT_YELL, 'OnMonsterMessage')
    self:RegisterEvent(EVENT_WHISPER, 'OnMonsterMessage')
    self:RegisterEvent(EVENT_PARTY, 'OnMonsterMessage')

    if db().disableTalkingHead then
        applyTalkingHeadSuppression(true)
    end

    local banterFrame = addon:GetModule('BanterFrame', true)
    if banterFrame then
        banterFrame:Enable()
    end
end

function banter:OnDisable()
    self:UnregisterEvent(EVENT_SAY)
    self:UnregisterEvent(EVENT_YELL)
    self:UnregisterEvent(EVENT_WHISPER)
    self:UnregisterEvent(EVENT_PARTY)

    local banterFrame = addon:GetModule('BanterFrame', true)
    if banterFrame then banterFrame:Disable() end
end

banter:Enable()

--#endregion
