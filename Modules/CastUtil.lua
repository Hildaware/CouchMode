local addonName = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

--- Shared utilities used by cast bar modules (CastRing, PlayerCastBar).
---@class CastUtil
---@field GetCastInfo      fun(isChannel: boolean): string?, string?, integer?, integer?
---@field ApplyDragToMove  fun(frame: Frame, cfgFn: fun(): table)
---@field RegisterCastEvents fun(module: AceModule)
---@field ResolveColor     fun(moduleCfg: table, isChannel: boolean): number, number, number, number
addon.CastUtil = {}
local CastUtil = addon.CastUtil

--- Returns name, iconTexture, startTimeMS, endTimeMS for the player's active cast or channel.
function CastUtil.GetCastInfo(isChannel)
    if isChannel then
        local name, _, texture, startTimeMS, endTimeMS = UnitChannelInfo("player")
        return name, texture, startTimeMS, endTimeMS
    else
        local name, _, texture, startTimeMS, endTimeMS = UnitCastingInfo("player")
        return name, texture, startTimeMS, endTimeMS
    end
end

--- Sets up left-button drag on a frame with automatic position persistence.
--- cfgFn must be a function returning a table with xPos and yPos fields.
function CastUtil.ApplyDragToMove(frame, cfgFn)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local sx, sy = f:GetCenter()
        cfgFn().xPos = sx - UIParent:GetWidth()  / 2
        cfgFn().yPos = sy - UIParent:GetHeight() / 2
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", cfgFn().xPos, cfgFn().yPos)
    end)
end

--- Registers the nine player spellcast/channel events on an AceEvent module.
--- The module must implement: OnCastStart, OnCastStop, OnCastDelayed,
--- OnChannelStart, OnChannelStop, OnChannelUpdate.
---@param module AceModule
function CastUtil.RegisterCastEvents(module)
    ---@cast module +AceEvent-3.0
    module:RegisterEvent("UNIT_SPELLCAST_START",          "OnCastStart")
    module:RegisterEvent("UNIT_SPELLCAST_STOP",           "OnCastStop")
    module:RegisterEvent("UNIT_SPELLCAST_FAILED",         "OnCastStop")
    module:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED",    "OnCastStop")
    module:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED",      "OnCastStop")
    module:RegisterEvent("UNIT_SPELLCAST_DELAYED",        "OnCastDelayed")
    module:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START",  "OnChannelStart")
    module:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "OnChannelStop")
    module:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "OnChannelUpdate")
end

--- Returns r, g, b, a for the cast color from a module's config table.
--- Respects useClassColor, and distinguishes cast vs channel.
function CastUtil.ResolveColor(moduleCfg, isChannel)
    if moduleCfg.useClassColor then
        local _, classToken = UnitClass("player")
        ---@diagnostic disable-next-line: undefined-global
        local cc = RAID_CLASS_COLORS[classToken]
        return cc.r, cc.g, cc.b, 1.0
    elseif isChannel then
        local c = moduleCfg.channelColor
        return c.r, c.g, c.b, c.a
    else
        local c = moduleCfg.castColor
        return c.r, c.g, c.b, c.a
    end
end
