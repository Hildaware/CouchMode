local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class PlayerPowerBar: AceModule
---@field preview         boolean
---@field visibilityCurve table
---@field targetValue     number|nil
---@field displayedValue  number|nil
local powerBar = addon:NewModule('PlayerPowerBar', 'AceEvent-3.0')
---@cast powerBar +AceEvent-3.0

local MEDIA = {
    TEXTURE = 'interface/hud/uiwowlabsactionbar',
    BAR_ATLAS = 'plunderstorm-stormbar-fill',
    BORDER_ATLAS = 'plunderstorm-stormbar-border',
    BG_ATLAS = 'plunderstorm-stormbar-background',
}

-- Fill-type primary resources: build from empty, opposite of mana.
local FILL_POWER_TYPES = {
    [Enum.PowerType.Rage] = true,       -- Warrior
    [Enum.PowerType.RunicPower] = true, -- Death Knight
    [Enum.PowerType.Fury] = true,       -- Demon Hunter (Havoc)
    [Enum.PowerType.Pain] = true,       -- Demon Hunter (Vengeance)
    [Enum.PowerType.Maelstrom] = true,  -- Shaman (Enhancement)
    [Enum.PowerType.LunarPower] = true, -- Druid (Balance / Astral Power)
    [Enum.PowerType.Insanity] = true,   -- Priest (Shadow)
}

---@class PlayerPowerBarGUI: StatusBarBaseGUI
local gui = {}

local function cfg()
    return addon.db.profile.playerPowerBar
end

--- Returns true when the player's current primary power is a fill-type resource.
local function playerUsesFillPower()
    return FILL_POWER_TYPES[UnitPowerType('player')] == true
end

--#region ── Refresh ───────────────────────────────────────────────────────────

function powerBar:Refresh()
    if not gui.frame then return end
    addon.StatusBarBase.Refresh(gui, cfg())
end

--#endregion

--#region ── Value update ──────────────────────────────────────────────────────

function powerBar:UpdateValue()
    -- Hide entirely when the player's primary power is not a fill-type resource.
    if not self.preview and not playerUsesFillPower() then
        gui.frame:SetAlpha(0)
        -- Reset smooth state so the bar snaps when the resource becomes active again.
        self.targetValue = nil
        self.displayedValue = nil
        return
    end

    local powerType = UnitPowerType('player')
    local current = UnitPower('player', powerType)
    local maxVal = UnitPowerMax('player', powerType)
    local pct = (maxVal > 0 and not issecretvalue(current) and not issecretvalue(maxVal))
        and (current / maxVal) or 0.0
    local c = cfg()

    gui.bar:SetMinMaxValues(0, maxVal)

    if self.displayedValue == nil then
        -- First update: snap rather than animate from zero.
        self.displayedValue = current
        gui.bar:SetValue(current)
    end
    self.targetValue = current

    -- Color
    local r, g, b
    if c.useClassColor then
        local _, classToken = UnitClass('player')
        ---@diagnostic disable-next-line: undefined-global
        local cc = RAID_CLASS_COLORS[classToken]
        r, g, b = cc.r, cc.g, cc.b
    else
        local col = c.barColor
        r, g, b = col.r, col.g, col.b
    end
    gui.bar:SetStatusBarColor(r, g, b, 1.0)

    -- Text
    if c.showText then
        gui.label:SetFormattedText('%d / %d', current, maxVal)
    end

    -- Visibility
    -- pct is pre-guarded (issecretvalue checked above, defaults to 0.0), so Lua comparisons are safe.
    local inCombat = UnitAffectingCombat('player')
    if self.preview then
        gui.frame:SetAlpha(1)
    elseif c.showWhenNotFull then
        -- In combat always show; otherwise show only when not full.
        if c.showOnlyInCombat and inCombat then
            gui.frame:SetAlpha(1)
        else
            gui.frame:SetAlpha(pct < 1.0 and 1 or 0)
        end
    elseif c.showOnlyInCombat and not inCombat then
        gui.frame:SetAlpha(0)
    elseif c.autoHide then
        gui.frame:SetAlpha((pct <= c.showThreshold / 100) and 1 or 0)
    else
        gui.frame:SetAlpha(1)
    end
end

--#endregion

--#region ── UI Construction ───────────────────────────────────────────────────

function powerBar:CreateUI()
    gui = addon.StatusBarBase.CreateBarUI({ media = MEDIA })

    gui.frame:SetScript('OnUpdate', addon.StatusBarBase.CreateOnUpdate(self, gui))

    self:Refresh()
end

--#endregion

--#region ── Preview ───────────────────────────────────────────────────────────

function powerBar:TogglePreview()
    self.preview = not self.preview
    if self.preview then gui.frame:Show() end
    self:UpdateValue()
