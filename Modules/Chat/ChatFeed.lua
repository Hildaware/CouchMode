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
        historyPreview = false,
        liveContentLimit = 300,
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
    local fadingHistory = self.historyExitFade == true
    local exitProgress = 1
    if fadingHistory then
        self.historyExitStartedAt = self.historyExitStartedAt or now
        exitProgress = math.min((now - self.historyExitStartedAt) / MESSAGE_FADE_TIME, 1)
    end

    local widgets, groups = self.widgets, self.groups
    for groupIndex = 1, #widgets do
        local g = widgets[groupIndex]
        local group = groups[groupIndex]
        local headerAlpha = 0
        local firstVisibleMessage
        local lineAlphas = g._lineAlphas
        if not lineAlphas then
            lineAlphas = {}
            g._lineAlphas = lineAlphas
        end
        local messages = group.messages
        if fadingHistory and not g._historyExitAlphas then
            g._historyExitAlphas = {}
            for i = 1, #messages do
                g._historyExitAlphas[i] = lineAlphas[i] or 1
            end
        end
        local exitAlphas = g._historyExitAlphas
        local lines = g.lines

        for messageIndex = 1, #messages do
            local msg = messages[messageIndex]
            local alpha = 1
            if enabled and delay >= 0 and type(msg.timestamp) == 'number' then
                local elapsed = now - msg.timestamp - delay
                if elapsed > 0 then
                    alpha = math.max(1 - elapsed / MESSAGE_FADE_TIME, 0)
                end
            end

            -- History rows are forced opaque while browsing. When browsing
            -- ends, interpolate from that displayed alpha to each row's live
            -- alpha before the live layout removes expired rows.
            if fadingHistory then
                local startAlpha = exitAlphas[messageIndex] or 1
                alpha = startAlpha + (alpha - startAlpha) * exitProgress
            end

            -- GetAlpha is authoritative and cheap: this skips the (dirty)
            -- SetAlpha in the common steady state where every row's alpha is
            -- already settled at 0 or 1.
            local line = lines[messageIndex]
            if line and line:GetAlpha() ~= alpha then line:SetAlpha(alpha) end
            lineAlphas[messageIndex] = alpha
            headerAlpha = math.max(headerAlpha, alpha)
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
        -- its group has faded.
        if g.background:GetAlpha() ~= headerAlpha then g.background:SetAlpha(headerAlpha) end
        if g.name:GetAlpha() ~= headerAlpha then g.name:SetAlpha(headerAlpha) end
        if g.channel:GetAlpha() ~= headerAlpha then g.channel:SetAlpha(headerAlpha) end
        if g.icon:GetAlpha() ~= headerAlpha then g.icon:SetAlpha(headerAlpha) end
        if g.iconBorder:GetAlpha() ~= headerAlpha then g.iconBorder:SetAlpha(headerAlpha) end
        if g.spec:GetAlpha() ~= headerAlpha then g.spec:SetAlpha(headerAlpha) end

        local hasVisibleGroup = headerAlpha > 0
        if g._hasVisibleMessages ~= hasVisibleGroup then
            g._hasVisibleMessages = hasVisibleGroup
            needsLiveLayout = true
        end
        if g._metrics then
            g._metrics.firstEligible = hasVisibleGroup and firstVisibleMessage or nil
        end

    end

    if fadingHistory and exitProgress >= 1 then
        self.historyExitFade = false
        self.historyExitStartedAt = nil
        for i = 1, #widgets do widgets[i]._historyExitAlphas = nil end
        -- Apply the live admission plan only after every visible history row
        -- has reached its intended alpha.
        self:Layout(false)
    elseif needsLiveLayout and not self:IsHistoryVisible() then
        local snapshot = self:CaptureLayoutPositions()
        self.pendingResizeSnapshot = snapshot
        self:Layout(true, snapshot)
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

--- Whether the reader has moved away from the live bottom position.
---@return boolean
function Feed:IsBrowsingHistory()
    return self.historyMode == true
end

function Feed:IsHistoryVisible()
    return self.historyMode == true or self.historyPreview == true or self.historyExitFade == true
end

function Feed:IsFadingHistoryOut()
    return self.historyExitFade == true
end

