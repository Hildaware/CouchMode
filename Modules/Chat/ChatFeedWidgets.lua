--[[ ChatFeedWidgets.lua
The visual anatomy of a single message group in the Chat feed.

Owns the group frame hierarchy (portrait, identity header and message lines),
the shared geometry constants, the hyperlink interaction policy, and per-group
measurement and rendering. Everything that spans *many* groups -
pooling, layout, scrolling, fading and motion - lives in
`ChatFeed`, which drives this module through `RenderGroup`/`ResetGroup`.

Styling (colors, fonts, icons, aliases) stays in `addon.Chat` so it remains in
one place.
]]

local addonName, addon = ...
local addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)

local M = {}

--#region ── Geometry ──────────────────────────────────────────────────────────

local PADDING      = 8
local ICON_SIZE    = 40
local ICON_GAP     = 8
local ICON_TOP_PAD = 8
local NAME_GAP     = 2
local MSG_TOP_GAP  = 6
local LINE_GAP     = 2

-- Portrait decoration borrowed from the overhead Chat Bubbles widget.
local ICON_BORDER_ATLAS = 'spellbook-item-iconframe'

local MESSAGE_BACKGROUND_ATLAS = 'playerchoice-text-gradient-tall'

M.PADDING       = PADDING

--#endregion

--#region ── Hyperlink interaction policy ─────────────────────────────────────

-- Blizzard's ChatFrameMixin sends clicks through SetItemRef, but forwards
-- hover independently. Keep that distinction here: only links whose normal
-- presentation is a GameTooltip may open one on hover. In particular,
-- journal/dungeonScore and trade links have LinkUtil click handlers that open
-- panels, so they deliberately stay click-only.
local HOVER_TOOLTIP_LINK_TYPES = {
    achievement = true,
    battlepet = true,
    currency = true,
    enchant = true,
    item = true,
    quest = true,
    spell = true,
}

---@param link string
---@return string|nil
local function getLinkType(link)
    if type(link) ~= 'string' then return nil end

    -- FontString hyperlink callbacks normally supply the bare link
    -- ("item:..."). Support complete markup too so this remains robust for
    -- clients/widgets that pass the original chat token.
    return link:match('^([^:|]+):') or link:match('|H([^:|]+):')
end

---@param link string
---@return boolean
local function supportsHoverTooltip(link)
    return HOVER_TOOLTIP_LINK_TYPES[getLinkType(link)] == true
end

--#endregion

--#region ── Widget factories ──────────────────────────────────────────────────

---@param parent Frame
---@return FontString
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

--- Anchors a group across its parent's padded width at the given top offset.
---@param g Frame
---@param parent Frame
---@param y number
function M.AnchorGroup(g, parent, y)
    g:ClearAllPoints()
    g:SetPoint('TOPLEFT', parent, 'TOPLEFT', PADDING, y)
    g:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', -PADDING, y)
end

---@param parent Frame
---@return Frame
function M.CreateGroup(parent)
    local g = CreateFrame('Frame', nil, parent)
    g:SetPoint('TOPLEFT', parent, 'TOPLEFT')
    g:SetPoint('TOPRIGHT', parent, 'TOPRIGHT')
    g:EnableMouse(true)
    -- FontStrings propagate hyperlink events to this frame. The parent must
    -- also opt into hyperlink handling before its scripts receive them.
    if g.SetHyperlinksEnabled then pcall(g.SetHyperlinksEnabled, g, true) end

    local background = g:CreateTexture(nil, 'BACKGROUND')
    background:SetAtlas(MESSAGE_BACKGROUND_ATLAS)
    background:SetAllPoints(g)
    background:SetAlpha(0.5)
    g.background = background

    g.lines = {}

    -- 2D portrait/icon. No 3D models: they are expensive per group.
    local icon = g:CreateTexture(nil, 'ARTWORK')
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint('TOPLEFT', g, 'TOPLEFT', 0, -ICON_TOP_PAD)
    icon:Hide()
    g.icon = icon

    -- Decorative frame, matching the overhead bubble portrait.
    local iconBorder = g:CreateTexture(nil, 'OVERLAY', nil, 1)
    iconBorder:SetAtlas(ICON_BORDER_ATLAS)
    -- The atlas's visual frame is offset within its bounds. Compact mode scales
    -- these offsets along with the portrait so the frame keeps the same ratio.
    iconBorder:SetPoint('TOPRIGHT', icon, 'TOPRIGHT', 2, 2)
    iconBorder:SetPoint('BOTTOMLEFT', icon, 'BOTTOMLEFT', -12, -6)
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
        if not supportsHoverTooltip(link) or not GameTooltip then return end

        GameTooltip:SetOwner(g, 'ANCHOR_CURSOR')
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok then
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end)

    g:SetScript('OnHyperlinkLeave', function()
        -- Do not dismiss a tooltip which another widget took ownership of.
        if GameTooltip and GameTooltip:GetOwner() == g then GameTooltip:Hide() end
    end)

    return g
