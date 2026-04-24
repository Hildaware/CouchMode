local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class NameplatesModule: AceModule
local nameplates = addon:GetModule('Nameplates')
---@cast nameplates +AceEvent-3.0

--#region ── Plate constants ──────────────────────────────────────────────────

local DIMMED_SCALE = 0.6

local THREAT_COLOR_WARNING = { 0.9, 0.15, 0.15 }
local THREAT_COLOR_TRANSITION = { 1.0, 0.65, 0.2 }
local THREAT_COLOR_SAFE = { 0.25, 0.5, 0.9 }
local THREAT_COLOR_OFFTANK = { 0.5, 0.75, 1.0 }

local PLAYER_CLASS = select(2, UnitClass("player"))
local playerIsDK = (PLAYER_CLASS == "DEATHKNIGHT")

-- Shared table reference set by NameplatesFrame.lua — mutations are visible here.
local active = nameplates.active
local inCombat = UnitAffectingCombat("player") == true
nameplates.inCombat = inCombat

--#endregion

--#region ── Unit queries ─────────────────────────────────────────────────────

-- Returns true when the unit is actively fighting the player specifically:
-- either targeting the player, or the player has threat on it (has hit/healed).
local function isEngagedWithPlayer(unit)
    if nameplates.isInInstance() then return true end
    if UnitIsUnit(unit .. "target", "player") then return true end
    return UnitThreatSituation("player", unit) ~= nil
end

local function isSelected(unit)
    return UnitIsUnit(unit, "target")
        or UnitIsUnit(unit, "softenemy")
        or UnitIsUnit(unit, "softfriend")
        or UnitIsUnit(unit, "softinteract")
end
nameplates.isSelected = isSelected

local function getLayoutType(unit)
    local PlateType = nameplates.PlateType
    if UnitIsPlayer(unit) then return PlateType.NameOnly end
    if not UnitCanAttack("player", unit) then return PlateType.NameOnly end
    if UnitIsUnit(unit, "target") then return PlateType.Full end
    if inCombat and isEngagedWithPlayer(unit) then return PlateType.Full end
    return PlateType.NameOnly
end

--#endregion

--#region ── Per-frame updates ────────────────────────────────────────────────

local function updateAlpha(f, unit)
    local dimmed = inCombat
        and not isSelected(unit)
        and UnitCanAttack("player", unit)
    f:SetAlpha(dimmed and 0.5 or 1.0)
end

local function updateElite(f, unit)
    if not nameplates.shouldShowName(unit) then
        f.elite:Hide()
        return
    end
    local c = UnitClassification(unit)
    if c == "elite" or c == "worldboss" then
        f.elite:SetAtlas("nameplates-icon-elite-gold")
        f.elite:Show()
    elseif c == "rareelite" or c == "rare" then
        f.elite:SetAtlas("nameplates-icon-rareelite")
        f.elite:Show()
    else
        f.elite:Hide()
    end
end

local function updateMark(f, unit)
    local index = GetRaidTargetIndex(unit)
    if index then
        SetRaidTargetIconTexture(f.mark, index)
        f.mark:Show()
    else
        f.mark:Hide()
    end
end

local function updateRoleIcon(f, unit)
    if UnitIsUnit(unit, "softinteract") then
        local hasIcon = SetUnitCursorTexture(f.roleIcon, unit)
        f.roleIcon:SetShown(hasIcon)
    else
        f.roleIcon:Hide()
    end
end

local function updateBarColor(f, unit)
    -- Priority 1: class color for players
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS[class]
        if c then
            f.bar.fill:SetStatusBarColor(c.r, c.g, c.b)
            return
        end
    end

    -- Priority 2: threat level
    local threat = UnitThreatSituation("player", unit)
    if threat ~= nil then
        local tank = UnitGroupRolesAssigned("player") == "TANK"
        local otherTankAggro = IsInRaid() and UnitGroupRolesAssigned(unit .. "target") == "TANK"
        local tc
        if (tank and threat <= 0 and not otherTankAggro) or (not tank and threat == 3) then
            tc = THREAT_COLOR_WARNING
        elseif threat == 1 or threat == 2 then
            tc = THREAT_COLOR_TRANSITION
        elseif tank and threat <= 0 and otherTankAggro then
            tc = THREAT_COLOR_OFFTANK
        else -- tank threat==3, or DPS threat==0
            tc = THREAT_COLOR_SAFE
        end
        f.bar.fill:SetStatusBarColor(tc[1], tc[2], tc[3])
        return
    end

    -- Default: safe blue
    f.bar.fill:SetStatusBarColor(THREAT_COLOR_SAFE[1], THREAT_COLOR_SAFE[2], THREAT_COLOR_SAFE[3])
