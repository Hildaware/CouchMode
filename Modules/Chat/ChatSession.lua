--[[ ChatSession.lua
The accepted-message session and its presentation queue.

Every message the router delivers is block-filtered, recorded in `session`, and
either displayed immediately or queued and paced. Filter changes and rebuilds go
through `Recompute`, which rebuilds groups via ChatGrouping and re-renders the
feed. `ChatMessage` is the router's subscriber entry point.
]]

local addonName, addon = ...

local chat = addon.Chat
local Sources = addon.ChatSources
local Grouping = addon.ChatGrouping
local Rules = addon.ChatRules

--#region ── Constants ────────────────────────────────────────────────────────

local QUEUE_SKIP_BUDGET = 50

--#endregion

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

--#region ── Blizzard General chat filtering ───────────────────────────────────

local messageGroupsByEvent

local function getMessageGroupsByEvent()
    if messageGroupsByEvent then return messageGroupsByEvent end

    messageGroupsByEvent = {}
    for group, events in pairs(ChatTypeGroup or {}) do
        for _, event in pairs(events) do
            local groups = messageGroupsByEvent[event]
            if not groups then
                groups = {}
                messageGroupsByEvent[event] = groups
            end
            groups[#groups + 1] = group
        end
    end
    return messageGroupsByEvent
end

local function generalChannelEnabled(frame, msg)
    local channels = frame.channelList
    if type(channels) ~= 'table' then return true end

    local base = msg.channelBase
    local zoneID = msg.zoneChannelID
    -- Channel notices without channel metadata cannot be matched to a setting.
    if not base and not zoneID then return true end
    if msg.event == 'CHAT_MSG_CHANNEL_NOTICE_USER'
        and Sources.isSafe(msg.text) and msg.text == 'INVITE' then
        return true
    end

    local uppercase = strupper or string.upper
    for index, name in pairs(channels) do
        if zoneID and frame.zoneChannelList and frame.zoneChannelList[index] == zoneID then
            return true
        end
        if base and type(name) == 'string' and uppercase(name) == uppercase(base) then
            return true
        end
    end
    return false
end

--- Read the General window's live message groups. Blizzard registers public
--- channels separately, so those also need the window's selected channel list.
--- This decision is made on receipt; changing a checkbox never rewrites history.
---@param msg ChatMessage
---@return boolean
function chat:IsEnabledInBlizzardGeneral(msg)
    local frame = _G.ChatFrame1
    if not frame or type(frame.ContainsMessageGroup) ~= 'function' then return true end

    local event = msg.event
    local isChannel = event == 'CHAT_MSG_CHANNEL' or event == 'CHAT_MSG_COMMUNITIES_CHANNEL'
    if not isChannel then
        local groups = getMessageGroupsByEvent()[event]
        if groups then
            for _, group in ipairs(groups) do
                if frame:ContainsMessageGroup(group) then
                    return true
                end
            end
            return false
        end
    end

    if isChannel or event == 'CHAT_MSG_CHANNEL_NOTICE'
        or event == 'CHAT_MSG_CHANNEL_NOTICE_USER' then
        return generalChannelEnabled(frame, msg)
    end
    return true
end

--#endregion

--#region ── State ─────────────────────────────────────────────────────────────

chat.session = {}         ---@type ChatMessage[] accepted this login
chat.groups = {}          ---@type ChatGroup[]
chat.lastGroup = nil      ---@type ChatGroup?
chat.lastVisible = nil    ---@type ChatMessage?

chat.messageQueue = {}
chat.messageQueueHead = 1
chat.messageQueueTail = 0
chat.messageQueueScheduled = false
chat.messageQueueToken = 0

--#endregion

--#region ── Session / routing ──────────────────────────────────────────────────

--- Enriches a message and applies local blocking rules.
--- Returns true when the message should be dropped entirely.
---@param msg ChatMessage
---@return boolean blocked
function chat:ApplyBlockFilter(msg)
    self:Enrich(msg)
    local unit = msg.unitToken or (msg.guid and self:ResolveUnit(msg)) or nil
    local guild = self:ResolveGuild(msg, unit)
    if Rules.IsBlocked(db().blocks, msg, guild) then
        msg.blocked = true
        return true
    end
    msg.guild = guild
    return false
end

function chat:ClearSession()
    self:ClearMessageQueue()
    wipe(self.session)
    self.groups = {}
    self.lastGroup = nil
    self.lastVisible = nil
    if self.feed then self.feed:Clear() end
    self:ClearHistoryView()
    if self.panel then
        self:ApplyLayout()
        self:OnFeedChanged()
    end
end

---@return boolean
function chat:HasQueuedMessages()
    return self.messageQueueHead <= self.messageQueueTail
end

--- Invalidates any pending timer callback without removing queued messages.
function chat:StopMessageQueue()
    self.messageQueueToken = self.messageQueueToken + 1
    self.messageQueueScheduled = false
end

--- Opens the next-message gate after the configured interval. The timer is also
--- kept when the queue is empty so synchronous event bursts are paced correctly.
--- Its token makes stale callbacks harmless after disabling, clearing, or
--- changing the pace setting.
---@param delay number?
function chat:ScheduleMessageQueue(delay)
    if self.messageQueueScheduled or not db().enabled then return end

    self.messageQueueScheduled = true
    self.messageQueueToken = self.messageQueueToken + 1
    local token = self.messageQueueToken
    C_Timer.After(math.max(delay or 0, 0), function()
        if token ~= chat.messageQueueToken then return end
        chat.messageQueueScheduled = false
        if not db().enabled or not chat:HasQueuedMessages() then return end
        chat:ProcessNextQueuedMessage()
    end)
end

--- Processes queued messages in order, pacing only messages that update the feed.
function chat:ProcessNextQueuedMessage()
    if not db().enabled or not self:HasQueuedMessages() then return end

    local displayed
    local processed = 0
    repeat
        local msg = self.messageQueue[self.messageQueueHead]
        self.messageQueue[self.messageQueueHead] = nil
        self.messageQueueHead = self.messageQueueHead + 1
        displayed = self:ProcessChatMessage(msg)
        processed = processed + 1
    until displayed or not self:HasQueuedMessages() or processed >= QUEUE_SKIP_BUDGET

    if not self:HasQueuedMessages() then
        self.messageQueue = {}
        self.messageQueueHead = 1
        self.messageQueueTail = 0
    end

    if displayed then
        self:ScheduleMessageQueue(db().messagePace or 0)
    elseif self:HasQueuedMessages() then
        self:ScheduleMessageQueue(0)
    end
end

--- Clears pending presentation work for an explicit user-requested history clear.
function chat:ClearMessageQueue()
    self:StopMessageQueue()
    self.messageQueue = {}
    self.messageQueueHead = 1
    self.messageQueueTail = 0
end

--- Reapplies a changed pace immediately to the existing backlog.
function chat:UpdateMessageQueuePace()
    if not self:HasQueuedMessages() and not self.messageQueueScheduled then return end
    self:StopMessageQueue()
    if self:HasQueuedMessages() then self:ScheduleMessageQueue(0) end
end

---@param msg ChatMessage
function chat:ChatMessage(msg)
    if not db().enabled then return end
    local toasts = addon.Toasts
    if not msg.synthetic and toasts and toasts.ShouldSuppressSystemMessageFromChat
        and toasts:ShouldSuppressSystemMessageFromChat(msg.event, msg.text) then
        return
    end
    if not self:IsEnabledInBlizzardGeneral(msg) then return end
    if self:ApplyBlockFilter(msg) then return end

    local wasEmpty = not self:HasQueuedMessages()
    self.messageQueueTail = self.messageQueueTail + 1
    self.messageQueue[self.messageQueueTail] = msg

    -- Show the first message immediately; only subsequent messages in a burst
    -- are paced. No queue-size limit or eviction is applied.
    if wasEmpty and not self.messageQueueScheduled then
        self:ProcessNextQueuedMessage()
    end
end

---@param msg ChatMessage
---@return boolean displayed
function chat:ProcessChatMessage(msg)
    -- Alerts (Talking Head suppression and similar) happen after blocking.
    msg.displayedAt = (type(GetTime) == 'function') and GetTime() or msg.timestamp
    self.session[#self.session + 1] = msg

    if not Sources.MatchesFilter(msg, db().filter) then
        return false
    end

    local followBottom = self.feed and not self.feed:IsBrowsingHistory()
    local historyFollowBottom = self:HistoryShouldFollowBottom()
    if self.lastVisible and Grouping.ShouldGroup(self.lastVisible, msg, db().groupWindow) and self.lastGroup then
        self.lastGroup.messages[#self.lastGroup.messages + 1] = msg
        if self.feed then self.feed:RefreshLastGroup(self.lastGroup, followBottom) end
        self:HistoryRefreshLastGroup(self.lastGroup, historyFollowBottom)
    else
        local group = { messages = { msg } }
        self.groups[#self.groups + 1] = group
        self.lastGroup = group
        if self.feed then self.feed:AppendGroup(group, followBottom) end
        self:HistoryAppendGroup(group, historyFollowBottom)
    end
    self.lastVisible = msg

    if self.feed then
        self:ApplyLayout()
        self:OnFeedChanged()
    end
    self:Touch()
    return true
end

function chat:Recompute()
    local preserveBrowse = self.feed and self.feed:IsBrowsingHistory()
    local previousOffset = preserveBrowse and self.feed:GetScrollOffset() or 0
    local previousContentHeight = preserveBrowse and self.feed:GetContentHeight() or 0
    local filtered = {}
    for i = 1, #self.session do
        local msg = self.session[i]
        if Sources.MatchesFilter(msg, db().filter) then
            filtered[#filtered + 1] = msg
        end
    end
    local groups = Grouping.Build(filtered, db().groupWindow)
    self.groups = groups
    self.lastGroup = groups[#groups]
    self.lastVisible = filtered[#filtered]
    self:RebuildHistoryView(groups)
    if self.feed then
        self.feed:SetFonts(self:FontMetrics())
        self.feed:SetCompactMode(db().compactMode)
        self.feed:Rebuild(groups)
        self.feed:UpdateMessageFade(
            (type(GetTime) == 'function') and GetTime() or 0,
            db().fadeDelay or 15, db().fadeEnabled == true
        )
        self:ApplyLayout()
        if preserveBrowse then
            local removedHeight = math.max(previousContentHeight - self.feed:GetContentHeight(), 0)
            self.feed:RestoreScrollOffset(math.max(previousOffset - removedHeight, 0))
        else
            self.feed:ScrollToBottom()
        end
    end
    self:OnFeedChanged()
end

function chat:OnFeedChanged()
    if not self.returnButton or not self.feed then return end
    if not self.feed:IsBrowsingHistory() then
        self.returnButton:Hide()
    else
        self.returnButton:Show()
    end
end

function chat:ScrollToBottom()
    if self:IsHistoryModeOpen() then
        self:HistoryToBottom()
        return
    end
    if self.feed then self.feed:ScrollToBottom() end
    self:OnFeedChanged()
    self:Touch()
end

--#endregion
