local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class BanterModule
local banter = addon:GetModule('Banter')

--#region ── Helpers ──────────────────────────────────────────────────────────

local function db() return addon.db.profile.banter end

banter.padding = 6
local padding = banter.padding

--#endregion

--#region ── Layout ───────────────────────────────────────────────────────────

function banter:RepositionBants()
    if not self.instance then return end
    local bants = self.instance.bants
    for i = 1, #bants do
        local bant = bants[i]
        if bant.animationGroup and bant.animationGroup:IsPlaying() then
            bant.animationGroup:Stop()
            bant.animationGroup = nil
        end

        bant.widget:ClearAllPoints()

        local prevBant = bants[i - 1]
        if prevBant and prevBant.widget then
            bant.widget:SetPoint('BOTTOMLEFT', prevBant.widget, 'TOPLEFT', 0, padding)
        else
            bant.widget:SetPoint('BOTTOMLEFT', self.instance.widget, 'BOTTOMLEFT', padding, padding)
        end
    end
end

---@param bantToRemove table
function banter:RemoveBant(bantToRemove)
    if bantToRemove.isBubbleMode then
        bantToRemove.isBubbleMode = false
        local shownFor = bantToRemove.shownAt and (GetTime() - bantToRemove.shownAt) or math.huge
        local minVisibleDuration = bantToRemove.bubbleDuration and bantToRemove.bubbleDuration * 0.8 or math.huge
        local premature = shownFor < minVisibleDuration
        UIFrameFadeOut(bantToRemove.widget, 0.5, 1, 0)
        C_Timer.After(0.5, function()
            if premature and bantToRemove.data then
                local fb, fbMsg, fbDur = self:_BuildBant(bantToRemove.data)
                self:_AddBantToStack(fb, fbMsg, fbDur)
            end
            self:Release(bantToRemove)
        end)
        return
    end

    if not self.instance then return end

    local bants = self.instance.bants
    local removedIndex
    for i = 1, #bants do
        if bants[i] == bantToRemove then
            removedIndex = i
            break
        end
    end

    if not removedIndex then return end

    -- Remove from array immediately so RepositionBants gets correct indices.
    table.remove(bants, removedIndex)

    -- Fade out the removed bant, then release it.
    UIFrameFadeOut(bantToRemove.widget, 0.5, 1, 0)
    C_Timer.After(0.5, function()
        self:Release(bantToRemove)
        if #self.instance.bants == 0 then self.instance.widget:Hide() end
    end)

    local slideDistance = bantToRemove.widget:GetHeight() + padding
    local DURATION = 0.5
    local repositioned = false
    for i = removedIndex, #bants do
        local bant = bants[i]

        -- Stop any in-progress slide.
        if bant.animationGroup then
            bant.animationGroup:Stop()
            bant.animationGroup = nil
        end
        bant.widget:SetScript('OnUpdate', nil)

        -- Anchor to the instance widget so we can drive Y directly each frame.
        local instanceWidget = self.instance.widget
        local startY = bant.widget:GetBottom() - instanceWidget:GetBottom()
        local endY = startY - slideDistance
        local elapsed = 0

        bant.widget:ClearAllPoints()
        bant.widget:SetPoint('BOTTOMLEFT', instanceWidget, 'BOTTOMLEFT', padding, startY)

        bant.widget:SetScript('OnUpdate', function(f, dt)
            elapsed = elapsed + dt
            local t = math.min(elapsed / DURATION, 1)
            local smooth = t * t * (3 - 2 * t) -- smoothstep (IN_OUT equivalent)
            f:ClearAllPoints()
            f:SetPoint('BOTTOMLEFT', instanceWidget, 'BOTTOMLEFT', padding, startY + (endY - startY) * smooth)
            if t >= 1 then
                f:SetScript('OnUpdate', nil)
                if not repositioned then
                    repositioned = true
                    self:RepositionBants()
                end
            end
        end)
    end
end

--#endregion

--#region ── Bant construction ────────────────────────────────────────────────

