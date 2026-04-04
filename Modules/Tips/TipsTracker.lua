local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips       = addon:GetModule('Tips')
---@cast tips +AceEvent-3.0

--#region ── Unit priority ────────────────────────────────────────────────────

local function getCurrentUnit()
    if UnitExists("mouseover") and not UnitIsUnit("mouseover", "player") then
        return "mouseover"
    end
    if UnitExists("softenemy") then return "softenemy" end
    if UnitExists("softfriend") then return "softfriend" end
    if UnitExists("softinteract") then return "softinteract" end
    if UnitExists("target") and not UnitIsUnit("target", "player") then
        return "target"
    end
    return nil
end

--#endregion

--#region ── Show / hide ───────────────────────────────────────────────────────

local currentUnit = nil

local function fadeInFrame(f)
    f:SetAlpha(0)
    f:Show()
    UIFrameFadeIn(f, 0.25, 0, 1)
end

local function showTip(unit)
    local f     = tips.activeFrame
    local isNew = (f == nil)
    if isNew then
        f = tips.acquire()
        tips.activeFrame = f
    end
    currentUnit = unit
    -- Request inspect for players so spec data can populate asynchronously.
    if UnitIsPlayer(unit) and addon.TipsUtils then
        addon.TipsUtils.requestInspect(unit)
    end
    tips.updateFrame(f, unit)
    if isNew then fadeInFrame(f) end
end

local function hideTip()
    if tips.activeFrame then
        local f = tips.activeFrame
        tips.activeFrame = nil
        currentUnit = nil
        UIFrameFadeOut(f, 0.25, f:GetAlpha(), 0)
        C_Timer.After(0.25, function()
            tips.release(f)
        end)
    end
end

local function refreshTip()
    local unit = getCurrentUnit()
    if unit then
        showTip(unit)
    else
        hideTip()
    end
end

--#endregion

--#region ── Module lifecycle ─────────────────────────────────────────────────

local tooltipHooked = false

function tips:OnEnable()
    -- Suppress the native GameTooltip when it's showing a unit.
    -- Guard with a flag so we don't double-hook on re-enable.
    if not tooltipHooked then
        tooltipHooked = true
        GameTooltip:HookScript("OnShow", function(self)
            if self:GetUnit() then self:Hide() end
        end)
    end

    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "OnInteractionChanged")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnInteractionChanged")
    self:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED", "OnInteractionChanged")
    self:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED", "OnInteractionChanged")
    self:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", "OnInteractionChanged")
    self:RegisterEvent("WORLD_CURSOR_TOOLTIP_UPDATE", "OnWorldCursorUpdate")
    self:RegisterEvent("UNIT_NAME_UPDATE", "OnUnitNameUpdate")
    self:RegisterEvent("PLAYER_GUILD_UPDATE", "OnGuildUpdate")
    self:RegisterEvent("INSPECT_READY", "OnInspectReady")

    refreshTip()
end

function tips:OnDisable()
    self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    self:UnregisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
    self:UnregisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
    self:UnregisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
    self:UnregisterEvent("WORLD_CURSOR_TOOLTIP_UPDATE")
    self:UnregisterEvent("UNIT_NAME_UPDATE")
    self:UnregisterEvent("PLAYER_GUILD_UPDATE")
    self:UnregisterEvent("INSPECT_READY")
    hideTip()
end

function tips:OnInteractionChanged()
    refreshTip()
end

function tips:OnWorldCursorUpdate(_, anchorType)
    if anchorType == Enum.WorldCursorAnchorType.None then
        if not getCurrentUnit() then hideTip() end
        return
    end
    local tooltipData = C_TooltipInfo.GetWorldCursor()
    if not tooltipData or not tooltipData.lines or #tooltipData.lines == 0 then
        if not getCurrentUnit() then hideTip() end
        return
    end
    local name = tooltipData.lines[1].leftText
    if not name or name == "" then return end

    -- Parse quest titles and objectives from the remaining lines
    local quests       = {}
    local currentQuest = nil
    for i = 2, #tooltipData.lines do
        local line = tooltipData.lines[i]
        local text = line.leftText
        if text and text ~= "" then
            if line.type == Enum.TooltipDataLineType.QuestObjective then
                local finished = false
                local p1, p2   = text:match("(%d+)/(%d+)")
                if p1 and p2 then
                    finished = tonumber(p1) >= tonumber(p2)
                else
                    local pct = text:match("(%d+)%%")
                    if pct then finished = tonumber(pct) >= 100 end
                end
                if currentQuest then
                    currentQuest.objectives[#currentQuest.objectives + 1] = { text = text, finished = finished }
                end
            else
                currentQuest = { title = text, objectives = {} }
                quests[#quests + 1] = currentQuest
            end
        end
    end

    local f     = tips.activeFrame
    local isNew = (f == nil)
    if isNew then
        f = tips.acquire()
        tips.activeFrame = f
    end
    currentUnit = nil
    tips.updateFrameForObject(f, name, #quests > 0 and quests or nil)
    if isNew then fadeInFrame(f) end
    GameTooltip:Hide()
end

function tips:OnUnitNameUpdate(_, unitToken)
    if currentUnit and UnitIsUnit(unitToken, currentUnit) then
        tips.wipeSubtitleCache()
        showTip(currentUnit)
    end
end

function tips:OnGuildUpdate(_, unitToken)
    if currentUnit and unitToken and UnitIsUnit(unitToken, currentUnit) then
        showTip(currentUnit)
    end
end

-- Fires when inspect data becomes available — cache it, then refresh if it's the current unit.
function tips:OnInspectReady(_, guid)
    if addon.TipsUtils then
        local unit = currentUnit
        if unit and UnitGUID(unit) == guid then
            addon.TipsUtils.onInspectReady(guid, unit)
            showTip(unit)
        end
    end
end

--#endregion

tips:Enable()
