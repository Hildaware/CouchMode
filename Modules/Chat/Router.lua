--[[ Router.lua
The single owner of WoW chat event registration for CouchMode.

Every CHAT_MSG_* event is received once, normalized once (via ChatSources) and
dispatched to interested modules. This guarantees:
  * no duplicate event registrations across Chat and Chat Bubbles,
  * one place to dedupe messages by Blizzard lineID,
  * one place that decides whether NPC dialogue is displayed overhead or routes
    through to the scrolling Chat feed.
]]

local addonName, addon = ...
addon = addon or (LibStub and LibStub('AceAddon-3.0'):GetAddon(addonName))

local Sources = addon and addon.ChatSources
local M = {}

M.SEEN_LIMIT = 256

--#region ── Construction ──────────────────────────────────────────────────────

---@return table
function M.New()
    return setmetatable({
        subscribers = {},
        subscriberSet = {},
        bubbleHandler = nil,
        seen = {},
        seenOrder = {},
        seenCount = 0,
        frame = nil,
        registered = false,
        eventHandler = nil, -- overridable for tests
        blockCheck = nil,   -- fun(msg): boolean, set by the Chat module
        supportedEvents = nil, -- cached list of events this client understands
    }, { __index = M })
end

--#endregion

--#region ── Subscribers ────────────────────────────────────────────────────────

