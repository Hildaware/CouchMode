local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local isSecretValue = addon.Utils.IsSecretValue

---@class PlayerManaBar: AceModule
---@field preview         boolean
---@field visibilityCurve table
---@field targetValue     number|nil
---@field displayedValue  number|nil
local manaBar = addon:NewModule('PlayerManaBar', 'AceEvent-3.0')
---@cast manaBar +AceEvent-3.0

local MEDIA = {
    TEXTURE = 'interface/hud/uiwowlabsactionbar',
    BAR_ATLAS = 'plunderstorm-stormbar-fill',
    BORDER_ATLAS = 'plunderstorm-stormbar-border',
    BG_ATLAS = 'plunderstorm-stormbar-background',
}

---@class PlayerManaBarGUI: StatusBarBaseGUI
local gui = {}

local function cfg()
    return addon.db.profile.playerManaBar
end

--- Returns true when the player's current primary power type is mana.
--- This correctly returns false for e.g. Druids in bear/cat form.
local function playerUsesMana()
    return UnitPowerType('player') == Enum.PowerType.Mana
end

--#region ── Refresh ───────────────────────────────────────────────────────────

function manaBar:Refresh()
    if not gui.frame then return end
    addon.StatusBarBase.Refresh(gui, cfg())
end

--#endregion

--#region ── Value update ──────────────────────────────────────────────────────

function manaBar:UpdateValue()
    -- Hide entirely when the player's primary power is not mana (e.g. Druid in bear/cat).
    if not self.preview and not playerUsesMana() then
        gui.frame:SetAlpha(0)
        -- Reset smooth state so the bar snaps when mana becomes active again.
        self.targetValue = nil
        self.displayedValue = nil
        return
    end

    local current = UnitPower('player', Enum.PowerType.Mana)
    local maxVal = UnitPowerMax('player', Enum.PowerType.Mana)
    local pct = (maxVal > 0 and not isSecretValue(current) and not isSecretValue(maxVal))
        and (current / maxVal) or 1.0
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
    -- pct is pre-guarded (secret values default to 1.0), so Lua comparisons are safe.
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

function manaBar:CreateUI()
    gui = addon.StatusBarBase.CreateBarUI({ media = MEDIA })

    gui.frame:SetScript('OnUpdate', addon.StatusBarBase.CreateOnUpdate(self, gui))

    self:Refresh()
end

--#endregion

--#region ── Preview ───────────────────────────────────────────────────────────

function manaBar:TogglePreview()
    self.preview = not self.preview
    if self.preview then gui.frame:Show() end
    self:UpdateValue()
end

--#endregion

--#region ── Event handlers ────────────────────────────────────────────────────

function manaBar:OnPowerChanged(_, unit)
    if unit ~= 'player' then return end
    self:UpdateValue()
end

function manaBar:OnDisplayPowerChanged(_, unit)
    -- Fires when the player's primary power type changes (e.g. Druid shapeshifting,
    -- spec change). Re-evaluate whether to show the bar.
    if unit ~= 'player' then return end
    self:UpdateValue()
end

function manaBar:OnPlayerEnteringWorld()
    self:UpdateValue()
end

function manaBar:OnEnterCombat()
    self:UpdateValue()
end

function manaBar:OnLeaveCombat()
    self:UpdateValue()
end

--#endregion

--#region ── Module lifecycle ──────────────────────────────────────────────────

function manaBar:BuildVisibilityCurve()
    -- Intentional no-op: mana visibility is computed from cfg().showThreshold directly
    -- (see UpdateValue) because C_CurveUtil curve objects don't expose :GetValue() in Lua.
end

function manaBar:OnEnable()
    if not cfg().enabled then
        self:Disable(); return
    end

    if not gui.frame then
        self:CreateUI()

        local db    = cfg()
        local frame = gui.frame

        addon.StatusBarBase.RegisterWithEditMode(frame, db, self, {
            label         = 'CouchMode Mana',
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

function manaBar:OnDisable()
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

function manaBar:GetDefaults()
    return {
        playerManaBar = addon.StatusBarBase.GetBaseDefaults({
            yPos = -175,
            barColor = { r = 0.0, g = 0.4, b = 1.0, a = 1.0 },
            useClassColor = false,
        }),
    }
end

function manaBar:GetOptions()
    local args = addon.StatusBarBase.GetBaseOptionArgs('playerManaBar', self, {
        description =
        'A simple horizontal bar that shows your current mana. Hidden automatically for specs that do not use mana.',
        extraDisplayArgs = {
            showText = {
                name = 'Show Mana Text',
                desc = 'Display current and maximum mana as numbers on the bar.',
                type = 'toggle',
                order = 1,
                get = function() return addon.db.profile.playerManaBar.showText end,
                set = function(_, value)
                    addon.db.profile.playerManaBar.showText = value
                    manaBar:Refresh()
                    manaBar:UpdateValue()
                end,
            },
        },
        extraColorArgs = {
            useClassColor = {
                name = 'Class Color',
                desc = 'Color the bar with your class color.',
                type = 'toggle',
                order = 1,
                get = function() return addon.db.profile.playerManaBar.useClassColor end,
                set = function(_, value)
                    addon.db.profile.playerManaBar.useClassColor = value
                    manaBar:UpdateValue()
                end,
            },
            -- barColor (order 10) is provided by the base; disable it when class color is active.
            barColor = {
                name = 'Bar Color',
                desc = 'Fill color for the mana bar.',
                type = 'color',
                order = 10,
                hasAlpha = false,
                disabled = function() return addon.db.profile.playerManaBar.useClassColor end,
                get = function()
                    local c = addon.db.profile.playerManaBar.barColor
                    return c.r, c.g, c.b
                end,
                set = function(_, r, g, b)
                    local c = addon.db.profile.playerManaBar.barColor
                    c.r, c.g, c.b = r, g, b
                    manaBar:UpdateValue()
                end,
            },
        },
    })

    return 'playerManaBar', {
        name = 'Mana',
        type = 'group',
        order = 3,
        args = args,
    }
end

--#endregion

manaBar:Enable()
