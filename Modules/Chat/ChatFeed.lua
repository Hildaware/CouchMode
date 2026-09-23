--[[ ChatFeed.lua
A pooled, variable-height scrolling list of grouped chat messages.

This file owns everything that spans many groups: the widget pool, admission
(via `ChatFeedLayout`), cross-group layout, scrolling, history state, fading and
motion. The anatomy and rendering of a single group live in `ChatFeedWidgets`,
and styling stays in `addon.Chat` so colors, fonts, icons and aliases remain in
one place.
]]

local addonName, addon = ...
local addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)
local LayoutPolicy = addon.ChatFeedLayout
local Widgets = addon.ChatFeedWidgets

local Feed = {}
Feed.__index = Feed

--#region ── Constants ────────────────────────────────────────────────────────

-- Geometry shared with the widget layer is read from `ChatFeedWidgets`.
local PADDING = Widgets.PADDING

local GROUP_GAP = 6
local MESSAGE_FADE_TIME = 0.35
local LAYOUT_ANIMATION_TIME = 0.3

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
        historyMode = false,
        compactMode = false,
        fadePaused = false,
        fadePausedAt = nil,
        liveContentLimit = 300,
        scrollRequest = 0,
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

function Feed:SetCompactMode(compactMode)
    self.compactMode = compactMode == true
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
    local needsLiveLayout = false
    local historyVisible = self:IsHistoryVisible()

    local widgets, groups = self.widgets, self.groups
    for groupIndex = 1, #widgets do
        local g = widgets[groupIndex]
        local group = groups[groupIndex]
        local liveHeaderAlpha = 0
        local firstVisibleMessage
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
            if not self.fadePaused and enabled and delay >= 0 and type(msg.timestamp) == 'number' then
                local elapsed = now - msg.timestamp - delay
                if elapsed > 0 then
                    alpha = math.max(1 - elapsed / MESSAGE_FADE_TIME, 0)
                end
            end

            -- Keep the live alpha current while browsing, but display history
            -- rows fully opaque. This lets the live layout collapse expired
            -- rows immediately when the reader returns to the bottom.
            local displayAlpha = historyVisible and 1 or alpha
            local line = lines[messageIndex]
            if line and line:GetAlpha() ~= displayAlpha then line:SetAlpha(displayAlpha) end
            lineAlphas[messageIndex] = alpha
            liveHeaderAlpha = math.max(liveHeaderAlpha, alpha)
            if alpha > 0 then
                hasVisibleMessages = true
                firstVisibleMessage = firstVisibleMessage or messageIndex
            end
        end

        firstVisibleMessage = firstVisibleMessage or #messages
        if g._firstVisibleMessage ~= firstVisibleMessage then
            g._firstVisibleMessage = firstVisibleMessage
            needsLiveLayout = true
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

        local hasVisibleGroup = liveHeaderAlpha > 0
        if g._hasVisibleMessages ~= hasVisibleGroup then
            g._hasVisibleMessages = hasVisibleGroup
            needsLiveLayout = true
        end
        if g._metrics then
            g._metrics.firstEligible = hasVisibleGroup and firstVisibleMessage or nil
        end

    end

    if needsLiveLayout and not historyVisible then
        local snapshot = self:CaptureLayoutPositions()
        self:Layout(true, snapshot)
    end
    return hasVisibleMessages
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

    local elapsed = math.max(0, now - (self.fadePausedAt or now))
    self.fadePausedAt = nil
    if elapsed == 0 then return end
    for i = 1, #self.groups do
        local messages = self.groups[i].messages
        for j = 1, #messages do
            local msg = messages[j]
            if type(msg.timestamp) == 'number' then msg.timestamp = msg.timestamp + elapsed end
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

function Feed:SetLiveContentLimit(height)
    height = math.max(height or 0, 0)
    self.liveContentLimit = height
end

function Feed:ResumeLive()
    if not self.historyMode then return end
    self.historyMode = false
    self:Layout(false)
    self:ScrollToBottom(true)
end

---@param preserveHistory boolean? Keep the browse latch while repositioning.
---@param defer boolean? Reapply next frame after an asynchronous range update.
function Feed:ScrollToBottom(preserveHistory, defer)
    if not preserveHistory and self.historyMode then
        self.historyMode = false
        self:Layout(false)
    end
    self.scrollRequest = self.scrollRequest + 1
    local request = self.scrollRequest
    local function go()
        if self.scrollRequest ~= request then return end
        self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange() or 0)
        if self.onScrollChanged then self.onScrollChanged() end
    end
    go()
    -- The scroll range lags a frame behind content changes; re-apply once.
    if defer ~= false and C_Timer then C_Timer.After(0, go) end
end

function Feed:GetScrollOffset()
    return self.scrollFrame:GetVerticalScroll() or 0
end

