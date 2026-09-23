local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local LibEditMode = LibStub('LibEditMode')
local isSecretValue = addon.Utils.IsSecretValue

local SMOOTH_RATE = 2 -- exponential lerp factor (higher = snappier)

---@class StatusBarBaseGUI
---@field frame     Frame
---@field bg        Texture
---@field bar       LayoutStatusBar
---@field absorbBar LayoutStatusBar|nil
---@field border    Texture
---@field label     LayoutFontString

---@class StatusBarBaseMedia
---@field TEXTURE      string
---@field BAR_ATLAS    string
---@field BORDER_ATLAS string
---@field BG_ATLAS     string

---@class StatusBarBaseCreateOpts
---@field media           StatusBarBaseMedia
---@field hasAbsorbBar?   boolean
---@field absorbBarColor? { r: number, g: number, b: number, a: number }

---@class StatusBarBaseOptionOpts
---@field description?      string
---@field extraDisplayArgs? table
---@field extraColorArgs?   table

addon.StatusBarBase = {}
local StatusBarBase = addon.StatusBarBase

--#region ── UI Construction ───────────────────────────────────────────────────

--- Creates the standard bar frame structure: container, background, bar(s), border,
--- and a text label overlay.
---@param opts  StatusBarBaseCreateOpts
---@return StatusBarBaseGUI
function StatusBarBase.CreateBarUI(opts)
    local media = opts.media
    local gui = {}

    local container = addon.Layout:Container(UIParent, {
        frameStrata = 'MEDIUM',
        frameLevel = 10,
    })
    gui.frame = container.frame

    gui.bg = container:AddBackground(media.BG_ATLAS)

    if opts.hasAbsorbBar then
        gui.absorbBar = container:StatusBar({
            texture = media.TEXTURE,
            atlas = media.BAR_ATLAS,
            desaturate = true,
        })
        gui.absorbBar:SetAllPoints(gui.frame)
        gui.absorbBar.bar:SetFrameLevel(gui.frame:GetFrameLevel() + 1)
        local ac = opts.absorbBarColor or { r = 0.2, g = 0.8, b = 1.0, a = 0.6 }
        gui.absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, ac.a)
    end

    gui.bar = container:StatusBar({
        texture = media.TEXTURE,
        atlas = media.BAR_ATLAS,
        desaturate = true,
    })
    gui.bar:SetAllPoints(gui.frame)
    gui.bar.bar:SetFrameLevel(gui.frame:GetFrameLevel() + (opts.hasAbsorbBar and 2 or 1))

    gui.border = container:AddBackground(media.BORDER_ATLAS, { layer = 'OVERLAY', subLevel = 2 })

    local overlay = container:Container({ frameLevel = 12 })
    overlay:SetAllPoints(container)

    local label = overlay:FontString({
        justifyH = 'LEFT',
        color = { 1, 1, 1 },
        font = function() return GameFontNormal:GetFont() end,
    })
    label:SetPoint('LEFT', overlay, 'LEFT', 8, 0)
    gui.label = label

    return gui
end

--#endregion

--#region ── Shared helpers ────────────────────────────────────────────────────

--- Applies size and label visibility from the config to the gui.
--- Position is managed by LibEditMode; this function intentionally does not touch anchors.
---@param gui StatusBarBaseGUI
---@param c   table  the module's config subtable
function StatusBarBase.Refresh(gui, c)
    gui.frame:SetFrameStrata(c.frameStrata or 'MEDIUM')
    gui.frame:SetSize(c.width, c.height)
    gui.frame:SetMovable(false)
    gui.frame:EnableMouse(true)
    gui.label:SetShown(c.showText)
end

--- Builds a step visibility curve: returns 1 (visible) at/below the threshold
--- percentage, 0 (hidden) above it.
---@param threshold number  percentage 0–100
---@return table  C_CurveUtil curve object
function StatusBarBase.BuildVisibilityCurve(threshold)
    local pct = threshold / 100
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0.0, 1) -- at/below threshold: visible
    curve:AddPoint(pct, 0) -- above threshold: hidden
    return curve
