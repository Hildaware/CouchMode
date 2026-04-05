local addonName, core = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

--#region ── Quest Utils ──────────────────────────────────────────────────────

-- Cache per GUID: { isObjective = bool, quests = {{title, objectives[]},...}|nil }
-- nil entry = not yet scanned
local questCache = {}

local function isQuestColor(color)
    -- Quest gold is approx NORMAL_FONT_COLOR: (1, 0.82, 0)
    return color and color.r >= 0.9 and color.g >= 0.6 and color.b <= 0.1
end

local function scanGUID(guid, unit)
    local guidType    = guid:match("^(%a+)-")
    local tooltipData
    if guidType == "GameObject" then
        tooltipData = unit and C_TooltipInfo.GetUnit(unit)
    else
        tooltipData = C_TooltipInfo.GetHyperlink("unit:" .. guid)
    end
    if not tooltipData then
        questCache[guid] = { isObjective = false, quests = nil }
        return
    end

    local isObjective  = false
    local quests       = {}
    local currentQuest = nil

    local lines = tooltipData.lines or {}
    for i = 2, #lines do
        local line = lines[i]
        if line.type == Enum.TooltipDataLineType.QuestObjective then
            local text = line.leftText or ""
            local finished = false
            local p1, p2 = text:match("(%d+)/(%d+)")
            if p1 and p2 then
                finished = tonumber(p1) >= tonumber(p2)
            else
                local pct = text:match("(%d+)%%")
                if pct then finished = tonumber(pct) >= 100 end
                -- no numbers = interact/speak objective, treat as incomplete
            end
            if not finished then isObjective = true end
            -- Attach objective to the current quest entry
            if not currentQuest then
                currentQuest = { title = nil, objectives = {} }
                quests[#quests + 1] = currentQuest
            end
            currentQuest.objectives[#currentQuest.objectives + 1] = { text = text, finished = finished }
        elseif line.leftText and line.leftText ~= "" and isQuestColor(line.leftColor) then
            currentQuest = { title = line.leftText, objectives = {} }
            quests[#quests + 1] = currentQuest
        end
    end

    -- Only keep entries that have at least one objective (unit is actually involved)
    local filtered = {}
    for _, q in ipairs(quests) do
        if #q.objectives > 0 then
            filtered[#filtered + 1] = q
        end
    end

    questCache[guid] = {
        isObjective = isObjective,
        quests      = #filtered > 0 and filtered or nil,
    }
end

local function getEntry(unit)
    local _, instanceType = IsInInstance()
    if instanceType ~= "none" then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    if not questCache[guid] then scanGUID(guid, unit) end
    return questCache[guid]
end

addon.QuestUtils = {
    --- Returns true if the unit is an incomplete quest objective.
    isQuestUnit = function(unit)
        local entry = getEntry(unit)
        return entry and entry.isObjective or false
    end,

    --- Returns an array of { title, objectives[] } for quests this unit is involved in, or nil.
    getQuestData = function(unit)
        local entry = getEntry(unit)
        return entry and entry.quests or nil
    end,

    --- Wipe the shared cache (call on zone change, quest log update, etc.)
    wipeCache = function()
        wipe(questCache)
    end,
}

--#endregion
