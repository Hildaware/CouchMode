--[[ Feed.lua
A pooled, bottom-anchored list of live toast rows.

The feed renders active entries and handles row layout and pooling. Styling and
fade timing are delegated to `addon.Toasts` through presenters.
]]

local addonName, addon = ...
addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)

local Feed = {}
Feed.__index = Feed

--#region ── Constants ────────────────────────────────────────────────────────

local ROW_HEIGHT = 36
local ROW_GAP = 2
local PADDING = 4
local ICON_SIZE = 22
local ICON_FRAME_SIZE = 28
local ICON_FRAME_ATLAS = 'UI-Journeys-Delve-rewardicon-square-frame'
local ICON_LEFT = 6
local ICON_GAP = 6
local QUEST_ICON_SIZE = 16
local QUEST_ICON_GAP = 4
local TEXT_PAD = 6
local WRAPPED_TEXT_PAD = 12
local FADE_TIME = 0.25

local ROW_BORDER_LAYOUT = {
    TopLeftCorner = { atlas = 'characterupdate-9slice-topleftcorner', layer = 'OVERLAY', subLevel = 7 },
    TopRightCorner = { atlas = 'characterupdate-9slice-toprightcorner', layer = 'OVERLAY', subLevel = 7 },
    BottomRightCorner = { atlas = 'characterupdate-9slice-bottomrightcorner', layer = 'OVERLAY', subLevel = 7 },
    BottomLeftCorner = { atlas = 'characterupdate-9slice-bottomleftcorner', layer = 'OVERLAY', subLevel = 7 },
    TopEdge = { atlas = '_characterupdate-9slice-topedge', layer = 'OVERLAY', subLevel = 7 },
    BottomEdge = { atlas = '_characterupdate-9slice-bottomedge', layer = 'OVERLAY', subLevel = 7 },
    RightEdge = { atlas = '!characterupdate-9slice-rightedge', layer = 'OVERLAY', subLevel = 7 },
    LeftEdge = { atlas = '!characterupdate-9slice-leftedge', layer = 'OVERLAY', subLevel = 7 },
}

--#endregion

--#region ── Row widgets ───────────────────────────────────────────────────────

