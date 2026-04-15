local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local LSM = LibStub('LibSharedMedia-3.0')

---@class BanterModule
local banter = addon:GetModule('Banter')

--#region ── Constants ────────────────────────────────────────────────────────

local FONT_PATH = 'Interface/AddOns/CouchMode/Modules/Banter/Resources/Fonts/BebasNeue-Regular.ttf'
local MIN_MESSAGE_HEIGHT = 24 -- minimum pixel height for a message content widget

-- Event name constants (same values as in Banter.lua — kept local to avoid cross-file coupling).
local EVENT_YELL = 'CHAT_MSG_MONSTER_YELL'
local EVENT_WHISPER = 'CHAT_MSG_MONSTER_WHISPER'
local EVENT_PARTY = 'CHAT_MSG_MONSTER_PARTY'

--#endregion

--#region ── Helpers ──────────────────────────────────────────────────────────

local function db() return addon.db.profile.banter end

local function fetchFont(face)
    return LSM:Fetch(LSM.MediaType.FONT, face) or FONT_PATH
end

--#endregion

--#region ── Message widget ───────────────────────────────────────────────────

---@class BanterContainerMessage
---@field widget        Frame
---@field message       FontString
---@field expiryTime    number?
---@field revealTicker  table?   C_Timer ticker; non-nil while reveal is in progress
---@field Format         fun(self: BanterContainerMessage, text: string, type: string)


local messageProto = {}
messageProto.__index = messageProto

---@param text string
---@param type string  CHAT_MSG_MONSTER_* event name
function messageProto:Format(text, type)
    local d = db()
    local r, g, b, a = d.msgFontColor.r, d.msgFontColor.g, d.msgFontColor.b, d.msgFontColor.a
    local messageSize = d.msgFontSize

    if d.styleByType then
        if type == EVENT_YELL then
            r, g, b, a = 1, 0.2, 0.2, 1 -- red
            messageSize = math.floor(d.msgFontSize * 1.25)
        elseif type == EVENT_WHISPER then
            r, g, b, a = 1, 0.5, 1, 1   -- pink
        elseif type == EVENT_PARTY then
            r, g, b, a = 0.6, 0.8, 1, 1 -- light blue
        else
            r, g, b, a = 1, 1, 1, 1     -- white (SAY)
        end
    end

    self.message:SetWidth(d.itemWidth - 20)
    self.message:SetText(text)
    self.message:SetFont(fetchFont(d.msgFontFace), messageSize, 'OUTLINE')
    self.message:SetTextColor(r, g, b, a)

    local contentHeight = math.max(self.message:GetHeight() + 10, MIN_MESSAGE_HEIGHT)
    self.widget:SetSize(d.itemWidth, contentHeight)

    if d.revealText then
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

    -- Reveal: grow the frame from height 0 to full over 0.25s, clipping children so
    -- the content is revealed bottom-up. Height is set to full first (above) so that
    -- callers reading GetHeight() this frame get the correct value; the grow starts
    -- next frame via C_Timer.After(0).
    local fullHeight = contentHeight
    C_Timer.After(0, function()
        if not self.widget:IsShown() then return end
        self.widget:SetHeight(0)
        local elapsed = 0
        self.widget:SetScript('OnUpdate', function(f, dt)
            elapsed = elapsed + dt
            local t = math.min(elapsed / 0.25, 1)
            f:SetHeight(fullHeight * (t * (2 - t))) -- ease-out
            if t >= 1 then
                f:SetHeight(fullHeight)
                f:SetScript('OnUpdate', nil)
            end
        end)
    end)

    self.widget:Show()
end

local function _MessageCreate()
    local i = setmetatable({}, messageProto)
    local d = db()
    local L = addon.Layout

    local content = L:Container(UIParent, { width = d.itemWidth, height = MIN_MESSAGE_HEIGHT })

    local message = content:FontString({ justifyH = 'LEFT' })
    message:SetPoint('TOPLEFT', content, 'TOPLEFT', 62, 0)
    message:SetPoint('BOTTOMRIGHT', content, 'BOTTOMRIGHT', -10, 0)
    message.fs:SetFont(fetchFont(d.msgFontFace), d.msgFontSize, 'OUTLINE')
    message.fs:SetShadowColor(0, 0, 0, 1)
    message.fs:SetShadowOffset(2, -2)

    i.widget = content.frame
    i.message = message.fs
    return i
