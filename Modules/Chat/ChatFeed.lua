--[[ ChatFeed.lua
A pooled, variable-height scrolling list of grouped chat messages.

This file owns everything that spans many groups: the widget pool, layout
(via `ChatFeedLayout`), scrolling, history state, fading and
motion. The anatomy and rendering of a single group live in `ChatFeedWidgets`,
and styling stays in `addon.Chat` so colors, fonts, icons and aliases remain in
one place.
]]

local addonName, addon = ...
local addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)
local LayoutPolicy = addon.ChatFeedLayout
local Widgets = addon.ChatFeedWidgets
local Animations = addon.Animations

local Feed = {}
Feed.__index = Feed

--#region ── Constants ────────────────────────────────────────────────────────

-- Geometry shared with the widget layer is read from `ChatFeedWidgets`.
local PADDING = Widgets.PADDING
Feed.PADDING = PADDING

local GROUP_GAP = 12
local MESSAGE_FADE_TIME = 0.35
local LAYOUT_ANIMATION_TIME = 0.3

--#endregion

--#region ── Construction ───────────────────────────────────────────────────────

---@param parent Frame  the scroll child
---@param options table? { historyOnly = boolean }
---@return table feed
function Feed.New(parent, options)
    local historyOnly = options and options.historyOnly == true
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
        historyMode = historyOnly,
        historyOnly = historyOnly,
        viewportHeight = nil,
        maxLiveMessages = 6,
        maxContentHeight = math.huge,
        growthDirection = 'bottom',
        compactMode = false,
        fadePaused = false,
        fadePausedAt = nil,
        scrollRequest = 0,
        onScrollChanged = nil,
        onHistoryModeChanged = nil,
    }, Feed)


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

function Feed:SetCompactMode(compactMode)
    self.compactMode = compactMode == true
end

function Feed:SetWidth(width)
    self.width = width
    self.scrollChild:SetWidth(width)
end

--- Whether the current mode has any rows eligible for its display list.
function Feed:HasDisplayableMessages(historyMode, maxMessages)
    if historyMode == nil then historyMode = self.historyMode end
    if historyMode then
        for i = 1, #self.groups do
            if self.groups[i].messages and #self.groups[i].messages > 0 then return true end
        end
        return false
    end

    if (maxMessages or self.maxLiveMessages or 6) <= 0 then return false end
    for i = #self.groups, 1, -1 do
        local messages = self.groups[i].messages or {}
        for j = #messages, 1, -1 do
            if (messages[j]._chatFadeAlpha or 1) <= 0 then return false end
            return true
        end
    end
    return false
end

