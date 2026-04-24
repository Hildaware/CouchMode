local addonName = ...

---@class BanterLookup
---@field GetByName fun(name: string): number?, number?

---@class BanterHistory
---@field Open   fun(self: BanterHistory)
---@field Close  fun(self: BanterHistory)
---@field Toggle fun(self: BanterHistory)

---@class CouchMode: AceAddon
---@field BanterData    BanterLookup
---@field BanterHistory BanterHistory
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local LSM = LibStub('LibSharedMedia-3.0')
local LibEditMode = LibStub('LibEditMode')

---@class BanterModule
local banter = addon:NewModule('Banter', 'AceEvent-3.0')

banter.history = {} ---@type BanterData[]

--#region ── Constants ────────────────────────────────────────────────────────

local FONT_PATH = 'Interface/AddOns/CouchMode/Modules/Banter/Resources/Fonts/BebasNeue-Regular.ttf'

banter.EVENTS = {
    CHAT_MSG_MONSTER_YELL = 'CHAT_MSG_MONSTER_YELL',
    CHAT_MSG_MONSTER_WHISPER = 'CHAT_MSG_MONSTER_WHISPER',
    CHAT_MSG_MONSTER_PARTY = 'CHAT_MSG_MONSTER_PARTY',
    CHAT_MSG_MONSTER_SAY = 'CHAT_MSG_MONSTER_SAY',
    CHAT_MSG_SAY = 'CHAT_MSG_SAY',
    CHAT_MSG_YELL = 'CHAT_MSG_YELL',
    CHAT_MSG_PARTY = 'CHAT_MSG_PARTY',
    CHAT_MSG_RAID = 'CHAT_MSG_RAID',
    CHAT_MSG_INSTANCE_CHAT = 'CHAT_MSG_INSTANCE_CHAT',
    CHAT_MSG_PARTY_LEADER = 'CHAT_MSG_PARTY_LEADER',
    CHAT_MSG_INSTANCE_CHAT_LEADER = 'CHAT_MSG_INSTANCE_CHAT_LEADER',
    CHAT_MSG_RAID_LEADER = 'CHAT_MSG_RAID_LEADER',
    CHAT_MSG_WHISPER = 'CHAT_MSG_WHISPER',
}

local MONSTER_EVENTS = {
    'CHAT_MSG_MONSTER_YELL',
    'CHAT_MSG_MONSTER_SAY',
    'CHAT_MSG_MONSTER_WHISPER',
    'CHAT_MSG_MONSTER_PARTY',
}

local PLAYER_EVENTS = {
    'CHAT_MSG_SAY',
    'CHAT_MSG_YELL',
    'CHAT_MSG_PARTY',
    'CHAT_MSG_RAID',
    'CHAT_MSG_INSTANCE_CHAT',
    'CHAT_MSG_PARTY_LEADER',
    'CHAT_MSG_INSTANCE_CHAT_LEADER',
    'CHAT_MSG_RAID_LEADER',
    'CHAT_MSG_WHISPER',
}

local TEST_ARGS = {
    { name = 'Lorewalker Cho',            id = 54961, message = 'Stay a while, and listen.' },
    { name = 'Highlord Bolvar Fordragon', id = 1748,  message = 'Power can be easily taken, but should not be given lightly. Those who lead through fear only stay in power while those they govern lack courage.' },
    { name = 'Lorewalker Cho',            id = 54961, message = 'Parents cannot always be assured of the legacy that they will leave behind, especially when the parents are gods and their children are monsters.' },
    { name = 'Highlord Bolvar Fordragon', id = 1748,  message = 'As such, knowledge is my armor, and I carry a quill in place of a sword.' },
}

--#endregion

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.banter end

--#endregion

--#region ── Utilities (from Gab Core/Utils.lua) ──────────────────────────────