end

local function updateHealth(f, unit)
    UnitGetDetailedHealPrediction(unit, nil, f.bar._calc)

    f.bar._calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
    local max = f.bar._calc:GetMaximumHealth()
    local absorbs = f.bar._calc:GetDamageAbsorbs()
    f.bar.absorb:SetMinMaxValues(0, max)
    f.bar.absorb:SetValue(absorbs)

    f.bar._calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
    local hp = f.bar._calc:GetCurrentHealth()
    f.bar.fill:SetMinMaxValues(0, max, Enum.StatusBarInterpolation.ExponentialEaseOut)
    f.bar.fill:SetValue(hp, Enum.StatusBarInterpolation.ExponentialEaseOut)
end

local function setShadow(fs, enabled)
    if enabled then
        addon.Utils.apply_font_shadow(fs)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function applyFrameShadow(f, enabled)
    setShadow(f.name, enabled)
    setShadow(f.guild, enabled)
    if f.cast and f.cast.spellName then setShadow(f.cast.spellName, enabled) end
    if f.auras then
        for i = 1, nameplates.AURA_MAX do
            local icon = f.auras.icons[i]
            if icon then
                if icon.count then setShadow(icon.count, enabled) end
                if icon.timer then setShadow(icon.timer, enabled) end
            end
        end
    end
    if f.cc and f.cc.timer then setShadow(f.cc.timer, enabled) end
end

local function applyFontToAll()
    local shadow = addon.db.profile.nameplates.shadowEnabled
    for _, f in pairs(active) do
        f.name:SetFont(nameplates.currentFont())
        f.guild:SetFont(nameplates.currentGuildFont())
        applyFrameShadow(f, shadow)
    end
end

local function applyShadowToAll()
    local shadow = addon.db.profile.nameplates.shadowEnabled
    for _, f in pairs(active) do
        applyFrameShadow(f, shadow)
    end
end

nameplates.applyFontToAll = applyFontToAll
nameplates.applyShadowToAll = applyShadowToAll

--#endregion

--#region ── Plate orchestration ──────────────────────────────────────────────

local function refreshBar(f, unitToken)
    local PlateType = nameplates.PlateType
    local plateType = getLayoutType(unitToken)
    f.bar:SetShown(plateType == PlateType.Full)
    nameplates.applyLayout(f, plateType)
    nameplates.applyName(f, unitToken, plateType)
    if plateType == PlateType.Full then
        updateBarColor(f, unitToken)
        updateHealth(f, unitToken)
        nameplates.updateCast(f, unitToken)
        nameplates.refreshAuras(f, unitToken)
        nameplates.refreshCC(f, unitToken)
        nameplates.updatePower(f, unitToken)
        f.roleIcon:Hide()
    else
        nameplates.hideCast(f)
        nameplates.hideAuras(f)
        nameplates.hideCC(f)
        nameplates.hidePower(f)
        updateRoleIcon(f, unitToken)
    end
end

local function showPlate(unitToken, np)
    local f = active[unitToken]
    if not f then
        f = nameplates.acquire()
        active[unitToken] = f
    end

    f:SetParent(np) -- inherit np's alpha so occlusion applies automatically
    f:SetScale(isSelected(unitToken) and 1.0 or DIMMED_SCALE)
    f:SetFrameStrata(isSelected(unitToken) and "HIGH" or "MEDIUM")
    updateAlpha(f, unitToken)
    f:SetPoint("CENTER", np.UnitFrame, "CENTER")
    f.unitFrame = np.UnitFrame
    nameplates.lockUnitFrame(np.UnitFrame)

    f.name:SetFont(nameplates.currentFont())
    local hasQuest = nameplates.isQuestUnit(unitToken)
    f.questIcon:SetShown(hasQuest)
    f.name:SetShown(nameplates.shouldShowName(unitToken) or hasQuest)
    nameplates.applyGuild(f, unitToken)
    nameplates.applyMusicIcon(f, unitToken)
    updateMark(f, unitToken)
    updateElite(f, unitToken)
    refreshBar(f, unitToken)
    f:Show()