end

--#endregion

--#region ── Event handlers ────────────────────────────────────────────────────

function powerBar:OnPowerChanged(_, unit)
    if unit ~= 'player' then return end
    self:UpdateValue()
end

function powerBar:OnDisplayPowerChanged(_, unit)
    -- Fires when the player's primary power type changes (e.g. spec change, shapeshift).
    if unit ~= 'player' then return end
    self:UpdateValue()
end

function powerBar:OnPlayerEnteringWorld()
    self:UpdateValue()
end

function powerBar:OnEnterCombat()
    self:UpdateValue()
end

function powerBar:OnLeaveCombat()
    self:UpdateValue()
end

--#endregion

--#region ── Module lifecycle ──────────────────────────────────────────────────

function powerBar:BuildVisibilityCurve()
    -- Intentional no-op: visibility is computed from cfg().showThreshold directly
    -- (see UpdateValue) because C_CurveUtil curve objects don't expose :GetValue() in Lua.
end

function powerBar:OnEnable()
    if not cfg().enabled then
        self:Disable(); return
    end

    if not gui.frame then
        self:CreateUI()

        local db    = cfg()
        local frame = gui.frame

        addon.StatusBarBase.RegisterWithEditMode(frame, db, self, {
            label         = 'CouchMode Power',
            widthDefault  = 220,
            heightDefault = 18,
        })
    end

    self:BuildVisibilityCurve()
    self:RegisterEvent('UNIT_POWER_FREQUENT', 'OnPowerChanged')
    self:RegisterEvent('UNIT_MAXPOWER', 'OnPowerChanged')
    self:RegisterEvent('UNIT_DISPLAYPOWER', 'OnDisplayPowerChanged')
    self:RegisterEvent('PLAYER_ENTERING_WORLD', 'OnPlayerEnteringWorld')
    self:RegisterEvent('PLAYER_REGEN_DISABLED', 'OnEnterCombat')
    self:RegisterEvent('PLAYER_REGEN_ENABLED', 'OnLeaveCombat')

    gui.frame:Show()
    self:UpdateValue()
end

function powerBar:OnDisable()
    self.preview = false
    self.targetValue = nil
    self.displayedValue = nil
    self:UnregisterAllEvents()
    if gui.frame then
        gui.frame:SetScript('OnUpdate', nil)
        gui.frame:Hide()
    end
end

--#endregion

--#region ── Options ───────────────────────────────────────────────────────────

function powerBar:GetDefaults()
    return {
        playerPowerBar = addon.StatusBarBase.GetBaseDefaults({
            yPos = -200,
            barColor = { r = 1.0, g = 0.49, b = 0.04, a = 1.0 },
            useClassColor = false,
        }),
    }
end

function powerBar:GetOptions()
    local args = addon.StatusBarBase.GetBaseOptionArgs('playerPowerBar', self, {
        description =
        'A horizontal bar that tracks fill-type primary resources: Rage (Warrior), Runic Power (Death Knight), Fury/Pain (Demon Hunter), and Maelstrom (Enhancement Shaman). Hidden for all other specs.',
        extraDisplayArgs = {
            showText = {
                name = 'Show Power Text',
                desc = 'Display current and maximum power as numbers on the bar.',
                type = 'toggle',
                order = 1,
                get = function() return addon.db.profile.playerPowerBar.showText end,
                set = function(_, value)
                    addon.db.profile.playerPowerBar.showText = value
                    powerBar:Refresh()
                    powerBar:UpdateValue()
                end,
            },
        },
        extraColorArgs = {
            useClassColor = {
                name = 'Class Color',
                desc = 'Color the bar with your class color.',
                type = 'toggle',
                order = 1,
                get = function() return addon.db.profile.playerPowerBar.useClassColor end,
                set = function(_, value)
                    addon.db.profile.playerPowerBar.useClassColor = value
                    powerBar:UpdateValue()
                end,
            },
            barColor = {
                name = 'Bar Color',
                desc = 'Fill color for the power bar.',
                type = 'color',
                order = 10,
                hasAlpha = false,
                disabled = function() return addon.db.profile.playerPowerBar.useClassColor end,
                get = function()
                    local c = addon.db.profile.playerPowerBar.barColor
                    return c.r, c.g, c.b
                end,
                set = function(_, r, g, b)
                    local c = addon.db.profile.playerPowerBar.barColor
                    c.r, c.g, c.b = r, g, b
                    powerBar:UpdateValue()
                end,
            },
        },
    })

    return 'playerPowerBar', {
        name = 'Power',
        type = 'group',
        order = 2,
        args = args,
    }
end

--#endregion

powerBar:Enable()