local function createRow(parent)
    local row = CreateFrame('Frame', nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row._mouseEnabled = true

    local bg = row:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    row.bg = bg

    -- A second copy of the background drains toward the left as the toast
    -- approaches its fade. Keep it behind the icon, label, and border.
    local countdown = row:CreateTexture(nil, 'BACKGROUND', nil, 1)
    countdown:SetPoint('TOPLEFT', row, 'TOPLEFT')
    countdown:SetPoint('BOTTOMLEFT', row, 'BOTTOMLEFT')
    countdown:Hide()
    row.countdown = countdown

    if NineSliceUtil and NineSliceUtil.ApplyLayout then
        NineSliceUtil.ApplyLayout(row, ROW_BORDER_LAYOUT)
        -- The source corners are 44px square. Scale them to fit a compact row
        -- while keeping the 9-slice edges as narrow accents.
        row.TopLeftCorner:SetSize(16, 16)
        row.TopRightCorner:SetSize(16, 16)
        row.BottomRightCorner:SetSize(16, 16)
        row.BottomLeftCorner:SetSize(16, 16)
        row.TopEdge:SetHeight(3)
        row.BottomEdge:SetHeight(3)
        row.LeftEdge:SetWidth(3)
        row.RightEdge:SetWidth(3)
    end

    local icon = row:CreateTexture(nil, 'ARTWORK')
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint('LEFT', row, 'LEFT', ICON_LEFT, 0)
    icon:Hide()
    row.icon = icon

    local iconFrame = row:CreateTexture(nil, 'OVERLAY', nil, 1)
    iconFrame:SetAtlas(ICON_FRAME_ATLAS)
    iconFrame:SetSize(ICON_FRAME_SIZE, ICON_FRAME_SIZE)
    iconFrame:SetPoint('CENTER', icon)
    iconFrame:Hide()
    row.iconFrame = iconFrame

    local questIcon = row:CreateTexture(nil, 'ARTWORK')
    questIcon:SetSize(QUEST_ICON_SIZE, QUEST_ICON_SIZE)
    questIcon:Hide()
    row.questIcon = questIcon

    local label = row:CreateFontString(nil, 'OVERLAY', 'ChatFontNormal')
    label:SetJustifyH('LEFT')
    label:SetJustifyV('MIDDLE')
    label:SetWordWrap(false)
    label:SetPoint('LEFT', row, 'LEFT', TEXT_PAD, 0)
    label:SetPoint('RIGHT', row, 'RIGHT', -TEXT_PAD, 0)
    row.label = label

    row:SetScript('OnEnter', function(self)
        if self._hover then return end
        self._hover = true
        local feed = self._feed
        if feed then feed:NoteHover(1) end
        local entry = self._entry
        if entry and entry.hyperlink and GameTooltip then
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:SetHyperlink(entry.hyperlink)
            GameTooltip:Show()
        end
    end)
    row:SetScript('OnLeave', function(self)
        if not self._hover then return end
        self._hover = false
        local feed = self._feed
        if feed then feed:NoteHover(-1) end
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)

    return row
end

--#endregion

--#region ── Construction ───────────────────────────────────────────────────────

---@param parent Frame  Frame the feed fills.
---@return table feed
function Feed.New(parent)
    local scrollFrame = CreateFrame('ScrollFrame', nil, parent)
    scrollFrame:SetAllPoints(parent)
    scrollFrame:SetClipsChildren(true)

    local scrollChild = CreateFrame('Frame', nil, scrollFrame)
    scrollChild:SetPoint('TOPLEFT', scrollFrame, 'TOPLEFT')
    scrollChild:SetPoint('TOPRIGHT', scrollFrame, 'TOPRIGHT')
    scrollFrame:SetScrollChild(scrollChild)

    local feed = setmetatable({
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        rowPool = {},
        rows = {},
        fonts = { label = { face = nil, size = 14 } },
        width = 300,
        viewportHeight = 0,
        contentHeight = 0,
        hoverCount = 0,
        hovering = false,
        presenter = nil,
        durationForEntry = nil,
    }, Feed)
    feed:SetWidth(300)
    return feed
end

--#endregion

--#region ── Sizing ────────────────────────────────────────────────────────────

function Feed:SetWidth(width)
    self.width = width
    self.scrollChild:SetWidth(width)
    for i = 1, #self.rows do self:SizeRow(self.rows[i]) end
    if self.viewportHeight > 0 then self:Layout() end
end

--- Stores the resolved font metrics and applies them to live rows.
---@param fonts table  { label = { face = string, size = number } }
function Feed:SetFonts(fonts)
    self.fonts = fonts or { label = { face = nil, size = 14 } }
    for i = 1, #self.rows do
        self:ApplyFont(self.rows[i])
        self:SizeRow(self.rows[i])
    end
    if self.viewportHeight > 0 then self:Layout() end
end

---@param row Frame
function Feed:ApplyFont(row)
    local font = self.fonts and self.fonts.label
    if font and font.face then
        row.label:SetFont(font.face, font.size or 14)
    end
end

function Feed:SizeRow(row)
    local presented = row._presented or {}
    local labelOffset = row._labelOffset or TEXT_PAD
    row.label:SetWidth(math.max(1, self.width - PADDING * 2 - labelOffset - TEXT_PAD))
    if presented.wrap then
        row:SetHeight(math.max(ROW_HEIGHT, math.ceil(row.label:GetStringHeight()) + WRAPPED_TEXT_PAD))
    else
        row:SetHeight(ROW_HEIGHT)
    end
end

---@param height number
function Feed:SetViewportHeight(height)
    self.viewportHeight = math.max(height or 0, 1)
    self:Layout()
    self:ScrollToBottom()
end

--- Height occupied by the newest `count` rows, including their gaps.
---@param count number
---@return number
function Feed:GetTailHeight(count)
    count = math.max(0, math.floor(count or 0))
    local first = math.max(1, #self.rows - count + 1)
    local height = 0
    for i = first, #self.rows do
        if height > 0 then height = height + ROW_GAP end
        height = height + self.rows[i]:GetHeight()
    end
    return height
end

--#endregion

--#region ── Content ───────────────────────────────────────────────────────────

function Feed:AcquireRow()
    local row = table.remove(self.rowPool)
    if not row then row = createRow(self.scrollChild) end
    row:SetParent(self.scrollChild)
    row._feed = self
    row._mouseEnabled = true
    row:EnableMouse(true)
    row:Show()
    return row
end

function Feed:ReleaseRow(row)
    -- A pooled row must never leave a stale tooltip or a stuck hover behind.
    if row._hover then
        row._hover = false
        self:NoteHover(-1)
    end
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == row then
        GameTooltip:Hide()
    end
    row._entry = nil
    row._presented = nil
    row._alpha = nil
    row._countdownWidth = nil
    row.countdown:Hide()
    row.label:SetText('')
    row.label:SetTextColor(1, 1, 1, 1)
    row.icon:Hide()
    row.icon:SetTexture(nil)
    row.iconFrame:Hide()
    row.questIcon:Hide()
    row.questIcon:SetTexture(nil)
    row:Hide()
    row:ClearAllPoints()
    self.rowPool[#self.rowPool + 1] = row
end

--- Applies the presenter's styling to one row.
---@param row Frame
---@param entry ToastEntry
function Feed:RenderRow(row, entry)
    row._entry = entry
    row._alpha = 1
    row:SetAlpha(1)

    local presented = self.presenter and self.presenter(entry) or nil
    if not presented then presented = { text = '' } end
    row._presented = presented

    row.label:SetText(presented.text or '')
    row.label:SetWordWrap(presented.wrap == true)
    self:ApplyFont(row)
    local text = presented.textColor
    row.label:SetTextColor(text and text[1] or 1, text and text[2] or 1, text and text[3] or 1, 1)

    local bg = presented.bg or { 0.1, 0.1, 0.1, 1 }
    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
    row.countdown:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
    row._countdownWidth = nil
    row.countdown:Hide()

    local labelOffset = TEXT_PAD
    if presented.icon or presented.iconAtlas then
        if presented.iconAtlas then
            row.icon:SetAtlas(presented.iconAtlas)
        else
            row.icon:SetTexture(presented.icon)
        end
        row.icon:Show()
        row.iconFrame:Show()
        labelOffset = ICON_LEFT + ICON_SIZE + ICON_GAP
    else
        row.icon:Hide()
        row.icon:SetTexture(nil)
        row.iconFrame:Hide()
    end

    row.questIcon:ClearAllPoints()
    if presented.questIconAtlas then
        row.questIcon:SetAtlas(presented.questIconAtlas)
        row.questIcon:SetPoint('LEFT', row, 'LEFT', labelOffset, 0)
        row.questIcon:Show()
        labelOffset = labelOffset + QUEST_ICON_SIZE + QUEST_ICON_GAP
    else
        row.questIcon:Hide()
        row.questIcon:SetTexture(nil)
    end

    row.label:ClearAllPoints()
    row.label:SetPoint('LEFT', row, 'LEFT', labelOffset, 0)
    row._labelOffset = labelOffset
    self:SizeRow(row)
end

--- Adds one entry below the existing rows.
---@param entry ToastEntry
function Feed:Append(entry)
    local row = self:AcquireRow()
    self:RenderRow(row, entry)
    self.rows[#self.rows + 1] = row
    self:Layout()
end

--- Drops the oldest rows when the live display limit is reduced.
---@param count number
function Feed:TrimToCount(count)
    while #self.rows > count do
        local row = table.remove(self.rows, 1)
        self:ReleaseRow(row)
    end
    self:Layout()
end

--- Removes rows whose weighted fade has completed, freeing display slots.
---@param now number
---@param ignoreHover boolean?
---@return number removedCount
function Feed:RemoveExpiredRows(now, ignoreHover)
    if self.hovering and not ignoreHover then return 0 end

    local removed = 0
    for i = #self.rows, 1, -1 do
        local row = self.rows[i]
        local entry = row._entry
        local timestamp = type(entry) == 'table' and (entry.displayedAt or entry.timestamp)
        local duration = self.durationForEntry and self.durationForEntry(entry) or 0
        local fadedOut = row._alpha ~= nil and row._alpha <= 0
        local fadeEnded = type(timestamp) == 'number'
            and now - timestamp >= duration + FADE_TIME
        if fadedOut or fadeEnded then
            table.remove(self.rows, i)
            self:ReleaseRow(row)
            removed = removed + 1
        end
    end

    if removed > 0 then self:Layout() end
    return removed
end

--- Returns the currently displayed entries in feed order.
---@return ToastEntry[]
function Feed:GetEntries()
    local entries = {}
    for i = 1, #self.rows do entries[i] = self.rows[i]._entry end
    return entries
end

--- Re-renders the current rows from `entries`.
---@param entries ToastEntry[]
function Feed:Rebuild(entries)
    for i = #self.rows, 1, -1 do
        self:ReleaseRow(self.rows[i])
        self.rows[i] = nil
    end
    for i = 1, #entries do
        local row = self:AcquireRow()
        self:RenderRow(row, entries[i])
        self.rows[i] = row
    end
    self:Layout()
end

function Feed:Clear()
    for i = #self.rows, 1, -1 do
        self:ReleaseRow(self.rows[i])
        self.rows[i] = nil
    end
    self:Layout()
end

--#endregion

--#region ── Layout ────────────────────────────────────────────────────────────

--- Stacks rows downward, bottom-anchored inside the viewport. When content is
--- shorter than the viewport the stack sits at the bottom.
function Feed:Layout()
    local count = #self.rows
    local contentHeight = count > 0 and (count - 1) * ROW_GAP or 0
    for i = 1, count do contentHeight = contentHeight + self.rows[i]:GetHeight() end
    local top = 0
    if contentHeight < self.viewportHeight then
        top = self.viewportHeight - contentHeight
    end

    for i = 1, count do
        local row = self.rows[i]
        local y = -top
        row:ClearAllPoints()
        row:SetPoint('TOPLEFT', self.scrollChild, 'TOPLEFT', PADDING, y)
        row:SetPoint('TOPRIGHT', self.scrollChild, 'TOPRIGHT', -PADDING, y)
        top = top + row:GetHeight() + ROW_GAP
    end

    self.contentHeight = contentHeight
    -- The child is exactly as tall as the content (or the viewport when the
    -- content is shorter), so there is never a phantom scroll range.
    self.scrollChild:SetHeight(math.max(self.viewportHeight, contentHeight))
end

--#endregion

--#region ── Fading ────────────────────────────────────────────────────────────

--- Fades each row from its presentation timestamp and drains its countdown over
--- the same weighted duration. Hover keeps the existing row alpha in place.
---@param now number
---@return boolean hasVisibleRows
function Feed:UpdateRowFade(now)
    local hasVisibleRows = false
    for i = 1, #self.rows do
        local row = self.rows[i]
        local entry = row._entry
        local alpha = row._alpha or 1
        local timestamp = type(entry) == 'table' and (entry.displayedAt or entry.timestamp)
        local duration = self.durationForEntry and self.durationForEntry(entry) or 0
        local elapsed = type(timestamp) == 'number' and now - timestamp or 0

        if type(timestamp) == 'number' and duration > 0 then
            local remaining = math.max(0, math.min(1, 1 - elapsed / duration))
            local width = row:GetWidth() * remaining
            if width > 0 then
                if row._countdownWidth ~= width then
                    row.countdown:SetWidth(width)
                    row._countdownWidth = width
                end
                row.countdown:Show()
            else
                row.countdown:Hide()
            end
        else
            row.countdown:Hide()
        end

        if type(timestamp) == 'number' then
            local target = 1
            local fadeElapsed = elapsed - duration
            if fadeElapsed > 0 then target = math.max(1 - fadeElapsed / FADE_TIME, 0) end
            if self.hovering then target = math.max(target, alpha) end
            alpha = target
        else
            alpha = 1
        end

        if row._alpha ~= alpha then
            row._alpha = alpha
            row:SetAlpha(alpha)
        end
        local mouseEnabled = alpha > 0
        if row._mouseEnabled ~= mouseEnabled then
            row._mouseEnabled = mouseEnabled
            row:EnableMouse(mouseEnabled)
        end
        if not mouseEnabled and row._hover then
            row._hover = false
            self:NoteHover(-1)
            if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == row then
                GameTooltip:Hide()
            end
        end
        if alpha > 0 then hasVisibleRows = true end
    end
    return hasVisibleRows
end

--#endregion

--#region ── Scrolling ─────────────────────────────────────────────────────────

function Feed:ScrollToBottom()
    local function go()
        self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange() or 0)
    end
    go()
    -- The scroll range lags a frame behind content changes; re-apply once.
    if C_Timer then C_Timer.After(0, go) end
end

--#endregion

--#region ── Hover ─────────────────────────────────────────────────────────────

--- Tracks hover depth so overlapping row/frame enter/leave events do not leave
--- the feed stuck in either state.
---@param delta number
function Feed:NoteHover(delta)
    self.hoverCount = math.max(0, (self.hoverCount or 0) + delta)
    self.hovering = self.hoverCount > 0
end

--#endregion

if addon then addon.ToastFeedProto = Feed end
return Feed
