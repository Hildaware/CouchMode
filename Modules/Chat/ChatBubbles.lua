local addonName, addon = ...

---@class CouchMode: AceAddon
---@field ChatRouter table
---@field ChatSources table
local stub = LibStub('AceAddon-3.0')
local addon = stub:GetAddon(addonName)

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

function bubbles:ApplyTalkingHeadSuppression(suppress)
    if not suppress or talkingHeadHooked or not TalkingHeadFrame then return end
    hooksecurefunc(TalkingHeadFrame, 'Show', function(f)
        if db().disableTalkingHead then f:Hide() end
    end)
    talkingHeadHooked = true
end

--#endregion

--#region ── Bubble construction ───────────────────────────────────────────────

--- Builds a fully-rendered overhead bubble for an NPC message.
---@param msg ChatMessage
---@return ChatBubblesInstance bubble
---@return number duration
function bubbles:BuildBubble(msg)
    local bubble = self:CreateBubble()
    bubble.data = msg
    bubble.released = false
    bubble.id = msg.npcId or msg.displayId or 0

    self:StyleBubbleHeader(bubble)

    local portrait3D = bubble.widget.subWidgets.portrait3D
    local unit = addon.Chat:ResolveUnit(msg)
    local hasDisplayId = msg.displayId and msg.displayId > 0
    local hasPortrait = hasDisplayId or unit

    if unit then
        hasPortrait = portrait3D:SetUnit(unit)
        -- Older clients may not return a success flag.
        if hasPortrait == nil then hasPortrait = true end
        if not hasPortrait and hasDisplayId then
            portrait3D:SetDisplayInfo(msg.displayId)
            hasPortrait = true
        end
    elseif hasDisplayId then
        portrait3D:SetDisplayInfo(msg.displayId)
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

    local messageWidget = bubble.controller:CreateMessage()
    local duration = bubble.controller:FormatMessage(messageWidget, msg.text, msg.event)
    bubble.widget:SetHeight(bubble.widget:GetHeight() + messageWidget.widget:GetHeight())
    bubble.controller:RepositionMessages()

    return bubble, duration
end

--- Resolves NPC identity (creature id / display id / unit token) for a message.
---@param msg ChatMessage
function bubbles:EnrichNpc(msg)
    addon.Chat:EnrichNpc(msg)
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
    if not C_ChatBubbles or not C_ChatBubbles.GetAllChatBubbles then return true end
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

    self:QueueBubbleSearch(msg, finish)
end

--- Build only after a unique, accessible native bubble has been found.
function bubbles:ShowMatchedBubble(request, frame, state)
    if self:ShouldFallBack(request.msg) or not self:IsEnabled() or frame:IsForbidden()
        or not frame:IsShown() or state.owner then
        request.finish('failed')
        return
    end
    self:EnrichNpc(request.msg)
    local bubble, duration = self:BuildBubble(request.msg)
    self:ClaimNativeBubble(bubble, frame, state)
    bubble.widget:SetParent(frame)
    bubble.widget:SetIgnoreParentAlpha(false)
    self:ShowBubble(bubble, duration, request.finish)
end

