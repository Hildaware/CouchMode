--[[ ChatFeedLayout.lua
Pure admission policy for the scrolling Chat feed.

Each group supplies its measured height for every possible first displayed
message, both with and without a leading divider. Live mode keeps the newest
complete suffix that fits; history mode admits everything.
]]

local addonName, addon = ...
local M = {}

--- Builds a display plan for measured chat groups.
---@param groups table[] { firstEligible, lastMessage, plainHeights, dividedHeights }
---@param budget number Maximum content height in live mode.
---@param history boolean Whether every retained message should be displayed.
---@param groupGap number Vertical gap between displayed groups.
---@return table plan { firstByGroup, displayed, contentHeight }
function M.Plan(groups, budget, history, groupGap)
    local plan = {
        firstByGroup = {},
        displayed = {},
        contentHeight = 0,
    }
    groupGap = groupGap or 0

    if history then
        local displayedCount = 0
        for i = 1, #groups do
            local group = groups[i]
            if (group.lastMessage or 0) > 0 then
                local first = 1
                plan.firstByGroup[i] = first
                plan.displayed[i] = true
                displayedCount = displayedCount + 1
                local heights = displayedCount == 1 and group.plainHeights or group.dividedHeights
                plan.contentHeight = plan.contentHeight + (heights[first] or 0)
                if displayedCount > 1 then
                    plan.contentHeight = plan.contentHeight + groupGap
                end
            end
        end
        return plan
    end

    budget = math.max(budget or 0, 0)
    local selectedMessages = 0
    local oldestSelectedGroup

    for groupIndex = #groups, 1, -1 do
        local group = groups[groupIndex]
        local firstEligible = group.firstEligible
        local lastMessage = group.lastMessage or 0
        if firstEligible and firstEligible <= lastMessage then
            for messageIndex = lastMessage, firstEligible, -1 do
                local candidateHeight
                if plan.displayed[groupIndex] then
                    local previousFirst = plan.firstByGroup[groupIndex]
                    candidateHeight = plan.contentHeight
                        - (group.plainHeights[previousFirst] or 0)
                        + (group.plainHeights[messageIndex] or 0)
                elseif selectedMessages == 0 then
                    candidateHeight = group.plainHeights[messageIndex] or 0
                else
                    local previousOldest = groups[oldestSelectedGroup]
                    local previousFirst = plan.firstByGroup[oldestSelectedGroup]
                    candidateHeight = plan.contentHeight
                        - (previousOldest.plainHeights[previousFirst] or 0)
                        + (previousOldest.dividedHeights[previousFirst] or 0)
                        + groupGap
                        + (group.plainHeights[messageIndex] or 0)
                end

                -- The newest message is always admitted. This is the single
                -- soft-cap exception for a message taller than the live limit.
                if selectedMessages > 0 and candidateHeight > budget then
                    return plan
                end

                plan.displayed[groupIndex] = true
                plan.firstByGroup[groupIndex] = messageIndex
                plan.contentHeight = candidateHeight
                selectedMessages = selectedMessages + 1
                oldestSelectedGroup = groupIndex
            end
        end
    end

    return plan
end

if addon then addon.ChatFeedLayout = M end
return M