--- Fades each message from its presentation time. Returns whether at
--- least one message remains visible, so the panel itself fades only after the
--- final visible message has expired.
---@param now number
---@param delay number
---@param enabled boolean
---@return boolean hasVisibleMessages
function Feed:UpdateMessageFade(now, delay, enabled)
    local hasVisibleMessages = false
    local historyVisible = self:IsHistoryVisible()
    local fadeNow = self.fadePaused and (self.fadePausedAt or now) or now
    local liveLayoutChanged = false

    local widgets, groups = self.widgets, self.groups
    for groupIndex = 1, #widgets do
        local g = widgets[groupIndex]
        local group = groups[groupIndex]
        local liveHeaderAlpha = 0
        local lineAlphas = g._lineAlphas
        if not lineAlphas then
            lineAlphas = {}
            g._lineAlphas = lineAlphas
        end
        local messages = group.messages
        local lines = g.lines

        for messageIndex = 1, #messages do
            local msg = messages[messageIndex]
            local alpha = 1
            local displayedAt = msg.displayedAt or msg.timestamp
            if enabled and delay >= 0 and type(displayedAt) == 'number' then
                local elapsed = fadeNow - displayedAt - delay
                if elapsed > 0 then
                    alpha = math.max(1 - elapsed / MESSAGE_FADE_TIME, 0)
                end
            end

            local previousAlpha = msg._chatFadeAlpha
            msg._chatFadeAlpha = alpha
            if not historyVisible and ((previousAlpha or 1) > 0) ~= (alpha > 0) then
                liveLayoutChanged = true
            end

            -- Keep the live alpha current while browsing; history remains in
            -- the layout and is revealed without moving any rows.
            local displayAlpha = historyVisible and 1 or alpha
            local line = lines[messageIndex]
            if line and line:GetAlpha() ~= displayAlpha then line:SetAlpha(displayAlpha) end
            if lineAlphas[messageIndex] ~= alpha then lineAlphas[messageIndex] = alpha end
            liveHeaderAlpha = math.max(liveHeaderAlpha, alpha)
            if alpha > 0 then
                hasVisibleMessages = true
            end
        end

        -- The shared speaker identity disappears only when every message in
        -- its group has faded, except while browsing where it stays opaque.
        local displayHeaderAlpha = historyVisible and 1 or liveHeaderAlpha
        if g.background:GetAlpha() ~= displayHeaderAlpha then g.background:SetAlpha(displayHeaderAlpha) end
        if g.name:GetAlpha() ~= displayHeaderAlpha then g.name:SetAlpha(displayHeaderAlpha) end
        if g.channel:GetAlpha() ~= displayHeaderAlpha then g.channel:SetAlpha(displayHeaderAlpha) end
        if g.icon:GetAlpha() ~= displayHeaderAlpha then g.icon:SetAlpha(displayHeaderAlpha) end
        if g.iconBorder:GetAlpha() ~= displayHeaderAlpha then g.iconBorder:SetAlpha(displayHeaderAlpha) end
        if g.spec:GetAlpha() ~= displayHeaderAlpha then g.spec:SetAlpha(displayHeaderAlpha) end

    end
    if liveLayoutChanged then self:Layout(false) end
    return hasVisibleMessages, liveLayoutChanged
end

--- Pauses message aging while the chat is being read or navigated.
---@param paused boolean
---@param now number
function Feed:SetFadePaused(paused, now)
    paused = paused == true
    if paused == self.fadePaused then return end
    self.fadePaused = paused
    if paused then
        self.fadePausedAt = now
        return
    end

    local pauseStart = self.fadePausedAt or now
    self.fadePausedAt = nil
    for i = 1, #self.groups do
        local messages = self.groups[i].messages
        for j = 1, #messages do
            local msg = messages[j]
            local displayedAt = msg.displayedAt or msg.timestamp
            if type(displayedAt) == 'number' then
                msg.displayedAt = displayedAt + math.max(0, now - math.max(pauseStart, displayedAt))
            end
        end
    end
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

--- Whether the reader has moved away from the live bottom position.
---@return boolean
function Feed:IsBrowsingHistory()
    return self.historyMode == true
end

function Feed:IsHistoryVisible()
    return self.historyMode == true
end

function Feed:ResumeLive()
    if self.historyOnly or not self.historyMode then return end
    self.historyMode = false
    self:Layout(false)
    if self.onHistoryModeChanged then self.onHistoryModeChanged(false) end
    self:ScrollToLiveEdge()
end

---@param preserveHistory boolean? Keep the browse latch while repositioning.
---@param defer boolean? Reapply next frame after an asynchronous range update.
function Feed:ScrollToBottom(preserveHistory, defer)
    self:StopLayoutAnimation(true)
    local wasHistory = self.historyMode
    if not preserveHistory and not self.historyOnly then self.historyMode = false end
    if wasHistory and not self.historyMode then
        self:Layout(false)
        if self.onHistoryModeChanged then self.onHistoryModeChanged(false) end
    end
    self.scrollRequest = self.scrollRequest + 1
    local request = self.scrollRequest
    local function go()
        if self.scrollRequest ~= request then return end
        if not self.historyMode and self.growthDirection == 'top' then
            self.scrollFrame:SetVerticalScroll(0)
        else
            self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange() or 0)
        end
        if self.onScrollChanged then self.onScrollChanged() end
    end
    go()
    -- The scroll range lags a frame behind content changes; re-apply once.
    if defer ~= false and C_Timer then C_Timer.After(0, go) end
end

