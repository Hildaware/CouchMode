local addon_name     = ...

---@class ConsoleTools: AceAddon
local addon          = LibStub('AceAddon-3.0'):GetAddon(addon_name)
local LSM            = LibStub('LibSharedMedia-3.0')

---@class NameplatesModule: AceModule
local nameplates     = addon:NewModule('Nameplates', 'AceEvent-3.0')
---@cast nameplates +AceEvent-3.0

--#region ── Constants ────────────────────────────────────────────────────────

local BAR_W          = 160
local BAR_H          = 14
local CAST_W         = math.floor(BAR_W * 2 / 3)
local CAST_H         = 10
local AURA_W         = 24
local AURA_H         = 16
local AURA_GAP       = 4
local AURA_MAX       = 8
local PIP_W          = 12
local PIP_H          = 12
local PIP_GAP        = 1
local PIP_MAX        = 10

local BAR_TEX        = "Interface\\Addons\\ConsoleTools\\Media\\basic_bar.tga"
local SELECTED_SCALE = 1.25

local PlateType = { Full = 1, NameOnly = 2 }
nameplates.PlateType = PlateType

-- Exposed so sub-modules can reference the same values.
nameplates.BAR_W     = BAR_W
nameplates.BAR_H     = BAR_H
nameplates.CAST_W    = CAST_W
nameplates.CAST_H    = CAST_H
nameplates.AURA_W    = AURA_W
nameplates.AURA_H    = AURA_H
nameplates.AURA_GAP  = AURA_GAP
nameplates.AURA_MAX  = AURA_MAX
nameplates.PIP_W     = PIP_W
nameplates.PIP_H     = PIP_H
nameplates.PIP_GAP   = PIP_GAP
nameplates.PIP_MAX   = PIP_MAX
nameplates.BAR_TEX   = BAR_TEX
nameplates.addon     = addon

local PLAYER_CLASS   = select(2, UnitClass("player"))
local playerIsDK     = (PLAYER_CLASS == "DEATHKNIGHT")

local FONT_FLAGS     = {
    ['']             = 'None',
    ['OUTLINE']      = 'Outline',
    ['THICKOUTLINE'] = 'Thick Outline',
    ['MONOCHROME']   = 'Monochrome',
}

local function npDB() return addon.db.profile.nameplates end

local function currentFont()
    local db = npDB()
    return LSM:Fetch(LSM.MediaType.FONT, db.font) or "Fonts\\ARIALN.TTF", db.fontSize, db.fontFlag
end

local function currentGuildFont()
    local path, size, flag = currentFont()
    return path, math.max(8, size - 4), flag
end

local function currentCastFont()
    local path, size, flag = currentFont()
    return path, math.max(8, size - 8), flag
end

nameplates.currentFont      = currentFont
nameplates.currentGuildFont = currentGuildFont
nameplates.currentCastFont  = currentCastFont

--#endregion

--#region ── Frame pool ───────────────────────────────────────────────────────

local pool                  = {}
local active                = {} -- [unitToken] = frame
local hookedUFs             = {} -- [UnitFrame] = true; tracks frames with the alpha lock hook

local function lockUnitFrame(uf)
    if uf:IsForbidden() then return end
    uf:SetAlpha(0)
    if hookedUFs[uf] then return end
    hookedUFs[uf] = true
    local locking = false
    hooksecurefunc(uf, "SetAlpha", function(frame)
        if locking or frame:IsForbidden() or not hookedUFs[frame] then return end
        locking = true
        frame:SetAlpha(0)
        locking = false
    end)
end

local function unlockUnitFrame(uf)
    if not uf or uf:IsForbidden() then return end
    hookedUFs[uf] = nil
    uf:SetAlpha(1)
end

local function buildFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    f:SetIgnoreParentScale(true)

    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetSize(BAR_W, BAR_H)
    f.bar:SetPoint("TOP", f, "TOP", 0, 0)
    f.bar:Hide()
    f.bar:SetAlpha(0.6)

    local barBg = f.bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture(BAR_TEX)
    barBg:SetVertexColor(0, 0, 0, 1)
    barBg:SetAllPoints(f.bar)

    f.bar.fill = CreateFrame("StatusBar", nil, f.bar)
    f.bar.fill:SetAllPoints(f.bar)
    f.bar.fill:SetStatusBarTexture(BAR_TEX)

    do
        local b = addon.Utils.create_border_textures(f.bar.fill, f.bar)
        addon.Utils.apply_border_textures(f.bar, b, true, 1, 0, 0, 0, 1)
    end

    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(f.bar:GetFrameLevel() + 15)

    nameplates.buildCastFrame(f, overlay)
    nameplates.buildAurasFrame(f)
    nameplates.buildPowerFrame(f)
    nameplates.buildNameFrame(f, overlay)

    f.mark = overlay:CreateTexture(nil, "OVERLAY")
    f.mark:SetSize(24, 24)
    f.mark:SetTexture("Interface/TargetingFrame/UI-RaidTargetingIcons")
    f.mark:Hide()

    return f