end

--- Returns an OnUpdate handler that smoothly lerps bar values on the module.
--- The module must expose targetValue / displayedValue for the primary bar.
--- When opts.hasAbsorbBar is true, also animates targetAbsorb / displayedAbsorb
--- against targetMax.
---@param module table              the AceModule instance
---@param gui    StatusBarBaseGUI
---@param opts?  { hasAbsorbBar?: boolean }
---@return fun(frame: Frame, elapsed: number)
function StatusBarBase.CreateOnUpdate(module, gui, opts)
    local hasAbsorb = opts and opts.hasAbsorbBar
    return function(_, elapsed)
        -- Primary bar smoothing
        if module.targetValue then
            local displayed = module.displayedValue
            local target = module.targetValue
            if isSecretValue(target) or isSecretValue(displayed) then
                -- Can't do arithmetic on secret values; snap immediately
                module.displayedValue = target
                gui.bar:SetValue(target)
            else
                local delta = target - displayed
                if math.abs(delta) < 1 then
                    module.displayedValue = target
                else
                    module.displayedValue = displayed + delta * math.min(SMOOTH_RATE * elapsed, 1)
                end
                gui.bar:SetValue(module.displayedValue)
            end
        end

        -- Absorb bar smoothing
        if hasAbsorb and module.targetAbsorb and module.targetMax then
            local dispAbs = module.displayedAbsorb or 0
            local targAbs = module.targetAbsorb
            if isSecretValue(targAbs) or isSecretValue(dispAbs) or isSecretValue(module.targetMax) then
                module.displayedAbsorb = targAbs
                gui.absorbBar:SetMinMaxValues(0, module.targetMax)
                gui.absorbBar:SetValue(targAbs)
            else
                local deltaAbs = targAbs - dispAbs
                if math.abs(deltaAbs) < 1 then
                    module.displayedAbsorb = targAbs
                else
                    module.displayedAbsorb = dispAbs + deltaAbs * math.min(SMOOTH_RATE * elapsed, 1)
                end
                gui.absorbBar:SetMinMaxValues(0, module.targetMax)
                gui.absorbBar:SetValue(
                    math.min((module.displayedValue or 0) + module.displayedAbsorb, module.targetMax)
                )
            end
        end
    end
end

--#endregion

--#region ── Visibility ───────────────────────────────────────────────────────

--- Evaluates the bar's show/hide rules in priority order and returns the target alpha.
--- Returns 1 (show), 0 (hide), or nil meaning "the caller should apply its autoHide logic".
--- Priority: showWhenNotFull > showOnlyInCombat > autoHide.
---
--- pct must already be safe to compare: compute it with IsSecretValue guards and default
--- to 1.0 when values are secret. That way pct < 1.0 never touches a secret value, and
--- showWhenNotFull conservatively does not fire when health cannot be read.
---@param pct      number   current/max in [0, 1]; use 1.0 for unknown/secret
---@param inCombat boolean
---@param c        table    the module's config subtable
---@return number|nil       0, 1, or nil (apply autoHide)
function StatusBarBase.ComputeVisibility(pct, inCombat, c)
    if c.showWhenNotFull and pct < 1.0 then return 1 end
    if c.showOnlyInCombat and not inCombat then return 0 end
    if not c.autoHide then return 1 end
    return nil -- caller applies its own autoHide alpha (e.g. curve, UnitHealthPercent)
end

--#endregion

--#region ── Options helpers ───────────────────────────────────────────────────

