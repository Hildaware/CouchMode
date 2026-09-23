--[[ Feed.lua
A pooled, bottom-anchored scrolling list of loot reward rows.

The feed owns no policy: it renders the entries it is handed and reports its
scroll state. Styling is delegated to `addon.Loot` through a presenter, so
colors, icons and labels stay in one place.
]]

local addonName, addon = ...
addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)

local Feed = {}
Feed.__index = Feed

--#region ── Constants ────────────────────────────────────────────────────────

local ROW_HEIGHT = 30
local ROW_GAP = 2
local PADDING = 4
local ICON_SIZE = 22
local ICON_LEFT = 6
local ICON_GAP = 6
local QUEST_ICON_SIZE = 16
local QUEST_ICON_GAP = 4
local TEXT_PAD = 6
local FADE_TIME = 0.25

--#endregion

--#region ── Row widgets ───────────────────────────────────────────────────────

local function createRow(parent)
    local row = CreateFrame('Frame', nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    row.bg = bg

    row.border = addon.Utils.create_border_textures(row, row)

    local icon = row:CreateTexture(nil, 'ARTWORK')
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint('LEFT', row, 'LEFT', ICON_LEFT, 0)
    icon:Hide()
    row.icon = icon

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
    if scrollFrame.EnableMouseWheel then scrollFrame:EnableMouseWheel(true) end
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
        historyMode = false,
        hoverCount = 0,
        hovering = false,
        presenter = nil,
        onScrollChanged = nil,
    }, Feed)

    scrollFrame:SetScript('OnScrollRangeChanged', function()
        if feed.onScrollChanged then feed.onScrollChanged() end
    end)
    scrollFrame:SetScript('OnMouseWheel', function(_, delta)
        feed:ScrollBy(delta * 30)
        return false
    end)

    feed:SetWidth(300)
    return feed
end

--#endregion

--#region ── Sizing ────────────────────────────────────────────────────────────

function Feed:SetWidth(width)
    self.width = width
    self.scrollChild:SetWidth(width)
end

--- Stores the resolved font metrics and applies them to live rows.
---@param fonts table  { label = { face = string, size = number } }
function Feed:SetFonts(fonts)
    self.fonts = fonts or { label = { face = nil, size = 14 } }
    for i = 1, #self.rows do
        self:ApplyFont(self.rows[i])
    end
end

---@param row Frame
function Feed:ApplyFont(row)
    local font = self.fonts and self.fonts.label
    if font and font.face then
        row.label:SetFont(font.face, font.size or 14)
    end
end

---@param height number
function Feed:SetViewportHeight(height)
    self.viewportHeight = math.max(height or 0, 1)
    self:Layout()
    if not self.historyMode then self:ScrollToBottom() end
end

--#endregion

--#region ── Content ───────────────────────────────────────────────────────────

function Feed:AcquireRow()
    local row = table.remove(self.rowPool)
    if not row then row = createRow(self.scrollChild) end
    row:SetParent(self.scrollChild)
    row._feed = self
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
    row._alpha = nil
    row.label:SetText('')
    row.label:SetTextColor(1, 1, 1, 1)
    row.icon:Hide()
    row.icon:SetTexture(nil)
    row.questIcon:Hide()
    row.questIcon:SetTexture(nil)
    row:Hide()
    row:ClearAllPoints()
    self.rowPool[#self.rowPool + 1] = row
end

--- Applies the presenter's styling to one row.
---@param row Frame
---@param entry LootEntry
function Feed:RenderRow(row, entry)
    row._entry = entry
    row._alpha = 1
    row:SetAlpha(1)

    local presented = self.presenter and self.presenter(entry) or nil
    if not presented then presented = { text = '' } end

    row.label:SetText(presented.text or '')
    self:ApplyFont(row)
    local text = presented.textColor
    row.label:SetTextColor(text and text[1] or 1, text and text[2] or 1, text and text[3] or 1, 1)

    local bg = presented.bg or { 0.1, 0.1, 0.1, 1 }
    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)

    local border = presented.border
    addon.Utils.apply_border_textures(row, row.border, true, 1,
        border and border[1] or 0.3, border and border[2] or 0.3, border and border[3] or 0.3, 1)

    local labelOffset = TEXT_PAD
    if presented.icon then
        row.icon:SetTexture(presented.icon)
        row.icon:Show()
        labelOffset = ICON_LEFT + ICON_SIZE + ICON_GAP
    else
        row.icon:Hide()
        row.icon:SetTexture(nil)
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
    row.label:SetPoint('RIGHT', row, 'RIGHT', -TEXT_PAD, 0)
end