---@param data BanterData
---@return BanterContainerMain bant
---@return BanterContainerMessage messageWidget
---@return number duration
function banter:_BuildBant(data)
    local bant = self:Create()
    bant.id = data.id
    bant.data = data

    local d = db()
    local LSM = LibStub('LibSharedMedia-3.0')

    local nameWidget = bant.widget.subWidgets.name
    local nameFontPath = LSM:Fetch(LSM.MediaType.FONT, d.nameFontFace)
        or 'Interface/AddOns/CouchMode/Resources/Fonts/BebasNeue-Regular.ttf'
    nameWidget:SetText(data.name)
    nameWidget:SetFont(nameFontPath, d.nameFontSize, 'OUTLINE')

    local classColor
    if data.guid then
        local _, englishClass = GetPlayerInfoByGUID(data.guid)
        classColor = englishClass and RAID_CLASS_COLORS[englishClass]
    end
    if classColor then
        nameWidget:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
    else
        local nc = d.nameFontColor
        nameWidget:SetTextColor(nc.r, nc.g, nc.b, nc.a)
    end

    local portrait3D = bant.widget.subWidgets.portrait3D
    local hasDisplayId = data.displayId and data.displayId > 0
    local hasPortrait = hasDisplayId or data.unitToken

    if hasDisplayId then
        portrait3D:SetDisplayInfo(data.displayId)
    elseif data.unitToken then
        portrait3D:SetUnit(data.unitToken)
    end
    if hasPortrait then
        portrait3D:SetCamera(0)
        portrait3D:SetPortraitZoom(1)
        portrait3D:SetAnimation(60)
    end

    bant.noPortrait = not hasPortrait
    if bant.noPortrait then
        bant.widget.subWidgets.portraitFrame:Hide()
    end

    local channelLabel = bant.widget.subWidgets.channelLabel
    if data.channel then
        channelLabel:SetText(data.channel)
        local chatKey = (data.channel == 'INSTANCE') and 'INSTANCE_CHAT' or data.channel
        local ci = ChatTypeInfo[chatKey]
        if ci then channelLabel:SetTextColor(ci.r, ci.g, ci.b, 1) end
    end

    local messageWidget = bant.controller:CreateMessage()
    local duration = bant.controller:FormatMessage(messageWidget, data.message, data.type)
    bant.widget:SetHeight(bant.widget:GetHeight() + messageWidget.widget:GetHeight())
    bant.controller:RepositionMessages()

    return bant, messageWidget, duration
end

-- Creates a fully-rendered bant for display in the history window.
-- Sets pinned=true so the expiry timer in FormatMessage never fires.
---@param data BanterData
---@return BanterContainerMain
function banter:BuildHistoryBant(data)
    local pinned = setmetatable({ pinned = true }, { __index = data })
    local bant = self:_BuildBant(pinned)
    return bant
end

-- Parents a pre-built bant into the scroll stack with duration extension,
-- stack anchoring, and a fade-in animation.
---@param bant BanterContainerMain
---@param messageWidget BanterContainerMessage
---@param duration number
function banter:_AddBantToStack(bant, messageWidget, duration)
    if not self.instance then return end

    bant.widget:SetParent(self.instance.widget)

    local activeBants = self.instance.bants

    -- Extend so a short message never expires before a longer one already active.
    local now = GetTime()
    local maxRemaining = 0
    for i = 1, #activeBants do
        local existing = activeBants[i]
        if existing.expiryTime then
            maxRemaining = math.max(maxRemaining, existing.expiryTime - now)
        end
    end
    local effectiveDuration = math.max(duration, maxRemaining + 1)
    if effectiveDuration > duration then
        local extended = now + effectiveDuration
        bant.expiryTime = extended
        messageWidget.expiryTime = extended
    end

    table.insert(activeBants, bant)

    local prevBant = activeBants[#activeBants - 1]
    local targetPoint = 'BOTTOMLEFT'
    local targetRelativeFrame, targetRelativePoint, targetX, targetY
    if prevBant then
        targetRelativeFrame, targetRelativePoint, targetX, targetY = prevBant.widget, 'TOPLEFT', 0, padding
    else
        targetRelativeFrame, targetRelativePoint, targetX, targetY = self.instance.widget, 'BOTTOMLEFT', padding, padding
    end

    bant.widget:SetPoint(targetPoint, targetRelativeFrame, targetRelativePoint, targetX, targetY)
    bant.widget:SetAlpha(1)
    bant.widget:Show()

    local ag = bant.widget:CreateAnimationGroup()
    bant.animationGroup = ag
    ag:SetToFinalAlpha(true)
    ag:SetScript('OnFinished', function()
        bant.widget:ClearAllPoints()
        bant.widget:SetPoint(targetPoint, targetRelativeFrame, targetRelativePoint, targetX, targetY)
        bant.animationGroup = nil
    end)

    local alpha = ag:CreateAnimation('Alpha')
    alpha:SetDuration(0.3)
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetOrder(1)
    ag:Play()

    self.instance.widget:Show()
end

--#endregion

--#region ── Bubble mode ──────────────────────────────────────────────────────

local function getBubbleText(bubble)
    if not bubble then return end
    for _, child in ipairs({ bubble:GetChildren() }) do
        for _, region in ipairs({ child:GetRegions() }) do
            if region:GetObjectType() == 'FontString' then
                local t = region:GetText()
                if t and not issecretvalue(t) and t ~= '' then return t end
            end
        end
    end
end

local function hideBubble(bubble)
    bubble:SetAlpha(0)
    if bubble.String then bubble.String:SetAlpha(0) end
    if bubble.Tail then bubble.Tail:SetAlpha(0) end
end

-- Iterates all accessible chat bubbles looking for one whose text matches
-- `text`. Polls up to 10 times (0.1 s apart) before giving up.
---@param text     string
---@param callback fun(bubble: Frame?)
---@param attempts number?
function banter:FindBubbleForMessage(text, callback, attempts)
    attempts = attempts or 0
    for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles(true)) do
        if getBubbleText(bubble) == text then
            callback(bubble)
            return
        end
    end
    if attempts < 10 then
        C_Timer.After(0.1, function()
            self:FindBubbleForMessage(text, callback, attempts + 1)
        end)
    else
        callback(nil)
    end
