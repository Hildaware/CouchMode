local addonName = ...

---@class ConsoleTools: AceAddon
local addon = LibStub("AceAddon-3.0"):GetAddon(addonName)

---@class Nameplates: AceModule
---@field partyGUIDs    table<string, true>
---@field activePlates  table<string, true>
---@field hookedDisplays table<string, table>
---@field inCombat      boolean
local nameplates = addon:NewModule("Nameplates", "AceEvent-3.0")
---@cast nameplates +AceEvent-3.0

--#region ── Helpers ───────────────────────────────────────────────────────────

local function cfg()
    return addon.db.profile.nameplates
end

local function isPlatynatorEnabled()
    return C_AddOns.IsAddOnLoaded("Platynator")
end

local function isInGroupInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "raid" or instanceType == "party")
end

local function findPlatynatorDisplay(nameplate)
    local children = { nameplate:GetChildren() }
    for _, child in ipairs(children) do
        if type(child.SetUnit) == "function" and type(child.widgets) == "table" then
            return child
        end
    end
end

--#endregion

--#region ── Party tracking ────────────────────────────────────────────────────

function nameplates:UpdatePartyGUIDs()
    if not isPlatynatorEnabled() then return end

    self.partyGUIDs = { [UnitGUID("player")] = true }
    local n = GetNumGroupMembers()
    for i = 1, n do
        local unit = (IsInRaid() and "raid" or "party") .. i
        local guid = UnitGUID(unit)
        if guid then
            self.partyGUIDs[guid] = true
        end
    end
end

--#endregion

--#region ── Platynator integration ───────────────────────────────────────────

--- Force Platynator to render its full display for a unit, bypassing the
--- widgets-only gate that fires when "Friendly Player Names" is OFF.
--- Directly replicates Platynator's SetUnit show-branch without invoking SetUnit
--- itself (which is gated behind UnitNameplateShowsWidgetsOnly).
function nameplates:ForceShowDisplay(unitToken, nameplate)
    nameplate = nameplate or C_NamePlate.GetNamePlateForUnit(unitToken)
    if not nameplate then return end
    local display = findPlatynatorDisplay(nameplate)
    if not display then return end

    display.unit         = unitToken
    display.interactUnit = unitToken
    display:Show()

    for _, w in ipairs(display.widgets) do
        if type(w.SetUnit) == "function" then w:SetUnit(unitToken) end
        if type(w.ApplyTarget) == "function" then w:ApplyTarget() end
        if type(w.ApplyMouseover) == "function" then w:ApplyMouseover() end
        if type(w.ApplyFocus) == "function" then w:ApplyFocus() end
        w:Show()
    end

    if display.BuffDisplay then
        display.BuffDisplay:SetShown(display.BuffDisplay.enabled)
    end
    if display.DebuffDisplay then
        display.DebuffDisplay:SetShown(display.DebuffDisplay.enabled)
    end
    if display.CrowdControlDisplay then
        display.CrowdControlDisplay:SetShown(display.CrowdControlDisplay.enabled)
    end
    if display.AurasManager and type(display.AurasManager.SetUnit) == "function" then
        display.AurasManager:SetUnit(unitToken)
    end

    -- Hook UpdateVisual on this specific display instance so that any time
    -- Platynator calls it (e.g. from UpdateForTarget on PLAYER_TARGET_CHANGED,
    -- PLAYER_SOFT_FRIEND_CHANGED, etc.) it can't reset alpha to NOT_TARGET_ALPHA.
    if not display._ctOriginalUpdateVisual then
        display._ctOriginalUpdateVisual = display.UpdateVisual
        display.UpdateVisual = function(self)
            self._ctOriginalUpdateVisual(self)
            self:SetAlpha(1)
        end
        self.hookedDisplays[unitToken] = display
    end

    display:SetAlpha(1)
end

