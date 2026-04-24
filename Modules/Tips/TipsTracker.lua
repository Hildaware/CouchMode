local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)
local LibEditMode = LibStub('LibEditMode')

---@class TipsModule: AceModule
local tips = addon:GetModule('Tips')
---@cast tips +AceEvent-3.0

--#region ── Unit priority ────────────────────────────────────────────────────

local function isFriendlyNpc(unit)
    return not UnitIsPlayer(unit) and not UnitCanAttack("player", unit)
end

local function isEnemyNpc(unit)
    return not UnitIsPlayer(unit) and UnitCanAttack("player", unit)
end

local function getCurrentUnit()
    local db = tips.tipsDB()
    local showFriendlyNpcs = db.showFriendlyNpcs
    local showEnemyNpcs = db.showEnemyNpcs
    local alwaysShowQuestObjectiveTips = db.alwaysShowQuestObjectiveTips
    local alwaysShowImportant = db.alwaysShowImportant
    local function allow(unit)
        local wouldHide = (not showFriendlyNpcs and isFriendlyNpc(unit))
            or (not showEnemyNpcs and isEnemyNpc(unit))
        if wouldHide then
            if alwaysShowQuestObjectiveTips and addon.QuestUtils.isQuestUnit(unit) then
                return true
            end
            if alwaysShowImportant and not UnitIsPlayer(unit) then
                local class = UnitClassification(unit)
                if class == "rare" or class == "rareelite" then return true end
            end
            return false
        end
        return true
    end

    if UnitExists("mouseover") and not UnitIsUnit("mouseover", "player") then
        if allow("mouseover") then return "mouseover" end
    end
    if UnitExists("softenemy") and allow("softenemy") then return "softenemy" end
    if UnitExists("softfriend") and allow("softfriend") then return "softfriend" end
    if UnitExists("softinteract") and allow("softinteract") then return "softinteract" end
    if UnitExists("target") and not UnitIsUnit("target", "player") then
        if allow("target") then return "target" end
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
    local f = tips.activeFrame
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
    if not tips.tipsDB().enabled then
        self:Disable(); return
    end

    tips.TIP_W = tips.tipsDB().width or 240
    if not tips._trpCallbackRegistered then
        tips._trpCallbackRegistered = true
        addon.TRPUtils.registerDataUpdatedCallback(function()
            if tips:IsEnabled() and currentUnit and tips.activeFrame then
                tips.updateFrame(tips.activeFrame, currentUnit)
            end
        end)
    end
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

    -- Initialize LibEditMode frame if not already done
    if not tips.editModeFrame then
        local f = CreateFrame('Frame', 'CouchModeTipsAnchor', UIParent)
        f:SetSize(tips.TIP_W + 4, 180)
        f:Hide()
        tips.editModeFrame = f

        LibEditMode:AddFrame(tips.editModeFrame, function(_, layoutName, point, x, y)
            tips.tipsDB().positions[layoutName] = { point = point, x = x, y = y }
        end, { point = 'TOPLEFT', x = 0, y = -400 }, 'CouchMode Tips')

        --     tips.tipsDB().positions = tips.tipsDB().positions or {}
        --     tips.tipsDB().positions[layoutName] = { point = point, x = x, y = y }
        --     if tips.activeFrame then
        --         tips.applyAnchor(tips.activeFrame)
        --     end
        -- end, { point = 'TOP', x = 0, y = -200 }, 'CouchMode Tips')

        LibEditMode:AddFrameSettings(tips.editModeFrame, {
            {
                kind = LibEditMode.SettingType.Slider,
                name = 'Width',
                desc = 'Width of the tooltip frame in pixels.',
                default = 240,
                minValue = 120,
                maxValue = 500,
                valueStep = 10,
                get = function(_) return tips.tipsDB().width end,
                set = function(_, value, fromReset)
                    tips.tipsDB().width = fromReset and 240 or value
                    tips.applyWidth()
                end,
            },
        })

        LibEditMode:RegisterCallback('layout', function(layoutName)
            local pos = tips.tipsDB().positions[layoutName]
            tips.editModeFrame:ClearAllPoints()
            if pos then
                tips.editModeFrame:SetPoint(pos.point, pos.x, pos.y)
            else
                tips.editModeFrame:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', 0, -400)
            end
        end)

        LibEditMode:RegisterCallback('enter', function()
            tips.editModeFrame:Show()
            if tips.activeFrame then
                tips.activeFrame:Show()
            end
        end)

        LibEditMode:RegisterCallback('exit', function()
            tips.editModeFrame:Hide()
        end)
    end

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
        C_Timer.After(0, refreshTip)
        return
    end
    local tooltipData = C_TooltipInfo.GetWorldCursor()
    if not tooltipData or not tooltipData.lines or #tooltipData.lines == 0 then
        refreshTip()
        return
    end
    local name = tooltipData.lines[1].leftText
    if not name then return end

    -- Tooltip text is a secret string in instances; pattern matching on it is forbidden there.
    local _, instanceType = IsInInstance()
    local quests = nil
    if instanceType == "none" then
        quests = {}
        local currentQuest = nil
        for i = 2, #tooltipData.lines do
            local line = tooltipData.lines[i]
            local text = line.leftText
            if text and text ~= "" then
                if line.type == Enum.TooltipDataLineType.QuestObjective then
                    local finished = false
                    local p1, p2 = text:match("(%d+)/(%d+)")
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
        if #quests == 0 then quests = nil end
    end

    local f = tips.activeFrame
    local isNew = (f == nil)
    if isNew then
        f = tips.acquire()
        tips.activeFrame = f
    end
    currentUnit = nil
    tips.updateFrameForObject(f, name, quests)
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
        local unitGUID = unit and UnitGUID(unit)
        if unitGUID and not issecretvalue(unitGUID) and unitGUID == guid then
            addon.TipsUtils.onInspectReady(guid, unit)
            showTip(unit)
        end
    end
end

--#endregion

tips:Enable()
