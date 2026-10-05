local addonName, addon = ...

---@class CouchMode: AceAddon
---@field ToastSources table
---@field ToastFeedProto table
---@field ToastMock table
---@field Toasts ToastsModule
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class ToastsModule: AceModule
---@field HandleCommand fun(self: ToastsModule, sub: string, arg: string)
local toasts = addon:NewModule('Toasts', 'AceEvent-3.0')
addon.Toasts = toasts

local Sources = addon.ToastSources

-- Constants shared by the module's split implementation files.
toasts.PANEL_ORDER = 12
toasts.DEFAULT_MAX_ITEMS = 15
toasts.MAX_ITEMS_LIMIT = 20
toasts.DEFAULT_WIDTH = 360
toasts.FADE_DELAY_DESC = 'Maximum seconds a toast remains visible before fading. Toast type and item quality use shorter weighted durations.'
toasts.QUEST_ICON_ATLAS = 'QuestNormal'
local PRESENTATION_PACE = 0.35

--#region ── Module state ──────────────────────────────────────────────────────

toasts.presentationQueue = {}
toasts.presentationQueueHead = 1
toasts.presentationQueueTail = 0
toasts.presentationQueueScheduled = false
toasts.presentationQueueToken = 0
toasts.lastMoney = nil    ---@type number?
toasts.panel = nil        ---@type Frame?
toasts.feed = nil
toasts.fadeAlpha = 1
toasts.refreshPending = false
toasts.filters = nil      ---@type { event: string, callback: fun(...) }[]?
toasts.filtersInstalled = false
toasts.pendingAppearanceIcons = {}

--#endregion

local function db() return addon.db.profile.toasts end
local function now() return (type(GetTime) == 'function') and GetTime() or 0 end

--#region ── Lifecycle ─────────────────────────────────────────────────────────

function toasts:OnInitialize()
    addon.Toasts = self
end

--- Registers an event only when the running client defines it.
---@param event string
---@param handler string|fun(...)
---@return boolean registered
function toasts:RegisterValidEvent(event, handler)
    return addon.Utils.RegisterEventIfValid(self, event, handler)
end

function toasts:HasQueuedEntries()
    return self.presentationQueueHead <= self.presentationQueueTail
end

function toasts:StopPresentationQueue()
    self.presentationQueueToken = self.presentationQueueToken + 1
    self.presentationQueueScheduled = false
end

function toasts:SchedulePresentationQueue(delay)
    if self.presentationQueueScheduled or not db().enabled then return end

    self.presentationQueueScheduled = true
    self.presentationQueueToken = self.presentationQueueToken + 1
    local token = self.presentationQueueToken
    C_Timer.After(math.max(delay or 0, 0), function()
        if token ~= toasts.presentationQueueToken then return end
        toasts.presentationQueueScheduled = false
        if not db().enabled or not toasts:HasQueuedEntries() then return end
        toasts:ProcessNextQueuedEntry()
    end)
end

function toasts:ProcessNextQueuedEntry()
    if not db().enabled or not self:HasQueuedEntries() then return end

    if self.feed then
        local hidden = self.panel and not self.panel:IsShown()
        local removed = self.feed:RemoveExpiredRows(now(), hidden)
        if removed > 0 then self:ApplyLayout() end
        local maxItems = math.max(1, math.floor(db().maxItems or self.DEFAULT_MAX_ITEMS))
        if #self.feed.rows >= maxItems then
            self:SchedulePresentationQueue(0.25)
            return
        end
    end

    local entry
    entry = self.presentationQueue[self.presentationQueueHead]
    self.presentationQueue[self.presentationQueueHead] = nil
    self.presentationQueueHead = self.presentationQueueHead + 1

    if not self:HasQueuedEntries() then
        self.presentationQueue = {}
        self.presentationQueueHead = 1
        self.presentationQueueTail = 0
    end

    if entry then
        entry.displayedAt = now()
        if self.feed then
            self.feed:Append(entry)
            self:ApplyLayout()
        end
        self:Touch()
    end

    if entry then
        self:SchedulePresentationQueue(PRESENTATION_PACE)
    end
end

function toasts:ClearPresentationQueue()
    self:StopPresentationQueue()
    self.presentationQueue = {}
    self.presentationQueueHead = 1
    self.presentationQueueTail = 0
end

function toasts:OnEnable()
    if not db().enabled then
        self:Disable()
        return
    end

    self:BuildPanel()
    self:SnapshotMoney()
    self:InstallChatFilters()

    for _, event in ipairs(Sources.SUPPORT_EVENTS) do
        local handler = self.EVENT_HANDLERS[event]
        if handler then
            self:RegisterValidEvent(event, handler)
        end
    end

    self:Touch()
    if self:HasQueuedEntries() then self:SchedulePresentationQueue(0) end
end

function toasts:OnDisable()
    self:ClearPresentationQueue()
    for _, event in ipairs(Sources.SUPPORT_EVENTS) do
        self:UnregisterEvent(event)
    end
    self:RemoveChatFilters()
    if self.feed then
        self.feed:Clear()
        self:ApplyLayout()
    end
    if self.panel then self.panel:Hide() end
end

--#endregion


toasts:Enable()
