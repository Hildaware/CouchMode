local addonName   = ...

---@class CouchMode: AceAddon
local addon       = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class PlayerHealthBar: AceModule
---@field preview         boolean
---@field visibilityCurve table
local healthBar   = addon:NewModule('PlayerHealthBar', 'AceEvent-3.0')
---@cast healthBar +AceEvent-3.0

---@type CastUtil
local CastUtil    = addon.CastUtil

local MEDIA       = {
    TEXTURE      = 'interface/castingbar/uicastingbar2x',
    BAR_ATLAS    = 'ui-castingbar-disabled-tier4-empower-2x',
    BORDER_ATLAS = 'UI-CastingBar-Frame',
    BG_ATLAS     = 'UI-CastingBar-Background',
}

---@class PlayerHealthBarGUI
---@field frame      Frame
---@field bg         Texture
---@field bar        StatusBar
---@field border     Texture
---@field healthText FontString
local gui         = {}

local healthColorCurve

local SMOOTH_RATE = 2 -- exponential lerp factor for health bar (higher = snappier)

local function cfg()
    return addon.db.profile.playerHealthBar
end

--#region ── Refresh ───────────────────────────────────────────────────────────

function healthBar:Refresh()
    if not gui.frame then return end
    local c = cfg()

    gui.frame:SetSize(c.width, c.height)
    gui.frame:ClearAllPoints()
    gui.frame:SetPoint('CENTER', UIParent, 'CENTER', c.xPos, c.yPos)

    gui.frame:SetMovable(not c.locked)
    gui.frame:EnableMouse(not c.locked)

    gui.healthText:SetShown(c.showText)
end

--#endregion

--#region ── Health update ─────────────────────────────────────────────────────

function healthBar:UpdateHealth()
    local current = UnitHealth('player')
    local maxHP   = UnitHealthMax('player')
    local c       = cfg()

    gui.bar:SetMinMaxValues(0, maxHP)

    if issecretvalue(current) or issecretvalue(maxHP) then
        -- Can't interpolate secret values; snap immediately
        gui.bar:SetValue(current)
        self.targetHealth    = nil
        self.displayedHealth = nil
    else
        self.targetMaxHP = maxHP
        if self.displayedHealth == nil then
            -- First update: snap rather than animate from zero
            self.displayedHealth = current
            gui.bar:SetValue(current)
        end
        self.targetHealth = current
    end

    -- Color
    local r, g, b
    if c.useClassColor then
        local _, classToken = UnitClass('player')
        ---@diagnostic disable-next-line: undefined-global
        local cc = RAID_CLASS_COLORS[classToken]
        r, g, b = cc.r, cc.g, cc.b
    elseif c.colorByPct then
        if not healthColorCurve then
            healthColorCurve = C_CurveUtil.CreateColorCurve()
            healthColorCurve:AddPoint(0.0, CreateColor(1, 0, 0)) -- red   at 0%
            healthColorCurve:AddPoint(0.5, CreateColor(1, 1, 0)) -- yellow at 50%
            healthColorCurve:AddPoint(1.0, CreateColor(0, 1, 0)) -- green  at 100%
        end
        local color = UnitHealthPercent('player', true, healthColorCurve)
        r, g, b = color:GetRGB()
    else
        local col = c.barColor
        r, g, b = col.r, col.g, col.b
    end
    gui.bar:SetStatusBarColor(r, g, b, 1.0)

    -- Text
    if c.showText then
        gui.healthText:SetFormattedText('%d / %d', current, maxHP)
    end

    -- Visibility
    if self.preview or not c.autoHide then
        gui.frame:SetAlpha(1)
    else
        -- Secret health value: pass curve result directly to SetAlpha (0 or 1, no arithmetic)
        gui.frame:SetAlpha(UnitHealthPercent('player', true, self.visibilityCurve))
    end
end

--#endregion

--#region ── UI Construction ───────────────────────────────────────────────────

