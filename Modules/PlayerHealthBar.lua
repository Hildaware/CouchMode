local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local isSecretValue = addon.Utils.IsSecretValue

---@class PlayerHealthBar: AceModule
---@field preview          boolean
---@field visibilityCurve  table
---@field targetValue      number|nil
---@field displayedValue   number|nil
---@field targetAbsorb     number|nil
---@field displayedAbsorb  number|nil
---@field targetMax        number|nil
---@field glowActive       boolean
local healthBar = addon:NewModule('PlayerHealthBar', 'AceEvent-3.0')
---@cast healthBar +AceEvent-3.0

local MEDIA = {
    TEXTURE = 'interface/hud/uiwowlabsactionbar',
    BAR_ATLAS = 'plunderstorm-stormbar-fill',
    BORDER_ATLAS = 'plunderstorm-stormbar-border',
    BG_ATLAS = 'plunderstorm-stormbar-background',
    COMBAT = 'plunderstorm-toast-swords',
}

---@class PlayerHealthBarGUI: StatusBarBaseGUI
---@field glowFrame        Frame
---@field glowAnim         AnimationGroup
---@field combatIconFrame  Frame
---@field combatModelScene ModelScene
local gui = {}

local healthColorCurve

local function cfg()
    return addon.db.profile.playerHealthBar
end

--#region ── Refresh ───────────────────────────────────────────────────────────

function healthBar:Refresh()
    if not gui.frame then return end
    addon.StatusBarBase.Refresh(gui, cfg())
end

--#endregion

--#region ── Health update ─────────────────────────────────────────────────────

function healthBar:UpdateValue()
    local current = UnitHealth('player')
    local maxHP = UnitHealthMax('player')
    local absorb = UnitGetTotalAbsorbs('player') or 0
    local c = cfg()

    gui.bar:SetMinMaxValues(0, maxHP)

    if isSecretValue(current) or isSecretValue(maxHP) then
        -- Can't interpolate secret values; snap immediately
        gui.bar:SetValue(current)
        gui.absorbBar:SetMinMaxValues(0, maxHP)
        gui.absorbBar:SetValue(current)
        self.targetValue = nil
        self.displayedValue = nil
        self.targetAbsorb = nil
        self.displayedAbsorb = nil
    else
        self.targetMax = maxHP
        if self.displayedValue == nil then
            -- First update: snap rather than animate from zero
            self.displayedValue = current
            gui.bar:SetValue(current)
        end
        if self.displayedAbsorb == nil then
            self.displayedAbsorb = absorb
            gui.absorbBar:SetMinMaxValues(0, maxHP)
            gui.absorbBar:SetValue(math.min(current + absorb, maxHP))
        end
        self.targetValue = current
        self.targetAbsorb = absorb
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
            healthColorCurve:AddPoint(0.0, CreateColor(1, 0, 0)) -- red    at   0%
            healthColorCurve:AddPoint(0.5, CreateColor(1, 1, 0)) -- yellow at  50%
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
        gui.label:SetFormattedText('%d / %d', current, maxHP)
    end

    -- Low-health glow
    local pct = (maxHP > 0 and not isSecretValue(current) and not isSecretValue(maxHP))
        and (current / maxHP) or 1
    local wasGlowing = self.glowActive
    self.glowActive = (pct <= 0.4)
    if self.glowActive and not wasGlowing then
        gui.glowFrame:SetAlpha(0.2)
        gui.glowAnim:Play()
    elseif not self.glowActive and wasGlowing then
        gui.glowAnim:Stop()
        gui.glowFrame:SetAlpha(0)
    end

    -- Visibility
    if self.preview then
        gui.frame:SetAlpha(1)
    elseif c.showWhenNotFull then
        -- Show when not full: evaluate via C API so secret values never touch Lua arithmetic.
        -- When combined with showOnlyInCombat, combat overrides to always-show.
        if c.showOnlyInCombat and UnitAffectingCombat('player') then
            gui.frame:SetAlpha(1)
        else
            gui.frame:SetAlpha(UnitHealthPercent('player', true, self.notFullCurve))
        end
    elseif c.showOnlyInCombat and not UnitAffectingCombat('player') then
        gui.frame:SetAlpha(0)
    elseif c.autoHide then
        gui.frame:SetAlpha(self.visibilityCurve and UnitHealthPercent('player', true, self.visibilityCurve) or 1)
    else
        gui.frame:SetAlpha(1)
    end
end

--#endregion

--#region ── UI Construction ───────────────────────────────────────────────────

