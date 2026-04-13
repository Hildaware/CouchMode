local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class BanterFrameModule: AceModule
---@field AddBants      fun(self: BanterFrameModule, data: BantsData)
---@field RemoveBant    fun(self: BanterFrameModule, bant: BantsMain)
---@field RepositionBants fun(self: BanterFrameModule)
---@field ToggleLock    fun(self: BanterFrameModule)
---@field Refresh       fun(self: BanterFrameModule)
local banterFrame = addon:NewModule('BanterFrame')

--#region ── Helpers ──────────────────────────────────────────────────────────

local function db() return addon.db.profile.banter end

local padding = 6

--#endregion

--#region ── Instance state ───────────────────────────────────────────────────

---@class BanterFrame.Instance
---@field widget           Frame
---@field bants             BantsMain[]
---@field currentBantsId  number|nil

banterFrame.proto = {}

--#endregion

--#region ── Public API ───────────────────────────────────────────────────────

function banterFrame:RepositionBants()
    if not self.instance then return end
    local bants = self.instance.bants
    for i = 1, #bants do
        local bant = bants[i]
        if bant.animationGroup and bant.animationGroup:IsPlaying() then
            bant.animationGroup:Stop()
            bant.animationGroup = nil
        end

        bant.widget:ClearAllPoints()

        ---@type Frame
        local targetRelativeFrame = self.instance.widget
        ---@type FramePoint
        local targetPoint = 'BOTTOMLEFT'
        ---@type FramePoint
        local targetRelativePoint = 'BOTTOMLEFT'
        local targetX = padding
        local targetY = padding

        local prevBant = bants[i - 1]
        if prevBant and prevBant.widget then
            targetRelativeFrame = prevBant.widget
            targetRelativePoint = 'TOPLEFT'
            targetX = 0
        end

        bant.widget:SetPoint(targetPoint, targetRelativeFrame, targetRelativePoint, targetX, targetY)
    end
end

---@param bantToRemove table
function banterFrame:RemoveBant(bantToRemove)
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
        local bantsModule = addon:GetModule('Bants', true) --[[@as BantsModule?]]
        if bantsModule then bantsModule:Release(bantToRemove) end
        if #self.instance.bants == 0 then self.instance.widget:Hide() end
    end)

    -- Slide bants that were above the gap downward. Anchors are updated inside
    -- OnFinished — before WoW removes the translation offset — so there is no
    -- snap between the animation end and the new anchor taking effect.
    local slideDistance = bantToRemove.widget:GetHeight() + padding
    local repositioned = false
    for i = removedIndex, #bants do
        local bant = bants[i]
        if bant.animationGroup and bant.animationGroup:IsPlaying() then
            bant.animationGroup:Stop()
            bant.animationGroup = nil
        end

        local ag = bant.widget:CreateAnimationGroup()
        local t = ag:CreateAnimation('Translation')
        t:SetDuration(0.5)
        t:SetOffset(0, -slideDistance)
        t:SetSmoothing('IN_OUT')
        ag:SetScript('OnFinished', function()
            if not repositioned then
                repositioned = true
                self:RepositionBants()
            end
        end)
        ag:Play()
    end
end