end

local function hidePlate(unitToken)
    local f = active[unitToken]
    if not f then return end
    active[unitToken] = nil
    nameplates.unlockUnitFrame(f.unitFrame)
    f.unitFrame = nil
    nameplates.release(f)
end

local function refreshAll()
    for unitToken, f in pairs(active) do
        f:SetScale(isSelected(unitToken) and 1.0 or DIMMED_SCALE)
        f:SetFrameStrata(isSelected(unitToken) and "HIGH" or "MEDIUM")
        updateAlpha(f, unitToken)
        f.name:SetShown(nameplates.shouldShowName(unitToken) or f.questIcon:IsShown())
        nameplates.applyGuild(f, unitToken)
        nameplates.applyMusicIcon(f, unitToken)
        updateMark(f, unitToken)
        updateElite(f, unitToken)
        refreshBar(f, unitToken) -- also calls applyName
    end
end

local function applyFriendlyVisibility()
    if nameplates.isInInstance() then
        SetCVar("nameplateShowFriendlyPlayers", 0)
        SetCVar("nameplateShowFriendlyNPCs", 0)
        SetCVar("UnitNameFriendlyPlayerName", 1)
    else
        SetCVar("nameplateShowFriendlyPlayers", 1)
        SetCVar("nameplateShowFriendlyNPCs", 1)
        SetCVar("UnitNameFriendlyPlayerName", 0)
    end
end

--#endregion

--#region ── Module lifecycle ─────────────────────────────────────────────────

function nameplates:OnEnable()
    if not addon.db.profile.nameplates.enabled then
        self:Disable()
        return
    end

    SetCVar("nameplateSelectedScale", 1.0)
    SetCVar("nameplateOccludedAlphaMult", addon.db.profile.nameplates.occludedAlpha)
    applyFriendlyVisibility()
    if not nameplates._trpCallbackRegistered then
        nameplates._trpCallbackRegistered = true
        addon.TRPUtils.registerDataUpdatedCallback(function()
            if nameplates:IsEnabled() then refreshAll() end
        end)
    end
    if not nameplates._musicianCallbackRegistered then
        nameplates._musicianCallbackRegistered = true
        self:RegisterMessage("MusicianSongPlay", function() if nameplates:IsEnabled() then refreshAll() end end)
        self:RegisterMessage("MusicianSongStop", function() if nameplates:IsEnabled() then refreshAll() end end)
    end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnUnitAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnUnitRemoved")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnInteractionChanged")
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "OnInteractionChanged")
    self:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED", "OnInteractionChanged")
    self:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED", "OnInteractionChanged")
    self:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", "OnInteractionChanged")
    self:RegisterEvent("RAID_TARGET_UPDATE", "OnRaidTargetUpdate")
    self:RegisterEvent("QUEST_LOG_UPDATE", "OnQuestLogUpdate")
    self:RegisterEvent("UNIT_HEALTH", "OnUnitHealth")
    self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", "OnUnitHealth")
    self:RegisterEvent("UNIT_NAME_UPDATE", "OnNameUpdate")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChanged")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChanged")
    self:RegisterEvent("UNIT_SPELLCAST_START", "OnCastStart")
    self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED", "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "OnCastStart")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "OnCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_DELAYED", "OnCastStart")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "OnCastStart")
    self:RegisterEvent("UNIT_CLASSIFICATION_CHANGED", "OnClassificationChanged")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function() nameplates.rebuildPartyGUIDs() end)
    nameplates.rebuildPartyGUIDs()
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("UNIT_TARGET", "OnUnitEngagement")
    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", "OnUnitEngagement")
    self:RegisterEvent("UNIT_POWER_FREQUENT", "OnPlayerPower")
    self:RegisterEvent("UNIT_DISPLAYPOWER", "OnPlayerPower")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnPlayerPower")
    if playerIsDK then
        self:RegisterEvent("RUNE_POWER_UPDATE", "OnPlayerPower")
    end

    for _, np in pairs(C_NamePlate.GetNamePlates()) do
        ---@diagnostic disable-next-line: undefined-field
        local unit = np.UnitFrame and np.UnitFrame.unit
        if unit then showPlate(unit, np) end
    end
