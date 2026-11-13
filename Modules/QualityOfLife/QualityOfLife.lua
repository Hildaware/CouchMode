-- Small independent conveniences share one module and settings category.
local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local qol = addon:NewModule('QualityOfLife', 'AceEvent-3.0')
addon.QualityOfLife = qol

function qol:OnEnable()
    if not self.profileCallbacks then
        for _, event in ipairs({ 'OnProfileChanged', 'OnProfileCopied', 'OnProfileReset' }) do
            addon.db.RegisterCallback(self, event, 'ConfigureQuickThanks')
        end
        self.profileCallbacks = true
    end
    if addon.Utils.IsFlavor('forever') then
        for event, handler in pairs({
            PLAYER_ENTERING_WORLD = 'ResetQuickThanks',
            GAME_PAD_DISCONNECTED = 'ResetQuickThanks',
            PLAYER_REGEN_ENABLED = 'InitializeQuickThanksEditMode',
            PLAYER_LOGOUT = 'StopQuickThanks',
        }) do
            addon.Utils.RegisterEventIfValid(self, event, handler)
        end
    end
    self:ConfigureQuickThanks()
end

function qol:OnDisable()
    self:UnregisterAllEvents()
    self:StopQuickThanks()
end

-- AceAddon defers enabling until all split files have loaded.
qol:Enable()