--- Hooks Platynator's UpdateVisual on the display so it is tracked in
--- hookedDisplays and can be cleanly restored on plate removal or module disable.
function nameplates:ForceHideNPCName(unitToken, nameplate)
    nameplate = nameplate or C_NamePlate.GetNamePlateForUnit(unitToken)
    if not nameplate then return end
    local display = findPlatynatorDisplay(nameplate)
    if not display then return end

    display.unit         = unitToken
    display.interactUnit = unitToken

    if not display._ctOriginalUpdateVisual then
        display._ctOriginalUpdateVisual = display.UpdateVisual
        display.UpdateVisual = function(self)
            self._ctOriginalUpdateVisual(self)
        end
        self.hookedDisplays[unitToken] = display
    end
end

--#endregion

--#region ── Nameplate management ─────────────────────────────────────────────

function nameplates:ApplyToNameplate(unitToken)
    if InCombatLockdown() then return end
    local c = cfg()

    local frame = C_NamePlate.GetNamePlateForUnit(unitToken)
    if not frame then return end

    if UnitIsUnit(unitToken, "target") or
        UnitIsUnit(unitToken, "softfriend") or
        UnitIsUnit(unitToken, "softenemy") or
        UnitIsUnit(unitToken, "softinteract") then
        frame:Show()
        return
    end

    if not UnitIsPlayer(unitToken) then
        if c.showEnemyNpcNames and not UnitIsEnemy("player", unitToken) then
            frame:Hide()
            self:ForceHideNPCName(unitToken, frame)
        else
            frame:Show()
        end
        return
    end

    if self.inCombat and not c.friendlyInCombat then
        frame:Show()
        return
    end

    local inInstance = IsInInstance()
    if inInstance then
        if not c.filterInstances then return end
    elseif GetRestState() == 1 then
        if not c.filterCityInn then return end
    else
        if not c.filterOpenWorld then return end
    end

    local guid = UnitGUID(unitToken)
    local name = UnitName(unitToken)
    local show = (c.partyFilter and self.partyGUIDs[guid])
        or guid == UnitGUID("target")
        or guid == UnitGUID("softfriend")
        or (name and c.allowedNames[name])
    if show then
        self:ForceShowDisplay(unitToken, frame)
    else
        frame:Hide()
    end
end

function nameplates:RefreshAllNameplates()
    if not isPlatynatorEnabled() then return end
    for unitToken in pairs(self.activePlates) do
        self:ApplyToNameplate(unitToken)
    end
end

function nameplates:HideAllNameplates()
    for _, frame in ipairs(C_NamePlate.GetNamePlates()) do
        frame:Hide()
    end
end

--#endregion

--#region ── CVar helpers ──────────────────────────────────────────────────────

function nameplates:ApplySoftTargetCVars()
    local c = cfg()
    SetCVar("SoftTargetFriendRange", c.softTargetFriendRange)
    SetCVar("SoftTargetFriendArc", c.softTargetFriendArc)
    SetCVar("SoftTargetEnemyRange", c.softTargetEnemyRange)
    SetCVar("SoftTargetEnemyArc", c.softTargetEnemyArc)
end

function nameplates:SetFriendlyNameplatesCVars(value)
    -- SetCVar("nameplateShowFriendlyPlayers", value and 1 or 0) -- TODO: Re-enable?
    SetCVar("nameplateShowFriendlyNpcs", value and 1 or 0)
end

function nameplates:ApplyCombatCVars()
    local c = cfg()
    if c.softTargetFriend then SetCVar("SoftTargetFriend", 0) end
    if not c.friendlyInCombat then self:SetFriendlyNameplatesCVars(false) end
end

function nameplates:RestoreCombatCVars()
    local c = cfg()
    if c.softTargetFriend then
        SetCVar("SoftTargetFriend", 1)
        self:ApplySoftTargetCVars()
    end
    if not c.friendlyInCombat then self:SetFriendlyNameplatesCVars(true) end
end

--#endregion

--#region ── Event handlers ────────────────────────────────────────────────────

function nameplates:OnNameplateAdded(_, unitToken)
    if isInGroupInstance() then return end
    if not isPlatynatorEnabled() then return end

    self.activePlates[unitToken] = true
    C_Timer.After(0, function()
        self:ApplyToNameplate(unitToken)
    end)
end

