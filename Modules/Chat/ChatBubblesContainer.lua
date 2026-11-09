local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class ChatBubblesModule
local bubbles = addon:GetModule('ChatBubbles')
local Animations = addon.Animations

--#region ── Constants ────────────────────────────────────────────────────────

local MIN_MESSAGE_HEIGHT = 24 -- minimum pixel height for a message content widget
local MESSAGE_BOTTOM_PAD = 4

--#endregion

--#region ── Helpers ──────────────────────────────────────────────────────────

local function db() return addon.db.profile.chatBubbles end

-- Apply every style property on reuse so pooled FontStrings cannot keep old styling.
function bubbles:ApplyBubbleFont(fs, prefix, size)
    local d = db()
    local outline = d[prefix .. 'FontOutline']
    fs:SetFont(addon.Media.ResolveFont(d[prefix .. 'FontFace']), size or d[prefix .. 'FontSize'],
        outline == 'NONE' and '' or outline)
    local shadow = d[prefix .. 'FontShadow']
    fs:SetShadowColor(0, 0, 0, shadow and 1 or 0)
    fs:SetShadowOffset(shadow and 2 or 0, shadow and -2 or 0)
end

local function speechColor(event)
    local key = addon.ChatSources and addon.ChatSources.ChatTypeKey(event)
    return key and ChatTypeInfo and ChatTypeInfo[key]
end

function bubbles:StyleBubbleHeader(bubble)
    local d, sw, data = db(), bubble.widget.subWidgets, bubble.data
    self:ApplyBubbleFont(sw.name, 'name')
    sw.name:SetText(data.sender or '')
    local c = d.nameFontColor
    sw.name:SetTextColor(c.r, c.g, c.b, c.a)

end

--#endregion

--#region ── Message widget ───────────────────────────────────────────────────

---@class ChatBubblesMessage
---@field widget        Frame
---@field message       FontString
---@field revealTicker  table?   C_Timer ticker; non-nil while reveal is in progress
---@field heightAnimation table? height-expansion tween while formatting
---@field topPad        number?  vertical offset used to center text; set by Format, read by _ApplyVisibility
---@field text          string?
---@field event         string?
---@field formatToken   table?
---@field Format        fun(self: ChatBubblesMessage, text: string, type: string, noPortrait: boolean?, noAnim: boolean?, preserveReveal: boolean?)

local messageProto = {}
messageProto.__index = messageProto