end

local function acquire()
    local f = table.remove(pool) or buildFrame()
    f:SetParent(UIParent)
    f:ClearAllPoints()
    return f
end

local function release(f)
    f:SetAlpha(1.0)
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(nil)
    f.name:SetText("")
    f.questIcon:Hide()
    f.mark:Hide()
    f.guild:SetText("")
    f.guild:Hide()
    f.bar:Hide()
    f.cast:Hide()
    f.cast.endMS = nil
    f.cast.spellName:SetText("")
    f.cast.spellName:Hide()
    f.cast.shield:Hide()
    nameplates.hideAuras(f)
    nameplates.hideCC(f)
    nameplates.hidePower(f)
    pool[#pool + 1] = f
end

--#endregion

--#region ── Plate logic ──────────────────────────────────────────────────────

local inCombat = UnitAffectingCombat("player") == true
nameplates.inCombat = inCombat

-- Returns true when the unit is actively fighting the player specifically:
-- either targeting the player, or the player has threat on it (has hit/healed).
local function isEngagedWithPlayer(unit)
    if UnitIsUnit(unit .. "target", "player") then return true end
    return UnitThreatSituation("player", unit) ~= nil
end

local function isSelected(unit)
    return UnitIsUnit(unit, "target")
        or UnitIsUnit(unit, "softenemy")
        or UnitIsUnit(unit, "softfriend")
        or UnitIsUnit(unit, "softinteract")
end

local function getLayoutType(unit)
    if UnitIsPlayer(unit) then return PlateType.NameOnly end
    if not UnitCanAttack("player", unit) then return PlateType.NameOnly end
    if UnitIsUnit(unit, "target") then return PlateType.Full end
    if inCombat and isEngagedWithPlayer(unit) then return PlateType.Full end
    return PlateType.NameOnly
end

local function updateAlpha(f, unit)
    local dimmed = inCombat
        and not isSelected(unit)
        and UnitCanAttack("player", unit)
    f:SetAlpha(dimmed and 0.65 or 1.0)
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

local function updateBarColor(f, unit)
    if isSelected(unit) then
        f.bar.fill:SetStatusBarColor(0.9, 0.1, 0.1)
    else
        f.bar.fill:SetStatusBarColor(0.9, 0.75, 0.0)
    end
end

local function updateHealth(f, unit)
    local max = UnitHealthMax(unit)
    f.bar.fill:SetMinMaxValues(0, max, Enum.StatusBarInterpolation.ExponentialEaseOut)
    f.bar.fill:SetValue(UnitHealth(unit), Enum.StatusBarInterpolation.ExponentialEaseOut)
end

local function applyFontToAll()
    for _, f in pairs(active) do
        f.name:SetFont(currentFont())
        f.guild:SetFont(currentGuildFont())
    end
end

-- Updates bar visibility and all bar-dependent sub-frames for one plate.
local function refreshBar(f, unitToken)
    local plateType = getLayoutType(unitToken)
    f.bar:SetShown(plateType == PlateType.Full)
    nameplates.applyLayout(f, plateType)
    if plateType == PlateType.Full then
        updateBarColor(f, unitToken)
        updateHealth(f, unitToken)
        nameplates.updateCast(f, unitToken)
        nameplates.refreshAuras(f, unitToken)
        nameplates.refreshCC(f, unitToken)
        nameplates.updatePower(f, unitToken)
    else
        nameplates.hideCast(f)
        nameplates.hideAuras(f)
        nameplates.hideCC(f)
        nameplates.hidePower(f)
    end
end

local function showPlate(unitToken, np)
    local f = active[unitToken]
    if not f then
        f = acquire()
        active[unitToken] = f
    end

    f:SetScale(isSelected(unitToken) and SELECTED_SCALE or 1.0)
    updateAlpha(f, unitToken)
    f:SetPoint("CENTER", np.UnitFrame, "CENTER")
    f.unitFrame = np.UnitFrame
    lockUnitFrame(np.UnitFrame)
    f:Show()

    f.name:SetFont(currentFont())
    nameplates.applyName(f, unitToken)
    f.name:SetShown(nameplates.shouldShowName(unitToken))
    f.questIcon:SetShown(nameplates.isQuestUnit(unitToken))
    nameplates.applyGuild(f, unitToken)
    updateMark(f, unitToken)
    refreshBar(f, unitToken)
end

local function hidePlate(unitToken)
    local f = active[unitToken]
    if not f then return end
    active[unitToken] = nil
    unlockUnitFrame(f.unitFrame)
    f.unitFrame = nil
    release(f)
end

local function refreshAll()
    for unitToken, f in pairs(active) do
        f:SetScale(isSelected(unitToken) and SELECTED_SCALE or 1.0)
        updateAlpha(f, unitToken)
        f.name:SetShown(nameplates.shouldShowName(unitToken))
        f.questIcon:SetShown(nameplates.isQuestUnit(unitToken))
        nameplates.applyGuild(f, unitToken)
        updateMark(f, unitToken)
        refreshBar(f, unitToken)
    end
end

--#endregion

--#region ── Module lifecycle ─────────────────────────────────────────────────

function nameplates:OnEnable()
    SetCVar("nameplateSelectedScale", SELECTED_SCALE)
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
    refreshAll()
end

function nameplates:OnRaidTargetUpdate()
    for unitToken, f in pairs(active) do
        updateMark(f, unitToken)
    end
end

function nameplates:OnQuestLogUpdate()
    nameplates.wipeQuestCache()
    refreshAll()
end

function nameplates:OnUnitHealth(_, unitToken)
    local f = active[unitToken]
    if f and f.bar:IsShown() then updateHealth(f, unitToken) end
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
    for unitToken, f in pairs(active) do
        if UnitIsUnit(unitToken, "target") and f.bar:IsShown() then
            nameplates.updatePower(f, unitToken)
            break
        end
    end
end

function nameplates:OnNameUpdate(_, unitToken)
    local f = active[unitToken]
    if f then
        nameplates.applyName(f, unitToken)
        nameplates.applyGuild(f, unitToken)
    end
end

function nameplates:OnDisable()
    SetCVar("nameplateSelectedScale", 1.2)
    self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
    self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
    self:UnregisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
    self:UnregisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
    self:UnregisterEvent("RAID_TARGET_UPDATE")
    self:UnregisterEvent("QUEST_LOG_UPDATE")
    self:UnregisterEvent("UNIT_HEALTH")
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
    self:UnregisterEvent("UNIT_AURA")
    self:UnregisterEvent("UNIT_TARGET")
    self:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    self:UnregisterEvent("UNIT_POWER_FREQUENT")
    self:UnregisterEvent("UNIT_DISPLAYPOWER")
    self:UnregisterEvent("PLAYER_TALENT_UPDATE")
    if playerIsDK then self:UnregisterEvent("RUNE_POWER_UPDATE") end

    for _, f in pairs(active) do
        unlockUnitFrame(f.unitFrame)
        f.unitFrame = nil
        release(f)
    end
    wipe(active)
    nameplates.wipeQuestCache()
end

--#endregion

--#region ── Defaults & Options ───────────────────────────────────────────────

function nameplates:GetDefaults()
    return {
        ---@type NameplatesDB
        nameplates = {
            enabled  = true,
            font     = 'Arial Narrow',
            fontSize = 16,
            fontFlag = 'OUTLINE',
        },
    }
end

function nameplates:GetOptions()
    return 'nameplates', {
        name  = 'Nameplates',
        type  = 'group',
        order = 9,
        args  = {
            description = {
                name  = 'Custom nameplate overlays.',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Enable',
                desc  = 'Show custom name and health bar on nameplates.',
                type  = 'toggle',
                order = 2,
                get   = function() return npDB().enabled end,
                set   = function(_, value)
                    npDB().enabled = value
                    if value then nameplates:Enable() else nameplates:Disable() end
                end,
            },
            appearance = {
                name   = 'Appearance',
                type   = 'group',
                inline = true,
                order  = 3,
                args   = {
                    font = {
                        name          = 'Font',
                        type          = 'select',
                        dialogControl = 'LSM30_Font',
                        order         = 1,
                        values        = LSM:HashTable(LSM.MediaType.FONT),
                        get           = function() return npDB().font end,
                        set           = function(_, value)
                            npDB().font = value
                            applyFontToAll()
                        end,
                    },
                    fontSize = {
                        name  = 'Size',
                        type  = 'range',
                        order = 2,
                        min   = 8,
                        max   = 32,
                        step  = 1,
                        get   = function() return npDB().fontSize end,
                        set   = function(_, value)
                            npDB().fontSize = value
                            applyFontToAll()
                        end,
                    },
                    fontFlag = {
                        name   = 'Style',
                        type   = 'select',
                        order  = 3,
                        values = FONT_FLAGS,
                        get    = function() return npDB().fontFlag end,
                        set    = function(_, value)
                            npDB().fontFlag = value
                            applyFontToAll()
                        end,
                    },
                },
            },
        },
    }
end

--#endregion
