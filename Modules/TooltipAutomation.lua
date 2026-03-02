local addonName = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class NameplateAutomation: AceModule
local tooltipAuto = addon:NewModule('TooltipAutomation', 'AceEvent-3.0', 'AceHook-3.0')
---@cast tooltipAuto +AceEvent-3.0

tooltipAuto:Enable()
