local addonName, addon = ...

---@class CouchMode: AceAddon
---@field ChatRouter table
---@field ChatSources table
local stub = LibStub('AceAddon-3.0')
local addon = stub:GetAddon(addonName)
local LibEditMode = LibStub('LibEditMode')

---@class ChatBubblesModule: AceModule
---@field CalculateDisplayDuration fun(message: string): number
---@field _pool ObjectPoolMixin
---@field _messagePool ObjectPoolMixin
---@field active ChatBubblesInstance[]
---@field CreateBubble fun(self: ChatBubblesModule): ChatBubblesInstance
---@field ReleaseBubble fun(self: ChatBubblesModule, bubble: ChatBubblesInstance)
---@field InitPools fun(self: ChatBubblesModule)
---@field RemoveChatBubble fun(self: ChatBubblesModule, bubble: ChatBubblesInstance)
local bubbles = addon:NewModule('ChatBubbles', 'AceEvent-3.0')

bubbles.active = {} ---@type ChatBubblesInstance[]

--#region ── Constants ────────────────────────────────────────────────────────

local BUBBLE_POLL_ATTEMPTS = 10
local BUBBLE_POLL_DELAY = 0.1

--#endregion

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chatBubbles end

--#endregion

--#region ── Utilities ─────────────────────────────────────────────────────────

local isSecret = addon.Utils.IsSecretValue

local function CalculateDisplayDuration(message)
    local baseDuration = 3
    if isSecret(message) then return baseDuration * 3 end
    local charsPerSecond = 16
    local duration = baseDuration + (#message / charsPerSecond)
    return math.min(duration, 20)
end

bubbles.CalculateDisplayDuration = CalculateDisplayDuration

--#endregion

--#region ── Blizzard UI suppression ───────────────────────────────────────────

local talkingHeadHooked = false

local function applyTalkingHeadSuppression(suppress)
    if not suppress or talkingHeadHooked or not TalkingHeadFrame then return end
    hooksecurefunc(TalkingHeadFrame, 'Show', function(f)
        if db().disableTalkingHead then f:Hide() end
    end)
    talkingHeadHooked = true
end

--#endregion

--#region ── Bubble matching ──────────────────────────────────────────────────

local function getBubbleText(bubble)
    if not bubble then return end
    for _, child in ipairs({ bubble:GetChildren() }) do
        for _, region in ipairs({ child:GetRegions() }) do
            if region:GetObjectType() == 'FontString' then
                local t = region:GetText()
                if t and not isSecret(t) and t ~= '' then return t end
            end
        end
    end
end

--- Iterates all accessible chat bubbles looking for one whose text matches
--- `text`. Polls up to BUBBLE_POLL_ATTEMPTS times before giving up.
---@param text     string
---@param callback fun(bubble: Frame?)
---@param attempts number?
function bubbles:FindBubbleForMessage(text, callback, attempts)
    attempts = attempts or 0
    for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(true)) do
        if getBubbleText(bubble) == text then
            callback(bubble)
            return
        end
    end
    if attempts < BUBBLE_POLL_ATTEMPTS then
        C_Timer.After(BUBBLE_POLL_DELAY, function()
            self:FindBubbleForMessage(text, callback, attempts + 1)
        end)
    else
        callback(nil)
    end
end

--#endregion

--#region ── Bubble construction ───────────────────────────────────────────────

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

--- Builds a fully-rendered overhead bubble for an NPC message.
---@param msg ChatMessage
---@return ChatBubblesInstance bubble
---@return number duration
function bubbles:BuildBubble(msg)
    local bubble = self:CreateBubble()
    bubble.data = msg
    bubble.released = false
    bubble.id = msg.npcId or msg.displayId or 0

    local d = db()

    local nameWidget = bubble.widget.subWidgets.name
    local nameFontPath = addon.Media.ResolveFont(d.nameFontFace)
    nameWidget:SetText(msg.sender or '')
    nameWidget:SetFont(nameFontPath, d.nameFontSize, 'OUTLINE')
    local nc = d.nameFontColor
    nameWidget:SetTextColor(nc.r, nc.g, nc.b, nc.a)

    local portrait3D = bubble.widget.subWidgets.portrait3D
    local hasDisplayId = msg.displayId and msg.displayId > 0
    local hasPortrait = hasDisplayId or msg.unitToken

    if hasDisplayId then
        portrait3D:SetDisplayInfo(msg.displayId)
    elseif msg.unitToken then
        portrait3D:SetUnit(msg.unitToken)
    end
    if hasPortrait then
        portrait3D:SetCamera(0)
        portrait3D:SetPortraitZoom(1)
        portrait3D:SetAnimation(60)
    end

    bubble.noPortrait = not hasPortrait
    if bubble.noPortrait then
        bubble.widget.subWidgets.portraitFrame:Hide()
    end

    local channelLabel = bubble.widget.subWidgets.channelLabel
    channelLabel:SetText(msg.type or '')
    local key = addon.ChatSources and addon.ChatSources.ChatTypeKey(msg.event)
    local ci = key and ChatTypeInfo and ChatTypeInfo[key]
    if ci then channelLabel:SetTextColor(ci.r, ci.g, ci.b, 1) end

    local messageWidget = bubble.controller:CreateMessage()
    local duration = bubble.controller:FormatMessage(messageWidget, msg.text, msg.event)
    bubble.widget:SetHeight(bubble.widget:GetHeight() + messageWidget.widget:GetHeight())
    bubble.controller:RepositionMessages()

    return bubble, duration
