--[[ ChatFeed.lua
A pooled, variable-height scrolling list of grouped chat messages.

The feed owns no policy: it renders the groups it is handed and reports its
scroll state. Styling is delegated to `addon.Chat` so colors, fonts, icons and
aliases stay in one place.
]]

local addonName, addon = ...
local addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)

local Feed = {}
Feed.__index = Feed

--#region ── Constants ────────────────────────────────────────────────────────

local PADDING      = 8
local ICON_SIZE    = 40
local ICON_GAP     = 8
local ICON_TOP_PAD = 8
local NAME_GAP     = 2
local MSG_TOP_GAP  = 6
local LINE_GAP     = 2
local GROUP_GAP    = 6

-- Portrait decoration borrowed from the overhead Chat Bubbles widget.
local ICON_BORDER_ATLAS = 'spellbook-item-iconframe'

-- Divider between messages. The atlas is a vertical bar (base size 22x466), so
-- it is drawn rotated 90 degrees into a wide, short band.
local DIVIDER_ATLAS     = 'playerchoice-gold-divider'
local DIVIDER_THICKNESS = 22
local DIVIDER_GAP       = 0
local DIVIDER_BAND      = DIVIDER_THICKNESS + DIVIDER_GAP * 2
local DIVIDER_ALPHA     = 0.5
local MESSAGE_FADE_TIME = 0.25
local LAYOUT_ANIMATION_TIME = 0.3

--#endregion

--#region ── Widget factories ──────────────────────────────────────────────────

local function createLine(parent)
    local fs = parent:CreateFontString(nil, 'OVERLAY', 'ChatFontNormal')
    fs:SetJustifyH('LEFT')
    fs:SetJustifyV('TOP')
    fs:SetWordWrap(true)
    fs:SetNonSpaceWrap(false)
    if fs.SetHyperlinksEnabled then pcall(fs.SetHyperlinksEnabled, fs, true) end
    if fs.SetHyperlinkPropagateToParent then pcall(fs.SetHyperlinkPropagateToParent, fs, true) end
    fs:Hide()
    return fs
end

-- Cached C_Texture.GetAtlasInfo result for the divider atlas (false = missing).
local dividerAtlasInfo

--- Applies the divider asset, rotated 90 degrees so the vertical bar lies flat.
--- Falls back to the unrotated atlas if the client can't describe the atlas.
---@param tex Texture
local function applyDividerAsset(tex)
    if dividerAtlasInfo == nil then
        dividerAtlasInfo = false
        if C_Texture and C_Texture.GetAtlasInfo then
            local ok, info = pcall(C_Texture.GetAtlasInfo, DIVIDER_ATLAS)
            if ok and info then dividerAtlasInfo = info end
        end
    end

    local info = dividerAtlasInfo
    if info then
        local file = info.file or info.filename
        if file then
            tex:SetTexture(file)
            local l, r = info.leftTexCoord, info.rightTexCoord
            local t, b = info.topTexCoord, info.bottomTexCoord
            -- Swap the u/v axes: source length (v) -> region width, source
            -- thickness (u) -> region height.
            tex:SetTexCoord(l, b, r, b, l, t, r, t)
            return
        end
    end
    tex:SetAtlas(DIVIDER_ATLAS)
end

local function createDivider(parent)
    local tex = parent:CreateTexture(nil, 'ARTWORK')
    applyDividerAsset(tex)
    tex:SetAlpha(DIVIDER_ALPHA)
    tex:Hide()
    return tex
end

--- Centres a divider on the group, spanning `width` pixels.
---@param g Frame
---@param tex Texture
---@param width number
---@param yCenter number
local function placeDivider(g, tex, width, yCenter)
    width = math.max(width, 1)
    tex:SetSize(width, DIVIDER_THICKNESS)
    tex:ClearAllPoints()
    tex:SetPoint('CENTER', g, 'TOPLEFT', width / 2, -yCenter)
    tex:Show()