local function CalculateDisplayDuration(message)
    local baseDuration = 3
    local charsPerSecond = 16
    local duration = baseDuration + (#message / charsPerSecond)
    return math.min(duration, 20)
end

-- Expose so BanterController can use it.
banter.CalculateDisplayDuration = CalculateDisplayDuration

--#endregion


--#region ── Blizzard UI suppression ──────────────────────────────────────────

local talkingHeadHooked = false

local function applyTalkingHeadSuppression(suppress)
    if not suppress or talkingHeadHooked or not TalkingHeadFrame then return end
    hooksecurefunc(TalkingHeadFrame, 'Show', function(f)
        if db().disableTalkingHead then f:Hide() end
    end)
    talkingHeadHooked = true
end

--#endregion

--#region ── Event handling ───────────────────────────────────────────────────

---@param event string  e.g. 'CHAT_MSG_MONSTER_YELL'
---@param message string
---@param name string
function banter:OnMonsterMessage(event, message, name, _, _, _, _, _, _, _, _, _, guid)
    local npcID, displayId = addon.BanterData.GetByName(name)
    local unitToken = (not displayId) and guid and UnitTokenFromGUID(guid) or nil

    ---@type BanterData
    local data = {
        id = npcID or 0,
        displayId = displayId,
        unitToken = unitToken,
        name = name,
        message = message,
        type = event,
        duration = CalculateDisplayDuration(message),
        timestamp = date('%H:%M:%S'),
    }

    banter:AddBants(data)
end

local function findUnitTokenByGUID(guid)
    if not guid then return nil end
    if UnitGUID('player') == guid then return 'player' end
    local n = GetNumGroupMembers()
    local isRaid = IsInRaid()
    for i = 1, n do
        local token = isRaid and ('raid' .. i) or ('party' .. i)
        if UnitGUID(token) == guid then return token end
    end
end

function banter:OnPlayerMessage(event, message, name, _, _, _, _, _, _, _, _, _, guid)
    -- Parse playerUID from GUID: "Player-realmID-playerUID" (playerUID is hex)
    local playerUID = guid and guid:match('Player%-%d+%-(%x+)')
    local playerId = playerUID and tonumber(playerUID, 16) or 0

    local unitToken = findUnitTokenByGUID(guid) or UnitTokenFromGUID(guid)

    local channel = event:gsub('^CHAT_MSG_', ''):gsub('_LEADER$', '')
    if channel == 'INSTANCE_CHAT' then channel = 'INSTANCE' end

    ---@type BanterData
    local data = {
        id = playerId,
        unitToken = unitToken,
        guid = guid,
        channel = channel,
        name = name,
        message = message,
        type = event,
        duration = CalculateDisplayDuration(message),
        timestamp = date('%H:%M:%S'),
    }

    banter:AddBants(data)
end

--#endregion

--#region ── Lifecycle ────────────────────────────────────────────────────────

function banter:OnInitialize()
    self:InitPools()
end

function banter:OnEnable()
    if not db().enabled then
        self:Disable(); return
    end

    -- Register custom font with LSM so it appears in the font picker.
    if not LSM:IsValid(LSM.MediaType.FONT, 'Bebas Neue') then
        LSM:Register(LSM.MediaType.FONT, 'Bebas Neue', FONT_PATH)
    end

    for _, event in ipairs(MONSTER_EVENTS) do
        self:RegisterEvent(event, 'OnMonsterMessage')
    end
    for _, event in ipairs(PLAYER_EVENTS) do
        self:RegisterEvent(event, 'OnPlayerMessage')
    end

    if db().disableTalkingHead then
        applyTalkingHeadSuppression(true)
    end

    -- Create the container frame on first enable, otherwise just show it.
    if self.instance then
        self.instance.widget:Show()
        return
    end

    local itemWidth = db().itemWidth
    local maxItems = 5
    local containerHeight = (maxItems * self.bantProto.minimumHeight) + ((maxItems + 1) * self.padding)

    ---@type BanterContainerFrame
    local frame = CreateFrame('Frame', 'CouchModeBanterContainer', UIParent) --[[@as BanterContainerFrame]]
    frame:SetSize(itemWidth + (self.padding * 2), containerHeight)
    frame:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 0, 0)
    frame:Hide()

    local bg = frame:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:Hide()

    frame.bg = bg

    ---@type BanterController.Instance
    self.instance = { widget = frame, bants = {} }

    LibEditMode:AddFrame(frame, function(_, layoutName, point, x, y)
        db().positions[layoutName] = { point = point, x = x, y = y }
    end, { point = 'BOTTOMLEFT', x = 0, y = 0 }, 'CouchMode Dialog')

    LibEditMode:AddFrameSettings(frame, {
        {
            kind = LibEditMode.SettingType.Slider,
            name = 'Width',
            desc = 'Width of each message frame in pixels.',
            default = 512,
            minValue = 200,
            maxValue = 1200,
            valueStep = 10,
            get = function(_) return db().itemWidth end,
            set = function(_, value, fromReset)
                db().itemWidth = fromReset and 512 or value
                banter:Refresh()
            end,
        },
    })

    LibEditMode:RegisterCallback('layout', function(layoutName)
        local pos = db().positions[layoutName]
        frame:ClearAllPoints()
        if pos then
            frame:SetPoint(pos.point, pos.x, pos.y)
        else
            frame:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 0, 0)
        end
    end)

    LibEditMode:RegisterCallback('enter', function()
        frame:Show()
        bg:Show()
    end)

    LibEditMode:RegisterCallback('exit', function()
        bg:Hide()
        if #banter.instance.bants == 0 then
            frame:Hide()
        end
    end)
