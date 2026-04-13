local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local LSM = LibStub('LibSharedMedia-3.0')

---@class BantsModule: AceModule
local bants = addon:NewModule('Bants')

--#region ── Constants ────────────────────────────────────────────────────────

local MEDIA = 'Interface/AddOns/CouchMode/Modules/Banter/Resources/Media/'
local FONT_PATH = 'Interface/AddOns/CouchMode/Modules/Banter/Resources/Fonts/BebasNeue-Regular.ttf'

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

---@class BantsMessage
---@field widget  Frame
---@field message FontString

local messageProto = {}
messageProto.__index = messageProto

---@param text string
---@param type string  CHAT_MSG_MONSTER_* event name
function messageProto:Format(text, type)
    local d = db()
    local messageColor = { r = d.msgFontColor.r, g = d.msgFontColor.g, b = d.msgFontColor.b, a = d.msgFontColor.a }
    local messageSize = d.msgFontSize

    if d.styleByType then
        if type == EVENT_YELL then
            messageColor = { r = 1, g = 0.2, b = 0.2, a = 1 } -- red
            messageSize = math.floor(d.msgFontSize * 1.25)
        elseif type == EVENT_WHISPER then
            messageColor = { r = 1, g = 0.5, b = 1, a = 1 }   -- pink
        elseif type == EVENT_PARTY then
            messageColor = { r = 0.6, g = 0.8, b = 1, a = 1 } -- light blue
        else
            messageColor = { r = 1, g = 1, b = 1, a = 1 }     -- white (SAY)
        end
    end

    self.message:SetText(text)
    self.message:SetFont(fetchFont(d.msgFontFace), messageSize, 'OUTLINE')
    self.message:SetTextColor(messageColor.r, messageColor.g, messageColor.b, messageColor.a)

    self.widget:SetSize(db().itemWidth, self.message:GetHeight() + 20)
    self.widget:Show()
end

local function _MessageCreate()
    local i = setmetatable({}, messageProto)

    local messageFrame = CreateFrame('Frame', nil, UIParent)
    messageFrame:SetSize(db().itemWidth, 128)

    local bg = messageFrame:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    bg:SetTexture(MEDIA .. 'center_repeat.png')

    local text = messageFrame:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    text:SetPoint('LEFT', messageFrame, 'LEFT', 32, 0)
    text:SetSize(db().itemWidth - 40, 0)
    text:SetJustifyH('LEFT')
    text:SetTextColor(1, 1, 1)

    i.widget = messageFrame
    i.message = text
    return i
end

---@param pool ObjectPoolMixin
---@param msg  BantsMessage
local function _MessageReset(pool, msg)
    if not msg or not msg.widget then return end
    msg.widget:SetParent(UIParent)
    msg.widget:SetAlpha(1)
    msg.widget:Hide()
    msg.widget:ClearAllPoints()
    msg.message:SetText('')
end

--#endregion

--#region ── Controller ───────────────────────────────────────────────────────

---@class BantsController
---@field parent            BantsMain
---@field CreateMessage     fun(self: BantsController): BantsMessage
---@field RepositionMessages fun(self: BantsController)
---@field RemoveMessage     fun(self: BantsController, msg: BantsMessage)
---@field FormatMessage     fun(self: BantsController, msg: BantsMessage, text: string, type: string): number

local controllerProto = {}
controllerProto.__index = controllerProto

---@return BantsMessage
function controllerProto:CreateMessage()
    ---@type BantsMessage
    local msg = bants._messagePool:Acquire()
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
end