--- Shows all history while active. On exit, retain the current geometry until
--- the visible lines have faded to their normal live alpha.
---@param active boolean
---@param fadeOut boolean? Whether the history-to-live handoff should animate.
function Feed:SetHistoryPreview(active, fadeOut)
    active = active == true
    if active then
        if self.historyPreview and not self.historyExitFade then return end
        self.historyPreview = true
        self.historyExitFade = false
        self.historyExitStartedAt = nil
        for i = 1, #self.widgets do self.widgets[i]._historyExitAlphas = nil end
        self:Layout(false)
    elseif self.historyPreview or self.historyMode or self.historyExitFade then
        self.historyPreview = false
        self.historyMode = false
        if fadeOut then
            self.historyExitFade = true
            self.historyExitStartedAt = nil
        else
            self.historyExitFade = false
            self.historyExitStartedAt = nil
            self:Layout(false)
        end
    else
        return
    end
    if self.onScrollChanged then self.onScrollChanged() end
end

function Feed:SetLiveContentLimit(height)
    height = math.max(height or 0, 0)
    if math.abs((self.liveContentLimit or 0) - height) < 0.5 then return end
    self.liveContentLimit = height
    if #self.widgets > 0 and not self:IsHistoryVisible() then self:Layout(false) end
end

function Feed:ResumeLive()
    if not self.historyMode and not self.historyExitFade then return end
    self.historyMode = false
    self.historyExitFade = false
    self.historyExitStartedAt = nil
    self:Layout(false)
end

---@param preserveHistory boolean? Keep the browse latch while repositioning.
---@param defer boolean? Reapply next frame after an asynchronous range update.
function Feed:ScrollToBottom(preserveHistory, defer)
    if not preserveHistory and self.historyMode then
        self.historyMode = false
        self:Layout(false)
    end
    local function go()
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
    local function restore()
        if not self.historyMode then return end
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
    if upAmount > 0 and not self.historyMode then
        self.historyExitFade = false
        self.historyExitStartedAt = nil
        self.historyMode = true
        -- Expanding history changes the scroll range. Do that first so the
        -- wheel/controller action that entered history also scrolls it.
        if self.onScrollChanged then self.onScrollChanged() end
    end
    local range = self.scrollFrame:GetVerticalScrollRange() or 0
    local offset = self.scrollFrame:GetVerticalScroll() or 0
    offset = math.max(0, math.min(range, offset - upAmount))
    self.scrollFrame:SetVerticalScroll(offset)
    if upAmount < 0 and self.historyMode and self:IsAtBottom() then
        self.historyMode = false
        self:Layout(false)
    end
    if self.onScrollChanged then self.onScrollChanged() end
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
    self.pendingResizeSnapshot = nil
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
    self.pendingResizeSnapshot = snapshot
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
    self.pendingResizeSnapshot = snapshot
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
    self.pendingResizeSnapshot = nil
    self.historyMode = false
    self.historyPreview = false
    self.historyExitFade = false
    self.historyExitStartedAt = nil
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

function Feed:FinishLayoutTransaction()
    self.pendingResizeSnapshot = nil
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

    local measured = {}
    for i = 1, #self.widgets do measured[i] = self.widgets[i]._metrics end
    local plan = LayoutPolicy.Plan(measured, self.liveContentLimit, self:IsHistoryVisible(), GROUP_GAP)
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
    if not self:IsHistoryVisible() then self.visibleContentHeight = contentHeight end

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
        end
        g._displayed = displayed[i] == true
    end

    self.scrollChild:SetHeight(math.max(spacerHeight + contentHeight + PADDING * 2, viewHeight))
    if animate and #moves > 0 then self:AnimateLayout(moves) end
end

--- Sets the height of the feed viewport (called when the panel resizes).
---@param animate boolean?  preserve and tween current group positions
function Feed:SetViewportHeight(height, animate)
    local oldHeight = self.viewportHeight or height
    local snapshot
    if animate then
        snapshot = self.pendingResizeSnapshot or self:CaptureLayoutPositions()
        local delta = height - oldHeight
        if math.abs(delta) > 0.5 then
            for _, origin in pairs(snapshot) do
                -- The panel is bottom-anchored. Compensate for its top edge
                -- moving so existing widgets start at the same screen point.
                origin.y = origin.y - delta
            end
        end
    end
    self.viewportHeight = height
    self.pendingResizeSnapshot = nil
    self.scrollFrame:SetHeight(height)
    self:Layout(animate, snapshot)
end

--#endregion

if addon then addon.ChatFeedProto = Feed end
return Feed