--- Returns a defaults table for a resource bar config key, merged with overrides.
---@param overrides? table
---@return table
function StatusBarBase.GetBaseDefaults(overrides)
    local defaults = {
        enabled = true,
        width = 220,
        height = 18,
        xPos = 0,
        yPos = -150,
        locked = false,
        positions = {},
        frameStrata = 'MEDIUM',
        showText = false,
        autoHide = false,
        showThreshold = 75,
        showOnlyInCombat = false,
        showWhenNotFull = false,
        barColor = { r = 0.2, g = 0.8, b = 0.2, a = 1.0 },
    }
    if overrides then
        for k, v in pairs(overrides) do defaults[k] = v end
    end
    return defaults
end

--- Builds the standard AceOptions args subtable for a resource bar.
--- Includes: enabled toggle, display group (showText/autoHide/showThreshold), colors group (barColor).
--- Extra args can be injected into display or colors via opts.extraDisplayArgs / opts.extraColorArgs.
--- The module must implement :Refresh(), :UpdateValue(), and :BuildVisibilityCurve().
---@param dbKey  string                the profile key (e.g. 'playerHealthBar')
---@param module table                 the AceModule instance
---@param opts?  StatusBarBaseOptionOpts
---@return table  args table ready to embed in a GetOptions group
function StatusBarBase.GetBaseOptionArgs(dbKey, module, opts)
    local db = function() return addon.db.profile[dbKey] end
    local extraDisplay = opts and opts.extraDisplayArgs or {}
    local extraColors = opts and opts.extraColorArgs or {}

    local args = {}

    if opts and opts.description then
        args.description = {
            name = opts.description,
            type = 'description',
            order = 1,
        }
    end

    args.enabled = {
        name = 'Enabled',
        type = 'toggle',
        order = 2,
        get = function() return db().enabled end,
        set = function(_, value)
            db().enabled = value
            if value then module:Enable() else module:Disable() end
        end,
    }

    args.display = {
        name = 'Display',
        type = 'group',
        order = 4,
        inline = true,
        args = {
            showText = {
                name = 'Show Text',
                desc = 'Display current and maximum values as numbers on the bar.',
                type = 'toggle',
                order = 1,
                get = function() return db().showText end,
                set = function(_, value)
                    db().showText = value
                    module:Refresh()
                    module:UpdateValue()
                end,
            },
            autoHide = {
                name = 'Auto-Hide',
                desc = 'Hide the bar when the value is above the threshold.',
                type = 'toggle',
                order = 2,
                get = function() return db().autoHide end,
                set = function(_, value)
                    db().autoHide = value
                    module:UpdateValue()
                end,
            },
            showThreshold = {
                name = 'Show Below %',
                desc = 'Show the bar when the value is at or below this percentage.',
                type = 'range',
                order = 3,
                min = 1,
                max = 99,
                step = 1,
                disabled = function() return not db().autoHide end,
                get = function() return db().showThreshold end,
                set = function(_, value)
                    db().showThreshold = value
                    module:BuildVisibilityCurve()
                    module:UpdateValue()
                end,
            },
            showOnlyInCombat = {
                name = 'Show Only in Combat',
                desc =
                'Hide the bar while out of combat. When combined with "Always Show When Not Full", the bar still appears out of combat if the value is below maximum.',
                type = 'toggle',
                order = 4,
                get = function() return db().showOnlyInCombat end,
                set = function(_, value)
                    db().showOnlyInCombat = value
                    module:UpdateValue()
                end,
            },
            showWhenNotFull = {
                name = 'Always Show When Not Full',
                desc = 'Always show the bar when the value is below maximum, regardless of other visibility settings.',
                type = 'toggle',
                order = 5,
                get = function() return db().showWhenNotFull end,
                set = function(_, value)
                    db().showWhenNotFull = value
                    module:UpdateValue()
                end,
            },
        },
    }

    args.colors = {
        name = 'Colors',
        type = 'group',
        order = 5,
        inline = true,
        args = {
            barColor = {
                name = 'Bar Color',
                desc = 'Fill color for the bar.',
                type = 'color',
                order = 10, -- leave room for module-specific color options before this
                hasAlpha = false,
                get = function()
                    local c = db().barColor
                    return c.r, c.g, c.b
                end,
                set = function(_, r, g, b)
                    local c = db().barColor
                    c.r, c.g, c.b = r, g, b
                    module:UpdateValue()
                end,
            },
        },
    }

    for k, v in pairs(extraDisplay) do args.display.args[k] = v end
    for k, v in pairs(extraColors) do args.colors.args[k] = v end

    return args
