local addon_name  = ...

---@class ConsoleTools: AceAddon
local addon       = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MapModule: AceModule
local map         = addon:GetModule('Minimap')

local _G          = _G
local math_ceil   = math.ceil
local CreateFrame = _G.CreateFrame
local UIParent    = _G.UIParent

--- Creates map.container — the outer frame that clips children, hosts alpha, and
--- acts as the drag target. Must be called before any child frames are created.
---@param w number frame width
---@param h number frame height
function map.createContainer(w, h)
    local db = addon.db.profile.minimap ---@type MinimapDB

    map.container = CreateFrame("Frame", "CTMinimapContainer", UIParent)
    map.container:SetSize(w, h)
    map.container:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    map.container:SetClipsChildren(true)
    map.container:SetAlpha(db.alpha)
    map.container:SetFrameStrata("DIALOG")

    -- Drag-to-move: thin bar at the top so the Minimap's own click handling doesn't interfere
    map.container:SetMovable(true)
    map.container:SetClampedToScreen(true)
    map.container:SetClampRectInsets(0, 0, math_ceil((w - h) / 2), math_ceil((w - h) / 2))
    map.dragBar = CreateFrame("Frame", nil, map.container)
    map.dragBar:SetHeight(10)
    map.dragBar:SetPoint("TOPLEFT", map.container, "TOPLEFT")
    map.dragBar:SetPoint("TOPRIGHT", map.container, "TOPRIGHT")
    map.dragBar:SetFrameLevel(map.container:GetFrameLevel() + 200)
    map.dragBar:EnableMouse(true)
    map.dragBar:RegisterForDrag("LeftButton")
    map.dragBar:SetScript("OnDragStart", function() map.container:StartMoving() end)
    map.dragBar:SetScript("OnDragStop", function()
        map.container:StopMovingOrSizing()
        local pt, _, _, ox, oy = map.container:GetPoint()
        db.point = pt
        db.x = ox
        db.y = oy
    end)
end
