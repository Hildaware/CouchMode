--[[ ChatFeedLayout.lua
Pure layout policy for the scrolling Chat feed.

Every retained message keeps its place in the scroll content. Expired rows are
hidden by opacity, so revealing history never changes the scroll geometry.
]]

local addonName, addon = ...
local M = {}

--- Builds a display plan for measured chat groups.
---@param groups table[] { lastMessage, heights }
---@param groupGap number Vertical gap between displayed groups.
---@return table plan { firstByGroup, displayed, contentHeight }
function M.Plan(groups, groupGap)
    local plan = {
        firstByGroup = {},
        displayed = {},
        contentHeight = 0,
    }
    groupGap = groupGap or 0

    local displayedCount = 0
    for i = 1, #groups do
        local group = groups[i]
        if (group.lastMessage or 0) > 0 then
            plan.firstByGroup[i] = 1
            plan.displayed[i] = true
            displayedCount = displayedCount + 1
            plan.contentHeight = plan.contentHeight + (group.heights[1] or 0)
            if displayedCount > 1 then
                plan.contentHeight = plan.contentHeight + groupGap
            end
        end
    end
    return plan
end

if addon then addon.ChatFeedLayout = M end
return M
