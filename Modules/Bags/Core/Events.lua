local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Events: AceModule|AceEvent-3.0
local events     = addon:NewModule('Bags.Events', 'AceEvent-3.0')
---@cast events +AceEvent-3.0

---@class Utils: AceModule
local utils      = addon:GetModule('Bags.Utils')

function events:OnInitialize()
    LibStub:GetLibrary('AceEvent-3.0'):Embed(self)

    self:RegisterEvent('PLAYER_ENTERING_WORLD')
    self:RegisterEvent('BAG_CONTAINER_UPDATE')
    self:RegisterEvent('EQUIPMENT_SETS_CHANGED')
    self:RegisterEvent('PLAYER_MONEY')
    self:RegisterEvent('ACCOUNT_MONEY')
    self:RegisterEvent('PLAYERBANKSLOTS_CHANGED')
    -- self:RegisterEvent('PLAYERBANKBAGSLOTS_CHANGED')
    -- self:RegisterEvent('PLAYERREAGENTBANKSLOTS_CHANGED')
    self:RegisterEvent('BAG_UPDATE')
    self:RegisterEvent('PLAYER_REGEN_DISABLED')
    self:RegisterEvent('CURRENCY_DISPLAY_UPDATE')
end

function events:PLAYER_ENTERING_WORLD()
    utils.CreateEnableBagButtons()
    utils.BagDestroyer()
    utils.DestroyDefaultBags()
end

---@param message string
---@param callback string|function
function events:Register(message, callback)
    self:RegisterMessage(message, callback)
end

---@param message string
---@param ... any
function events:Send(message, ...)
    self:SendMessage(message, ...)
end

events:Enable()