function nameplates:OnNameplateRemoved(_, unitToken)
    if isInGroupInstance() then return end
    if not isPlatynatorEnabled() then return end

    local display = self.hookedDisplays[unitToken]
    if display and display._ctOriginalUpdateVisual then
        display.UpdateVisual            = display._ctOriginalUpdateVisual
        display._ctOriginalUpdateVisual = nil
    end
    self.hookedDisplays[unitToken] = nil
    self.activePlates[unitToken]   = nil
end

function nameplates:OnRosterUpdate()
    if isInGroupInstance() then return end

    self:UpdatePartyGUIDs()
    self:RefreshAllNameplates()
end

function nameplates:OnPlayerEnteringWorld()
    if isInGroupInstance() then return end

    self:UpdatePartyGUIDs()
    self:RefreshAllNameplates()
    if not InCombatLockdown() then
        self:ApplySoftTargetCVars()
    end
end

function nameplates:OnTargetChanged()
    if isInGroupInstance() then return end

    self:RefreshAllNameplates()
end

function nameplates:OnEnterCombat()
    if isInGroupInstance() then return end

    self.inCombat = true
    self:ApplyCombatCVars()
    self:RefreshAllNameplates()
end

function nameplates:OnLeaveCombat()
    if isInGroupInstance() then return end

    self.inCombat = false
    self:RestoreCombatCVars()
    self:RefreshAllNameplates()
end

--#endregion

--#region ── Module lifecycle ──────────────────────────────────────────────────

function nameplates:OnEnable()
    self.activePlates   = {}
    self.hookedDisplays = {}
    self.inCombat       = UnitAffectingCombat("player") == true
    self:UpdatePartyGUIDs()
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnNameplateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNameplateRemoved")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnLeaveCombat")
    self:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", "OnTargetChanged")
end

function nameplates:OnDisable()
    self:UnregisterAllEvents()
    -- Restore any Platynator displays we hooked back to their natural state so
    -- SetUnit() will re-evaluate UnitNameplateShowsWidgetsOnly normally.
    for unitToken, display in pairs(self.hookedDisplays) do
        if display._ctOriginalUpdateVisual then
            display.UpdateVisual            = display._ctOriginalUpdateVisual
            display._ctOriginalUpdateVisual = nil
        end
        display:SetUnit(unitToken)
    end
    self:HideAllNameplates()
    self.activePlates   = {}
    self.hookedDisplays = {}
    self.partyGUIDs     = {}
end

--#endregion

--#region ── Options ───────────────────────────────────────────────────────────

local pendingName  = ""
local nameListArgs = {
    description = {
        name  = "Always show nameplates for specific players, regardless of group membership.",
        type  = "description",
        order = 1,
    },
    newNameInput = {
        name  = "Player Name",
        type  = "input",
        order = 2,
        get   = function() return pendingName end,
        set   = function(_, v) pendingName = v end,
    },
    addName = {
        name  = "Add",
        type  = "execute",
        order = 3,
        func  = function()
            local n = pendingName:match("^%s*(.-)%s*$")
            if n ~= "" then
                cfg().allowedNames[n] = true
                pendingName = ""
                nameplates:RebuildOptions()
            end
        end,
    },
}

function nameplates:RebuildOptions()
    for k in pairs(nameListArgs) do
        if k ~= "description" and k ~= "newNameInput" and k ~= "addName" then
            nameListArgs[k] = nil
        end
    end
    local i = 10
    for name in pairs(cfg().allowedNames) do
        local n = name
        nameListArgs["entry_" .. n] = {
            name  = "Remove: " .. n,
            type  = "execute",
            order = i,
            func  = function()
                cfg().allowedNames[n] = nil
                nameplates:RebuildOptions()
            end,
        }
        i = i + 1
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

function nameplates:GetDefaults()
    return {
        nameplates = {
            enabled               = true,
            softTargetFriend      = false,
            softTargetFriendRange = 45,
            softTargetFriendArc   = 1,
            softTargetEnemy       = true,
            softTargetEnemyRange  = 45,
            softTargetEnemyArc    = 1,
            partyFilter           = true,
            filterOpenWorld       = true,
            filterCityInn         = false,
            filterInstances       = false,
            allowedNames          = {},
            showEnemyNpcNames     = false,
            friendlyInCombat      = true,
        },
    }