--- Registers a module that receives `module:ChatMessage(msg)` for every
--- non-overhead message. Modules are notified in registration order.
---@param module table
function M:Subscribe(module)
    if not module or self.subscriberSet[module] then return end
    self.subscriberSet[module] = true
    self.subscribers[#self.subscribers + 1] = module
    self:RefreshRegistration()
end

---@param module table
function M:Unsubscribe(module)
    if not module or not self.subscriberSet[module] then return end
    self.subscriberSet[module] = nil
    for i = #self.subscribers, 1, -1 do
        if self.subscribers[i] == module then
            table.remove(self.subscribers, i)
        end
    end
    self:RefreshRegistration()
end

--- Registers the module that can display NPC dialogue overhead. Only one such
--- handler may exist at a time.
---@param module table
function M:SetBubbleHandler(module)
    self.bubbleHandler = module
    self:RefreshRegistration()
end

---@param module table
function M:ClearBubbleHandler(module)
    if self.bubbleHandler == module then
        self.bubbleHandler = nil
        self:RefreshRegistration()
    end
end

--#endregion

--#region ── Registration ───────────────────────────────────────────────────────

---@return boolean
function M:NeedsEvents()
    if self.bubbleHandler then return true end
    for i = 1, #self.subscribers do
        local sub = self.subscribers[i]
        if not sub.IsSubscriberEnabled or sub:IsSubscriberEnabled() then return true end
    end
    return false
end

function M:EnsureFrame()
    if self.frame or type(CreateFrame) ~= 'function' then return end
    local frame = CreateFrame('Frame')
    frame:SetScript('OnEvent', function(_, event, ...)
        self:OnEvent(event, ...)
    end)
    self.frame = frame
end

--- Events this client can actually register for. Combines the flavor map in
--- ChatSources with the client's own event table so unknown/flavor-specific
--- events (e.g. CHAT_MSG_PARTY_GUIDE on WoW: Forever) are never registered.
---@return string[]
function M:SupportedEvents()
    if self.supportedEvents then return self.supportedEvents end
    local Utils = addon and addon.Utils
    local flavor = Utils and Utils.FLAVOR
    local out = {}
    for _, event in ipairs(Sources.EventsForFlavor(flavor)) do
        local exists = Utils and Utils.EventExists and Utils.EventExists(event)
        if exists ~= false then out[#out + 1] = event end
    end
    self.supportedEvents = out
    return out
end

--- Registers or unregisters the underlying frame based on whether any consumer
--- is currently enabled.
function M:RefreshRegistration()
    if not Sources then return end
    self:EnsureFrame()
    if not self.frame then return end

    local want = self:NeedsEvents()
    if want and not self.registered then
        for _, event in ipairs(self:SupportedEvents()) do
            if not self.frame:IsEventRegistered(event) then
                pcall(self.frame.RegisterEvent, self.frame, event)
            end
        end
        self.registered = true
    elseif not want and self.registered then
        for _, event in ipairs(self:SupportedEvents()) do
            if self.frame:IsEventRegistered(event) then
                pcall(self.frame.UnregisterEvent, self.frame, event)
            end
        end
        self.registered = false
    end
end

--#endregion

--#region ── Deduplication ──────────────────────────────────────────────────────

---@param msg ChatMessage
---@return boolean duplicate
function M:IsDuplicate(msg)
    local id = msg.lineID
    if not id then return false end
    if self.seen[id] then return true end
    self.seen[id] = true
    self.seenCount = self.seenCount + 1
    self.seenOrder[#self.seenOrder + 1] = id
    if #self.seenOrder > M.SEEN_LIMIT then
        local oldest = table.remove(self.seenOrder, 1)
        self.seen[oldest] = nil
    end
    return false
end

function M:ResetDedup()
    wipe(self.seen)
    wipe(self.seenOrder)
    self.seenCount = 0
end

--#endregion

--#region ── Dispatch ───────────────────────────────────────────────────────────

--- Delivers a normalized message to every enabled plain subscriber.
---@param msg ChatMessage
function M:DeliverChat(msg)
    for i = 1, #self.subscribers do
        local sub = self.subscribers[i]
        if not sub.IsSubscriberEnabled or sub:IsSubscriberEnabled() then
            if sub.ChatMessage then sub:ChatMessage(msg) end
        end
    end
end

--- Routes NPC dialogue through the overhead bubble handler when one is active,
--- falling back to the Chat feed according to the handler's configured mode.
---@param msg ChatMessage
function M:DispatchNpc(msg)
    local handler = self.bubbleHandler
    local mode = handler and handler.GetNpcMode and handler:GetNpcMode()

    if not mode then
        self:DeliverChat(msg)
        return
    end

    if mode == 'always' then
        -- Record immediately; the overhead replacement is best-effort.
        self:DeliverChat(msg)
        if handler.Attempt then handler:Attempt(msg, nil) end
        return
    end

    -- 'fallback': hold the Chat record until the bubble attempt resolves.
    if not handler.Attempt then
        self:DeliverChat(msg)
        return
    end
    handler:Attempt(msg, function(result)
        if result ~= 'displayed' then
            self:DeliverChat(msg)
        end
    end)
end

---@param msg ChatMessage
function M:Dispatch(msg)
    if Sources.IsNpc(msg.event) then
        self:DispatchNpc(msg)
    else
        self:DeliverChat(msg)
    end
end

--#endregion

--#region ── Event entry point ──────────────────────────────────────────────────

--- Normalizes and dispatches one raw Blizzard chat event.
--- `now`/`clock` are injectable so tests remain deterministic.
---@param event string
---@param ...
function M:OnEvent(event, ...)
    if not Sources or not Sources.CATEGORY_BY_EVENT[event] then return end

    local now = (type(GetTime) == 'function') and GetTime() or 0
    local clock = (type(date) == 'function') and date('%H:%M:%S') or ''

    local msg = Sources.Normalize(event, now, clock, ...)
    if not msg then return end
    if self:IsDuplicate(msg) then return end
    -- Locally blocked senders are dropped before alerts, grouping, filters and
    -- session history (including the overhead bubble path).
    if self.blockCheck and self.blockCheck(msg) then return end
    self:Dispatch(msg)
end

--- The shared router instance every module talks to. `M.New()` remains
--- available so tests can build isolated routers.
M.instance = M.New()
if addon then addon.ChatRouter = M.instance end
return M
