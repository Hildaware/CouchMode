local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class BanterModule
local banter = addon:GetModule('Banter')

--#region ── Constants ────────────────────────────────────────────────────────

local WINDOW_HEIGHT = 520
local PADDING = 8
local BANT_GAP = 6
local FILTER_BTN_W = 72
local FILTER_BTN_H = 22
local FILTER_BAR_H = FILTER_BTN_H + PADDING * 2
-- BasicFrameTemplateWithInset chrome offsets
local CHROME_TOP = 28 -- title bar height
local CHROME_SIDE = 6
local CHROME_BOTTOM = 6
local SCROLLBAR_W = 22 -- UIPanelScrollFrameTemplate scroll bar width
local HEADER_H    = 20
local HEADER_GAP  = 4

local FILTERS = { 'all', 'npc', 'whisper', 'say', 'party', 'instance', 'raid' }

local FILTER_LABELS = {
    all = 'All',
    npc = 'NPC',
    whisper = 'Whisper',
    say = 'Say',
    party = 'Party',
    instance = 'Instance',
    raid = 'Raid',
}

--#endregion

--#region ── State ────────────────────────────────────────────────────────────

local window = nil ---@type Frame
local scrollFrame = nil ---@type ScrollFrame
local scrollChild = nil ---@type Frame
local filterBtns = {} ---@type table<string, Button>
local historyBants  = {} ---@type BanterContainerMain[]
local headerPool    = {} ---@type Frame[]
local headerFrames  = {} ---@type Frame[]
local activeFilter  = 'all'

--#endregion

--#region ── Filter ───────────────────────────────────────────────────────────

---@param data BanterData
local function matchesFilter(data)
    if activeFilter == 'all' then return true end
    if activeFilter == 'npc' then return data.type:find('^CHAT_MSG_MONSTER_') ~= nil end
    if activeFilter == 'whisper' then return data.channel == 'WHISPER' end
    if activeFilter == 'say' then return data.channel == 'SAY' end
    if activeFilter == 'party' then return data.channel == 'PARTY' end
    if activeFilter == 'instance' then return data.channel == 'INSTANCE' end
    if activeFilter == 'raid' then return data.channel == 'RAID' end
    return false
end

--#endregion

--#region ── Filter bar styling ───────────────────────────────────────────────

local function refreshFilterBtns()
    for filter, btn in pairs(filterBtns) do
        if filter == activeFilter then
            btn:GetFontString():SetTextColor(1, 1, 1, 1)
            btn:LockHighlight()
        else
            btn:GetFontString():SetTextColor(0.55, 0.55, 0.55, 1)
            btn:UnlockHighlight()
        end
    end
end

--#endregion

--#region ── Header pool ──────────────────────────────────────────────────────

local function acquireHeader()
    local frame = table.remove(headerPool)
    if not frame then
        frame = CreateFrame('Frame', nil, UIParent)
        frame:SetHeight(HEADER_H)

        local label = frame:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
        label:SetJustifyH('CENTER')
        label:SetPoint('TOP', frame, 'TOP', 0, -3)
        label:SetPoint('LEFT', frame, 'LEFT')
        label:SetPoint('RIGHT', frame, 'RIGHT')
        frame.label = label

        local divider = frame:CreateTexture(nil, 'ARTWORK')
        divider:SetColorTexture(1, 1, 1, 0.12)
        divider:SetHeight(1)
        divider:SetPoint('BOTTOMLEFT',  frame, 'BOTTOMLEFT')
        divider:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT')
    end
    return frame
end