end

function nameplates:OnEnteringWorld()
    applyFriendlyVisibility()
end

function nameplates:OnUnitAdded(_, unitToken)
    local np = C_NamePlate.GetNamePlateForUnit(unitToken)
    if np then showPlate(unitToken, np) end
end

function nameplates:OnUnitRemoved(_, unitToken)
    hidePlate(unitToken)
end

function nameplates:OnInteractionChanged()
    refreshAll()
end

function nameplates:OnCombatChanged(event)
    inCombat = (event == "PLAYER_REGEN_DISABLED")
    nameplates.inCombat = inCombat

    if addon.db.profile.nameplates.disableSoftTargetFriendInCombat then
        if inCombat then
            nameplates._softTargetFriendSaved = GetCVar('SoftTargetFriend')
            SetCVar('SoftTargetFriend', 0)
        elseif nameplates._softTargetFriendSaved then
            SetCVar('SoftTargetFriend', nameplates._softTargetFriendSaved)
            nameplates._softTargetFriendSaved = nil
        end
    end

    refreshAll()
end

function nameplates:OnRaidTargetUpdate()
    for unitToken, f in pairs(active) do
        updateMark(f, unitToken)
    end
end

function nameplates:OnQuestLogUpdate()
    nameplates.wipeQuestCache()
    -- Instead of a full refresh, just update quest-related visuals.
    for unitToken, f in pairs(active) do
        local hasQuest = nameplates.isQuestUnit(unitToken)
        f.questIcon:SetShown(hasQuest)
        f.name:SetShown(nameplates.shouldShowName(unitToken) or hasQuest)
    end
end

function nameplates:OnUnitHealth(_, unitToken)
    local f = active[unitToken]
    if f and f.bar:IsShown() then updateHealth(f, unitToken) end
end

function nameplates:OnClassificationChanged(_, unitToken)
    local f = active[unitToken]
    if f then updateElite(f, unitToken) end
end

function nameplates:OnUnitAura(_, unitToken)
    local f = active[unitToken]
    if f and f.bar:IsShown() then
        nameplates.refreshAuras(f, unitToken)
        nameplates.refreshCC(f, unitToken)
    end
end

-- Fires when a unit changes target (UNIT_TARGET) or threat shifts (UNIT_THREAT_SITUATION_UPDATE).
-- Both indicate the unit's engagement state with the player may have changed.
function nameplates:OnUnitEngagement(_, unitToken)
    if not inCombat then return end
    local f = active[unitToken]
    if f then refreshBar(f, unitToken) end
end

function nameplates:OnCastStart(_, unitToken)
    local f = active[unitToken]
    if f and f.bar:IsShown() then nameplates.updateCast(f, unitToken) end
end

function nameplates:OnCastStop(_, unitToken)
    local f = active[unitToken]
    if f then nameplates.hideCast(f) end
end

function nameplates:OnPlayerPower()
    local np = C_NamePlate.GetNamePlateForUnit("target")
    if np then
        ---@diagnostic disable-next-line: undefined-field
        local unitToken = np.UnitFrame and np.UnitFrame.unit
        if unitToken then
            local f = active[unitToken]
            if f and f.bar:IsShown() then
                nameplates.updatePower(f, unitToken)
            end
        end
    end
end

function nameplates:OnNameUpdate(_, unitToken)
    local f = active[unitToken]
    if f then
        nameplates.applyName(f, unitToken, getLayoutType(unitToken))
        nameplates.applyGuild(f, unitToken)
        nameplates.applyMusicIcon(f, unitToken)
    end