--- Aligns the live feed to its fixed growth edge after a resize or reflow.
function Feed:ScrollToLiveEdge()
    self.scrollRequest = self.scrollRequest + 1
    local request = self.scrollRequest
    local function align()
        if self.scrollRequest ~= request or self.historyMode then return end
        if self.growthDirection == 'bottom' then
            self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange() or 0)
        else
            self.scrollFrame:SetVerticalScroll(0)
        end
        if self.onScrollChanged then self.onScrollChanged() end
    end
    align()
    if C_Timer then C_Timer.After(0, align) end
end

function Feed:GetScrollOffset()
    return self.scrollFrame:GetVerticalScroll() or 0
end

--- Restores a history offset after a full rebuild, including the deferred
--- pass needed after WoW recalculates the scroll range.
---@param offset number
function Feed:RestoreScrollOffset(offset)
    self:StopLayoutAnimation(true)
    self.scrollRequest = self.scrollRequest + 1
    local request = self.scrollRequest
    local function restore()
        if self.scrollRequest ~= request or not self.historyMode then return end
        local range = self.scrollFrame:GetVerticalScrollRange() or 0
        self.scrollFrame:SetVerticalScroll(math.max(0, math.min(offset or 0, range)))
        if self.onScrollChanged then self.onScrollChanged() end
    end
    restore()
    if C_Timer then C_Timer.After(0, restore) end
end

--- Scrolls the viewport. Positive `upAmount` reveals older messages.
---@param upAmount number
function Feed:ScrollBy(upAmount)
    -- Let any group motion finish, but hand the scroll offset to the reader.
    self.layoutFollowBottom = false
    self.scrollRequest = self.scrollRequest + 1
    local request = self.scrollRequest
    local enteringHistory = upAmount > 0 and not self.historyMode
    if enteringHistory then
        self.historyMode = true
        self:Layout(false)
        if self.onHistoryModeChanged then self.onHistoryModeChanged(true) end
    end
    local function applyScroll()
        if self.scrollRequest ~= request then return end
        local range = self.scrollFrame:GetVerticalScrollRange() or 0
        local offset = self.scrollFrame:GetVerticalScroll() or 0
        if enteringHistory then
            offset = math.max(0, range - upAmount)
        else
            offset = math.max(0, math.min(range, offset - upAmount))
        end
        self.scrollFrame:SetVerticalScroll(offset)
        if upAmount < 0 and self:IsAtBottom() and self.historyMode and not self.historyOnly then
            self.historyMode = false
            if self.onHistoryModeChanged then self.onHistoryModeChanged(false) end
            self:ScrollToLiveEdge()
        end
        if self.onScrollChanged then self.onScrollChanged() end
    end
    applyScroll()
    if enteringHistory and C_Timer then C_Timer.After(0, applyScroll) end
end

--#endregion

--#region ── Widget pool ─────────────────────────────────────────────────────────

function Feed:AcquireGroup()
    local g = table.remove(self.groupPool)
    if not g then g = Widgets.CreateGroup(self.scrollChild) end
    g:SetParent(self.scrollChild)
    -- A pooled widget may still have an anchor from its former logical group.
    -- Keep it hidden until Layout assigns its final position.
    g:Hide()
    return g
end

