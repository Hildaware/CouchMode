local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class AttachToTarget: AceModule
local attach = addon:NewModule('AttachToTarget', 'AceEvent-3.0')
---@cast attach +AceEvent-3.0

-- Keyed by frameName; stores the frame's position before the first attach so
-- it can be restored when the target is lost.
-- { point, relativeTo, relativePoint, x, y }
attach.savedPositions = {}

local function SavePosition(frame)
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    return { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
end

function attach:AttachAll()
    ---@diagnostic disable-next-line: param-type-mismatch
    local nameplate = C_NamePlate.GetNamePlateForUnit('target')
    if not nameplate then return end

    for _, entry in pairs(addon.db.profile.attachments) do
        if entry.enabled and entry.frameName ~= '' then
            local frame = _G[entry.frameName]
            if frame then
                if not self.savedPositions[entry.frameName] then
                    self.savedPositions[entry.frameName] = SavePosition(frame)
                end
                frame:ClearAllPoints()
                frame:SetPoint(entry.anchorPoint, nameplate, entry.relativePoint, entry.xOffset, entry.yOffset)
            end
        end
    end
end

function attach:DetachAll()
    for frameName, saved in pairs(self.savedPositions) do
        local frame = _G[frameName]
        if frame then
            frame:ClearAllPoints()
            frame:SetPoint(saved.point, saved.relativeTo, saved.relativePoint, saved.x, saved.y)
        end
    end
    self.savedPositions = {}
end

function attach:OnTargetChanged()
    if UnitExists('target') then
        self:AttachAll()
    else
        self:DetachAll()
    end
end

function attach:OnNamePlateAdded(_, unitToken)
    if UnitIsUnit(unitToken, 'target') then
        self:AttachAll()
    end
end

function attach:OnNamePlateRemoved(_, unitToken)
    if UnitIsUnit(unitToken, 'target') then
        self:DetachAll()
    end
end

function attach:OnEnable()
    self:RegisterEvent('PLAYER_TARGET_CHANGED', 'OnTargetChanged')
    self:RegisterEvent('NAME_PLATE_UNIT_ADDED', 'OnNamePlateAdded')
    self:RegisterEvent('NAME_PLATE_UNIT_REMOVED', 'OnNamePlateRemoved')
end

function attach:OnDisable()
    self:UnregisterAllEvents()
    self:DetachAll()
end

-- ── Options ────────────────────────────────────────────────────────────────────

local ANCHOR_POINTS = {
    ['CENTER']      = 'Center',
    ['TOP']         = 'Top',
    ['BOTTOM']      = 'Bottom',
    ['LEFT']        = 'Left',
    ['RIGHT']       = 'Right',
    ['TOPLEFT']     = 'Top Left',
    ['TOPRIGHT']    = 'Top Right',
    ['BOTTOMLEFT']  = 'Bottom Left',
    ['BOTTOMRIGHT'] = 'Bottom Right',
}

local attachArgs -- holds the live args table for dynamic rebuilding

local function BuildAttachmentArgs(id)
    return {
        enabled = {
            name  = 'Enabled',
            type  = 'toggle',
            order = 1,
            width = 'half',
            get   = function() return addon.db.profile.attachments[id].enabled end,
            set   = function(_, value) addon.db.profile.attachments[id].enabled = value end,
        },
        frameName = {
            name  = 'Frame Name',
            desc  = 'The global name of the WoW frame to attach (e.g. PlayerFrame).',
            type  = 'input',
            order = 2,
            width = 'double',
            get   = function() return addon.db.profile.attachments[id].frameName end,
            set   = function(_, value) addon.db.profile.attachments[id].frameName = value end,
        },
        anchorPoint = {
            name   = 'Frame Anchor',
            desc   = 'The point on your frame that will be anchored to the nameplate.',
            type   = 'select',
            order  = 3,
            values = ANCHOR_POINTS,
            get    = function() return addon.db.profile.attachments[id].anchorPoint end,
            set    = function(_, value) addon.db.profile.attachments[id].anchorPoint = value end,
        },
        relativePoint = {
            name   = 'Nameplate Anchor',
            desc   = 'The point on the nameplate that your frame anchors to.',
            type   = 'select',
            order  = 4,
            values = ANCHOR_POINTS,
            get    = function() return addon.db.profile.attachments[id].relativePoint end,
            set    = function(_, value) addon.db.profile.attachments[id].relativePoint = value end,
        },
        xOffset = {
            name  = 'X Offset',
            desc  = 'Horizontal offset from the anchor point.',
            type  = 'range',
            order = 5,
            min   = -500,
            max   = 500,
            step  = 1,
            get   = function() return addon.db.profile.attachments[id].xOffset end,
            set   = function(_, value) addon.db.profile.attachments[id].xOffset = value end,
        },
        yOffset = {
            name  = 'Y Offset',
            desc  = 'Vertical offset from the anchor point.',
            type  = 'range',
            order = 6,
            min   = -500,
            max   = 500,
            step  = 1,
            get   = function() return addon.db.profile.attachments[id].yOffset end,
            set   = function(_, value) addon.db.profile.attachments[id].yOffset = value end,
        },
        remove = {
            name  = 'Remove',
            type  = 'execute',
            order = 7,
            func  = function()
                addon.db.profile.attachments[id] = nil
                attach:RebuildOptions()
            end,
        },
    }
end

function attach:GetDefaults()
    return {
        attachments = {},
        -- [id] = { enabled, frameName, anchorPoint, relativePoint, xOffset, yOffset }
    }
end

function attach:GetOptions()
    attachArgs = {
        description = {
            name  =
            'Attach one or more frames to the current target\'s nameplate. Frames are restored to their original position when you lose the target.',
            type  = 'description',
            order = 1,
        },
        addButton = {
            name  = 'Add Frame',
            type  = 'execute',
            order = 2,
            func  = function()
                local id = tostring(GetTime())
                addon.db.profile.attachments[id] = {
                    enabled       = true,
                    frameName     = '',
                    anchorPoint   = 'BOTTOM',
                    relativePoint = 'TOP',
                    xOffset       = 0,
                    yOffset       = 0,
                }
                attach:RebuildOptions()
            end,
        },
    }
    return 'attachToTarget', {
        name  = 'Attach To Target',
        type  = 'group',
        order = 2,
        args  = attachArgs,
    }
end

function attach:RebuildOptions()
    for key in pairs(attachArgs) do
        if key ~= 'description' and key ~= 'addButton' then
            attachArgs[key] = nil
        end
    end

    local order = 10
    for id in pairs(addon.db.profile.attachments) do
        attachArgs['entry_' .. id] = {
            name   = addon.db.profile.attachments[id].frameName ~= '' and
                addon.db.profile.attachments[id].frameName or '(unnamed)',
            type   = 'group',
            order  = order,
            inline = true,
            args   = BuildAttachmentArgs(id),
        }
        order = order + 1
    end

    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
end

attach:Enable()
