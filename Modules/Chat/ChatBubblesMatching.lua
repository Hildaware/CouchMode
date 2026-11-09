local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local bubbles = addon:GetModule('ChatBubbles')
local isSecret = addon.Utils.IsSecretValue

local POLL_INTERVAL = .1
local MATCH_TIMEOUT = 1
local pending = {}
local states = {}
local replacements = setmetatable({}, { __mode = 'k' })
local ticker

local function accessible(frame)
    if not frame then return false end
    local forbidden = frame:IsForbidden()
    return not isSecret(forbidden) and not forbidden
end

local function fontText(region)
    if not accessible(region) or region:GetObjectType() ~= 'FontString' then return end
    local text = region:GetText()
    if isSecret(text) then return end
    if type(text) == 'string' and text ~= '' then return text end
end

local function regionText(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        local text = fontText(region)
        if text then return text end
    end
end

local function bubbleText(frame)
    if not accessible(frame) then return end
    -- Retail's template exposes String directly; older clients use child frames.
    local text = fontText(frame.String) or regionText(frame)
    if text then return text end
    for _, child in ipairs({ frame:GetChildren() }) do
        if accessible(child) and not replacements[child] then
            text = fontText(child.String) or regionText(child)
            if text then return text end
        end
    end
end

local function observe(frame)
    local state = states[frame]
    if not state then
        state = {}
        states[frame] = state
        -- One permanent hook per native frame; ownership is looked up at call time.
        frame:HookScript('OnHide', function()
            state.text, state.consumed = nil, nil
            if state.owner then bubbles:RemoveChatBubble(state.owner, true) end
        end)
    end
    return state
end

function bubbles:SnapshotNativeBubbles()
    if not C_ChatBubbles or not C_ChatBubbles.GetAllChatBubbles
        or (InCombatLockdown and InCombatLockdown()) then return end
    for _, frame in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
        if accessible(frame) and frame:IsShown() then
            local state = observe(frame)
            state.text, state.consumed = bubbleText(frame), true
            state.changedAt = GetTime()
        end
    end
end

function bubbles:ReleaseNativeBubble(bubble)
    local state = bubble.nativeState
    if not state then return end
    if state.owner == bubble then
        state.owner = nil
        for region, alpha in pairs(state.alphas or {}) do
            if accessible(region) then region:SetAlpha(alpha) end
        end
        state.alphas = nil
    end
    bubble.nativeState, bubble.nativeFrame = nil, nil
end

function bubbles:ClaimNativeBubble(bubble, frame, state)
    state.owner, state.consumed, state.alphas = bubble, true, {}
    bubble.nativeFrame, bubble.nativeState = frame, state
    replacements[bubble.widget] = true
    -- Preserve the frame's own alpha so native distance/fade behavior still applies.
    local function suppress(region)
        if accessible(region) and region ~= bubble.widget then
            state.alphas[region] = region:GetAlpha()
            region:SetAlpha(0)
        end
    end
    for _, region in ipairs({ frame:GetRegions() }) do suppress(region) end
    for _, child in ipairs({ frame:GetChildren() }) do suppress(child) end
end

function bubbles:CancelBubbleSearches()
    local cancelled = pending
    pending = {}
    if ticker then ticker:Cancel(); ticker = nil end
    for request in pairs(cancelled) do request.finish('interrupted') end
end

function bubbles:ScanBubbles()
    if not self:IsEnabled() or not self:GetNpcMode() then
        self:CancelBubbleSearches()
        for i = #self.active, 1, -1 do self:RemoveChatBubble(self.active[i], true) end
        return
    end

    local candidates, visible = {}, {}
    if not (InCombatLockdown and InCombatLockdown()) then
        for _, frame in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
            if accessible(frame) and frame:IsShown() then
                visible[frame] = true
                local state = observe(frame)
                local text = bubbleText(frame)
                if state.text ~= text then
                    if state.owner then self:RemoveChatBubble(state.owner, true) end
                    state.text, state.consumed = text, nil
                    state.changedAt = GetTime()
                end
                if text and not state.consumed then
                    local list = candidates[text] or {}
                    candidates[text] = list
                    list[#list + 1] = { frame = frame, state = state }
                end
            end
        end
    end

    -- Remove vanished, forbidden, or changed native frames before assigning new owners.
    for i = #self.active, 1, -1 do
        local bubble = self.active[i]
        if not visible[bubble.nativeFrame] then
            self:RemoveChatBubble(bubble, true)
        elseif not bubble.released then
            self:ApplyBubblePosition(bubble)
        end
    end

    local byText = {}
    for request in pairs(pending) do
        local text = request.msg.text
        local list = byText[text] or {}
        byText[text] = list
        list[#list + 1] = request
    end
    for text, requests in pairs(byText) do
        local matches = {}
        for _, match in ipairs(candidates[text] or {}) do
            -- A line observed well before this event must not be claimed again.
            if match.state.changedAt >= requests[1].startedAt - POLL_INTERVAL * 2 then
                matches[#matches + 1] = match
            end
        end
        local ambiguous = #requests > 1 or #matches > 1
        if ambiguous then
            -- Do not let a later event claim an ambiguous, still-visible line.
            for _, match in ipairs(matches) do match.state.consumed = true end
        end
        for _, request in ipairs(requests) do
            if ambiguous or self:ShouldFallBack(request.msg) then
                pending[request] = nil
                request.finish('failed')
            elseif #matches == 1 then
                pending[request] = nil
                local match = matches[1]
                self:ShowMatchedBubble(request, match.frame, match.state)
            elseif GetTime() >= request.deadline then
                pending[request] = nil
                request.finish('failed')
            end
        end
    end

    if not next(pending) and #self.active == 0 and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function bubbles:QueueBubbleSearch(msg, finish)
    local now = GetTime()
    local request = { msg = msg, finish = finish, startedAt = now, deadline = now + MATCH_TIMEOUT }
    pending[request] = true
    if not ticker then
        -- Defer the first scan to collect simultaneous events before choosing a match.
        ticker = C_Timer.NewTicker(POLL_INTERVAL, function() self:ScanBubbles() end)
    end
end