end

local function anchorGroup(g, parent, y)
    g:ClearAllPoints()
    g:SetPoint('TOPLEFT', parent, 'TOPLEFT', PADDING, y)
    g:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', -PADDING, y)
end

local function createGroup(parent)
    local g = CreateFrame('Frame', nil, parent)
    g:SetPoint('TOPLEFT', parent, 'TOPLEFT')
    g:SetPoint('TOPRIGHT', parent, 'TOPRIGHT')
    g:EnableMouse(true)
    -- FontStrings propagate hyperlink events to this frame. The parent must
    -- also opt into hyperlink handling before its scripts receive them.
    if g.SetHyperlinksEnabled then pcall(g.SetHyperlinksEnabled, g, true) end

    g.lines = {}
    g.dividers = {}

    -- 2D portrait/icon. No 3D models: they are expensive per group.
    local icon = g:CreateTexture(nil, 'ARTWORK')
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint('TOPLEFT', g, 'TOPLEFT', 0, -ICON_TOP_PAD)
    icon:Hide()
    g.icon = icon

    -- Decorative frame, matching the overhead bubble portrait.
    local iconBorder = g:CreateTexture(nil, 'OVERLAY', nil, 1)
    iconBorder:SetAtlas(ICON_BORDER_ATLAS)
    -- The atlas's visual frame is offset within its bounds. Anchor opposite
    -- corners so it grows evenly around the portrait by 10px in each axis.
    iconBorder:SetPoint('TOPRIGHT', icon, 'TOPRIGHT', 5, 5)
    iconBorder:SetPoint('BOTTOMLEFT', icon, 'BOTTOMLEFT', -5, -5)
    iconBorder:Hide()
    g.iconBorder = iconBorder

    local spec = g:CreateTexture(nil, 'OVERLAY', nil, 2)
    spec:SetSize(14, 14)
    spec:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT', 5, -5)
    spec:Hide()
    g.spec = spec

    -- Text block. Positioned per-render in RenderGroup so the icon column can
    -- collapse entirely when a speaker has no icon.
    local name = g:CreateFontString(nil, 'OVERLAY', 'ChatFontNormal')
    name:SetJustifyH('LEFT')
    name:SetWordWrap(false)
    name:SetPoint('TOPLEFT', g, 'TOPLEFT', 0, 0)
    g.name = name

    local channel = g:CreateFontString(nil, 'OVERLAY', 'ChatFontNormal')
    channel:SetJustifyH('LEFT')
    channel:SetWordWrap(false)
    channel:SetPoint('TOPLEFT', g, 'TOPLEFT', 0, 0)
    g.channel = channel

    -- The context menu belongs to the speaker identity, not message text.
    -- Keeping this hitbox out of the line area leaves message-line hyperlinks
    -- free to propagate to this group's Blizzard link handlers.
    local identityMenu = CreateFrame('Button', nil, g)
    identityMenu:SetFrameLevel(g:GetFrameLevel() + 10)
    identityMenu:RegisterForClicks('RightButtonUp')
    identityMenu:SetScript('OnClick', function()
        if addon.Chat and addon.Chat.ShowGroupMenu then addon.Chat:ShowGroupMenu(g) end
    end)
    identityMenu:Hide()
    g.identityMenu = identityMenu

    g:SetScript('OnHyperlinkClick', function(_, link, text, button)
        if SetItemRef then SetItemRef(link, text, button, g) end
    end)
    g:SetScript('OnHyperlinkEnter', function(_, link)
        if GameTooltip and link then
            GameTooltip:SetOwner(g, 'ANCHOR_CURSOR')
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end
    end)
    g:SetScript('OnHyperlinkLeave', function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return g
end

--#endregion

--#region ── Construction ───────────────────────────────────────────────────────

---@param parent Frame  the scroll child
---@return table feed
function Feed.New(parent)
    local scrollFrame = CreateFrame('ScrollFrame', nil, parent)
    scrollFrame:SetAllPoints(parent)
    if scrollFrame.EnableMouseWheel then scrollFrame:EnableMouseWheel(true) end
    scrollFrame:SetClipsChildren(true)

    local scrollChild = CreateFrame('Frame', nil, scrollFrame)
    scrollChild:SetPoint('TOPLEFT', scrollFrame, 'TOPLEFT')
    scrollChild:SetPoint('TOPRIGHT', scrollFrame, 'TOPRIGHT')
    scrollFrame:SetScrollChild(scrollChild)

    local spacer = CreateFrame('Frame', nil, scrollChild)
    spacer:SetPoint('TOPLEFT', scrollChild, 'TOPLEFT')
    spacer:SetPoint('TOPRIGHT', scrollChild, 'TOPRIGHT')
    spacer:SetHeight(0)

    local feed = setmetatable({
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        spacer = spacer,
        groupPool = {},
        widgets = {},
        groups = {},
        fonts = {
            msg     = { face = nil, size = 12 },
            name    = { face = nil, size = 12 },
            channel = { face = nil, size = 10 },
        },
        showDividers = true,
        historyMode = false,
        onScrollChanged = nil,
    }, Feed)

    local layoutDriver = CreateFrame('Frame', nil, scrollChild)
    layoutDriver:Hide()
    feed.layoutDriver = layoutDriver

    scrollFrame:SetScript('OnScrollRangeChanged', function()
        if feed.onScrollChanged then feed.onScrollChanged() end
    end)
    scrollFrame:SetScript('OnMouseWheel', function(_, delta)
        feed:ScrollBy(delta * 30)
        return false
    end)

    feed:SetWidth(400)
    return feed
end

--- Stores the resolved font metrics for the three text fields.
---@param fonts table  { msg = {...}, name = {...}, channel = {...} }
function Feed:SetFonts(fonts)
    self.fonts = fonts
end

--- Enables or disables the divider textures drawn between messages.
---@param enabled boolean
function Feed:SetDividers(enabled)
    if self.showDividers == enabled then return end
    self.showDividers = enabled ~= false
    if #self.widgets > 0 then
        for i = 1, #self.widgets do
            self:RenderGroup(self.widgets[i], self.groups[i], false, i == 1)
        end
        self:Layout()
    end
end

function Feed:SetWidth(width)
    self.width = width
    self.scrollChild:SetWidth(width)
end

--- Fades each message from its own receive timestamp. Returns whether at
--- least one message remains visible, so the panel itself fades only after the
--- final visible message has expired.
---@param now number
---@param delay number
---@param enabled boolean
---@return boolean hasVisibleMessages
function Feed:UpdateMessageFade(now, delay, enabled)
    local hasVisibleMessages = false
    local visibleContentHeight = 0
    local visibleGroupCount = 0
    local needsLiveLayout = false
    local groupsToReflow = {}

    for groupIndex = 1, #self.widgets do
        local g = self.widgets[groupIndex]
        local group = self.groups[groupIndex]
        local headerAlpha = 0
        local firstVisibleMessage
        g._lineAlphas = g._lineAlphas or {}

        for messageIndex = 1, #group.messages do
            local msg = group.messages[messageIndex]
            local alpha = 1
            if enabled and delay >= 0 and type(msg.timestamp) == 'number' then
                local elapsed = now - msg.timestamp - delay
                if elapsed > 0 then
                    alpha = math.max(1 - elapsed / MESSAGE_FADE_TIME, 0)
                end
            end

            local line = g.lines[messageIndex]
            if line then line:SetAlpha(alpha) end
            g._lineAlphas[messageIndex] = alpha
            headerAlpha = math.max(headerAlpha, alpha)
            if alpha > 0 then
                hasVisibleMessages = true
                firstVisibleMessage = firstVisibleMessage or messageIndex
            end
        end

        firstVisibleMessage = firstVisibleMessage or #group.messages
        if g._firstVisibleMessage ~= firstVisibleMessage then
            g._firstVisibleMessage = firstVisibleMessage
            groupsToReflow[#groupsToReflow + 1] = groupIndex
        end

        -- The shared speaker identity disappears only when every message in
        -- its group has faded.
        g.name:SetAlpha(headerAlpha)
        g.channel:SetAlpha(headerAlpha)
        g.icon:SetAlpha(headerAlpha)
        g.iconBorder:SetAlpha(headerAlpha)
        g.spec:SetAlpha(headerAlpha)

        local hasVisibleGroup = headerAlpha > 0
        if g._hasVisibleMessages ~= hasVisibleGroup then
            g._hasVisibleMessages = hasVisibleGroup
            needsLiveLayout = true
        end

        if hasVisibleGroup then
            visibleContentHeight = visibleContentHeight + g:GetHeight()
            visibleGroupCount = visibleGroupCount + 1
        end

        for dividerIndex = 1, #g.dividers do
            local divider = g.dividers[dividerIndex]
            local alpha = headerAlpha
            divider:SetAlpha(DIVIDER_ALPHA * alpha)
        end
    end

    if visibleGroupCount > 1 then
        visibleContentHeight = visibleContentHeight + GROUP_GAP * (visibleGroupCount - 1)
    end
    self.visibleContentHeight = visibleContentHeight
    if #groupsToReflow > 0 then
        for i = 1, #groupsToReflow do
            local groupIndex = groupsToReflow[i]
            self:RenderGroup(self.widgets[groupIndex], self.groups[groupIndex], false, groupIndex == 1)
        end
        self:Layout(not self.historyMode)
    elseif needsLiveLayout and not self.historyMode then
        self:Layout()
    end
    return hasVisibleMessages
end

---@return number
function Feed:GetVisibleContentHeight()
    return self.visibleContentHeight or 0
end

---@return number
function Feed:GetContentHeight()
    return self.contentHeight or 0
end

--#endregion

--#region ── Scrolling ─────────────────────────────────────────────────────────

function Feed:IsAtBottom()
    local range = self.scrollFrame:GetVerticalScrollRange() or 0
    local offset = self.scrollFrame:GetVerticalScroll() or 0
    return offset >= (range - 1)
end

--- History mode persists after a reader scrolls upward, including when they
--- later reach the bottom. A new live message explicitly resumes live mode.
---@return boolean
function Feed:IsBrowsingHistory()
    return self.historyMode == true
end

function Feed:ResumeLive()
    self.historyMode = false
end

function Feed:ScrollToBottom()
    local function go()
        self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange() or 0)
        if self.onScrollChanged then self.onScrollChanged() end
    end
    go()
    -- The scroll range lags a frame behind content changes; re-apply once.
    if C_Timer then C_Timer.After(0, go) end
end

--- Scrolls the viewport. Positive `upAmount` reveals older messages.
---@param upAmount number
function Feed:ScrollBy(upAmount)
    if upAmount > 0 and not self.historyMode then
        self.historyMode = true
        -- Expanding history changes the scroll range. Do that first so the
        -- wheel/controller action that entered history also scrolls it.
        if self.onScrollChanged then self.onScrollChanged() end
    end
    local range = self.scrollFrame:GetVerticalScrollRange() or 0
    local offset = self.scrollFrame:GetVerticalScroll() or 0
    offset = math.max(0, math.min(range, offset - upAmount))
    self.scrollFrame:SetVerticalScroll(offset)
    if self.onScrollChanged then self.onScrollChanged() end
end

--#endregion

--#region ── Widget pool ─────────────────────────────────────────────────────────

function Feed:AcquireGroup()
    local g = table.remove(self.groupPool)
    if not g then g = createGroup(self.scrollChild) end
    g:SetParent(self.scrollChild)
    g:Show()
    return g
end

function Feed:ReleaseGroup(g)
    local chat = addon.Chat
    for i = 1, #g.lines do
        if chat then chat:CancelReveal(g.lines[i]) end
        g.lines[i]._revealedText = nil
        g.lines[i]:Hide()
        g.lines[i]:SetText('')
        g.lines[i]:ClearAllPoints()
        g.lines[i]:SetAlpha(1)
    end
    if chat then
        chat:CancelReveal(g.name)
        chat:CancelReveal(g.channel)
        chat:CancelTextFade(g.name)
        chat:CancelTextFade(g.channel)
    end
    g.name._revealedText = nil
    g.channel._revealedText = nil
    g.name._fadedText = nil
    g.channel._fadedText = nil
    g.name:SetAlpha(1)
    g.channel:SetAlpha(1)
    g.icon:Hide()
    g.iconBorder:Hide()
    g.spec:Hide()
    g.identityMenu:Hide()
    g.icon:SetAlpha(1)
    g.iconBorder:SetAlpha(1)
    g.spec:SetAlpha(1)
    g.name:SetText('')
    g.channel:SetText('')
    for i = 1, #g.dividers do
        g.dividers[i]:Hide()
        g.dividers[i]:ClearAllPoints()
        g.dividers[i]:SetAlpha(DIVIDER_ALPHA)
    end
    g:ClearAllPoints()
    g._wasLaidOut = false
    g._hasVisibleMessages = nil
    g._displayed = nil
    g._firstVisibleMessage = nil
    g._lineAlphas = nil
    g:SetPoint('TOPLEFT', self.scrollChild, 'TOPLEFT')
    g:SetPoint('TOPRIGHT', self.scrollChild, 'TOPRIGHT')
    g:Hide()
    self.groupPool[#self.groupPool + 1] = g
end

local function acquireLine(g, index)
    local fs = g.lines[index]
    if not fs then
        fs = createLine(g)
        g.lines[index] = fs
    end
    fs:Show()
    return fs
end

--- Sets a FontString's text. Newly arriving groups animate; historical
--- rebuilds (filter change, resize) render instantly and are marked revealed so
--- they never re-animate later.
---@param fs FontString
---@param text string?
---@param animate boolean
local function applyText(fs, text, animate)
    local chat = addon.Chat
    chat:SetTextPlain(fs, text)
    if animate then
        chat:Reveal(fs, text)
    else
        fs._revealedText = text or ''
    end
end

--- Applies a channel/name label. New groups fade the label in; rebuilds snap it.
---@param fs FontString
---@param animate boolean
local function applyHeader(fs, animate)
    local chat = addon.Chat
    if animate then
        chat:FadeInText(fs)
    else
        chat:CancelTextFade(fs)
        fs._fadedText = fs:GetText() or ''
        fs:SetAlpha(1)
    end
end

--#endregion

--#region ── Rendering ───────────────────────────────────────────────────────────

--- Renders one group widget and returns its height.
---@param g Frame
---@param group ChatGroup
---@param animate boolean?  reveal text character-by-character (new messages)
---@param isFirst boolean?  first group in the feed (suppresses its top divider)
---@return number height
function Feed:RenderGroup(g, group, animate, isFirst)
    local chat = addon.Chat
    local first = group.messages[1]
    local indent = 0
    local y = 0
    g.groupData = group
    g._renderedAsFirst = isFirst == true

    -- Divider pool for this render pass.
    local dividerCount = 0
    local function nextDivider()
        dividerCount = dividerCount + 1
        local tex = g.dividers[dividerCount]
        if not tex then
            tex = createDivider(g)
            g.dividers[dividerCount] = tex
        end
        return tex
    end

    -- Layout insets every group by PADDING, so derive the width from the feed.
    local groupWidth = math.max((self.width or 400) - PADDING * 2, 40)

    -- Between groups: a divider sits above this group's header (the previous
    -- group's message already ends the block above).
    local top = 0
    g.hasTopDivider = not isFirst and self.showDividers
    if not isFirst and self.showDividers then
        placeDivider(g, nextDivider(), groupWidth, DIVIDER_BAND / 2)
        top = DIVIDER_BAND
    end

    -- The divider reserves space above every group after the first.  The text
    -- header already uses `top`, but the portrait's original construction-time
    -- anchor did not; that left it visually inside the divider band.  Anchor it
    -- for this render pass so the entire identity block moves together.
    g.icon:ClearAllPoints()
    g.icon:SetPoint('TOPLEFT', g, 'TOPLEFT', 0, -(top + ICON_TOP_PAD))

    local showsIdentity = chat:GroupShowsIdentity(group)

    -- Identity block. With an icon: channel and name sit to the right of it and
    -- the message list starts below the icon at full width. Without an icon the
    -- icon column is dropped entirely, collapsing to:
    --
    --     CHANNEL
    --     NAME
    --     message...
    local hasIcon = false
    if showsIdentity then
        hasIcon = chat:StyleIdentity(g, first) == true

        local headerX = hasIcon and (ICON_SIZE + ICON_GAP) or 0
        local channelTop = top + (hasIcon and ICON_TOP_PAD or 0)

        g.channel:ClearAllPoints()
        g.channel:SetPoint('TOPLEFT', g, 'TOPLEFT', headerX, -channelTop)
        g.channel:SetPoint('RIGHT', g, 'RIGHT', -4, 0)

        -- Measure against the full text *before* revealing so heights (and the
        -- name's position) stay stable while characters appear.
        local channelH = math.max(g.channel:GetHeight() or 0, self.fonts.channel.size)
        local nameH = math.max(g.name:GetHeight() or 0, self.fonts.name.size)

        g.name:ClearAllPoints()
        g.name:SetPoint('TOPLEFT', g, 'TOPLEFT', headerX, -(channelTop + channelH + NAME_GAP))
        g.name:SetPoint('RIGHT', g, 'RIGHT', -4, 0)

        local textBottom = channelTop + channelH + NAME_GAP + nameH
        local iconBottom = top + (hasIcon and (ICON_TOP_PAD + ICON_SIZE) or 0)

        y = math.max(textBottom, iconBottom) + MSG_TOP_GAP
        indent = 0

        g.identityMenu:ClearAllPoints()
        g.identityMenu:SetPoint('TOPLEFT', g, 'TOPLEFT', 0, -top)
        g.identityMenu:SetPoint('BOTTOMRIGHT', g, 'TOPRIGHT', 0, -(y - MSG_TOP_GAP))
        g.identityMenu:Show()

        applyHeader(g.channel, animate ~= false)
        applyHeader(g.name, animate ~= false)
    else
        g.icon:Hide()
        g.iconBorder:Hide()
        g.spec:Hide()
        g.identityMenu:Hide()
        chat:SetTextPlain(g.name, '')
        chat:SetTextPlain(g.channel, '')
        g.name._revealedText = nil
        g.channel._revealedText = nil
        g.name._fadedText = nil
        g.channel._fadedText = nil
        g.name:SetAlpha(1)
        g.channel:SetAlpha(1)
        indent = 0
        y = top
    end

    -- Consecutive messages in a group share one identity block. They do not
    -- receive dividers; once an older line fades, later lines reflow upward.
    local available = math.max(self.width - PADDING * 2 - indent, 40)
    local firstVisibleMessage = self.historyMode and 1 or (g._firstVisibleMessage or 1)
    for i = firstVisibleMessage, #group.messages do
        local msg = group.messages[i]
        local fs = acquireLine(g, i)
        fs:SetAlpha((g._lineAlphas and g._lineAlphas[i]) or 1)
        chat:StyleLine(fs, msg, i == 1 and showsIdentity)
        fs:SetFont(self.fonts.msg.face, self.fonts.msg.size, 'OUTLINE')
        fs:SetWidth(available)
        chat:SetTextPlain(fs, msg.text)
        local lineHeight = fs:GetHeight() or self.fonts.msg.size
        applyText(fs, msg.text, animate ~= false)
        fs:ClearAllPoints()
        fs:SetPoint('TOPLEFT', g, 'TOPLEFT', indent, -y)
        y = y + lineHeight + LINE_GAP
    end
    -- Hide faded lines and stale pooled lines.
    for i = 1, #g.lines do
        if i < firstVisibleMessage or i > #group.messages then
            chat:CancelReveal(g.lines[i])
            g.lines[i]._revealedText = nil
            g.lines[i]:Hide()
            g.lines[i]:SetText('')
        end
    end
    -- Hide stale pooled dividers.
    for i = dividerCount + 1, #g.dividers do
        g.dividers[i]:Hide()
    end

    local height = math.max(y, ICON_TOP_PAD + ICON_SIZE)
    g:SetHeight(height)
    return height
end

--#endregion

--#region ── Public API ─────────────────────────────────────────────────────────

--- Replaces the entire visible list with the given groups.
---@param groups ChatGroup[]
function Feed:Rebuild(groups)
    self:StopLayoutAnimation()
    for i = #self.widgets, 1, -1 do
        self:ReleaseGroup(table.remove(self.widgets, i))
    end
    self.groups = groups
    for i = 1, #groups do
        local g = self:AcquireGroup()
        self.widgets[i] = g
        self:RenderGroup(g, groups[i], false, i == 1)
    end
    self:Layout()
end

--- Appends a single rendered group to the end of the list.
---@param group ChatGroup
function Feed:AppendGroup(group)
    self.groups[#self.groups + 1] = group
    local g = self:AcquireGroup()
    self.widgets[#self.widgets + 1] = g
    g._hasVisibleMessages = true
    self:RenderGroup(g, group, true, #self.widgets == 1)
    self:Layout(true)
    return g
end

--- Re-renders the last group in place (used when a message joins it).
---@param group ChatGroup
function Feed:RefreshLastGroup(group)
    local g = self.widgets[#self.widgets]
    if not g then return end
    g._hasVisibleMessages = true
    self:RenderGroup(g, group, true, #self.widgets == 1)
    self:Layout(true)
end

function Feed:Clear()
    self:StopLayoutAnimation()
    self.historyMode = false
    for i = #self.widgets, 1, -1 do
        self:ReleaseGroup(table.remove(self.widgets, i))
    end
    self.groups = {}
    self:Layout()
end

function Feed:StopLayoutAnimation()
    if self.layoutDriver then self.layoutDriver:Hide() end
    self.layoutMoves = nil
end

function Feed:AnimateLayout(moves)
    if #moves == 0 then return end
    local elapsed = 0
    self.layoutMoves = moves
    self.layoutDriver:SetScript('OnUpdate', function(_, dt)
        elapsed = elapsed + dt
        local progress = math.min(elapsed / LAYOUT_ANIMATION_TIME, 1)
        -- Cubic ease-out matches the quick, gentle stack shift from the old
        -- Banter container.
        local eased = 1 - (1 - progress) ^ 3
        for i = 1, #moves do
            local move = moves[i]
            anchorGroup(move.group, self.scrollChild, move.fromY + (move.toY - move.fromY) * eased)
        end
        if progress >= 1 then
            for i = 1, #moves do
                local move = moves[i]
                anchorGroup(move.group, self.scrollChild, move.toY)
            end
            self:StopLayoutAnimation()
        end
    end)
    self.layoutDriver:Show()
end

--- Anchors all group widgets top-to-bottom, bottom-aligning short content.
---@param animate boolean?  tween existing groups to their new positions
function Feed:Layout(animate, skipDividerRefresh)
    self:StopLayoutAnimation()
    local previousY = {}
    if animate then
        for i = 1, #self.widgets do
            local g = self.widgets[i]
            if g._wasLaidOut then
                local _, relativeTo, _, _, y = g:GetPoint(1)
                if relativeTo == self.scrollChild and type(y) == 'number' then
                    previousY[g] = y
                end
            end
        end
    end

    -- Live chat never relies on the scroll frame to crop partial rows. Starting
    -- with the newest group, admit complete visible groups only while they fit.
    -- History mode restores every group for normal scrollback.
    local displayed = {}
    if self.historyMode then
        for i = 1, #self.widgets do displayed[i] = true end
    else
        local available = math.max((self.scrollFrame:GetHeight() or 0) - PADDING * 2, 0)
        local used = 0
        for i = #self.widgets, 1, -1 do
            local g = self.widgets[i]
            if g._hasVisibleMessages ~= false then
                local required = g:GetHeight() + (used > 0 and GROUP_GAP or 0)
                -- Always retain the newest visible group, even if it is taller
                -- than the viewport, so a newly received message is never
                -- discarded by the admission policy.
                if used == 0 or used + required <= available then
                    displayed[i] = true
                    used = used + required
                end
            end
        end
    end

    local contentHeight = 0
    local displayedCount = 0
    local firstDisplayed
    for i = 1, #self.widgets do
        local g = self.widgets[i]
        local isDisplayed = displayed[i] == true
        g._displayed = isDisplayed
        g:SetShown(isDisplayed)
        if isDisplayed then
            firstDisplayed = firstDisplayed or i
            contentHeight = contentHeight + g:GetHeight()
            displayedCount = displayedCount + 1
        end
    end
    if displayedCount > 1 then contentHeight = contentHeight + GROUP_GAP * (displayedCount - 1) end

    -- A group can become the first displayed item after older live messages
    -- are hidden. Re-render changed groups so only an item with content above
    -- it reserves and draws a leading divider.
    if not skipDividerRefresh then
        local refreshed = false
        for i = 1, #self.widgets do
            if displayed[i] then
                local isFirstDisplayed = i == firstDisplayed
                if self.widgets[i]._renderedAsFirst ~= isFirstDisplayed then
                    self:RenderGroup(self.widgets[i], self.groups[i], false, isFirstDisplayed)
                    refreshed = true
                end
            end
        end
        if refreshed then
            self:Layout(animate, true)
            return
        end
    end
    self.contentHeight = contentHeight

    local viewHeight = self.scrollFrame:GetHeight() or 0
    local spacerHeight = math.max(viewHeight - contentHeight - PADDING * 2, 0)
    self.spacer:SetHeight(spacerHeight)

    local y = PADDING
    local moves = {}
    for i = 1, #self.widgets do
        local g = self.widgets[i]
        if displayed[i] then
            local targetY = -(spacerHeight + PADDING + y)
            local startY = previousY[g]
            if startY and math.abs(startY - targetY) > 0.5 then
                anchorGroup(g, self.scrollChild, startY)
                moves[#moves + 1] = { group = g, fromY = startY, toY = targetY }
            else
                anchorGroup(g, self.scrollChild, targetY)
            end
            y = y + g:GetHeight() + GROUP_GAP
        end
        g._wasLaidOut = true
    end

    self.scrollChild:SetHeight(math.max(spacerHeight + contentHeight + PADDING * 2, viewHeight))
    if animate then self:AnimateLayout(moves) end
end

--- Sets the height of the feed viewport (called when the panel resizes).
---@param animate boolean?  preserve and tween current group positions
function Feed:SetViewportHeight(height, animate)
    self.scrollFrame:SetHeight(height)
    self:Layout(animate)
end

if addon then addon.ChatFeedProto = Feed end
return Feed