end

--- Resolves NPC identity (creature id / display id / unit token) for a message.
---@param msg ChatMessage
function bubbles:EnrichNpc(msg)
    if not msg.npcId and msg.sender and not isSecret(msg.sender) and addon.BanterData then
        msg.npcId, msg.displayId = addon.BanterData.GetByName(msg.sender)
    end
    if not msg.displayId and msg.guid then
        msg.unitToken = findUnitTokenByGUID(msg.guid) or UnitTokenFromGUID(msg.guid)
    end
end

--#endregion

--#region ── Attempt / routing ──────────────────────────────────────────────────

--- The routing mode reported to the router. `nil` means Chat Bubbles cannot
--- replace anything and NPC dialogue should go straight to Chat.
---@return string?
function bubbles:GetNpcMode()
    if not db().enabled then return nil end
    if not db().reskinBubbles then return nil end
    return db().mode or 'fallback'
end

---@return boolean
function bubbles:IsSubscriberEnabled()
    return self:GetNpcMode() ~= nil
end

---@param msg ChatMessage
---@return boolean
function bubbles:ShouldFallBack(msg)
    if InCombatLockdown and InCombatLockdown() then return true end
    -- Secret text cannot be compared against bubble text; never risk matching.
    if isSecret(msg.text) then return true end
    if not msg.sender or isSecret(msg.sender) then return true end
    return false
end