function healthBar:CreateUI()
    gui = addon.StatusBarBase.CreateBarUI({
        media = MEDIA,
        hasAbsorbBar = true,
    })

    -- Low-health red glow (rendered behind the bar)
    local container = addon.Layout:Container(gui.frame, { frameLevel = 8 })
    container:SetPoint('TOPLEFT', gui.frame, 'TOPLEFT', -65, 30)
    container:SetPoint('BOTTOMRIGHT', gui.frame, 'BOTTOMRIGHT', 65, -30)
    container:AddBackground('CovenantSanctum-Reservoir-Spark-Glow-Venthyr')
    container:AddBackground('CovenantSanctum-Reservoir-Spark-Glow-Venthyr', { flipH = true })
    container:SetAlpha(0)
    gui.glowFrame = container.frame

    local glowAnim = gui.glowFrame:CreateAnimationGroup()
    glowAnim:SetLooping('BOUNCE')
    local fadeIn = glowAnim:CreateAnimation('Alpha')
    fadeIn:SetFromAlpha(0.2)
    fadeIn:SetToAlpha(0.8)
    fadeIn:SetDuration(1)
    fadeIn:SetOrder(1)
    gui.glowAnim = glowAnim

    -- Combat icon above the bar
    local iconContainer = addon.Layout:Container(gui.frame, { frameLevel = 6, height = 40, width = 90 })
    iconContainer:SetPoint('BOTTOM', gui.frame, 'TOP', 0, -15)
    iconContainer:AddBackground(MEDIA.COMBAT)
    gui.combatIconFrame = iconContainer.frame
    gui.combatIconFrame:SetAlpha(UnitAffectingCombat('player') and 1 or 0)

    -- ModelScene animation behind the combat icon
    local scene = CreateFrame('ModelScene', nil, gui.combatIconFrame)
    scene:SetSize(160, 160)
    scene:SetPoint('CENTER', gui.combatIconFrame, 'CENTER', 0, 0)
    scene:SetFrameLevel(4)
    if scene.SetCameraFieldOfView then scene:SetCameraFieldOfView(0.7) end
    if scene.SetLightDirection then scene:SetLightDirection(0.7, -0.7, 0.7) end
    if scene.SetLightAmbientColor then scene:SetLightAmbientColor(0.6, 0.6, 0.6) end
    if scene.SetLightDiffuseColor then scene:SetLightDiffuseColor(1.0, 1.0, 1.0) end

    local combatActor = scene:CreateActor()
    combatActor:SetModelByFileID(1453157)
    combatActor:SetAnimation(0)
    combatActor:SetPosition(0, 0, 0)
    scene:SetCameraPosition(-20, 0.32, -0.08)

    C_Timer.After(0.2, function()
        if not combatActor or not combatActor.GetActiveBoundingBox then return end
        local _, _, z0, _, _, z1 = combatActor:GetActiveBoundingBox()
        if z0 and z1 then
            combatActor:SetPosition(0, 0, -(z0 + z1) / 2)
        end
    end)

    gui.combatModelScene = scene

    gui.frame:SetScript('OnUpdate', addon.StatusBarBase.CreateOnUpdate(self, gui, { hasAbsorbBar = true }))

    self:Refresh()
end

--#endregion

--#region ── Preview ───────────────────────────────────────────────────────────

function healthBar:TogglePreview()
    self.preview = not self.preview
    if self.preview then gui.frame:Show() end
    self:UpdateValue()
end

--#endregion

--#region ── Event handlers ────────────────────────────────────────────────────

function healthBar:OnHealthChanged(_, unit)
    if unit ~= 'player' then return end
    self:UpdateValue()
end

function healthBar:OnPlayerEnteringWorld()
    self:UpdateValue()
end

function healthBar:OnEnterCombat()
    UIFrameFadeIn(gui.combatIconFrame, 0.3, 0, 1)
    self:UpdateValue()
end

function healthBar:OnLeaveCombat()
    UIFrameFadeOut(gui.combatIconFrame, 0.5, 1, 0)
    self:UpdateValue()
end

--#endregion

--#region ── Module lifecycle ──────────────────────────────────────────────────

function healthBar:HandleBlizzPlayerFrame()
    UnregisterUnitWatch(PlayerFrame)
    PlayerFrame:SetAlpha(0)
    PlayerFrame:SetParent(gui.frame)
    PlayerFrame:SetAllPoints(gui.frame)
    PlayerFrame:HookScript("OnShow", function(self) self:SetAlpha(0) end)
    if PlayerFrameBottomManagedFramesContainer then
        PlayerFrameBottomManagedFramesContainer:UnregisterAllEvents()
        PlayerFrameBottomManagedFramesContainer:Hide()
    end
    if PlayerFrame.healthbar then PlayerFrame.healthbar:UnregisterAllEvents() end
    if PlayerFrame.manabar then PlayerFrame.manabar:UnregisterAllEvents() end
    if PlayerFrame.powerBarAlt then PlayerFrame.powerBarAlt:UnregisterAllEvents() end
    if PlayerFrame.spellbar then PlayerFrame.spellbar:UnregisterAllEvents() end
end