---@param text string
---@param type string  CHAT_MSG_* event name
---@param noPortrait boolean?
function messageProto:Format(text, type, noPortrait, noAnim, preserveReveal)
    local visibleText = preserveReveal and self.message:GetText()
    if self.heightAnimation then
        self.heightAnimation:Cancel()
        self.heightAnimation = nil
    end
    local formatToken = {}
    self.formatToken = formatToken
    self.text, self.event = text, type
    local d = db()
    local r, g, b, a = d.msgFontColor.r, d.msgFontColor.g, d.msgFontColor.b, d.msgFontColor.a
    local messageSize = d.msgFontSize

    -- NPC messages may be colored by their canonical chat type. Player colors
    -- are never reached here: overhead replacement is NPC-only.
    local ci = speechColor(type)
    if d.styleByType and ci then
        r, g, b, a = ci.r, ci.g, ci.b, 1
    end
    if d.enlargeYells and type == 'CHAT_MSG_MONSTER_YELL' then
        messageSize = math.floor(d.msgFontSize * 1.25)
    end

    local leftPad = noPortrait and 8 or 48
    local rightPad = noPortrait and 8 or 24
    local availableWidth = d.itemWidth - leftPad - rightPad

    self.message:SetWidth(availableWidth)
    self.message:SetText(text)

    local contentHeight, topPad
    if addon.Utils.IsSecretValue(text) then
        -- Can't measure a secret-aspected FontString; use safe defaults
        bubbles:ApplyBubbleFont(self.message, 'msg', messageSize)
        contentHeight = MIN_MESSAGE_HEIGHT
        topPad = math.max(math.floor((contentHeight - messageSize) / 2), 0)
    else
        -- Scale up single-line messages
        local bumpedSize = d.enlargeSingleLine and math.floor(messageSize * 1.3) or messageSize
        bubbles:ApplyBubbleFont(self.message, 'msg', bumpedSize)
        if self.message:GetUnboundedStringWidth() <= availableWidth then
            messageSize = bumpedSize
        else
            bubbles:ApplyBubbleFont(self.message, 'msg', messageSize)
        end

        local textHeight = self.message:GetHeight()
        local vPad = math.max(math.ceil(d.msgFontSize * 0.5), 8)
        local numLines = math.max(1, math.ceil(textHeight / (d.msgFontSize * 1.2)))
        local correction = math.min(
            math.floor(d.msgFontSize / 8 * (numLines + 1)),
            math.floor(d.msgFontSize / 2)
        )
        topPad = math.max(vPad - correction, 0)
        contentHeight = math.max(textHeight + topPad + MESSAGE_BOTTOM_PAD, MIN_MESSAGE_HEIGHT)
    end

    self.message:SetTextColor(r, g, b, a)
    self.widget:SetSize(d.itemWidth, contentHeight)
    self.topPad = topPad
    self.message:ClearAllPoints()
    self.message:SetPoint('TOPLEFT', self.widget, 'TOPLEFT', leftPad, -topPad)
    self.message:SetPoint('TOPRIGHT', self.widget, 'TOPRIGHT', -rightPad, -topPad)

    if preserveReveal then
        if not d.revealText and self.revealTicker then
            self.revealTicker:Cancel()
            self.revealTicker = nil
        else
            self.message:SetText(visibleText)
        end
    elseif d.revealText and not addon.Utils.IsSecretValue(text) then
        self.message:SetText('')
        local total = #text
        local shown = 0
        self.revealTicker = C_Timer.NewTicker(1 / d.revealSpeed, function()
            shown = shown + 1
            self.message:SetText(text:sub(1, shown))
            if shown >= total then
                self.revealTicker:Cancel()
                self.revealTicker = nil
            end
        end)
    end

    if not noAnim then
        local fullHeight = contentHeight
        C_Timer.After(0, function()
            if self.formatToken ~= formatToken or not self.widget:IsShown() then return end
            if self.heightAnimation then self.heightAnimation:Cancel() end
            self.widget:SetHeight(0)
            local animation
            animation = Animations.Progress(self.widget, 0.25, Animations.QuadraticOut,
                function(eased, progress)
                    if progress < 1 then self.widget:SetHeight(fullHeight * eased) end
                end,
                function()
                    self.widget:SetHeight(fullHeight)
                    if self.heightAnimation == animation then self.heightAnimation = nil end
                end)
            self.heightAnimation = animation
        end)
    end

    self.widget:Show()
end

local function _MessageCreate()
    local i = setmetatable({}, messageProto)
    local d = db()
    local L = addon.Layout

    local content = L:Container(UIParent, { width = d.itemWidth, height = MIN_MESSAGE_HEIGHT })

    local message = content:FontString({ justifyH = 'LEFT', justifyV = 'TOP' })
    message:SetPoint('TOPLEFT', content, 'TOPLEFT', 48, 0)
    message:SetPoint('TOPRIGHT', content, 'TOPRIGHT', -24, 0)
    bubbles:ApplyBubbleFont(message.fs, 'msg')

    i.widget = content.frame
    i.message = message.fs
    return i
end

---@param pool ObjectPoolMixin
---@param msg  ChatBubblesMessage
local function _MessageReset(pool, msg)
    if not msg or not msg.widget then return end
    if msg.revealTicker then
        msg.revealTicker:Cancel()
        msg.revealTicker = nil
    end
    if msg.heightAnimation then
        msg.heightAnimation:Cancel()
        msg.heightAnimation = nil
    end
    msg.widget:SetParent(UIParent)
    msg.widget:SetAlpha(1)
    msg.widget:Hide()
    msg.widget:ClearAllPoints()
    msg.message:SetText('')
    msg.message:ClearAllPoints()
    msg.topPad = nil
    msg.text, msg.event, msg.formatToken = nil, nil, nil