function healthBar:CreateUI()
    gui.frame = CreateFrame('Frame', 'PlayerHealthBarFrame', UIParent)
    gui.frame:SetFrameStrata('MEDIUM')
    gui.frame:SetFrameLevel(10)

    CastUtil.ApplyDragToMove(gui.frame, cfg)

    -- Background
    gui.bg = gui.frame:CreateTexture(nil, 'BACKGROUND')
    gui.bg:SetAllPoints(gui.frame)
    gui.bg:SetTexture(MEDIA.TEXTURE)
    gui.bg:SetAtlas(MEDIA.BG_ATLAS)

    -- Fill bar (StatusBar accepts secret health values in SetMinMaxValues/SetValue)
    gui.bar = CreateFrame('StatusBar', nil, gui.frame)
    gui.bar:SetAllPoints(gui.frame)
    gui.bar:SetStatusBarTexture(MEDIA.TEXTURE)
    gui.bar:GetStatusBarTexture():SetAtlas(MEDIA.BAR_ATLAS)
    gui.bar:SetMinMaxValues(0, 1)
    gui.bar:SetValue(0)

    -- Border overlay (separate frame so it renders above the StatusBar child frame)
    local borderFrm = CreateFrame('Frame', nil, gui.frame)
    borderFrm:SetFrameLevel(gui.frame:GetFrameLevel() + 2)
    borderFrm:SetAllPoints(gui.frame)

    gui.border = borderFrm:CreateTexture(nil, 'OVERLAY')
    gui.border:SetAllPoints(gui.frame)
    gui.border:SetTexture(MEDIA.TEXTURE)
    gui.border:SetAtlas(MEDIA.BORDER_ATLAS)

    -- Health text
    gui.healthText = gui.frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    gui.healthText:SetPoint('CENTER', gui.frame, 'CENTER')
    gui.healthText:SetJustifyH('CENTER')
    gui.healthText:SetTextColor(1, 1, 1, 1)

    gui.frame:SetScript('OnUpdate', function(_, elapsed)
        -- Health smoothing
        if healthBar.targetHealth then
            local displayed = healthBar.displayedHealth
            local target    = healthBar.targetHealth
            local delta     = target - displayed

            if math.abs(delta) < 1 then
                healthBar.displayedHealth = target
            else
                healthBar.displayedHealth = displayed + delta * math.min(SMOOTH_RATE * elapsed, 1)
            end

            gui.bar:SetValue(healthBar.displayedHealth)
        end
    end)

    self:Refresh()
    self:UpdateHealth()
    gui.frame:Show()
end

--#endregion

--#region ── Preview ───────────────────────────────────────────────────────────

function healthBar:TogglePreview()
    if self.preview then
        self.preview = false
    else
        self.preview = true
        gui.frame:ClearAllPoints()
        gui.frame:SetPoint('CENTER', UIParent, 'CENTER', cfg().xPos, cfg().yPos)
        gui.frame:Show()
    end
end

--#endregion

--#region ── Event handlers ────────────────────────────────────────────────────

function healthBar:OnHealthChanged(_, unit)
    if unit ~= 'player' then return end
    self:UpdateHealth()
end

function healthBar:OnPlayerEnteringWorld()
    self:UpdateHealth()
end

--#endregion

--#region ── Module lifecycle ──────────────────────────────────────────────────

function healthBar:BuildVisibilityCurve()
    local threshold = cfg().showThreshold / 100
    self.visibilityCurve = C_CurveUtil.CreateCurve()
    self.visibilityCurve:SetType(Enum.LuaCurveType.Step)
    self.visibilityCurve:AddPoint(0.0, 1)       -- at/below threshold: visible
    self.visibilityCurve:AddPoint(threshold, 0) -- above threshold: hidden
end

function healthBar:OnEnable()
    self:CreateUI()
    self:BuildVisibilityCurve()
    self:RegisterEvent('UNIT_HEALTH', 'OnHealthChanged')
    self:RegisterEvent('UNIT_MAXHEALTH', 'OnHealthChanged')
    self:RegisterEvent('PLAYER_ENTERING_WORLD', 'OnPlayerEnteringWorld')
end

function healthBar:OnDisable()
    self.preview         = false
    self.targetHealth    = nil
    self.displayedHealth = nil
    self.targetMaxHP     = nil
    self:UnregisterAllEvents()
    if gui.frame then
        gui.frame:SetScript('OnUpdate', nil)
        gui.frame:Hide()
    end
end

--#endregion

--#region ── Options ───────────────────────────────────────────────────────────

function healthBar:GetDefaults()
    return {
        playerHealthBar = {
            enabled       = true,
            width         = 220,
            height        = 18,
            xPos          = 0,
            yPos          = -150,
            locked        = false,
            showText      = false,
            autoHide      = false,
            showThreshold = 75,
            useClassColor = false,
            colorByPct    = false,
            barColor      = { r = 0.2, g = 0.8, b = 0.2, a = 1.0 },
        },
    }
end