-- Shared presentation for native replacements and the NPC preview.
function bubbles:ShowBubble(bubble, duration, finish)
    local token = {}
    bubble._bubbleToken, bubble.finish = token, finish
    bubble.shownAt, bubble.bubbleDuration = GetTime(), duration
    if self:ApplyBubblePosition(bubble) == false then
        self:RemoveChatBubble(bubble, true)
        return false
    end
    bubble.widget:SetAlpha(0)
    bubble.widget:Show()
    self.active[#self.active + 1] = bubble

    local ag = bubble.widget:CreateAnimationGroup()
    bubble.animationGroup = ag
    ag:SetToFinalAlpha(true)
    ag:SetScript('OnFinished', function()
        if bubble._bubbleToken == token then bubble.animationGroup = nil end
    end)
    local alpha = ag:CreateAnimation('Alpha')
    alpha:SetDuration(.3)
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    ag:Play()

    if finish then
        bubble.resultTimer = C_Timer.NewTimer(duration * .8, function()
            if bubble._bubbleToken ~= token then return end
            bubble.resultTimer = nil
            if bubble.widget:IsShown() then finish('displayed') end
        end)
    end
    bubble.expiryTimer = C_Timer.NewTimer(duration, function()
        if bubble._bubbleToken ~= token then return end
        bubble.expiryTimer = nil
        self:RemoveChatBubble(bubble)
    end)
    return true
end

--- Native anchoring follows the NPC; our own frame owns scale and screen bounds.
function bubbles:ApplyBubblePosition(bubble)
    local frame, widget, d = bubble.previewFrame or bubble.nativeFrame, bubble.widget, db()
    if not frame or frame:IsForbidden() then return false end
    local scale = d.scale * UIParent:GetEffectiveScale() / widget:GetParent():GetEffectiveScale()
    local clamp = not bubble.previewFrame and d.clampToScreen or false
    local previous = bubble.position
    if previous and previous.scale == scale and previous.x == d.offsetX and previous.y == d.offsetY
        and previous.clamp == clamp and previous.noPortrait == bubble.noPortrait then return end
    widget:ClearAllPoints()
    widget:SetScale(scale)
    if bubble.previewFrame then
        -- Nameplates cannot be measured, and anchoring to one restricts our widget.
        -- Disable clamping while detached, before establishing that relationship.
        widget:SetClampedToScreen(false)
        widget:SetPoint('BOTTOM', frame, 'TOP', d.offsetX, d.offsetY)
    else
        widget:SetPoint('BOTTOM', frame, 'BOTTOM', d.offsetX, d.offsetY)
        -- Include the portrait border and text shadows extending outside the body.
        widget:SetClampRectInsets(bubble.noPortrait and -4 or -40, 8, 24, -8)
        widget:SetClampedToScreen(clamp)
    end
    bubble.position = {
        scale = scale, x = d.offsetX, y = d.offsetY,
        clamp = clamp, noPortrait = bubble.noPortrait,
    }
end

local function cancelTimer(bubble, key)
    if bubble[key] then bubble[key]:Cancel(); bubble[key] = nil end
end

--- End ownership exactly once, including interrupted and disabled displays.
function bubbles:RemoveChatBubble(bubble, immediate)
    if not bubble then return end
    if bubble.released then
        if immediate and bubble.fadeTimer then
            cancelTimer(bubble, 'fadeTimer')
            self:ReleaseBubble(bubble)
        end
        return
    end
    bubble.released = true
    bubble._bubbleToken = nil
    cancelTimer(bubble, 'resultTimer')
    cancelTimer(bubble, 'expiryTimer')
    cancelTimer(bubble, 'previewTicker')
    if bubble.animationGroup then
        bubble.animationGroup:Stop()
        bubble.animationGroup = nil
    end
    if bubble.finish then
        local readable = bubble.widget:IsShown() and bubble.shownAt
            and GetTime() - bubble.shownAt >= bubble.bubbleDuration * .8
        bubble.finish(readable and 'displayed' or 'interrupted')
        bubble.finish = nil
    end
    if immediate then
        self:ReleaseBubble(bubble)
        return
    end
    UIFrameFadeOut(bubble.widget, .5, bubble.widget:GetAlpha(), 0)
    bubble.fadeTimer = C_Timer.NewTimer(.5, function()
        bubble.fadeTimer = nil
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
        self:ApplyTalkingHeadSuppression(true)
    end

    self:SnapshotNativeBubbles()
    addon.ChatRouter:SetBubbleHandler(self)
end

function bubbles:OnDisable()
    addon.ChatRouter:ClearBubbleHandler(self)

    self:CancelBubbleSearches()
    for i = #self.active, 1, -1 do
        self:RemoveChatBubble(self.active[i], true)
    end
end

bubbles:Enable()

--#endregion