---@param msg BantsMessage
function controllerProto:RemoveMessage(msg)
    if self.parent.animationGroup and self.parent.animationGroup:IsPlaying() then
        self.parent.animationGroup:Stop()
    end

    local messages = self.parent.widget.subWidgets.messages

    -- Last message — remove the icon/name and message together as one unit.
    if #messages == 1 and messages[1] == msg then
        local banterFrame = addon:GetModule('BanterFrame', true) --[[@as BanterFrameModule?]]
        if banterFrame then banterFrame:RemoveBant(self.parent) end
        return
    end

    local removed_index
    for i = 1, #messages do
        if messages[i] == msg then
            removed_index = i
            break
        end
    end

    if not removed_index then return end

    local messageHeight = msg.widget:GetHeight()
    local parentWidget = self.parent.widget
    local originalParentHeight = parentWidget:GetHeight()
    local targetParentHeight = originalParentHeight - messageHeight

    -- 1. Fade out the message text.
    msg.message:SetText('')
    UIFrameFadeOut(msg.widget, 0.5, 1, 0)

    -- 2. Animation group for everything else.
    local ag = parentWidget:CreateAnimationGroup()
    self.parent.animationGroup = ag

    local function cleanup()
        if self.parent.animationGroup ~= ag then return end
        self.parent.animationGroup = nil

        table.remove(messages, removed_index)
        bants._messagePool:Release(msg)

        parentWidget:SetHeight(targetParentHeight)
        self:RepositionMessages()

        -- If this removal leaves the bant empty, fade out the whole thing.
        if #messages == 0 then
            local banterFrame = addon:GetModule('BanterFrame', true) --[[@as BanterFrameModule?]]
            if banterFrame then banterFrame:RemoveBant(self.parent) end
        end
    end

    ag:SetScript('OnFinished', cleanup)

    -- 3. Slide messages above the removed one downward.
    for i = removed_index + 1, #messages do
        local msg_to_move = messages[i]
        local anim = ag:CreateAnimation('Translation')
        anim:SetTarget(msg_to_move.widget)
        anim:SetDuration(0.5)
        anim:SetOrder(1)
        anim:SetOffset(0, -messageHeight)
        anim:SetSmoothing('IN_OUT')
    end

    -- 4. Slide the top texture down too.
    local top_texture = self.parent.widget.subWidgets.textureTop
    local topAnim = ag:CreateAnimation('Translation')
    topAnim:SetTarget(top_texture)
    topAnim:SetDuration(0.5)
    topAnim:SetOrder(1)
    topAnim:SetOffset(0, -messageHeight)
    topAnim:SetSmoothing('IN_OUT')

    ag:Play()
end

---@param msg  BantsMessage
---@param text string
---@param type string
---@return number duration
function controllerProto:FormatMessage(msg, text, type)
    local banter = addon:GetModule('Banter')
    local duration = banter.CalculateDisplayDuration(text)
    msg:Format(text, type)

    self.parent.expiryTime = GetTime() + duration

    local function onExpire()
        if not self.parent.expiryTime then return end
        local remaining = self.parent.expiryTime - GetTime()
        if remaining > 0.05 then
            C_Timer.After(remaining, onExpire)
        else
            self:RemoveMessage(msg)
        end
    end
    C_Timer.After(duration, onExpire)

    return duration
end

---@param parent BantsMain
---@return BantsController
local function newController(parent)
    local i = setmetatable({}, controllerProto)
    i.parent = parent
    return i
end

--#endregion

--#region ── Bant widget ──────────────────────────────────────────────────────

---@class BantsSubWidgets
---@field portrait      Texture
---@field name          FontString
---@field messages      BantsMessage[]
---@field textureBottom Frame
---@field textureTop    Frame
---@field titleLeft     Texture
---@field titleMiddle   Texture
---@field titleRight    Texture

---@class BantsWidget: Frame
---@field subWidgets BantsSubWidgets

---@class BantsMain
---@field id             number
---@field data           BantsData
---@field minimumHeight  number
---@field expiryTime     number?
---@field widget         BantsWidget
---@field animationGroup AnimationGroup?
---@field controller     BantsController

bants.proto = {
    minimumHeight = 112,
}