--- Attempts to replace the Blizzard overhead bubble for an NPC message.
--- `onResult` receives exactly one of 'displayed' | 'failed' | 'interrupted'.
---@param msg ChatMessage
---@param onResult (fun(result: string))?
function bubbles:Attempt(msg, onResult)
    local resolved = false
    local function finish(result)
        if resolved then return end
        resolved = true
        if onResult then onResult(result) end
    end

    if self:ShouldFallBack(msg) then
        finish('failed')
        return
    end

    self:EnrichNpc(msg)

    local bubble, duration = self:BuildBubble(msg)
    local token = {}
    bubble._bubbleToken = token

    self:FindBubbleForMessage(msg.text, function(frame)
        if not frame then
            -- Bubble never appeared; degrade gracefully to the Chat feed.
            self:ReleaseBubble(bubble)
            finish('failed')
            return
        end

        bubble.shownAt = GetTime()
        bubble.bubbleDuration = duration
        bubble.widget:SetParent(frame)
        bubble.widget:SetIgnoreParentAlpha(true)
        bubble.widget:SetScale(UIParent:GetEffectiveScale() / frame:GetEffectiveScale())
        bubble.widget:ClearAllPoints()
        bubble.widget:SetPoint('BOTTOM', frame, 'BOTTOM', 0, -24)

        -- Hide the original bubble while the replacement is on screen.
        frame:SetAlpha(0)
        for _, region in ipairs({ frame:GetRegions() }) do
            region:SetAlpha(0)
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            if child ~= bubble.widget then
                child:SetAlpha(0)
            end
        end

        frame:HookScript('OnHide', function()
            if bubble._bubbleToken ~= token then return end
            self:RemoveChatBubble(bubble)
            finish('interrupted')
        end)

        bubble.widget:SetAlpha(0)
        bubble.widget:Show()
        self.active[#self.active + 1] = bubble

        local ag = bubble.widget:CreateAnimationGroup()
        bubble.animationGroup = ag
        ag:SetToFinalAlpha(true)
        ag:SetScript('OnFinished', function() bubble.animationGroup = nil end)
        local alpha = ag:CreateAnimation('Alpha')
        alpha:SetDuration(0.3)
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetOrder(1)
        ag:Play()

        -- Success is only declared once the bubble has survived 80% of its
        -- intended lifetime; anything shorter commits to Chat instead.
        C_Timer.After(duration * 0.8, function()
            if bubble._bubbleToken ~= token then return end
            finish('displayed')
        end)
    end)
end

--- Fades out and releases an active overhead bubble.
---@param bubble ChatBubblesInstance
function bubbles:RemoveChatBubble(bubble)
    if not bubble or bubble.released then return end
    bubble.released = true
    bubble._bubbleToken = nil
    for i = #self.active, 1, -1 do
        if self.active[i] == bubble then table.remove(self.active, i) end
    end
    UIFrameFadeOut(bubble.widget, 0.5, bubble.widget:GetAlpha(), 0)
    C_Timer.After(0.5, function()
        self:ReleaseBubble(bubble)
    end)
end

--#endregion

--#region ── Lifecycle ─────────────────────────────────────────────────────────

function bubbles:OnInitialize()
    self:InitPools()
end

function bubbles:OnEnable()
    if not db().enabled then
        self:Disable(); return
    end

    if db().disableTalkingHead then
        applyTalkingHeadSuppression(true)
    end

    addon.ChatRouter:SetBubbleHandler(self)
end

function bubbles:OnDisable()
    addon.ChatRouter:ClearBubbleHandler(self)

    for i = #self.active, 1, -1 do
        local bubble = self.active[i]
        bubble.released = true
        bubble._bubbleToken = nil
        self:ReleaseBubble(bubble)
    end
    wipe(self.active)
end

bubbles:Enable()

--#endregion

--#region ── Defaults ─────────────────────────────────────────────────────────

function bubbles:GetDefaults()
    return {
        chatBubbles = {
            enabled = true,
            -- Overhead replacement is NPC-only and needs reskinning on.
            reskinBubbles = true,
            -- 'fallback' (only replace overhead, record failures) or 'always'.
            mode = 'fallback',
            -- Blizzard UI suppression
            disableTalkingHead = true,
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
        },
    }
end

--#endregion

--#region ── Options ──────────────────────────────────────────────────────────

function bubbles:GetOptions()
    return 'chatBubbles', {
        name = 'Chat Bubbles',
        type = 'group',
        order = 30,
        args = {
            description = {
                name = 'Reskins NPC overhead speech bubbles with portraits and reveal animation. '
                    .. 'Messages it cannot replace are routed to the CouchMode Chat feed.',
                type = 'description',
                order = 1,
            },
            enabled = {
                name = 'Enable',
                desc = 'Replace NPC overhead speech bubbles.',
                type = 'toggle',
                order = 2,
                get = function() return db().enabled end,
                set = function(_, value)
                    db().enabled = value
                    if value then bubbles:Enable() else bubbles:Disable() end
                end,
            },
            misc = {
                name = 'Misc',
                type = 'group',
                inline = true,
                order = 99,
                args = {
                    openChat = {
                        name = 'Open Chat',
                        desc = 'Open the CouchMode Chat feed.',
                        type = 'execute',
                        order = 1,
                        func = function() addon.Chat:Toggle() end,
                    },
                    test = {
                        name = 'Test',
                        desc = 'Fire sample NPC messages to preview the overhead display.',
                        type = 'execute',
                        order = 2,
                        func = function()
                            addon.ChatMock.Run(addon.ChatRouter, 'npc', 3)
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
                        desc = 'Hide the Blizzard Talking Head frame while Chat Bubbles is active.',
                        type = 'toggle',
                        order = 1,
                        get = function() return db().disableTalkingHead end,
                        set = function(_, val)
                            db().disableTalkingHead = val
                            applyTalkingHeadSuppression(val)
                        end,
                    },
                    mode = {
                        name = 'NPC Routing',
                        desc = 'Fallback only keeps successful overhead replacements out of Chat. '
                            .. 'Always record mirrors every NPC line into Chat as well.',
                        type = 'select',
                        style = 'dropdown',
                        order = 2,
                        values = {
                            ['fallback'] = 'Fallback only',
                            ['always'] = 'Always record',
                        },
                        get = function() return db().mode end,
                        set = function(_, val) db().mode = val end,
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
                        values = addon.Media.GetFontOptions(),
                        get = function() return db().nameFontFace end,
                        set = function(_, val) db().nameFontFace = val end,
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
                        set = function(_, val) db().nameFontSize = val end,
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
                        end,
                    },
                    msgHeader = { name = 'Message', type = 'header', order = 5 },
                    msgFont = {
                        name = 'Font',
                        desc = 'Font for message text.',
                        type = 'select',
                        order = 6,
                        style = 'dropdown',
                        values = addon.Media.GetFontOptions(),
                        get = function() return db().msgFontFace end,
                        set = function(_, val) db().msgFontFace = val end,
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
                        set = function(_, val) db().msgFontSize = val end,
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
                        end,
                    },
                    styleByType = {
                        name = 'Style by Type',
                        desc = 'Automatically color messages by chat type (yells red, whispers pink, etc.).',
                        type = 'toggle',
                        order = 9,
                        get = function() return db().styleByType end,
                        set = function(_, val) db().styleByType = val end,
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