end

-- Creates a bant and anchors it above the matching chat bubble. Falls back to
-- the scroll log if no bubble is found within ~1 second.
---@param data BanterData
function banter:SpawnBubbleBant(data)
    local bant, messageWidget, duration = self:_BuildBant(data)
    bant.isBubbleMode = true
    local bubbleToken = {}
    bant._bubbleToken = bubbleToken

    self:FindBubbleForMessage(data.message, function(bubble)
        if bubble then
            bant.shownAt = GetTime()
            bant.bubbleDuration = duration
            bant.widget:SetParent(bubble)
            bant.widget:SetIgnoreParentAlpha(true)
            bant.widget:SetScale(UIParent:GetEffectiveScale() / bubble:GetEffectiveScale())
            bant.widget:ClearAllPoints()
            bant.widget:SetPoint('BOTTOM', bubble, 'BOTTOM', 0, -24)

            bubble:SetAlpha(0)
            for _, region in ipairs({ bubble:GetRegions() }) do
                region:SetAlpha(0)
            end
            for _, child in ipairs({ bubble:GetChildren() }) do
                if child ~= bant.widget then
                    child:SetAlpha(0)
                end
            end

            bubble:HookScript('OnHide', function()
                if bant._bubbleToken ~= bubbleToken then return end
                self:RemoveBant(bant)
            end)

            bant.widget:SetAlpha(0)
            bant.widget:Show()

            local ag = bant.widget:CreateAnimationGroup()
            bant.animationGroup = ag
            ag:SetToFinalAlpha(true)
            ag:SetScript('OnFinished', function() bant.animationGroup = nil end)
            local alpha = ag:CreateAnimation('Alpha')
            alpha:SetDuration(0.3)
            alpha:SetFromAlpha(0)
            alpha:SetToAlpha(1)
            alpha:SetOrder(1)
            ag:Play()
        else
            -- Bubble never found; degrade gracefully to the scroll log.
            bant.isBubbleMode = false
            self:_AddBantToStack(bant, messageWidget, duration)
        end
    end)
end

--#endregion

--#region ── AddBants ─────────────────────────────────────────────────────────

---@param data BanterData
function banter:AddBants(data)
    table.insert(banter.history, data)

    if not self.instance then return end

    -- Append to the existing scroll-stack bant for this NPC if it's the most recent one.
    local bants = self.instance.bants
    for i = 1, #bants do
        if bants[i].id == data.id then
            local isLatest = true
            for j = i + 1, #bants do
                if bants[j].id ~= data.id then
                    isLatest = false
                    break
                end
            end
            if isLatest then
                local bant = bants[i]
                local messageWidget = bant.controller:CreateMessage()
                bant.controller:FormatMessage(messageWidget, data.message, data.type)
                bant.widget:SetHeight(bant.widget:GetHeight() + messageWidget.widget:GetHeight())
                bant.controller:RepositionMessages()
                self:RepositionBants()
                return
            end
        end
    end

    -- Route to bubble mode when enabled, but never during combat or in instances.
    if db().reskinBubbles then
        if not InCombatLockdown() then
            self:SpawnBubbleBant(data)
            if db().hideScrollLog then return end
        else
            -- In combat: hide the original bubble so it doesn't overlap the scroll log.
            self:FindBubbleForMessage(data.message, function(bubble)
                if bubble then hideBubble(bubble) end
            end)
        end
    end

    -- Scroll log path.
    local bant, messageWidget, duration = self:_BuildBant(data)
    self:_AddBantToStack(bant, messageWidget, duration)
end

--#endregion

--#region ── Utilities ────────────────────────────────────────────────────────

---Called by options setters after width or font changes.
function banter:Refresh()
    if not self.instance then return end
    local d = db()
    self.instance.widget:SetWidth(d.itemWidth + (padding * 2))
end

--#endregion