end

function banter:OnDisable()
    for _, event in ipairs(MONSTER_EVENTS) do
        self:UnregisterEvent(event)
    end
    for _, event in ipairs(PLAYER_EVENTS) do
        self:UnregisterEvent(event)
    end

    if self.instance then
        self.instance.widget:Hide()
    end
end

banter:Enable()

--#endregion

--#region ── Defaults ─────────────────────────────────────────────────────────

function banter:GetDefaults()
    return {
        banter = {
            enabled = true,
            -- Blizzard UI suppression
            disableTalkingHead = true,
            -- Bubble mode
            reskinBubbles = true,
            hideScrollLog = true,
            -- Visibility
            -- Position (per Edit Mode layout)
            positions = {},
            -- Sizing
            itemWidth = 240,
            -- Name font
            nameFontFace = 'Arial Narrow',
            nameFontSize = 28,
            nameFontColor = { r = .902, g = .702, b = 0, a = 1 },
            -- Message font
            msgFontFace = 'Arial Narrow',
            msgFontSize = 16,
            msgFontColor = { r = 1, g = 1, b = 0, a = 1 },
            styleByType = true,
            -- Text reveal
            revealText = false,
            revealSpeed = 44,
        }
    }
end

--#endregion

--#region ── Options ──────────────────────────────────────────────────────────


function banter:GetOptions()
    return 'banter', {
        name = 'Chat Bubbles',
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
            misc = {
                name = 'Misc',
                type = 'group',
                inline = true,
                order = 99,
                args = {
                    openHistory = {
                        name = 'View History',
                        desc = 'Open the banter history log for this session.',
                        type = 'execute',
                        order = 1,
                        func = function() addon.BanterHistory:Toggle() end,
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
                                    banter:OnMonsterMessage(banter.EVENTS.CHAT_MSG_MONSTER_SAY, args.message, args.name)
                                end)
                                delay = delay + 3
                            end
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
                    reskinBubbles = {
                        name = 'Reskinned Bubbles',
                        desc =
                        'Show a Banter container above each NPC chat bubble in open world. Falls back to scrolling log in instanced content.',
                        type = 'toggle',
                        order = 2,
                        get = function() return db().reskinBubbles end,
                        set = function(_, val) db().reskinBubbles = val end,
                    },
                    hideScrollLog = {
                        name = 'Hide Scrolling Log',
                        desc =
                        'When Reskinned Bubbles is active, suppress the fixed scrolling log so only the world-anchored bants are shown.',
                        type = 'toggle',
                        order = 3,
                        disabled = function() return not db().reskinBubbles end,
                        get = function() return db().hideScrollLog end,
                        set = function(_, val) db().hideScrollLog = val end,
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
                            banter:Refresh()
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
                            banter:Refresh()
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
                            banter:Refresh()
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
                            banter:Refresh()
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
                            banter:Refresh()
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
                            banter:Refresh()
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
                    revealText = {
                        name = 'Reveal Text',
                        desc = 'Animate message text character-by-character as if being read.',
                        type = 'toggle',
                        order = 10,
                        get = function() return db().revealText end,
                        set = function(_, val) db().revealText = val end,
                    },
                    revealSpeed = {
                        name = 'Reveal Speed',
                        desc = 'Characters revealed per second.',
                        type = 'range',
                        order = 11,
                        min = 10,
                        max = 120,
                        step = 5,
                        get = function() return db().revealSpeed end,
                        set = function(_, val) db().revealSpeed = val end,
                    },
                },
            },
        },
    }
end

--#endregion
