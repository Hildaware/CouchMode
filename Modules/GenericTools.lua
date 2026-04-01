local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class Generic: AceModule
local generic = addon:NewModule('Generic', 'AceEvent-3.0', 'AceHook-3.0')
---@cast generic +AceEvent-3.0

function generic:Toggle(shouldToggle)
    if not addon.db.profile.genericTools.enabled then return end
    if not BuffFrame or not BuffFrame.CollapseAndExpandButton then return end

    local inInstance, instanceType = IsInInstance()

    if InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() or C_Secrets.ShouldCooldownsBeSecret() or
        (inInstance and instanceType ~= "neighborhood" and instanceType ~= "interior") then
        return
    end

    BuffFrame.CollapseAndExpandButton:SetChecked(shouldToggle)
    BuffFrame.CollapseAndExpandButton:UpdateOrientation();
    BuffFrame:SetBuffsExpandedState();
end

function generic:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Toggle", true)
end

function generic:GetDefaults()
    return {
        genericTools = {
            enabled = true,
        },
    }
end

function generic:GetOptions()
    return 'genericTools', {
        name  = 'Generic Tools',
        type  = 'group',
        order = 5,
        args  = {
            description = {
                name  = 'Miscellaneous quality-of-life tools.',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Collapse Buff Frame',
                desc  = 'Automatically collapse the buff on login / zone change.',
                type  = 'toggle',
                order = 2,
                get   = function() return addon.db.profile.genericTools.enabled end,
                set   = function(_, value)
                    addon.db.profile.genericTools.enabled = value
                end,
            },
        },
    }
end

generic:Enable()