end

--#endregion

--#region ── Item controller ──────────────────────────────────────────────────

---@class ChatBubblesController
---@field parent             ChatBubblesWidget
---@field CreateMessage      fun(self: ChatBubblesController): ChatBubblesMessage
---@field RepositionMessages fun(self: ChatBubblesController)
---@field RemoveMessage      fun(self: ChatBubblesController, msg: ChatBubblesMessage)
---@field FormatMessage      fun(self: ChatBubblesController, msg: ChatBubblesMessage, text: string, type: string): number
---@field layoutAnimation   table?

local controllerProto = {}
controllerProto.__index = controllerProto

---@return ChatBubblesMessage
function controllerProto:CreateMessage()
    ---@type ChatBubblesMessage
    local msg = bubbles._messagePool:Acquire()
    msg.widget:SetParent(self.parent.widget)
    table.insert(self.parent.widget.subWidgets.messages, msg)
    return msg
end

function controllerProto:RepositionMessages()
    local messages = self.parent.widget.subWidgets.messages
    local currentYOffset = self.parent.widget.subWidgets.textureBottom:GetHeight()

    for i = 1, #messages do
        local msg = messages[i]
        msg.widget:ClearAllPoints()
        msg.widget:SetPoint('BOTTOMLEFT', self.parent.widget, 'BOTTOMLEFT', 0, currentYOffset)
        currentYOffset = currentYOffset + msg.widget:GetHeight()
    end

    -- Keep topContainer tracking the top edge of the topmost message so it
    -- slides up in sync with the grow-reveal animation.
    local topFrame = self.parent.widget.subWidgets.textureTop
    topFrame:ClearAllPoints()
    if #messages > 0 then
        topFrame:SetPoint('BOTTOMLEFT', messages[#messages].widget, 'TOPLEFT', 0, 0)
    else
        topFrame:SetPoint('TOPLEFT', self.parent.widget, 'TOPLEFT')
    end
end

---@param msg ChatBubblesMessage
function controllerProto:RemoveMessage(msg)
    local messages = self.parent.widget.subWidgets.messages

    if #messages == 1 and messages[1] == msg then
        bubbles:RemoveChatBubble(self.parent)
        return
    end

    local removedIndex
    for i = 1, #messages do
        if messages[i] == msg then
            removedIndex = i; break
        end
    end
    if not removedIndex then return end

    local messageHeight = msg.widget:GetHeight()
    local parentWidget = self.parent.widget

    local targetParentHeight = self.parent.minimumHeight
    for i = 1, #messages do
        if i ~= removedIndex then
            targetParentHeight = targetParentHeight + messages[i].widget:GetHeight()
        end
    end

    -- Capture start/end Y for messages that will slide (those above the removed one).
    -- Must be captured BEFORE table.remove so GetBottom() still returns the live position.
    local sliding = {}
    for i = removedIndex + 1, #messages do
        local startY = messages[i].widget:GetBottom() - parentWidget:GetBottom()
        sliding[#sliding + 1] = {
            msg = messages[i],
            startY = startY,
            endY = startY - messageHeight,
        }
    end

    table.remove(messages, removedIndex)

    -- Raise fading message above siblings so the fade is visible as others slide into its space.
    local origLevel = msg.widget:GetFrameLevel()
    msg.widget:SetFrameLevel(parentWidget:GetFrameLevel() + 30)

    -- Alpha-fade the removed message simultaneously with the slide below.
    local fadeAg = msg.widget:CreateAnimationGroup()
    fadeAg:SetToFinalAlpha(true)
    local fadeAlpha = fadeAg:CreateAnimation('Alpha')
    fadeAlpha:SetFromAlpha(1)
    fadeAlpha:SetToAlpha(0)
    fadeAlpha:SetDuration(0.5)
    fadeAlpha:SetSmoothing('OUT')
    fadeAg:SetScript('OnFinished', function()
        msg.widget:SetFrameLevel(origLevel)
        bubbles._messagePool:Release(msg)
        if #messages == 0 then bubbles:RemoveChatBubble(self.parent) end
    end)
    fadeAg:Play()

    -- If nothing needs to slide (topmost message was removed), snap and re-anchor immediately.
    if #sliding == 0 then
        parentWidget:SetHeight(targetParentHeight)
        self:RepositionMessages()
        return
    end

    local DURATION = 0.5
    local startParentH = parentWidget:GetHeight()
    if self.layoutAnimation then self.layoutAnimation:Cancel() end

    local animation
    animation = Animations.Progress(parentWidget, DURATION, Animations.QuadraticOut,
        function(eased)
            for _, entry in ipairs(sliding) do
                local y = entry.startY + (entry.endY - entry.startY) * eased
                entry.msg.widget:ClearAllPoints()
                entry.msg.widget:SetPoint('BOTTOMLEFT', parentWidget, 'BOTTOMLEFT', 0, y)
            end

            parentWidget:SetHeight(startParentH + (targetParentHeight - startParentH) * eased)
        end,
        function()
            parentWidget:SetHeight(targetParentHeight)
            self:RepositionMessages()
            if self.layoutAnimation == animation then self.layoutAnimation = nil end
        end)
    self.layoutAnimation = animation
end

---@param msg  ChatBubblesMessage
---@param text string
---@param type string
---@return number duration
function controllerProto:FormatMessage(msg, text, type)
    -- Sync container width in case itemWidth changed since this widget was created.
    local w = db().itemWidth
    local sw = self.parent.widget.subWidgets
    self.parent.widget:SetWidth(w)
    sw.textureBottom:SetWidth(w)
    sw.textureTop:SetWidth(w)

    local duration = bubbles.CalculateDisplayDuration(text)
    msg:Format(text, type, self.parent.noPortrait, self.parent.pinned)

    -- The owning bubble starts its timers only after attachment to a native frame.
    return duration
end

---@param parent ChatBubblesWidget
---@return ChatBubblesController
local function newController(parent)
    local i = setmetatable({}, controllerProto)
    i.parent = parent
    return i
end

--#endregion

--#region ── Bubble widget ─────────────────────────────────────────────────────

---@class ChatBubblesSubWidgets
---@field portraitFrame Frame
---@field portrait3D    PlayerModel
---@field name          FontString
---@field messages      ChatBubblesMessage[]
---@field textureBottom Frame
---@field textureTop    Frame

---@class ChatBubblesWidget: Frame
---@field subWidgets ChatBubblesSubWidgets

---@class ChatBubblesInstance
---@field id             number
---@field data           ChatMessage
---@field minimumHeight  number
---@field nativeFrame    Frame?
---@field nativeState    table?
---@field finish         fun(result: string)?
---@field resultTimer    table?
---@field expiryTimer    table?
---@field fadeTimer      table?
---@field position       table?
---@field pinned         boolean?
---@field noPortrait     boolean?
---@field _bubbleToken   table?
---@field shownAt        number?
---@field bubbleDuration number?
---@field widget         ChatBubblesWidget
---@field animationGroup AnimationGroup?
---@field controller     ChatBubblesController

bubbles.bubbleProto = {
    minimumHeight = 64,
}

local function _BubbleCreate()
    local i = setmetatable({}, { __index = bubbles.bubbleProto })
    i.controller = newController(i)

    local d = db()
    local L = addon.Layout
    local widgetWidth = d.itemWidth

    local TEX = 'interface/housing/housingcelebratorytoast'
    local TOP_L, TOP_R, TOP_T, TOP_B = 0, 0.41273, 0.107, 0.16
    local BOT_L, BOT_R, BOT_T, BOT_B = 0, 0.41273, 0.33, 0.383
    local barHeight = 32 -- fixed pixel height; width stretches to fill widgetWidth
    i.minimumHeight = barHeight * 2

    local container = L:Container(UIParent, { width = widgetWidth, height = i.minimumHeight })

    -- Top
    local topContainer = L:Container(container, { width = widgetWidth, height = barHeight })
    topContainer:SetPoint('TOPLEFT', container, 'TOPLEFT')
    local tTex = topContainer:Texture("ARTWORK", { texture = TEX })
    tTex:SetAllPoints(topContainer)
    tTex:SetTexCoord(TOP_L, TOP_R, TOP_T, TOP_B)

    -- Bottom
    local bottomContainer = L:Container(container, { width = widgetWidth, height = barHeight })
    bottomContainer:SetPoint('BOTTOMLEFT', container, 'BOTTOMLEFT')
    local bTex = bottomContainer:Texture("ARTWORK", { texture = TEX })
    bTex:SetAllPoints(bottomContainer)
    bTex:SetTexCoord(BOT_L, BOT_R, BOT_T, BOT_B)

    -- Message bg
    local messageBg = L:Container(container, { width = widgetWidth })
    messageBg:SetPoint('BOTTOMLEFT', bottomContainer, 'TOPLEFT', 0, 0)
    messageBg:SetPoint('TOPRIGHT', topContainer, 'BOTTOMRIGHT', 0, 0)

    local mbLeft = messageBg:Texture('BACKGROUND')
    mbLeft:SetColorTexture(1, 1, 1, 1)
    mbLeft:SetPoint('TOPLEFT', messageBg, 'TOPLEFT', 0, 16)
    mbLeft:SetPoint('BOTTOMRIGHT', messageBg, 'BOTTOM', 0, -12)
    mbLeft:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, .7))

    local mbRight = messageBg:Texture('BACKGROUND')
    mbRight:SetColorTexture(1, 1, 1, 1)
    mbRight:SetPoint('TOPLEFT', messageBg, 'TOP', 0, 16)
    mbRight:SetPoint('BOTTOMRIGHT', messageBg, 'BOTTOMRIGHT', 0, -12)
    mbRight:SetGradient('HORIZONTAL', CreateColor(0, 0, 0, .7), CreateColor(0, 0, 0, 0))

    -- Portrait
    local portraitContainer = L:Container(container,
        { width = 64, height = 64 })
    portraitContainer:SetPoint('BOTTOMLEFT', bTex, 'TOPLEFT', -20, 10)

    local portraitBackdrop = portraitContainer:Texture('BACKGROUND', { atlas = 'house-chest-list-item-active' })
    portraitBackdrop:SetAllPoints(portraitContainer.frame)

    local portrait3D = CreateFrame('PlayerModel', nil, portraitContainer.frame)
    portrait3D:SetPoint('CENTER', portraitContainer.frame, 'CENTER')
    portrait3D:SetSize(54, 54)

    local portraitBorderFrame = CreateFrame('Frame', nil, portraitContainer.frame)
    portraitBorderFrame:SetFrameLevel(portrait3D:GetFrameLevel() + 1)
    portraitBorderFrame:SetAllPoints(portraitContainer.frame)
    local portraitBorder = portraitBorderFrame:CreateTexture(nil, 'OVERLAY')
    portraitBorder:SetAtlas('spellbook-item-iconframe')
    portraitBorder:SetPoint('TOPRIGHT', portraitBorderFrame, 'TOPRIGHT', 2, 4)
    portraitBorder:SetSize(84, 84)
    portraitBorder:SetVertexColor(.4, .4, .4, 1)

    -- Name
    local nameOverlay = L:Container(container, { frameLevel = container.frame:GetFrameLevel() + 20 })
    nameOverlay:SetAllPoints(container)
    local name = L:FontString(nameOverlay, { justifyH = 'LEFT', maxLines = 1 })
    bubbles:ApplyBubbleFont(name.fs, 'name')
    name:SetPoint('BOTTOMLEFT', tTex, 'TOPLEFT', 8, -16)
    name:SetPoint('BOTTOMRIGHT', tTex, 'TOPRIGHT', -8, -16)

    local widget = container.frame --[[@as ChatBubblesWidget]]
    widget.subWidgets = {
        portraitFrame = portraitContainer.frame,
        portrait3D = portrait3D,
        name = name.fs,
        messages = {},
        textureBottom = bottomContainer.frame,
        textureTop = topContainer.frame,
    }

    i.widget = widget
    return i
