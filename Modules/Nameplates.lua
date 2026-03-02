local addonName = ...

---@class ConsoleTools: AceAddon
local addon = LibStub("AceAddon-3.0"):GetAddon(addonName)

---@class Nameplates: AceModule
---@field partyGUIDs   table<string, true>
---@field activePlates table<string, true>
local nameplates = addon:NewModule("Nameplates", "AceEvent-3.0")
---@cast nameplates +AceEvent-3.0

local function cfg()
    return addon.db.profile.nameplates
end

--#region ── Party tracking ────────────────────────────────────────────────────

function nameplates:UpdatePartyGUIDs()
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

--#region ── Nameplate filtering ───────────────────────────────────────────────

function nameplates:ApplyToNameplate(unitToken)
    if IsInInstance() then return end
    if not InCombatLockdown() then
        if not UnitIsPlayer(unitToken) then
            return
        end
        local frame = C_NamePlate.GetNamePlateForUnit(unitToken)
        if frame then
            local guid = UnitGUID(unitToken)
            if self.partyGUIDs[guid] or guid == UnitGUID("target") or guid == UnitGUID("softfriend") then
                frame:Show()
            else
                frame:Hide()
            end
        end
    end
end

function nameplates:RefreshAllNameplates()
    for unitToken in pairs(self.activePlates) do
        self:ApplyToNameplate(unitToken)
    end
end

function nameplates:RestoreAllNameplates()
    for _, frame in ipairs(C_NamePlate.GetNamePlates()) do
        frame:Show()
    end
end

--#endregion

--#region ── Event handlers ────────────────────────────────────────────────────

function nameplates:OnNameplateAdded(_, unitToken)
    self.activePlates[unitToken] = true
    self:ApplyToNameplate(unitToken)
end

function nameplates:OnNameplateRemoved(_, unitToken)
    self.activePlates[unitToken] = nil
end

function nameplates:OnRosterUpdate()
    self:UpdatePartyGUIDs()
    self:RefreshAllNameplates()
end

function nameplates:OnPlayerEnteringWorld()
    self:UpdatePartyGUIDs()
    self:RefreshAllNameplates()
    if not InCombatLockdown() then
        self:ApplySoftTargetCVars()
    end
end

function nameplates:OnTargetChanged()
    self:RefreshAllNameplates()
end

function nameplates:ApplySoftTargetCVars()
    local c = cfg()
    SetCVar("SoftTargetFriendRange", c.softTargetFriendRange)
    SetCVar("SoftTargetFriendArc", c.softTargetFriendArc)
end

function nameplates:OnEnterCombat()
    -- SetCVar("UnitNameFriendlyPlayerName", 0)
    if cfg().softTargetFriend then
        SetCVar("SoftTargetFriend", 0)
    end
end

function nameplates:OnLeaveCombat()
    -- SetCVar("UnitNameFriendlyPlayerName", 1)
    if cfg().softTargetFriend then
        SetCVar("SoftTargetFriend", 1)
        self:ApplySoftTargetCVars()
    end
end

--#endregion

--#region ── Module lifecycle ──────────────────────────────────────────────────

function nameplates:OnEnable()
    self.activePlates = {}
    self:UpdatePartyGUIDs()
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnNameplateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNameplateRemoved")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED", "OnTargetChanged")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnLeaveCombat")
end

function nameplates:OnDisable()
    self:UnregisterAllEvents()
    self:RestoreAllNameplates()
    self.activePlates = {}
    self.partyGUIDs = {}
end

--#endregion

--#region ── Options ───────────────────────────────────────────────────────────

function nameplates:GetDefaults()
    return {
        nameplates = {
            enabled               = true,
            softTargetFriend      = true,
            softTargetFriendRange = 45,
            softTargetFriendArc   = 1,
        },
    }
end

function nameplates:GetOptions()
    return "nameplates",
        {
            name = "Nameplates",
            type = "group",
            order = 5,
            args = {
                description = {
                    name = "Hide player nameplates for anyone not in your group. NPC nameplates are unaffected.",
                    type = "description",
                    order = 1,
                },
                enabled = {
                    name  = 'Enabled',
                    type  = 'toggle',
                    order = 2,
                    get   = function() return cfg().enabled end,
                    set   = function(_, value)
                        cfg().enabled = value
                        if value then nameplates:Enable() else nameplates:Disable() end
                    end,
                },
                softTarget = {
                    name   = 'Soft Target',
                    type   = 'group',
                    order  = 3,
                    inline = true,
                    args   = {
                        softTargetFriend = {
                            name  = 'Enable Soft Target Friend',
                            desc  =
                            'Automatically enable/disable soft-targeting of friendly players based on combat state.',
                            type  = 'toggle',
                            order = 1,
                            get   = function() return cfg().softTargetFriend end,
                            set   = function(_, value)
                                cfg().softTargetFriend = value
                                if not InCombatLockdown() then
                                    SetCVar('SoftTargetFriend', value and 1 or 0)
                                    if value then nameplates:ApplySoftTargetCVars() end
                                end
                            end,
                        },
                        softTargetFriendRange = {
                            name     = 'Range',
                            desc     = 'Maximum range for soft-targeting a friendly player (0–100).',
                            type     = 'range',
                            order    = 2,
                            disabled = function() return not cfg().softTargetFriend end,
                            min      = 0,
                            max      = 100,
                            step     = 1,
                            get      = function() return cfg().softTargetFriendRange end,
                            set      = function(_, value)
                                cfg().softTargetFriendRange = value
                                if not InCombatLockdown() then
                                    SetCVar('SoftTargetFriendRange', value)
                                end
                            end,
                        },
                        softTargetFriendArc = {
                            name     = 'Arc',
                            desc     = 'Direction requirement for soft-targeting a friendly player.',
                            type     = 'select',
                            order    = 3,
                            disabled = function() return not cfg().softTargetFriend end,
                            values   = { [0] = 'None', [1] = 'Must Be in Front', [2] = 'Anywhere' },
                            get      = function() return cfg().softTargetFriendArc end,
                            set      = function(_, value)
                                cfg().softTargetFriendArc = value
                                if not InCombatLockdown() then
                                    SetCVar('SoftTargetFriendArc', value)
                                end
                            end,
                        },
                    },
                },
            },
        }
end

--#endregion

nameplates:Enable()