end

--- Resets a group widget to a pristine state so it can be returned to the pool.
---@param g Frame
function M.ResetGroup(g)
    g:Hide()
    local chat = addon and addon.Chat
    for i = 1, #g.lines do
        local line = g.lines[i]
        if chat then chat:CancelReveal(line) end
        line._revealedText = nil
        line:Hide()
        line:SetText('')
        line:ClearAllPoints()
        line:SetAlpha(1)
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
    g:ClearAllPoints()
    g._wasLaidOut = false
    g._displayed = nil
    g._lineAlphas = nil
    g._lineHeights = nil
    g._metrics = nil
    g._firstDisplayedMessage = nil
    g.groupData = nil
    -- g.background:SetAlpha(1)
    local parent = g:GetParent()
    g:SetPoint('TOPLEFT', parent, 'TOPLEFT')
    g:SetPoint('TOPRIGHT', parent, 'TOPRIGHT')
    g:Hide()
end

--- Applies the current live/history alpha state after a group becomes visible.
---@param g Frame
---@param historyVisible boolean
function M.ApplyDisplayAlpha(g, historyVisible)
    local messages = g.groupData and g.groupData.messages or {}
    local lineAlphas = g._lineAlphas
    local headerAlpha = 0

    for i = 1, #messages do
        local liveAlpha = (lineAlphas and lineAlphas[i]) or 1
        local alpha = historyVisible and 1 or liveAlpha
        local line = g.lines[i]
        if line and line:IsShown() and line:GetAlpha() ~= alpha then
            line:SetAlpha(alpha)
        end
        headerAlpha = math.max(headerAlpha, alpha)
    end

    if g.background:GetAlpha() ~= headerAlpha then g.background:SetAlpha(headerAlpha) end
    if g.name:GetAlpha() ~= headerAlpha then g.name:SetAlpha(headerAlpha) end
    if g.channel:GetAlpha() ~= headerAlpha then g.channel:SetAlpha(headerAlpha) end
    if g.icon:GetAlpha() ~= headerAlpha then g.icon:SetAlpha(headerAlpha) end
    if g.iconBorder:GetAlpha() ~= headerAlpha then g.iconBorder:SetAlpha(headerAlpha) end
    if g.spec:GetAlpha() ~= headerAlpha then g.spec:SetAlpha(headerAlpha) end
end

--#endregion

--#region ── Per-group rendering ─────────────────────────────────────────────────

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

--- Applies the message font, skipping the engine call when it is unchanged.
local function applyLineFont(fs, face, size)
    if fs._fontFace ~= face or fs._fontSize ~= size then
        fs:SetFont(face, size, 'OUTLINE')
        fs._fontFace, fs._fontSize = face, size
    end
end

--- Applies the wrap width, skipping the engine call when it is unchanged.
local function applyLineWidth(fs, width)
    if fs._textWidth ~= width then
        fs:SetWidth(width)
        fs._textWidth = width
    end
