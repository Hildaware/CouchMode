--[[ ChatFeedLayout.lua
Pure layout policy for the scrolling Chat feed.

History keeps every presented message in arrival order. Live mode takes a
suffix of unfaded messages and trims older rows at message boundaries to fit
the available space.
]]

local addonName, addon = ...
local M = {}

local function messageAlpha(message)
    local alpha = message and message._chatFadeAlpha
    return type(alpha) == 'number' and alpha or 1
end

local function planHistory(groups, groupGap)
    local plan = {
        firstByGroup = {},
        displayed = {},
        contentHeight = 0,
    }
    local displayedCount = 0
    for i = 1, #groups do
        local group = groups[i]
        if (group.lastMessage or 0) > 0 then
            plan.firstByGroup[i] = 1
            plan.displayed[i] = true
            displayedCount = displayedCount + 1
            plan.contentHeight = plan.contentHeight + (group.heights[1] or 0)
            if displayedCount > 1 then plan.contentHeight = plan.contentHeight + groupGap end
        end
    end
    return plan
end

--- Builds a display plan for measured chat groups.
---@param groups table[] { lastMessage, heights, messages }
---@param groupGap number Vertical gap between displayed groups.
---@param options table? { history, maxMessages, maxContentHeight }
---@return table plan { firstByGroup, displayed, contentHeight, fitHeight, oversizedGroup }
function M.Plan(groups, groupGap, options)
    groupGap = groupGap or 0
    options = options or {}
    if options.history then return planHistory(groups, groupGap) end

    local plan = {
        firstByGroup = {},
        displayed = {},
        contentHeight = 0,
        fitHeight = 0,
    }
    local starts = {}
    local remainingMessages = math.max(1, math.floor(options.maxMessages or 6))

    -- Find the newest contiguous suffix that has not fully faded.
    for groupIndex = #groups, 1, -1 do
        local group = groups[groupIndex]
        local messages = group.messages or {}
        local first = #messages + 1
        while first > 1 and remainingMessages > 0 do
            if messageAlpha(messages[first - 1]) <= 0 then break end
            first = first - 1
            remainingMessages = remainingMessages - 1
        end
        if first <= #messages then starts[groupIndex] = first end
        if remainingMessages == 0 or first > 1 then break end
    end

    local available = math.max(0, options.maxContentHeight or math.huge)
    local remainingHeight = available
    local hasNewerGroup = false
    local selectedAny = false

    -- Fit from the newest end so a partial grouped row always drops older
    -- messages and keeps the most recent complete message visible.
    for groupIndex = #groups, 1, -1 do
        local firstAllowed = starts[groupIndex]
        if firstAllowed then
            local group = groups[groupIndex]
            local newest = #group.messages
            local groupGapCost = hasNewerGroup and groupGap or 0
            local groupRoom = math.max(0, remainingHeight - groupGapCost)
            local chosenFirst

            for first = newest, firstAllowed, -1 do
                local height = group.heights[first] or 0
                if height <= groupRoom then
                    chosenFirst = first
                else
                    -- Only clip when the latest single message cannot fit by
                    -- itself. An older row never displaces a newer message.
                    if not selectedAny and first == newest and height > 0 then
                        chosenFirst = newest
                        plan.oversizedGroup = groupIndex
                        plan.fitHeight = available
                        plan.contentHeight = height
                        plan.firstByGroup[groupIndex] = newest
                        plan.displayed[groupIndex] = true
                        return plan
                    end
                    break
                end
            end

            if chosenFirst then
                local height = group.heights[chosenFirst] or 0
                plan.firstByGroup[groupIndex] = chosenFirst
                plan.displayed[groupIndex] = true
                plan.contentHeight = plan.contentHeight + height + groupGapCost
                plan.fitHeight = plan.fitHeight + height + groupGapCost
                remainingHeight = math.max(0, remainingHeight - height - groupGapCost)
                selectedAny = true
                hasNewerGroup = true
                -- If an older message in this group did not fit, no still
                -- older group can fit without displacing a newer message.
                if chosenFirst > firstAllowed then break end
            else
                break
            end
        end
    end

    return plan
end

if addon then addon.ChatFeedLayout = M end
return M
