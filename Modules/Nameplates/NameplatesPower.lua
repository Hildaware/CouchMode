local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class NameplatesModule: AceModule
local nameplates = addon:GetModule('Nameplates')

function nameplates.buildPowerFrame(f)
    local PIP_W = nameplates.PIP_W
    local PIP_H = nameplates.PIP_H
    local PIP_GAP = nameplates.PIP_GAP
    local PIP_MAX = nameplates.PIP_MAX

    f.power = CreateFrame("Frame", nil, f)
    f.power:SetFrameLevel(f.bar:GetFrameLevel() + 5)
    f.power:SetPoint("TOP", f.bar, "BOTTOM", 0, 6)
    f.power:SetSize(1, PIP_H)
    f.power:Hide()

    f.power.pips = {}
    for i = 1, PIP_MAX do
        local pip = CreateFrame("Frame", nil, f.power)
        pip:SetSize(PIP_W, PIP_H)
        if i == 1 then
            pip:SetPoint("LEFT", f.power, "LEFT")
        else
            pip:SetPoint("LEFT", f.power.pips[i - 1], "RIGHT", PIP_GAP, 0)
        end
        pip.bg = pip:CreateTexture(nil, "BACKGROUND")
        pip.bg:SetAllPoints(pip)
        pip.bg:SetAtlas("talents-node-choiceflyout-circle-greenglow")
        pip.bg:SetVertexColor(0, 0, 0, 1)

        pip.tex = pip:CreateTexture(nil, "ARTWORK")
        pip.tex:SetAllPoints(pip)
        pip.tex:SetVertexColor(1, 1, 1, 1)
        pip.tex:SetAtlas("common-radiobutton-dot")
        pip:Hide()
        f.power.pips[i] = pip
    end
end

local PLAYER_CLASS    = select(2, UnitClass("player"))
local playerIsDK      = (PLAYER_CLASS == "DEATHKNIGHT")

local SECONDARY_POWER = {
    ROGUE   = Enum.PowerType.ComboPoints,
    DRUID   = Enum.PowerType.ComboPoints,
    PALADIN = Enum.PowerType.HolyPower,
    MONK    = Enum.PowerType.Chi,
    WARLOCK = Enum.PowerType.SoulShards,
    MAGE    = Enum.PowerType.ArcaneCharges,
    EVOKER  = Enum.PowerType.Essence,
}
local playerPowerType = SECONDARY_POWER[PLAYER_CLASS]

local function playerClassColor()
    local c = RAID_CLASS_COLORS[PLAYER_CLASS]
    return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

function nameplates.updatePower(f, unitToken)
    local PIP_W   = nameplates.PIP_W
    local PIP_GAP = nameplates.PIP_GAP
    local PIP_MAX = nameplates.PIP_MAX

    if not UnitIsUnit(unitToken, "target") then
        f.power:Hide()
        return
    end

    local current, maxPower

    if playerIsDK then
        current, maxPower = 0, 6
        for i = 1, 6 do
            local _, _, runeReady = GetRuneCooldown(i)
            if runeReady then current = current + 1 end
        end
    elseif playerPowerType then
        if PLAYER_CLASS == "DRUID" and UnitPowerType("player") ~= Enum.PowerType.Energy then
            f.power:Hide()
            return
        end
        current  = UnitPower("player", playerPowerType)
        maxPower = UnitPowerMax("player", playerPowerType)
    else
        f.power:Hide()
        return
    end

    if maxPower <= 0 then
        f.power:Hide()
        return
    end

    local r, g, b = playerClassColor()
    f.power:SetWidth(maxPower * PIP_W + (maxPower - 1) * PIP_GAP)

    for i = 1, PIP_MAX do
        local pip = f.power.pips[i]
        if i <= maxPower then
            pip:Show()
            if i <= current then
                pip.tex:Show()
                pip.tex:SetVertexColor(r, g, b, 1)
            else
                pip.tex:Hide()
                -- pip.tex:SetVertexColor(r * 0.3, g * 0.3, b * 0.3, 1)
            end
        else
            pip:Hide()
        end
    end

    f.power:Show()
end

function nameplates.hidePower(f)
    f.power:Hide()
end

nameplates:Enable()
