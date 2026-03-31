local addon_name     = ...

---@class ConsoleTools: AceAddon
local addon          = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class NameplatesModule: AceModule
local nameplates     = addon:GetModule('Nameplates')

--#region ── Frame pool ───────────────────────────────────────────────────────

local pool           = {}
local active         = {} -- [unitToken] = frame
local hookedUFs      = {} -- [UnitFrame] = true; lock is currently active
local installedHooks = {} -- [UnitFrame] = true; hook has been installed (never cleared)

-- Shared with NameplatesPlate so event handlers can look up frames by unit token.
nameplates.active    = active

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

nameplates.lockUnitFrame   = lockUnitFrame
nameplates.unlockUnitFrame = unlockUnitFrame

--#endregion

--#region ── Frame building ───────────────────────────────────────────────────

local function buildFrame()
    local BAR_W   = nameplates.BAR_W
    local BAR_H   = nameplates.BAR_H
    local BAR_TEX = nameplates.BAR_TEX

    local f       = CreateFrame("Frame", nil, UIParent)
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

    f.bar.fill = CreateFrame("StatusBar", nil, f.bar)
    f.bar.fill:SetAllPoints(f.bar)
    f.bar.fill:SetStatusBarTexture(BAR_TEX)
    f.bar.fill:SetAlpha(0.75)

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

    f.elite = overlay:CreateTexture(nil, "OVERLAY")
    f.elite:SetSize(20, 20)
    f.elite:Hide()

    return f
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
    f:SetAlpha(1.0)
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(nil)
    f.name:SetText("")
    f.questIcon:Hide()
    f.mark:Hide()
    f.elite:Hide()
    f.guild:SetText("")
    f.guild:Hide()
    f.bar:Hide()
    f.cast:Hide()
    f.cast.spellName:SetText("")
    f.cast.spellName:Hide()
    f.cast.shield:SetAlpha(0)
    nameplates.hideAuras(f)
    nameplates.hideCC(f)
    nameplates.hidePower(f)
    pool[#pool + 1] = f
end

nameplates.acquire = acquire
nameplates.release = release

--#endregion