function healthBar:BuildVisibilityCurve()
    self.visibilityCurve = addon.StatusBarBase.BuildVisibilityCurve(cfg().showThreshold)

    -- Static step curve: 1 when health < 100%, 0 at exactly 100%.
    -- Built once; evaluated via UnitHealthPercent so secret values never touch Lua arithmetic.
    if not self.notFullCurve then
        self.notFullCurve = C_CurveUtil.CreateCurve()
        self.notFullCurve:SetType(Enum.LuaCurveType.Step)
        self.notFullCurve:AddPoint(0.0, 1)
        self.notFullCurve:AddPoint(1.0, 0)
    end
end

function healthBar:OnEnable()
    if not cfg().enabled then
        self:Disable(); return
    end

    if not gui.frame then
        self:CreateUI()
        self:HandleBlizzPlayerFrame()

        local db  = cfg()
        local frame = gui.frame

        addon.StatusBarBase.RegisterWithEditMode(frame, db, self, {
            label         = 'CouchMode Health',
            widthDefault  = 220,
            heightDefault = 18,
        })
    end

    self:BuildVisibilityCurve()
    self:RegisterEvent('UNIT_HEALTH', 'OnHealthChanged')
    self:RegisterEvent('UNIT_MAXHEALTH', 'OnHealthChanged')
    self:RegisterEvent('UNIT_ABSORB_AMOUNT_CHANGED', 'OnHealthChanged')
    self:RegisterEvent('PLAYER_ENTERING_WORLD', 'OnPlayerEnteringWorld')
    self:RegisterEvent('PLAYER_REGEN_DISABLED', 'OnEnterCombat')
    self:RegisterEvent('PLAYER_REGEN_ENABLED', 'OnLeaveCombat')

    gui.frame:Show()
    self:UpdateValue()
end

function healthBar:OnDisable()
    self.preview = false
    self.targetValue = nil
    self.displayedValue = nil
    self.targetMax = nil
    self.targetAbsorb = nil
    self.displayedAbsorb = nil
    self.glowActive = false
    if gui.glowAnim then gui.glowAnim:Stop() end
    if gui.glowFrame then gui.glowFrame:SetAlpha(0) end
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
        playerHealthBar = addon.StatusBarBase.GetBaseDefaults({
            yPos = -150,
            barColor = { r = 0.2, g = 0.8, b = 0.2, a = 1.0 },
            -- health-specific extras
            useClassColor = false,
            colorByPct = false,
        }),
    }
end

function healthBar:GetOptions()
    local args = addon.StatusBarBase.GetBaseOptionArgs('playerHealthBar', self, {
        description = 'A simple horizontal bar that always shows your current health.',
        extraColorArgs = {
            useClassColor = {
                name = 'Class Color',
                desc = 'Color the bar with your class color.',
                type = 'toggle',
                order = 1,
                disabled = function() return addon.db.profile.playerHealthBar.colorByPct end,
                get = function() return addon.db.profile.playerHealthBar.useClassColor end,
                set = function(_, value)
                    addon.db.profile.playerHealthBar.useClassColor = value
                    healthBar:UpdateValue()
                end,
            },
            colorByPct = {
                name = 'Color by Health %',
                desc = 'Fade the bar green → yellow → red as health decreases.',
                type = 'toggle',
                order = 2,
                disabled = function() return addon.db.profile.playerHealthBar.useClassColor end,
                get = function() return addon.db.profile.playerHealthBar.colorByPct end,
                set = function(_, value)
                    addon.db.profile.playerHealthBar.colorByPct = value
                    healthBar:UpdateValue()
                end,
            },
            -- barColor (order 10) is provided by the base; disable it when a
            -- computed color mode is active
            barColor = {
                name = 'Bar Color',
                desc = 'Fill color for the health bar.',
                type = 'color',
                order = 10,
                hasAlpha = false,
                disabled = function()
                    local p = addon.db.profile.playerHealthBar
                    return p.useClassColor or p.colorByPct
                end,
                get = function()
                    local c = addon.db.profile.playerHealthBar.barColor
                    return c.r, c.g, c.b
                end,
                set = function(_, r, g, b)
                    local c = addon.db.profile.playerHealthBar.barColor
                    c.r, c.g, c.b = r, g, b
                    healthBar:UpdateValue()
                end,
            },
        },
        extraDisplayArgs = {
            showText = {
                name = 'Show Health Text',
                desc = 'Display current and maximum health as numbers on the bar.',
                type = 'toggle',
                order = 1,
                get = function() return addon.db.profile.playerHealthBar.showText end,
                set = function(_, value)
                    addon.db.profile.playerHealthBar.showText = value
                    healthBar:Refresh()
                    healthBar:UpdateValue()
                end,
            },
        },
    })

    return 'playerHealthBar', {
        name = 'Health',
        type = 'group',
        order = 1,
        args = args,
    }
end

--#endregion

healthBar:Enable()