end

function nameplates:OnDisable()
    SetCVar("nameplateSelectedScale", 1.2)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
    self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
    self:UnregisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
    self:UnregisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
    self:UnregisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
    self:UnregisterEvent("RAID_TARGET_UPDATE")
    self:UnregisterEvent("QUEST_LOG_UPDATE")
    self:UnregisterEvent("UNIT_HEALTH")
    self:UnregisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    self:UnregisterEvent("UNIT_NAME_UPDATE")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("UNIT_SPELLCAST_START")
    self:UnregisterEvent("UNIT_SPELLCAST_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_FAILED")
    self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    self:UnregisterEvent("UNIT_SPELLCAST_DELAYED")
    self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    self:UnregisterEvent("UNIT_CLASSIFICATION_CHANGED")
    self:UnregisterEvent("UNIT_AURA")
    self:UnregisterEvent("UNIT_TARGET")
    self:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    self:UnregisterEvent("UNIT_POWER_FREQUENT")
    self:UnregisterEvent("UNIT_DISPLAYPOWER")
    self:UnregisterEvent("PLAYER_TALENT_UPDATE")
    if playerIsDK then self:UnregisterEvent("RUNE_POWER_UPDATE") end

    for _, f in pairs(active) do
        nameplates.unlockUnitFrame(f.unitFrame)
        f.unitFrame = nil
        nameplates.release(f)
    end
    wipe(active)
    nameplates.wipeQuestCache()
end

--#endregion

--#region ── Debug ────────────────────────────────────────────────────────────

local debugFrame

function nameplates.debugShow()
    if debugFrame then nameplates.debugHide() end

    debugFrame = nameplates.acquire()
    debugFrame:SetScale(1.0)
    debugFrame:SetAlpha(1.0)
    debugFrame:SetPoint("CENTER", UIParent, "CENTER")
    debugFrame:Show()

    debugFrame.name:SetFont(nameplates.currentFont())
    debugFrame.name:SetText("Rare Elite Dragon")
    debugFrame.name:Show()
    debugFrame.guild:SetText("<Dragon Guild>")
    debugFrame.guild:Show()
    debugFrame.questIcon:Show()

    debugFrame.bar:Show()
    debugFrame.bar.fill:SetStatusBarColor(0.9, 0.1, 0.1)
    debugFrame.bar.fill:SetMinMaxValues(0, 100)
    debugFrame.bar.fill:SetValue(65)
    nameplates.applyLayout(debugFrame, nameplates.PlateType.Full)

    SetRaidTargetIconTexture(debugFrame.mark, 8)
    debugFrame.mark:Show()

    debugFrame.elite:SetAtlas("nameplates-icon-elite-gold")
    debugFrame.elite:Show()

    local PIP_W, PIP_GAP, PIP_MAX = nameplates.PIP_W, nameplates.PIP_GAP, nameplates.PIP_MAX
    local maxPower, current = 5, 3
    debugFrame.power:SetWidth(maxPower * PIP_W + (maxPower - 1) * PIP_GAP)
    for i = 1, PIP_MAX do
        local pip = debugFrame.power.pips[i]
        if i <= maxPower then
            pip:Show()
            if i <= current then
                pip.tex:Show()
                pip.tex:SetVertexColor(1, 0.5, 0, 1)
            else
                pip.tex:Hide()
            end
        else
            pip:Hide()
        end
    end
    debugFrame.power:Show()

    debugFrame.cast.fill:SetStatusBarColor(0.9, 0.6, 0.1) -- interruptible cast colour
    debugFrame.cast.fill:SetMinMaxValues(0, 100)
    debugFrame.cast.fill:SetValue(60)
    debugFrame.cast.spellName:SetFont(nameplates.currentCastFont())
    debugFrame.cast.spellName:SetText("Pyroblast")
    debugFrame.cast.spellName:Show()
    debugFrame.cast.shield:SetAlpha(0)
    debugFrame.cast:Show()
end

function nameplates.debugHide()
    if not debugFrame then return end
    nameplates.release(debugFrame)
    debugFrame = nil
end

--#endregion