end

---@param pool ObjectPoolMixin
---@param bubble ChatBubblesInstance
local function _BubbleReset(pool, bubble)
    if not bubble or not bubble.widget then return end

    -- Release messages directly — no animations during pool reset.
    if bubble.controller.layoutAnimation then
        bubble.controller.layoutAnimation:Cancel()
        bubble.controller.layoutAnimation = nil
    end
    local messages = bubble.widget.subWidgets.messages
    for i = #messages, 1, -1 do
        bubbles._messagePool:Release(table.remove(messages, i))
    end

    -- Park topContainer directly above the bottom bar so messageBg collapses to zero height.
    local sw = bubble.widget.subWidgets
    sw.textureTop:ClearAllPoints()
    sw.textureTop:SetPoint('BOTTOMLEFT', sw.textureBottom, 'TOPLEFT', 0, 0)

    bubble._bubbleToken = nil
    bubble.finish = nil
    bubble.position = nil
    bubble.shownAt = nil
    bubble.bubbleDuration = nil
    bubble.widget:SetHeight(bubble.minimumHeight)
    bubble.widget:SetScale(1)
    bubble.widget:Hide()
    bubble.widget:ClearAllPoints()
    bubble.widget:SetParent(UIParent)
    bubble.widget:SetIgnoreParentAlpha(false)
    bubble.widget:SetAlpha(1)
    bubble.data = nil
    bubble.pinned = nil
    bubble.widget.subWidgets.name:SetText('')
    bubble.widget.subWidgets.name:Show()
    bubble.widget.subWidgets.portrait3D:ClearModel()
    bubble.widget.subWidgets.portraitFrame:Show()