end

function nameplates:GetOptions()
    return "nameplates",
        {
            name  = "Nameplates",
            type  = "group",
            order = 5,
            args  = {
                description = {
                    name  = "Manage nameplate visibility and display for friendly and enemy units.",
                    type  = "description",
                    order = 1,
                },
                enabled = {
                    name  = "Enabled",
                    type  = "toggle",
                    order = 2,
                    get   = function() return cfg().enabled end,
                    set   = function(_, value)
                        cfg().enabled = value
                        if value then nameplates:Enable() else nameplates:Disable() end
                    end,
                },
                friendlyNameplates = {
                    name  = "Friendly Nameplates",
                    type  = "group",
                    order = 3,
                    args  = {
                        filtering = {
                            name   = "Filtering",
                            type   = "group",
                            order  = 1,
                            inline = true,
                            args   = {
                                partyFilter = {
                                    name  = "Raid/Party Only",
                                    desc  = "Only show nameplates for players in your group.",
                                    type  = "toggle",
                                    order = 1,
                                    get   = function() return cfg().partyFilter end,
                                    set   = function(_, v)
                                        cfg().partyFilter = v
                                        nameplates:RefreshAllNameplates()
                                    end,
                                },
                                nameFilter = {
                                    name   = "Name-based Filters",
                                    type   = "group",
                                    order  = 2,
                                    inline = true,
                                    args   = nameListArgs,
                                },
                                whenToFilter = {
                                    name   = "When",
                                    type   = "group",
                                    order  = 3,
                                    inline = true,
                                    args   = {
                                        filterOpenWorld = {
                                            name  = "Open World",
                                            desc  = "Apply nameplate filtering outside of instances.",
                                            type  = "toggle",
                                            order = 1,
                                            get   = function() return cfg().filterOpenWorld end,
                                            set   = function(_, v)
                                                cfg().filterOpenWorld = v
                                                nameplates:RefreshAllNameplates()
                                            end,
                                        },
                                        filterCityInn = {
                                            name  = "City / Inn",
                                            desc  = "Apply nameplate filtering while in a city or inn (rested area).",
                                            type  = "toggle",
                                            order = 2,
                                            get   = function() return cfg().filterCityInn end,
                                            set   = function(_, v)
                                                cfg().filterCityInn = v
                                                nameplates:RefreshAllNameplates()
                                            end,
                                        },
                                        filterInstances = {
                                            name  = "Instances",
                                            desc  = "Apply nameplate filtering inside dungeons and raids.",
                                            type  = "toggle",
                                            order = 3,
                                            get   = function() return cfg().filterInstances end,
                                            set   = function(_, v)
                                                cfg().filterInstances = v
                                                nameplates:RefreshAllNameplates()
                                            end,
                                        },
                                    },
                                },
                            },
                        },
                        visibility = {
                            name   = "Visibility",
                            type   = "group",
                            order  = 2,
                            inline = true,
                            args   = {
                                visibilityTag = {
                                    name  = "Toggle when Friendly Nameplates are shown.",
                                    type  = "description",
                                    order = 1,
                                },
                                friendlyInCombat = {
                                    name  = "In Combat",
                                    desc  = "Enable / Disable Friendly Nameplates in Combat.",
                                    type  = "toggle",
                                    order = 2,
                                    get   = function() return cfg().friendlyInCombat end,
                                    set   = function(_, v)
                                        cfg().friendlyInCombat = v
                                        nameplates:SetFriendlyNameplatesCVars(v)
                                    end,
                                },
                            },
                        },
                        softTarget = {
                            name   = "Soft Target",
                            type   = "group",
                            order  = 3,
                            inline = true,
                            args   = {
                                softTargetFriend = {
                                    name  = "Friend In Combat",
                                    desc  =
                                    "Automatically enable/disable soft-targeting of friendly players based on combat state.",
                                    type  = "toggle",
                                    order = 1,
                                    get   = function() return cfg().softTargetFriend end,
                                    set   = function(_, value)
                                        cfg().softTargetFriend = value
                                        if not InCombatLockdown() then
                                            SetCVar("SoftTargetFriend", value and 1 or 0)
                                            if value then nameplates:ApplySoftTargetCVars() end
                                        end
                                    end,
                                },
                                softTargetFriendRange = {
                                    name  = "Range",
                                    desc  = "Maximum range for soft-targeting a friendly player (0–100).",
                                    type  = "range",
                                    order = 2,
                                    min   = 0,
                                    max   = 100,
                                    step  = 1,
                                    get   = function() return cfg().softTargetFriendRange end,
                                    set   = function(_, value)
                                        cfg().softTargetFriendRange = value
                                        if not InCombatLockdown() then
                                            SetCVar("SoftTargetFriendRange", value)
                                        end
                                    end,
                                },
                                softTargetFriendArc = {
                                    name   = "Arc",
                                    desc   = "Direction requirement for soft-targeting a friendly player.",
                                    type   = "select",
                                    order  = 3,
                                    values = { [0] = "None", [1] = "Must Be in Front", [2] = "Anywhere" },
                                    get    = function() return cfg().softTargetFriendArc end,
                                    set    = function(_, value)
                                        cfg().softTargetFriendArc = value
                                        if not InCombatLockdown() then
                                            SetCVar("SoftTargetFriendArc", value)
                                        end
                                    end,
                                },
                            },
                        },
                    },
                },
                enemyNameplates = {
                    name  = "Enemy Nameplates",
                    type  = "group",
                    order = 4,
                    args  = {
                        visibility = {
                            name   = "Visibility",
                            type   = "group",
                            order  = 1,
                            inline = true,
                            args   = {
                                showEnemyNpcNames = {
                                    name  = "Show Hostile NPC Names",
                                    desc  =
                                    "Force-show name text on hostile enemy NPC nameplates, even when NPC Names is OFF.",
                                    type  = "toggle",
                                    order = 1,
                                    get   = function() return cfg().showEnemyNpcNames end,
                                    set   = function(_, v)
                                        cfg().showEnemyNpcNames = v
                                        nameplates:RefreshAllNameplates()
                                    end,
                                },
                            },
                        },
                        softTarget = {
                            name   = "Soft Target",
                            type   = "group",
                            order  = 2,
                            inline = true,
                            args   = {
                                softTargetEnemy = {
                                    name  = "Enemy in Combat",
                                    desc  =
                                    "Automatically enable/disable soft-targeting of enemy players based on combat state.",
                                    type  = "toggle",
                                    order = 1,
                                    get   = function() return cfg().softTargetEnemy end,
                                    set   = function(_, value)
                                        cfg().softTargetEnemy = value
                                        if not InCombatLockdown() then
                                            SetCVar("SoftTargetEnemy", value and 1 or 0)
                                            if value then nameplates:ApplySoftTargetCVars() end
                                        end
                                    end,
                                },
                                softTargetEnemyRange = {
                                    name  = "Range",
                                    desc  = "Maximum range for soft-targeting an enemy player (0–100).",
                                    type  = "range",
                                    order = 2,
                                    min   = 0,
                                    max   = 100,
                                    step  = 1,
                                    get   = function() return cfg().softTargetEnemyRange end,
                                    set   = function(_, value)
                                        cfg().softTargetEnemyRange = value
                                        if not InCombatLockdown() then
                                            SetCVar("SoftTargetEnemyRange", value)
                                        end
                                    end,
                                },
                                softTargetEnemyArc = {
                                    name   = "Arc",
                                    desc   = "Direction requirement for soft-targeting an enemy player.",
                                    type   = "select",
                                    order  = 3,
                                    values = { [0] = "None", [1] = "Must Be in Front", [2] = "Anywhere" },
                                    get    = function() return cfg().softTargetEnemyArc end,
                                    set    = function(_, value)
                                        cfg().softTargetEnemyArc = value
                                        if not InCombatLockdown() then
                                            SetCVar("SoftTargetEnemyArc", value)
                                        end
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        }
end

--#endregion

nameplates:Enable()