end

--- Renders one group widget and returns its height.
---@param feed table  the owning ChatFeed (supplies width, fonts and history mode)
---@param g Frame
---@param group ChatGroup
---@param animate boolean?  reveal text character-by-character (new messages)
---@param firstMessage number? first message displayed from this group
---@return number height
function M.RenderGroup(feed, g, group, animate, firstMessage)
    local chat = addon.Chat
    local first = group.messages[1]
    g.groupData = group

    local top = 0
    local compactMode = feed.compactMode == true
    local iconSize = compactMode and (ICON_SIZE / 2) or ICON_SIZE
    local iconGap = compactMode and (ICON_GAP / 2) or ICON_GAP
    local iconTopPad = compactMode and (ICON_TOP_PAD / 2) or ICON_TOP_PAD

    local showsIdentity = chat:GroupShowsIdentity(group)
    local hasIcon = false
    local channelH = feed.fonts.channel.size
    local nameH = feed.fonts.name.size
    if showsIdentity then
        -- Release any prior pooled row's explicit widths before styling the
        -- next identity so GetStringWidth measures the new speaker's name.
        g.name:SetWidth(0)
        g.channel:SetWidth(0)
        hasIcon = chat:StyleIdentity(g, first) == true
        local headerX = hasIcon and (iconSize + iconGap) or 0
        local channelTop = top + (hasIcon and iconTopPad or 0)

        g.icon:ClearAllPoints()
        g.icon:SetSize(iconSize, iconSize)
        g.icon:SetPoint('TOPLEFT', g, 'TOPLEFT', 0, -(top + iconTopPad))
        g.iconBorder:ClearAllPoints()
        local borderScale = compactMode and 0.5 or 1
        g.iconBorder:SetPoint('TOPRIGHT', g.icon, 'TOPRIGHT', 2 * borderScale, 2 * borderScale)
        g.iconBorder:SetPoint('BOTTOMLEFT', g.icon, 'BOTTOMLEFT', -12 * borderScale, -6 * borderScale)
        g.spec:ClearAllPoints()
        g.spec:SetSize(compactMode and 7 or 14, compactMode and 7 or 14)
        g.spec:SetPoint('BOTTOMRIGHT', g.icon, 'BOTTOMRIGHT', compactMode and 2.5 or 5, compactMode and -2.5 or -5)

        g.channel:ClearAllPoints()
        g.name:ClearAllPoints()
        -- RebuildGroup can run before a pooled frame's anchors resolve, so its
        -- GetWidth() may still be zero. The feed width is established before
        -- groups are rendered and is stable for both new and pooled widgets.
        local headerWidth = math.max(feed.width - headerX - 4, 1)
        if compactMode then
            local measuredNameWidth = g.name:GetStringWidth() or 0
            local nameWidth = measuredNameWidth > 0
                and math.min(measuredNameWidth, headerWidth * 0.6)
                or (headerWidth * 0.4)
            local channelWidth = math.max(headerWidth - nameWidth - NAME_GAP, 1)
            g.name:SetWidth(math.max(nameWidth, 1))
            g.name:SetPoint('TOPLEFT', g, 'TOPLEFT', headerX, -channelTop)
            g.channel:SetWidth(channelWidth)
            g.channel:SetPoint('LEFT', g.name, 'RIGHT', NAME_GAP, 0)
            channelH = math.max(g.channel:GetHeight() or 0, feed.fonts.channel.size)
            nameH = math.max(g.name:GetHeight() or 0, feed.fonts.name.size)
        else
            g.channel:SetWidth(headerWidth)
            g.channel:SetPoint('TOPLEFT', g, 'TOPLEFT', headerX, -channelTop)
            channelH = math.max(g.channel:GetHeight() or 0, feed.fonts.channel.size)
            g.name:SetWidth(headerWidth)
            g.name:SetPoint('TOPLEFT', g, 'TOPLEFT', headerX, -(channelTop + channelH + NAME_GAP))
            nameH = math.max(g.name:GetHeight() or 0, feed.fonts.name.size)
        end

        local textBottom
        if compactMode then
            textBottom = channelTop + math.max(channelH, nameH)
        else
            textBottom = channelTop + channelH + NAME_GAP + nameH
        end
        local iconBottom = top + (hasIcon and (iconTopPad + iconSize) or 0)
        local messageTop = math.max(textBottom, iconBottom) + MSG_TOP_GAP

        g.identityMenu:ClearAllPoints()
        g.identityMenu:SetPoint('TOPLEFT', g, 'TOPLEFT', 0, -top)
        g.identityMenu:SetPoint('BOTTOMRIGHT', g, 'TOPRIGHT', 0, -(messageTop - MSG_TOP_GAP))
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
    end

    local function messageTopFor(groupTop)
        if not showsIdentity then return groupTop end
        local channelTop = groupTop + (hasIcon and iconTopPad or 0)
        local textBottom
        if compactMode then
            textBottom = channelTop + math.max(channelH, nameH)
        else
            textBottom = channelTop + channelH + NAME_GAP + nameH
        end
        local iconBottom = groupTop + (hasIcon and (iconTopPad + iconSize) or 0)
        return math.max(textBottom, iconBottom) + MSG_TOP_GAP
    end

    -- Measure every line against its complete text so the scroll geometry stays
    -- stable while the visible text is being revealed.
    local messageLeft = compactMode and hasIcon and (iconSize + iconGap) or 0
    local available = math.max(feed.width - PADDING * 2 - messageLeft, 40)
    local msgFace, msgSize = feed.fonts.msg.face, feed.fonts.msg.size
    local messages = group.messages
    local messageCount = #messages
    g._lineHeights = g._lineHeights or {}
    for i = 1, messageCount do
        local msg = messages[i]
        local fs = acquireLine(g, i)
        chat:StyleLine(fs, msg, i == 1 and showsIdentity)
        applyLineFont(fs, msgFace, msgSize)
        applyLineWidth(fs, available)
        chat:SetTextPlain(fs, msg.text)
        g._lineHeights[i] = fs:GetHeight() or msgSize
    end

    local heights = {}
    local suffixHeight = 0
    for i = messageCount, 1, -1 do
        suffixHeight = suffixHeight + g._lineHeights[i] + LINE_GAP
        heights[i] = math.max(messageTopFor(0) + suffixHeight, iconTopPad + iconSize)
    end
    g._metrics = {
        lastMessage = messageCount,
        heights = heights,
    }

    firstMessage = math.max(1, math.min(firstMessage or 1, messageCount))
    g._firstDisplayedMessage = firstMessage
    local historyVisible = feed:IsHistoryVisible()
    local lineAlphas = g._lineAlphas
    local y = messageTopFor(top)
    for i = firstMessage, messageCount do
        local msg = messages[i]
        local fs = g.lines[i]
        local alpha = historyVisible and 1 or ((lineAlphas and lineAlphas[i]) or 1)
        if fs:GetAlpha() ~= alpha then fs:SetAlpha(alpha) end
        applyText(fs, msg.text, animate ~= false)
        fs:ClearAllPoints()
        fs:SetPoint('TOPLEFT', g, 'TOPLEFT', messageLeft, -y)
        fs:Show()
        y = y + g._lineHeights[i] + LINE_GAP
    end

    for i = 1, #g.lines do
        if i < firstMessage or i > messageCount then
            local fs = g.lines[i]
            chat:CancelReveal(fs)
            fs._revealedText = nil
            fs:Hide()
            fs:SetText('')
        end
    end
    local height = heights[firstMessage]
    g:SetHeight(height)
    g.background:ClearAllPoints()
    g.background:SetSize(g:GetWidth() + 32, height + 12)
    g.background:SetPoint('TOPLEFT', g, 'TOPLEFT', -24, -8)
    return height
end

--#endregion

if addon then addon.ChatFeedWidgets = M end
return M