end

---@param pool ObjectPoolMixin
---@param msg  BanterContainerMessage
local function _MessageReset(pool, msg)
    if not msg or not msg.widget then return end
    if msg.revealTicker then
        msg.revealTicker:Cancel()
        msg.revealTicker = nil
    end
    msg.widget:SetScript('OnUpdate', nil)
    msg.widget:SetParent(UIParent)
    msg.widget:SetAlpha(1)
    msg.widget:Hide()
    msg.widget:ClearAllPoints()
    msg.message:SetText('')
    -- Restore default portrait-present anchors so pool reuse starts clean.
    msg.message:ClearAllPoints()
    msg.message:SetPoint('TOPLEFT',     msg.widget, 'TOPLEFT',     62,  0)
    msg.message:SetPoint('BOTTOMRIGHT', msg.widget, 'BOTTOMRIGHT', -10, 0)
end

--#endregion

--#region ── Item controller ──────────────────────────────────────────────────

---@class BanterContainerController
---@field parent             BanterContainerMain
---@field CreateMessage      fun(self: BanterContainerController): BanterContainerMessage
---@field RepositionMessages fun(self: BanterContainerController)
---@field RemoveMessage      fun(self: BanterContainerController, msg: BanterContainerMessage)
---@field FormatMessage      fun(self: BanterContainerController, msg: BanterContainerMessage, text: string, type: string): number

local controllerProto = {}
controllerProto.__index = controllerProto

---@return BanterContainerMessage
function controllerProto:CreateMessage()
    ---@type BanterContainerMessage
    local msg = banter._messagePool:Acquire()
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

---@param msg BanterContainerMessage
function controllerProto:RemoveMessage(msg)
    local messages = self.parent.widget.subWidgets.messages

    if #messages == 1 and messages[1] == msg then
        banter:RemoveBant(self.parent)
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
        banter._messagePool:Release(msg)
        if #messages == 0 then banter:RemoveBant(self.parent) end
    end)
    fadeAg:Play()

    -- If nothing needs to slide (topmost message was removed), snap and re-anchor immediately.
    if #sliding == 0 then
        parentWidget:SetHeight(targetParentHeight)
        self:RepositionMessages()
        return
    end

    -- OnUpdate-based slide: actual positions change each frame via ClearAllPoints + SetPoint,
    -- so topContainer (anchored to messages[#messages].TOPLEFT) and messageBg (anchored to
    -- topContainer.BOTTOMRIGHT) follow automatically — no explicit topContainer animation needed.
    local DURATION = 0.5
    local startParentH = parentWidget:GetHeight()
    local elapsed = 0

    parentWidget:SetScript('OnUpdate', function(f, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / DURATION, 1)
        local eased = t * (2 - t) -- ease-out

        for _, entry in ipairs(sliding) do
            local y = entry.startY + (entry.endY - entry.startY) * eased
            entry.msg.widget:ClearAllPoints()
            entry.msg.widget:SetPoint('BOTTOMLEFT', parentWidget, 'BOTTOMLEFT', 0, y)
        end

        f:SetHeight(startParentH + (targetParentHeight - startParentH) * eased)

        if t >= 1 then
            f:SetScript('OnUpdate', nil)
            f:SetHeight(targetParentHeight)
            self:RepositionMessages()
        end
    end)
end

---@param msg  BanterContainerMessage
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
    -- messageBg is anchored by two points (BOTTOMLEFT/TOPRIGHT) so its width follows automatically.

    local duration = banter.CalculateDisplayDuration(text)
    msg:Format(text, type)

    local expiryTime = GetTime() + duration
    msg.expiryTime = expiryTime         -- per-message, so multiple messages don't trample each other
    self.parent.expiryTime = expiryTime -- parent-level, for BanterController's duration-extension logic

    local function onExpire()
        local remaining = msg.expiryTime - GetTime()
        if remaining > 0.05 then
            C_Timer.After(remaining, onExpire)
        else
            self:RemoveMessage(msg)
        end
    end
    C_Timer.After(duration, onExpire)

    return duration
end

---@param parent BanterContainerMain
---@return BanterContainerController
local function newController(parent)
    local i = setmetatable({}, controllerProto)
    i.parent = parent
    return i
end

--#endregion

--#region ── Bant widget ──────────────────────────────────────────────────────

---@class BanterContainerSubWidgets
---@field portrait      Texture
---@field portraitFrame Frame
---@field name          FontString
---@field messages      BanterContainerMessage[]
---@field textureBottom Frame
---@field textureTop    Frame

---@class BanterContainerWidget: Frame
---@field subWidgets BanterContainerSubWidgets

---@class BanterContainerMain
---@field id             number
---@field data           BanterData
---@field minimumHeight  number
---@field expiryTime     number?
---@field isBubbleMode   boolean?
---@field widget         BanterContainerWidget
---@field animationGroup AnimationGroup?
---@field controller     BanterContainerController

banter.bantProto = {
    minimumHeight = 64,
}

local function _BantCreate()
    local i = setmetatable({}, { __index = banter.bantProto })
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
        { width = MIN_MESSAGE_HEIGHT, height = MIN_MESSAGE_HEIGHT })
    portraitContainer:SetPoint('LEFT', container, 'LEFT', 2)

    local portrait = portraitContainer:Texture('ARTWORK')
    portrait:SetAllPoints(portraitContainer)

    local portraitBorder = portraitContainer:Texture('OVERLAY', {
        atlas = 'auctionhouse-itemicon-border-artifact',
        size = { w = 64, h = 64 }
    })
    portraitBorder:SetPoint('CENTER', portraitContainer, 'CENTER')

    -- Name
    local nameOverlay = L:Container(container, { frameLevel = container.frame:GetFrameLevel() + 20 })
    nameOverlay:SetAllPoints(container)
    local name = L:FontString(nameOverlay, { justifyH = 'LEFT', maxLines = 1 })
    name.fs:SetFont(fetchFont(d.nameFontFace), d.nameFontSize, 'OUTLINE')
    local c = FACTION_BAR_COLORS[4]
    name:SetTextColor(c.r, c.g, c.b)
    name:SetPoint('BOTTOMLEFT', tTex, 'BOTTOMLEFT', 6, 13)
    name.fs:SetShadowColor(0, 0, 0, 1)
    name.fs:SetShadowOffset(2, -2)

    local widget = container.frame --[[@as BanterContainerWidget]]
    widget.subWidgets = {
        portrait      = portrait.tex,
        portraitFrame = portraitContainer.frame,
        name          = name.fs,
        messages      = {},
        textureBottom = bottomContainer.frame,
        textureTop    = topContainer.frame,
    }

    i.widget = widget
    return i