--- Restores a history offset after a full rebuild, including the deferred
--- pass needed after WoW recalculates the scroll range.
---@param offset number
function Feed:RestoreScrollOffset(offset)
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
    self.scrollRequest = self.scrollRequest + 1
    local request = self.scrollRequest
    local enteringHistory = upAmount > 0 and not self.historyMode
    if enteringHistory then
        self.historyMode = true
        -- Reveal the retained rows before applying this first scroll action.
        -- The panel itself stays at its configured size.
        self:Layout(false)
    end
    local function applyScroll()
        if self.scrollRequest ~= request then return end
        local range = self.scrollFrame:GetVerticalScrollRange() or 0
        local offset = enteringHistory and range or (self.scrollFrame:GetVerticalScroll() or 0)
        offset = math.max(0, math.min(range, offset - upAmount))
        self.scrollFrame:SetVerticalScroll(offset)
        if self.onScrollChanged then self.onScrollChanged() end
    end
    applyScroll()
    -- The range may update on the next frame after history rows are exposed.
    if enteringHistory and C_Timer then C_Timer.After(0, applyScroll) end

    if upAmount < 0 and self.historyMode and self:IsAtBottom() then
        self.historyMode = false
        self:Layout(false)
        self:ScrollToBottom(true)
    end
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
        g._hasVisibleMessages = true
        g._firstVisibleMessage = 1
        Widgets.RenderGroup(self, g, groups[i], false, 1)
    end
    self:Layout(false)
end

--- Appends a single rendered group to the end of the list.
---@param group ChatGroup
function Feed:AppendGroup(group)
    local snapshot = self:CaptureLayoutPositions()
    -- Chat and Feed intentionally share the grouped history table. The Chat
    -- owner may already have appended this logical group.
    if self.groups[#self.groups] ~= group then self.groups[#self.groups + 1] = group end
    local g = self:AcquireGroup()
    self.widgets[#self.widgets + 1] = g
    g._hasVisibleMessages = true
    g._firstVisibleMessage = 1
    Widgets.RenderGroup(self, g, group, true, 1)
    self:Layout(true, snapshot)
    return g
end

--- Re-renders the last group in place (used when a message joins it).
---@param group ChatGroup
function Feed:RefreshLastGroup(group)
    local g = self.widgets[#self.widgets]
    if not g then return end
    local snapshot = self:CaptureLayoutPositions()
    if g._hasVisibleMessages == false then
        g._firstVisibleMessage = #group.messages
    end
    g._hasVisibleMessages = true
    g._lineAlphas = g._lineAlphas or {}
    g._lineAlphas[#group.messages] = 1
    Widgets.RenderGroup(self, g, group, true, g._firstDisplayedMessage or 1)
    self:Layout(true, snapshot)
end

function Feed:Clear()
    self:StopLayoutAnimation()
    self.scrollRequest = self.scrollRequest + 1
    self.historyMode = false
    for i = #self.widgets, 1, -1 do
        self:ReleaseGroup(table.remove(self.widgets, i))
    end
    self.groups = {}
    self:Layout()
end

--#endregion

--#region ── Layout and motion ───────────────────────────────────────────────────

function Feed:StopLayoutAnimation()
    if self.layoutDriver then self.layoutDriver:Hide() end
    self.layoutMoves = nil
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
            Widgets.AnchorGroup(move.group, self.scrollChild,
                move.fromY + (move.toY - move.fromY) * eased)
        end
        if progress >= 1 then
            for i = 1, #moves do
                local move = moves[i]
                Widgets.AnchorGroup(move.group, self.scrollChild, move.toY)
            end
            self:StopLayoutAnimation()
        end
    end)
    self.layoutDriver:Show()
end

--- Anchors admitted group widgets top-to-bottom, bottom-aligning short content.
---@param animate boolean? tween stable displayed groups to new positions
---@param snapshot table? positions captured before rendering/pool mutations
function Feed:Layout(animate, snapshot)
    snapshot = snapshot or (animate and self:CaptureLayoutPositions() or {})
    self:StopLayoutAnimation()

    local historyVisible = self:IsHistoryVisible()
    local measured = {}
    for i = 1, #self.widgets do measured[i] = self.widgets[i]._metrics end
    local plan = LayoutPolicy.Plan(measured, self.liveContentLimit, historyVisible, GROUP_GAP)
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
    local spacerHeight = math.max(viewHeight - contentHeight - PADDING * 2, 0)
    self.spacer:SetHeight(spacerHeight)

    local y = 0
    local moves = {}
    for i = 1, #self.widgets do
        local g = self.widgets[i]
        if displayed[i] then
            local targetY = -(spacerHeight + PADDING + y)
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

    self.scrollChild:SetHeight(math.max(spacerHeight + contentHeight + PADDING * 2, viewHeight))
    if animate and #moves > 0 then self:AnimateLayout(moves) end
end

--- Sets the fixed feed viewport height and reflows rows to its new budget.
function Feed:SetViewportHeight(height)
    self.scrollFrame:SetHeight(height)
    self:Layout(false)
    if not self:IsHistoryVisible() then self:ScrollToBottom(true) end
end

--#endregion

if addon then addon.ChatFeedProto = Feed end
return Feed