--- Adds one entry below the existing rows.
---@param entry LootEntry
function Feed:Append(entry)
    local row = self:AcquireRow()
    self:RenderRow(row, entry)
    self.rows[#self.rows + 1] = row
    self:Layout()
end

--- Drops the oldest `count` rows (used when the session cap trims history).
---@param count number
function Feed:TrimFirst(count)
    for _ = 1, math.min(count, #self.rows) do
        local row = table.remove(self.rows, 1)
        if row then self:ReleaseRow(row) end
    end
    self:Layout()
end

--- Re-renders the whole list from `entries`, preserving the scroll position.
---@param entries LootEntry[]
function Feed:Rebuild(entries)
    local offset = self.scrollFrame:GetVerticalScroll() or 0
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
    local range = self.scrollFrame:GetVerticalScrollRange() or 0
    self.scrollFrame:SetVerticalScroll(math.min(offset, range))
    if self.onScrollChanged then self.onScrollChanged() end
end

function Feed:Clear()
    for i = #self.rows, 1, -1 do
        self:ReleaseRow(self.rows[i])
        self.rows[i] = nil
    end
    self:Layout()
    if self.onScrollChanged then self.onScrollChanged() end
end

--#endregion

--#region ── Layout ────────────────────────────────────────────────────────────

--- Stacks rows downward, bottom-anchored inside the viewport. When content is
--- shorter than the viewport the stack sits at the bottom.
function Feed:Layout()
    local count = #self.rows
    local contentHeight = count > 0 and (count * ROW_HEIGHT + (count - 1) * ROW_GAP) or 0
    local top = 0
    if contentHeight < self.viewportHeight then
        top = self.viewportHeight - contentHeight
    end

    for i = 1, count do
        local row = self.rows[i]
        local y = -(top + (i - 1) * (ROW_HEIGHT + ROW_GAP))
        row:ClearAllPoints()
        row:SetPoint('TOPLEFT', self.scrollChild, 'TOPLEFT', PADDING, y)
        row:SetPoint('TOPRIGHT', self.scrollChild, 'TOPRIGHT', -PADDING, y)
    end

    self.contentHeight = contentHeight
    -- The child is exactly as tall as the content (or the viewport when the
    -- content is shorter), so there is never a phantom scroll range.
    self.scrollChild:SetHeight(math.max(self.viewportHeight, contentHeight))
end

--#endregion

--#region ── Fading ────────────────────────────────────────────────────────────

--- Fades each row from its own receive timestamp. While the feed is hovered the
--- fade pauses (row timestamps are never rewritten); while history is being
--- browsed fading is disabled outright. Returns whether any row is visible.
---@param now number
---@param delay number
---@param enabled boolean
---@return boolean hasVisibleRows
function Feed:UpdateRowFade(now, delay, enabled)
    local hasVisibleRows = false
    for i = 1, #self.rows do
        local row = self.rows[i]
        local entry = row._entry
        local alpha = row._alpha or 1

        if not enabled then
            alpha = 1
        elseif type(entry) == 'table' and type(entry.timestamp) == 'number' then
            local target = 1
            local elapsed = now - entry.timestamp - delay
            if elapsed > 0 then target = math.max(1 - elapsed / FADE_TIME, 0) end
            if self.hovering then target = math.max(target, alpha) end
            alpha = target
        else
            alpha = 1
        end

        if row._alpha ~= alpha then
            row._alpha = alpha
            row:SetAlpha(alpha)
        end
        if alpha > 0 then hasVisibleRows = true end
    end
    return hasVisibleRows
end

--#endregion

--#region ── Scrolling ─────────────────────────────────────────────────────────

function Feed:IsAtBottom()
    local range = self.scrollFrame:GetVerticalScrollRange() or 0
    local offset = self.scrollFrame:GetVerticalScroll() or 0
    return offset >= (range - 1)
end

--- History mode persists after a reader scrolls upward, including when they
--- later reach the bottom. A new live entry explicitly resumes live mode.
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

--- Scrolls the viewport. A positive `upAmount` reveals older entries.
---@param upAmount number
function Feed:ScrollBy(upAmount)
    if upAmount > 0 and not self.historyMode then
        self.historyMode = true
        if self.onScrollChanged then self.onScrollChanged() end
    end
    local range = self.scrollFrame:GetVerticalScrollRange() or 0
    local offset = self.scrollFrame:GetVerticalScroll() or 0
    offset = math.max(0, math.min(range, offset - upAmount))
    self.scrollFrame:SetVerticalScroll(offset)
    if self.onScrollChanged then self.onScrollChanged() end
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

if addon then addon.LootFeedProto = Feed end
return Feed