local function _BantCreate()
    local i = setmetatable({}, { __index = bants.proto })
    i.controller = newController(i)

    local d = db()
    local L = addon.Layout
    local widgetWidth = d.itemWidth

    local container = L:Container(UIParent, { width = widgetWidth, height = i.minimumHeight })

    -- Bottom section: portrait + title bar.
    local bottom = L:Container(container, { width = widgetWidth, height = 80 })
    bottom:SetPoint('BOTTOMLEFT', container, 'BOTTOMLEFT')
    local bottomBg = bottom:AddBackground(MEDIA .. 'bottom.png')
    bottomBg:SetDesaturated(true)
    bottomBg:SetVertexColor(0.8, 0.5, 0.8, 0.75)

    local portraitContainer = L:Container(bottom, { width = 64, height = 64 })
    portraitContainer:SetPoint('LEFT', bottom, 'LEFT', 38, 0)

    local portrait = portraitContainer:Texture('ARTWORK')
    portrait:SetAllPoints(portraitContainer)

    local portraitOverlay = portraitContainer:Texture('OVERLAY', {
        atlas = 'auctionhouse-itemicon-border-account',
        size = { w = 84, h = 84 },
    })
    portraitOverlay:SetPoint('CENTER', portraitContainer, 'CENTER')

    -- Title bar: three atlas pieces that scale with the name font size.
    local titleBarH = d.nameFontSize
    local titleScale = titleBarH / 85
    local capWidth = math.floor(202 * titleScale)

    local titleLeft = bottom:Texture('BORDER', {
        atlas = 'UI-Frame-Oribos-TitleLeft',
        size = { w = capWidth, h = titleBarH + 12 },
    })
    titleLeft:SetPoint('LEFT', portraitContainer, 'RIGHT', 10, 0)

    local titleMiddle = bottom:Texture('BORDER', { atlas = '_UI-Frame-Oribos-TitleMiddle' })
    titleMiddle.tex:SetHorizTile(true)
    titleMiddle.tex:SetHeight(titleBarH + 12)
    titleMiddle:SetPoint('LEFT', titleLeft, 'RIGHT', 0, 0)
    -- Width is set dynamically in AddBants based on the name text length.

    local titleRight = bottom:Texture('BORDER', {
        atlas = 'UI-Frame-Oribos-TitleRight',
        size = { w = capWidth, h = titleBarH + 12 },
    })
    titleRight:SetPoint('LEFT', titleMiddle, 'RIGHT', 0, 0)

    local name = L:FontString(bottom, { justifyH = 'CENTER', maxLines = 1 })
    name.fs:SetFont(fetchFont(d.nameFontFace), d.nameFontSize, 'OUTLINE')
    name:SetTextColor(1, 1, 1)
    name:SetPoint('LEFT', titleLeft, 'RIGHT', 8, 0)
    name:SetPoint('RIGHT', titleRight, 'LEFT', -8, 0)

    -- Top section: decorative top border.
    local top = L:Container(container, { width = widgetWidth, height = 32 })
    top:SetPoint('TOPLEFT', container, 'TOPLEFT')
    top:AddBackground(MEDIA .. 'top.png')

    local widget = container.frame --[[@as BantsWidget]]
    widget.subWidgets = {
        portrait = portrait.tex,
        name = name.fs,
        messages = {},
        textureBottom = bottom.frame,
        textureTop = top.frame,
        titleLeft = titleLeft.tex,
        titleMiddle = titleMiddle.tex,
        titleRight = titleRight.tex,
    }

    i.widget = widget
    return i
end

---@param pool ObjectPoolMixin
---@param bant BantsMain
local function _BantReset(pool, bant)
    if not bant or not bant.widget then return end

    -- Release messages directly — no animations during pool reset.
    local messages = bant.widget.subWidgets.messages
    for i = #messages, 1, -1 do
        bants._messagePool:Release(table.remove(messages, i))
    end

    bant.expiryTime = nil
    bant.widget:SetHeight(bants.proto.minimumHeight)
    bant.widget:Hide()
    bant.widget:ClearAllPoints()
    bant.widget:SetParent(UIParent)
    bant.widget:SetAlpha(1)
    bant.data = nil
    bant.widget.subWidgets.name:SetText('')
    bant.widget.subWidgets.portrait:SetTexture(nil)
    bant.widget.subWidgets.portrait:Show()
end

--#endregion

--#region ── Public API ───────────────────────────────────────────────────────

---@return BantsMain
function bants:Create()
    return self._pool:Acquire()
end

---@param bant BantsMain
function bants:Release(bant)
    self._pool:Release(bant)
end

--#endregion

--#region ── Lifecycle ────────────────────────────────────────────────────────

function bants:OnInitialize()
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

bants:Enable()