local function releaseHeader(frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    headerPool[#headerPool + 1] = frame
end

--#endregion

--#region ── Rebuild ──────────────────────────────────────────────────────────

local function releaseAll()
    for i = #historyBants, 1, -1 do
        banter:Release(table.remove(historyBants, i))
    end
    for i = #headerFrames, 1, -1 do
        releaseHeader(table.remove(headerFrames, i))
    end
end

local function positionBants()
    local yOffset = PADDING
    for i = 1, #historyBants do
        local h = headerFrames[i]
        if h then
            h:ClearAllPoints()
            h:SetPoint('TOP', scrollChild, 'TOP', 0, -yOffset)
            yOffset = yOffset + HEADER_H + HEADER_GAP
        end
        local b = historyBants[i]
        b.widget:ClearAllPoints()
        b.widget:SetPoint('TOP', scrollChild, 'TOP', 0, -yOffset)
        yOffset = yOffset + b.widget:GetHeight() + BANT_GAP
    end
    scrollChild:SetHeight(math.max(yOffset + PADDING, 1))
end

local function Rebuild()
    releaseAll()

    local filtered = {}
    for i = 1, #banter.history do
        if matchesFilter(banter.history[i]) then
            filtered[#filtered + 1] = banter.history[i]
        end
    end

    local itemWidth = addon.db.profile.banter.itemWidth
    for i = 1, #filtered do
        local data = filtered[i]

        local b = banter:BuildHistoryBant(data)
        b.widget:SetParent(scrollChild)
        b.widget:Show()
        historyBants[#historyBants + 1] = b

        local h = acquireHeader()
        h:SetParent(scrollChild)
        h:SetWidth(itemWidth)
        h.label:SetText(data.timestamp or '')
        h:Show()
        headerFrames[#headerFrames + 1] = h
    end

    positionBants()
end

--#endregion

--#region ── Window construction ──────────────────────────────────────────────

local function buildWindow()
    local itemWidth = addon.db.profile.banter.itemWidth
    -- scrollbar lives outside the scroll frame so we need room for it
    local contentW = (itemWidth * 1.75) + (PADDING * 2)
    local winWidth = CHROME_SIDE * 2 + contentW + SCROLLBAR_W

    window = CreateFrame('Frame', 'CouchModeBanterHistory', UIParent, 'BasicFrameTemplateWithInset')
    window:SetSize(winWidth, WINDOW_HEIGHT)
    window:SetPoint('CENTER')
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:SetFrameStrata('DIALOG')
    window:EnableMouse(true)
    window:RegisterForDrag('LeftButton')
    window:SetScript('OnDragStart', window.StartMoving)
    window:SetScript('OnDragStop', window.StopMovingOrSizing)
    window:Hide()

    window.TitleText:SetText('Banter History')

    -- Filter bar sits directly below the title bar
    local filterBar = CreateFrame('Frame', nil, window)
    filterBar:SetPoint('TOPLEFT', window, 'TOPLEFT', CHROME_SIDE, -CHROME_TOP)
    filterBar:SetPoint('TOPRIGHT', window, 'TOPRIGHT', -CHROME_SIDE, -CHROME_TOP)
    filterBar:SetHeight(FILTER_BAR_H)

    local FILTER_BTN_GAP = 4
    local totalGroupW = #FILTERS * FILTER_BTN_W + (#FILTERS - 1) * FILTER_BTN_GAP
    local prevBtn = nil
    for _, filter in ipairs(FILTERS) do
        local btn = CreateFrame('Button', nil, filterBar, 'UIPanelButtonTemplate')
        btn:SetSize(FILTER_BTN_W, FILTER_BTN_H)
        btn:SetText(FILTER_LABELS[filter])

        if prevBtn then
            btn:SetPoint('LEFT', prevBtn, 'RIGHT', FILTER_BTN_GAP, 0)
        else
            btn:SetPoint('LEFT', filterBar, 'CENTER', -(totalGroupW / 2), 0)
        end
        btn:SetPoint('TOP', filterBar, 'TOP', 0, -PADDING)

        btn:SetScript('OnClick', function()
            activeFilter = filter
            refreshFilterBtns()
            Rebuild()
        end)

        filterBtns[filter] = btn
        prevBtn = btn
    end

    -- Scroll frame fills the rest of the window below the filter bar
    scrollFrame = CreateFrame('ScrollFrame', nil, window, 'UIPanelScrollFrameTemplate')
    scrollFrame:SetPoint('TOPLEFT',
        window, 'TOPLEFT',
        CHROME_SIDE, -(CHROME_TOP + FILTER_BAR_H))
    scrollFrame:SetPoint('BOTTOMRIGHT',
        window, 'BOTTOMRIGHT',
        -(CHROME_SIDE + SCROLLBAR_W), CHROME_BOTTOM)

    scrollChild = CreateFrame('Frame', nil, scrollFrame)
    scrollChild:SetSize(contentW, 1)
    scrollFrame:SetScrollChild(scrollChild)

    refreshFilterBtns()
end

--#endregion

--#region ── Public API ───────────────────────────────────────────────────────

addon.BanterHistory = {}

function addon.BanterHistory:Open()
    if not window then buildWindow() end
    Rebuild()
    window:Show()
end

function addon.BanterHistory:Close()
    if not window then return end
    releaseAll()
    window:Hide()
end

function addon.BanterHistory:Toggle()
    if window and window:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

--#endregion