function Feed:ReleaseGroup(g)
    Widgets.ResetGroup(g)
    self.groupPool[#self.groupPool + 1] = g
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
        Widgets.RenderGroup(self, g, groups[i], false, 1)
    end
    self:Layout(false)
end

--- Appends a single rendered group to the end of the list.
---@param group ChatGroup
---@param followBottom boolean?
function Feed:AppendGroup(group, followBottom)
    local animate = not self.historyOnly
    local snapshot = animate and self:CaptureLayoutPositions() or nil
    local fromOffset = animate and self:GetScrollOffset() or nil
    -- Chat and Feed intentionally share the grouped history table. The Chat
    -- owner may already have appended this logical group.
    if self.groups[#self.groups] ~= group then self.groups[#self.groups + 1] = group end
    local g = self:AcquireGroup()
    self.widgets[#self.widgets + 1] = g
    Widgets.RenderGroup(self, g, group, animate, 1)
    self:Layout(animate, snapshot, followBottom, fromOffset)
    if self.historyOnly and followBottom then self:ScrollToBottom(true) end
    return g
end

--- Re-renders the last group in place (used when a message joins it).
---@param group ChatGroup
---@param followBottom boolean?
function Feed:RefreshLastGroup(group, followBottom)
    local g = self.widgets[#self.widgets]
    if not g then return end
    local animate = not self.historyOnly
    local snapshot = animate and self:CaptureLayoutPositions() or nil
    local fromOffset = animate and self:GetScrollOffset() or nil
    g._lineAlphas = g._lineAlphas or {}
    g._lineAlphas[#group.messages] = 1
    Widgets.RenderGroup(self, g, group, animate, 1)
    self:Layout(animate, snapshot, followBottom, fromOffset)
    if self.historyOnly and followBottom then self:ScrollToBottom(true) end
end

function Feed:Clear()
    self:StopLayoutAnimation()
    self.scrollRequest = self.scrollRequest + 1
    self.historyMode = self.historyOnly
    for i = #self.widgets, 1, -1 do
        self:ReleaseGroup(table.remove(self.widgets, i))
    end
    self.groups = {}
    self:Layout()
end

--#endregion

--#region ── Layout and motion ───────────────────────────────────────────────────

function Feed:StopLayoutAnimation(settle)
    if self.layoutAnimation then
        self.layoutAnimation:Cancel()
        self.layoutAnimation = nil
    end
    if settle and self.layoutMoves then
        for i = 1, #self.layoutMoves do
            local move = self.layoutMoves[i]
            Widgets.AnchorGroup(move.group, self.scrollChild, move.toY)
        end
    end
    self.layoutMoves = nil
    self.layoutFollowBottom = nil
end

--- Captures only visible widgets that still represent their current logical
--- group. Hidden or recycled frames must never provide animation origins.
function Feed:CaptureLayoutPositions()
    local snapshot = {}
    for i = 1, #self.widgets do
        local g = self.widgets[i]
        if g._displayed and g:IsShown() and g.groupData == self.groups[i] then
            local _, relativeTo, _, _, y = g:GetPoint(1)
            if relativeTo == self.scrollChild and type(y) == 'number' then
                snapshot[g] = { y = y, group = g.groupData }
            end
        end
    end
    return snapshot
end

function Feed:AnimateLayout(moves, fromOffset, targetOffset, followBottom)
    if #moves == 0 and (not followBottom or math.abs(fromOffset - targetOffset) <= 0.5) then
        return
    end
    self.layoutMoves = moves
    self.layoutFollowBottom = followBottom == true
    local animation
    animation = Animations.Progress(self.scrollChild, LAYOUT_ANIMATION_TIME, Animations.CubicOut,
        function(eased)
            for i = 1, #moves do
                local move = moves[i]
                Widgets.AnchorGroup(move.group, self.scrollChild,
                    move.fromY + (move.toY - move.fromY) * eased)
            end
            if self.layoutFollowBottom then
                self.scrollFrame:SetVerticalScroll(fromOffset + (targetOffset - fromOffset) * eased)
            end
        end,
        function()
            for i = 1, #moves do
                local move = moves[i]
                Widgets.AnchorGroup(move.group, self.scrollChild, move.toY)
            end
            if self.layoutFollowBottom then
                self.scrollFrame:SetVerticalScroll(targetOffset)
            end
            if self.layoutAnimation == animation then
                self.layoutAnimation = nil
                self.layoutMoves = nil
                self.layoutFollowBottom = nil
            end
            if self.onScrollChanged then self.onScrollChanged() end
        end)
    self.layoutAnimation = animation
end

--- Anchors retained groups in arrival order, with live rows aligned to their
--- selected growth edge and history rows aligned to the top of the scroll list.
---@param animate boolean? tween stable displayed groups to new positions
---@param snapshot table? positions captured before rendering/pool mutations
---@param followBottom boolean? animate the viewport along with new content
---@param fromOffset number? viewport offset before the content changed
function Feed:Layout(animate, snapshot, followBottom, fromOffset)
    snapshot = snapshot or (animate and self:CaptureLayoutPositions() or {})
    self:StopLayoutAnimation()

    local historyVisible = self:IsHistoryVisible()
    local measured = {}
    for i = 1, #self.widgets do measured[i] = self.widgets[i]._metrics end
    local plan = LayoutPolicy.Plan(measured, GROUP_GAP, {
        history = historyVisible,
        maxMessages = self.maxLiveMessages,
        maxContentHeight = self.maxContentHeight,
    })
    local displayed = plan.displayed
    -- Apply the plan before showing anything. This gives newly acquired and
    -- newly restored widgets their final geometry while they are still hidden.
    for i = 1, #self.widgets do
        local g = self.widgets[i]
        if displayed[i] then
            local desiredFirst = plan.firstByGroup[i]
            if g._firstDisplayedMessage ~= desiredFirst then
                Widgets.RenderGroup(self, g, self.groups[i], false, desiredFirst)
            end
        else
            g:Hide()
        end
    end

    local contentHeight = plan.contentHeight
    self.contentHeight = contentHeight

    local viewHeight = self.scrollFrame:GetHeight() or 0
    local spacerHeight = 0
    if not historyVisible and self.growthDirection == 'bottom' then
        spacerHeight = math.max(viewHeight - contentHeight - PADDING * 2, 0)
    end
    self.spacer:SetHeight(spacerHeight)

    local y = 0
    local moves = {}
    for i = 1, #self.widgets do
        local g = self.widgets[i]
        if displayed[i] then
            local targetY = -(spacerHeight + PADDING + y)
            local displayedHeight = g._metrics.heights[plan.firstByGroup[i]] or g:GetHeight()
            if plan.oversizedGroup == i then
                -- The ScrollFrame clips the oversized row. Its full measured
                -- height keeps a range so bottom growth can reveal its newest end.
                displayedHeight = g._metrics.heights[plan.firstByGroup[i]] or displayedHeight
            end
            if g:GetHeight() ~= displayedHeight then
                g:SetHeight(displayedHeight)
                g.background:SetHeight(displayedHeight)
            end
            local origin = snapshot[g]
            local startY = origin and origin.group == self.groups[i] and origin.y or nil
            if animate and startY and math.abs(startY - targetY) > 0.5 then
                Widgets.AnchorGroup(g, self.scrollChild, startY)
                moves[#moves + 1] = { group = g, fromY = startY, toY = targetY }
            else
                Widgets.AnchorGroup(g, self.scrollChild, targetY)
            end
            y = y + g:GetHeight() + GROUP_GAP
            g:Show()
            Widgets.ApplyDisplayAlpha(g, historyVisible)
        end
        g._displayed = displayed[i] == true
    end

    local contentPadding = contentHeight > 0 and PADDING * 2 or 0
    local childHeight = math.max(spacerHeight + contentHeight + contentPadding, viewHeight)
    self.scrollChild:SetHeight(childHeight)
    if animate then
        local targetOffset = self.growthDirection == 'bottom'
            and math.max(childHeight - viewHeight, 0) or 0
        self:AnimateLayout(moves, fromOffset or self:GetScrollOffset(),
            targetOffset, followBottom)
    end
end

--- Sets the fixed feed viewport height and reflows the retained rows.
function Feed:SetViewportHeight(height)
    if self.viewportHeight == height then return end
    self.viewportHeight = height
    if self.scrollFrame:GetHeight() ~= height then self.scrollFrame:SetHeight(height) end
    self:Layout(false)
end

--- Sets the live row limit and the message space available after panel chrome.
function Feed:SetLiveLayout(maxMessages, maxContentHeight, growthDirection)
    local nextMaxMessages = math.max(1, math.floor(maxMessages or 6))
    local nextMaxHeight = math.max(0, maxContentHeight or 0)
    local nextDirection = growthDirection == 'top' and 'top' or 'bottom'
    local changed = nextMaxMessages ~= self.maxLiveMessages
        or nextMaxHeight ~= self.maxContentHeight
        or nextDirection ~= self.growthDirection
    self.maxLiveMessages = nextMaxMessages
    self.maxContentHeight = nextMaxHeight
    self.growthDirection = nextDirection
    if changed then self:Layout(false) end
end

--#endregion

if addon then addon.ChatFeedProto = Feed end
return Feed
