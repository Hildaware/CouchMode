local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class Bags: AceModule
local bags       = addon:NewModule('Bags', 'AceEvent-3.0', 'AceHook-3.0')