end

--#endregion

--#region ── Public API ───────────────────────────────────────────────────────

---@return ChatBubblesInstance
function bubbles:CreateBubble()
    return (self._pool:Acquire())
end

---@param bubble ChatBubblesInstance
function bubbles:ReleaseBubble(bubble)
    if not self._pool:IsActive(bubble) then return end
    bubble._bubbleToken = nil
    for _, key in ipairs({ 'resultTimer', 'expiryTimer', 'fadeTimer' }) do
        if bubble[key] then bubble[key]:Cancel(); bubble[key] = nil end
    end
    if bubble.animationGroup then
        bubble.animationGroup:Stop()
        bubble.animationGroup = nil
    end
    UIFrameFadeRemoveFrame(bubble.widget)
    bubble.widget:Hide()
    self:ReleaseNativeBubble(bubble)
    for i = #self.active, 1, -1 do
        if self.active[i] == bubble then table.remove(self.active, i) end
    end
    self._pool:Release(bubble)
end

-- Re-measure existing messages without restarting their reveal or expiry timers.
function bubbles:RefreshVisibleBubbles()
    if not self._pool then return end
    if InCombatLockdown and InCombatLockdown() then return end
    for bubble in self._pool:EnumerateActive() do
        if bubble.data and not bubble.released then
            self:StyleBubbleHeader(bubble)
            local height = bubble.minimumHeight
            for _, msg in ipairs(bubble.widget.subWidgets.messages) do
                msg:Format(msg.text, msg.event, bubble.noPortrait, true, true)
                height = height + msg.widget:GetHeight()
            end
            bubble.widget:SetHeight(height)
            bubble.controller:RepositionMessages()
            self:ApplyBubblePosition(bubble)
        end
    end
end

function bubbles:InitPools()
    self._messagePool = CreateObjectPool(_MessageCreate, _MessageReset)
    if self._messagePool.SetResetDisallowedIfNew then
        self._messagePool:SetResetDisallowedIfNew()
    end

    self._pool = CreateObjectPool(_BubbleCreate, _BubbleReset)
    if self._pool.SetResetDisallowedIfNew then
        self._pool:SetResetDisallowedIfNew()
    end
end

--#endregion