end

--#endregion

--#region ── LibEditMode helpers ──────────────────────────────────────────────

---@class StatusBarBaseEditModeOpts
---@field label         string  Edit Mode label (e.g. 'CouchMode Health')
---@field widthDefault  number  Default/reset value for the Width slider
---@field heightDefault number  Default/reset value for the Height slider
---@field exitFn?       fun()   Exit callback; defaults to module:UpdateValue()

--- Registers a standard horizontal bar frame with LibEditMode.
--- Sets the initial position, wires up AddFrame + AddFrameSettings (Width, Height, Frame Strata),
--- and registers layout / enter / exit callbacks.
---@param frame  Frame
---@param db     table  the module's config subtable
---@param module table  the AceModule instance (must implement :Refresh() and :UpdateValue())
---@param opts   StatusBarBaseEditModeOpts
function StatusBarBase.RegisterWithEditMode(frame, db, module, opts)
    frame:SetPoint('CENTER', UIParent, 'CENTER', db.xPos, db.yPos)

    LibEditMode:AddFrame(frame, function(_, layoutName, point, x, y)
        db.positions[layoutName] = { point = point, x = x, y = y }
    end, { point = 'CENTER', x = db.xPos, y = db.yPos }, opts.label)

    LibEditMode:AddFrameSettings(frame, {
        {
            kind      = LibEditMode.SettingType.Slider,
            name      = 'Width',
            desc      = 'Width of the bar in pixels.',
            default   = opts.widthDefault,
            minValue  = 80,
            maxValue  = 600,
            valueStep = 2,
            get = function(_) return db.width end,
            set = function(_, value, fromReset)
                db.width = fromReset and opts.widthDefault or value
                module:Refresh()
            end,
        },
        {
            kind      = LibEditMode.SettingType.Slider,
            name      = 'Height',
            desc      = 'Height of the bar in pixels.',
            default   = opts.heightDefault,
            minValue  = 10,
            maxValue  = 60,
            valueStep = 2,
            get = function(_) return db.height end,
            set = function(_, value, fromReset)
                db.height = fromReset and opts.heightDefault or value
                module:Refresh()
            end,
        },
        {
            kind    = LibEditMode.SettingType.Dropdown,
            name    = 'Frame Strata',
            desc    = 'Rendering layer for the bar. Raise this if other frames overlap it.',
            default = 'MEDIUM',
            values  = {
                { text = 'Background',        value = 'BACKGROUND' },
                { text = 'Low',               value = 'LOW' },
                { text = 'Medium',            value = 'MEDIUM' },
                { text = 'High',              value = 'HIGH' },
                { text = 'Dialog',            value = 'DIALOG' },
                { text = 'Fullscreen',        value = 'FULLSCREEN' },
                { text = 'Fullscreen Dialog', value = 'FULLSCREEN_DIALOG' },
                { text = 'Tooltip',           value = 'TOOLTIP' },
            },
            get = function(_) return db.frameStrata end,
            set = function(_, value, fromReset)
                db.frameStrata = fromReset and 'MEDIUM' or value
                module:Refresh()
            end,
        },
    })

    LibEditMode:RegisterCallback('layout', function(layoutName)
        local pos = db.positions[layoutName]
        frame:ClearAllPoints()
        if pos then
            frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
        else
            frame:SetPoint('CENTER', UIParent, 'CENTER', db.xPos, db.yPos)
        end
    end)

    LibEditMode:RegisterCallback('enter', function() frame:Show() end)
    LibEditMode:RegisterCallback('exit',  opts.exitFn or function() module:UpdateValue() end)
end

--#endregion