function healthBar:GetOptions()
    return 'playerHealthBar', {
        name  = 'Player Health Bar',
        type  = 'group',
        order = 3,
        args  = {
            description = {
                name  = 'A simple horizontal bar that always shows your current health.',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Enabled',
                type  = 'toggle',
                order = 2,
                get   = function() return addon.db.profile.playerHealthBar.enabled end,
                set   = function(_, value)
                    addon.db.profile.playerHealthBar.enabled = value
                    if value then healthBar:Enable() else healthBar:Disable() end
                end,
            },
            general = {
                name   = 'General',
                type   = 'group',
                order  = 3,
                inline = true,
                args   = {
                    width = {
                        name  = 'Width',
                        desc  = 'Width of the health bar in pixels.',
                        type  = 'range',
                        order = 1,
                        min   = 80,
                        max   = 600,
                        step  = 2,
                        get   = function() return addon.db.profile.playerHealthBar.width end,
                        set   = function(_, value)
                            addon.db.profile.playerHealthBar.width = value
                            healthBar:Refresh()
                            healthBar:UpdateHealth()
                        end,
                    },
                    height = {
                        name  = 'Height',
                        desc  = 'Height of the health bar in pixels.',
                        type  = 'range',
                        order = 2,
                        min   = 10,
                        max   = 60,
                        step  = 2,
                        get   = function() return addon.db.profile.playerHealthBar.height end,
                        set   = function(_, value)
                            addon.db.profile.playerHealthBar.height = value
                            healthBar:Refresh()
                        end,
                    },
                    locked = {
                        name  = 'Lock Position',
                        desc  = 'Prevent the bar from being dragged.',
                        type  = 'toggle',
                        order = 3,
                        get   = function() return addon.db.profile.playerHealthBar.locked end,
                        set   = function(_, value)
                            addon.db.profile.playerHealthBar.locked = value
                            healthBar:Refresh()
                        end,
                    },
                    preview = {
                        name  = function()
                            return healthBar.preview and 'Hide Preview' or 'Show Preview'
                        end,
                        desc  = 'Show the health bar so you can drag it into position.',
                        type  = 'execute',
                        order = 4,
                        func  = function() healthBar:TogglePreview() end,
                    },
                },
            },
            display = {
                name   = 'Display',
                type   = 'group',
                order  = 4,
                inline = true,
                args   = {
                    showText = {
                        name  = 'Show Health Text',
                        desc  = 'Display current and maximum health as numbers on the bar.',
                        type  = 'toggle',
                        order = 1,
                        get   = function() return addon.db.profile.playerHealthBar.showText end,
                        set   = function(_, value)
                            addon.db.profile.playerHealthBar.showText = value
                            healthBar:Refresh()
                            healthBar:UpdateHealth()
                        end,
                    },
                    autoHide = {
                        name  = 'Auto-Hide',
                        desc  = 'Hide the bar when health is above the threshold.',
                        type  = 'toggle',
                        order = 2,
                        get   = function() return addon.db.profile.playerHealthBar.autoHide end,
                        set   = function(_, value)
                            addon.db.profile.playerHealthBar.autoHide = value
                            healthBar:UpdateHealth()
                        end,
                    },
                    showThreshold = {
                        name     = 'Show Below %',
                        desc     = 'Show the bar when health is at or below this percentage.',
                        type     = 'range',
                        order    = 3,
                        min      = 1,
                        max      = 99,
                        step     = 1,
                        disabled = function() return not addon.db.profile.playerHealthBar.autoHide end,
                        get      = function() return addon.db.profile.playerHealthBar.showThreshold end,
                        set      = function(_, value)
                            addon.db.profile.playerHealthBar.showThreshold = value
                            healthBar:BuildVisibilityCurve()
                            healthBar:UpdateHealth()
                        end,
                    },
                },
            },
            colors = {
                name   = 'Colors',
                type   = 'group',
                order  = 5,
                inline = true,
                args   = {
                    useClassColor = {
                        name     = 'Class Color',
                        desc     = 'Color the bar with your class color.',
                        type     = 'toggle',
                        order    = 1,
                        disabled = function() return addon.db.profile.playerHealthBar.colorByPct end,
                        get      = function() return addon.db.profile.playerHealthBar.useClassColor end,
                        set      = function(_, value)
                            addon.db.profile.playerHealthBar.useClassColor = value
                            healthBar:UpdateHealth()
                        end,
                    },
                    colorByPct = {
                        name     = 'Color by Health %',
                        desc     = 'Fade the bar green → yellow → red as health decreases.',
                        type     = 'toggle',
                        order    = 2,
                        disabled = function() return addon.db.profile.playerHealthBar.useClassColor end,
                        get      = function() return addon.db.profile.playerHealthBar.colorByPct end,
                        set      = function(_, value)
                            addon.db.profile.playerHealthBar.colorByPct = value
                            healthBar:UpdateHealth()
                        end,
                    },
                    barColor = {
                        name     = 'Bar Color',
                        desc     = 'Fill color for the health bar.',
                        type     = 'color',
                        order    = 3,
                        hasAlpha = false,
                        disabled = function()
                            local p = addon.db.profile.playerHealthBar
                            return p.useClassColor or p.colorByPct
                        end,
                        get      = function()
                            local c = addon.db.profile.playerHealthBar.barColor
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            local c = addon.db.profile.playerHealthBar.barColor
                            c.r, c.g, c.b = r, g, b
                            healthBar:UpdateHealth()
                        end,
                    },
                },
            },
        },
    }
end

--#endregion

healthBar:Enable()
