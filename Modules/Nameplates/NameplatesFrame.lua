local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class NameplatesModule: AceModule
local nameplates = addon:GetModule('Nameplates')

--#region ── Frame pool ───────────────────────────────────────────────────────

local pool = {}
local active = {}         -- [unitToken] = frame
local hookedUFs = {}      -- [UnitFrame] = true; lock is currently active
local installedHooks = {} -- [UnitFrame] = true; hook has been installed (never cleared)

-- Shared with NameplatesPlate so event handlers can look up frames by unit token.
nameplates.active = active

local function lockUnitFrame(uf)
    if uf:IsForbidden() then return end
    uf:SetAlpha(0)
    hookedUFs[uf] = true
    if installedHooks[uf] then return end
    installedHooks[uf] = true
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

nameplates.lockUnitFrame = lockUnitFrame
nameplates.unlockUnitFrame = unlockUnitFrame

--#endregion

--#region ── Frame building ───────────────────────────────────────────────────

local function buildFrame()
    local BAR_W = nameplates.BAR_W
    local BAR_H = nameplates.BAR_H
    local BAR_TEX = nameplates.BAR_TEX

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    f:SetIgnoreParentScale(true)

    f.bar = CreateFrame("Frame", nil, f)
    f.bar:SetSize(BAR_W, BAR_H)
    f.bar:SetPoint("TOP", f, "TOP", 0, 0)
    f.bar:Hide()

    local barBg = f.bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetTexture(BAR_TEX)
    barBg:SetVertexColor(0, 0, 0, 1)
    barBg:SetAllPoints(f.bar)
    barBg:SetAlpha(0.75)

    f.bar.absorb = CreateFrame("StatusBar", nil, f.bar)
    f.bar.absorb:SetAllPoints(f.bar)
    f.bar.absorb:SetStatusBarTexture(BAR_TEX)
    f.bar.absorb:SetStatusBarColor(1, 1, 1, 1)
    f.bar.absorb:SetAlpha(0.75)
    f.bar.absorb:SetMinMaxValues(0, 1)
    f.bar.absorb:SetValue(0)
    f.bar.absorb:SetReverseFill(true)

    f.bar._calc = CreateUnitHealPredictionCalculator()
    f.bar._calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
    f.bar._calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)

    f.bar.fill = CreateFrame("StatusBar", nil, f.bar)
    f.bar.fill:SetAllPoints(f.bar)
    f.bar.fill:SetStatusBarTexture(BAR_TEX)
    f.bar.fill:SetAlpha(0.75)
    f.bar.fill:SetFrameLevel(f.bar.absorb:GetFrameLevel() + 1)

    do
        local b = addon.Utils.create_border_textures(f.bar.fill, f.bar)
        addon.Utils.apply_border_textures(f.bar, b, true, 1, 0, 0, 0, 1)
    end

    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(f.bar:GetFrameLevel() + 15)
    f.overlay = overlay

    nameplates.buildNameFrame(f, overlay)

    f.roleIcon = overlay:CreateTexture(nil, "OVERLAY")
    f.roleIcon:SetSize(32, 32)
    f.roleIcon:SetPoint("BOTTOM", f.name, "TOP", 0, 6)
    f.roleIcon:Hide()

    f.mark = overlay:CreateTexture(nil, "OVERLAY")
    f.mark:SetSize(24, 24)
    f.mark:SetTexture("Interface/TargetingFrame/UI-RaidTargetingIcons")
    f.mark:Hide()

    f.elite = overlay:CreateTexture(nil, "OVERLAY")
    f.elite:SetSize(20, 20)
    f.elite:Hide()

    return f
end

local function ensureCombatFrames(f)
    if f.cast then return end
    nameplates.buildCastFrame(f, f.overlay)
    nameplates.buildAurasFrame(f)
    nameplates.buildPowerFrame(f)
end

local function acquire()
    local f = table.remove(pool) or buildFrame()
    f:SetParent(UIParent)
    f:ClearAllPoints()
    return f
end

local function release(f)
    f:SetScript("OnUpdate", nil)
    f.layoutTrans = nil
    f.plateType = nil
    f.isSelected = nil
    f.showName = nil
    f:SetAlpha(1.0)
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(nil)
    f.name:SetText("")
    f.questIcon:Hide()
    f.mark:Hide()
    f.elite:Hide()
    f.roleIcon:Hide()
    f.guild:SetText("")
    f.guild:Hide()
    f.bar:Hide()
    f.bar.absorb:SetValue(0)
    if f.cast then
        f.cast:Hide()
        f.cast.spellName:SetText("")
        f.cast.spellName:Hide()
        f.cast.shield:SetAlpha(0)
        nameplates.hideAuras(f)
        nameplates.hideCC(f)
        nameplates.hidePower(f)
    end
    pool[#pool + 1] = f
end

nameplates.acquire = acquire
nameplates.release = release
nameplates.ensureCombatFrames = ensureCombatFrames

--#endregion