end

---@param pool ObjectPoolMixin
---@param bant BanterContainerMain
local function _BantReset(pool, bant)
    if not bant or not bant.widget then return end

    -- Release messages directly — no animations during pool reset.
    local messages = bant.widget.subWidgets.messages
    for i = #messages, 1, -1 do
        banter._messagePool:Release(table.remove(messages, i))
    end

    -- Park topContainer directly above the bottom bar so messageBg collapses to zero height.
    local sw = bant.widget.subWidgets
    sw.textureTop:ClearAllPoints()
    sw.textureTop:SetPoint('BOTTOMLEFT', sw.textureBottom, 'TOPLEFT', 0, 0)

    bant.widget:SetScript('OnUpdate', nil)
    bant.expiryTime = nil
    bant.widget:SetHeight(bant.minimumHeight)
    bant.widget:Hide()
    bant.widget:ClearAllPoints()
    bant.widget:SetParent(UIParent)
    bant.widget:SetIgnoreParentAlpha(false)
    bant.widget:SetAlpha(1)
    bant.isBubbleMode = nil
    bant.data = nil
    bant.widget.subWidgets.name:SetText('')
    bant.widget.subWidgets.name:Show()
    bant.widget.subWidgets.portrait:SetTexture(nil)
    bant.widget.subWidgets.portraitFrame:Show()
end

--#endregion

--#region ── Public API ───────────────────────────────────────────────────────

---@return BanterContainerMain
function banter:Create()
    return (self._pool:Acquire())
end

---@param bant BanterContainerMain
function banter:Release(bant)
    self._pool:Release(bant)
end

function banter:InitPools()
    self._messagePool = CreateObjectPool(_MessageCreate, _MessageReset)
    if self._messagePool.SetResetDisallowedIfNew then
        self._messagePool:SetResetDisallowedIfNew()
    end

    self._pool = CreateObjectPool(_BantCreate, _BantReset)
    if self._pool.SetResetDisallowedIfNew then
        self._pool:SetResetDisallowedIfNew()
    end
end

--#endregion