---@param data BantsData
function banterFrame:AddBants(data)
    if not self.instance then return end

    -- Every message creates a new bant — chronological order is preserved in the stack.
    local bantsModule = addon:GetModule('Bants') --[[@as BantsModule]]
    local bant = bantsModule:Create()
    bant.id = data.id
    bant.data = data

    local d = db()
    local LSM = LibStub('LibSharedMedia-3.0')

    local nameWidget = bant.widget.subWidgets.name
    local nameFontPath = LSM:Fetch(LSM.MediaType.FONT, d.nameFontFace)
        or 'Interface/AddOns/CouchMode/Modules/Banter/Resources/Fonts/BebasNeue-Regular.ttf'
    nameWidget:SetText(data.name)
    nameWidget:SetFont(nameFontPath, d.nameFontSize, 'OUTLINE')
    local nc = d.nameFontColor
    nameWidget:SetTextColor(nc.r, nc.g, nc.b, nc.a)

    -- Size the title bar to fit the name text.
    local nameTextWidth = nameWidget:GetUnboundedStringWidth()
    bant.widget.subWidgets.titleMiddle:SetWidth(math.max(nameTextWidth + 24, 40))

    local portrait = bant.widget.subWidgets.portrait
    if data.displayId and data.displayId > 0 then
        SetPortraitTextureFromCreatureDisplayID(portrait, data.displayId)
        portrait:Show()
    end

    bant.widget:SetParent(self.instance.widget)

    local messageWidget = bant.controller:CreateMessage()
    local duration = bant.controller:FormatMessage(messageWidget, data.message, data.type)
    bant.widget:SetHeight(bant.widget:GetHeight() + messageWidget.widget:GetHeight())
    bant.controller:RepositionMessages()

    local activeBants = self.instance.bants

    -- Extend the incoming bant to match whatever is already on screen, so a short
    -- message never expires before a longer one that was already active.
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
        bant.expiryTime = now + effectiveDuration
    end

    table.insert(activeBants, bant)

    local prevBant = activeBants[#activeBants - 1]
    local targetPoint, targetRelativeFrame, targetRelativePoint, targetX, targetY

    if prevBant then
        targetPoint = 'BOTTOMLEFT'
        targetRelativeFrame = prevBant.widget
        targetRelativePoint = 'TOPLEFT'
        targetX = 0
        targetY = padding
    else
        targetPoint = 'BOTTOMLEFT'
        targetRelativeFrame = self.instance.widget
        targetRelativePoint = 'BOTTOMLEFT'
        targetX = padding
        targetY = padding
    end

    bant.widget:SetPoint(targetPoint, targetRelativeFrame, targetRelativePoint, targetX, targetY)
    bant.widget:SetAlpha(1)
    bant.widget:Show()

    -- Fade-in animation.
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

function banterFrame:ToggleLock()
    if not self.instance then return end
    local widget = self.instance.widget
    if widget.dragger:IsShown() then
        widget.dragger:Hide()
        widget.bg:Hide()
        widget:Hide()
    else
        widget.dragger:Show()
        widget.bg:Show()
        widget:Show()
    end
end

---Called by options setters after width or font changes.
function banterFrame:Refresh()
    if not self.instance then return end
    local d = db()
    self.instance.widget:SetWidth(d.itemWidth + (padding * 2))
end

--#endregion

--#region ── Lifecycle ────────────────────────────────────────────────────────

function banterFrame:OnEnable()
    if self.instance then
        self.instance.widget:Show()
        return
    end

    local i = setmetatable({}, { __index = self.proto })

    local itemWidth = db().itemWidth
    local maxItems = db().maxItems
    local bantsModule = addon:GetModule('Bants')
    local normalHeight = bantsModule.proto.minimumHeight
    local containerHeight = (maxItems * normalHeight) + ((maxItems + 1) * padding)

    ---@type Frame
    local frame = CreateFrame('Frame', 'CouchModeBanterContainer', UIParent)
    frame:SetSize(itemWidth + (padding * 2), containerHeight)
    local d = db()
    frame:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', d.x, d.y)
    frame:SetMovable(true)
    frame:Hide()

    local bg = frame:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:Hide()

    local dragger = CreateFrame('Frame', nil, frame)
    dragger:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT')
    dragger:SetSize(80, 12)
    dragger:EnableMouse(true)
    dragger:SetMovable(true)
    dragger:RegisterForDrag('LeftButton')
    dragger:SetScript('OnDragStart', function() frame:StartMoving() end)
    dragger:SetScript('OnDragStop', function()
        frame:StopMovingOrSizing()
        local pos = db()
        pos.x = frame:GetLeft() - UIParent:GetLeft()
        pos.y = frame:GetBottom() - UIParent:GetBottom()
    end)

    local draggerBg = dragger:CreateTexture(nil, 'BACKGROUND')
    draggerBg:SetAllPoints()
    draggerBg:SetColorTexture(0, 0, 1, 0.5)

    local draggerText = dragger:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
    draggerText:SetPoint('CENTER', dragger, 'CENTER')
    draggerText:SetText('Banter Anchor')

    dragger:Hide()

    frame.dragger = dragger
    frame.bg = bg

    i.widget = frame
    i.bants = {}

    self.instance = i
end

function banterFrame:OnDisable()
    if self.instance then
        self.instance.widget:Hide()
    end
end

--#endregion

banterFrame:Enable()
