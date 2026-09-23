local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

addon.Components = addon.Components or {}
addon.Components.MetalHeader = addon.Components.MetalHeader or {}
local metalHeader = addon.Components.MetalHeader

--- Adds the continuous Diamond Metal header background to a frame.
---@param parent Frame
---@return table parts Corner and tile textures, for callers that need to adjust them.
function metalHeader.Create(parent)
    local left = parent:CreateTexture(nil, 'BACKGROUND', nil, 1)
    left:SetAtlas('UI-Frame-DiamondMetal-Header-CornerLeft', true)
    left:SetSize(32, 39)
    left:SetScale(0.8)
    left:SetPoint('LEFT', parent, 'LEFT', -7, 0)

    local right = parent:CreateTexture(nil, 'BACKGROUND', nil, 1)
    right:SetAtlas('UI-Frame-DiamondMetal-Header-CornerRight', true)
    right:SetSize(32, 39)
    right:SetScale(0.8)
    right:SetPoint('RIGHT', parent, 'RIGHT', 7, 0)

    local tile = parent:CreateTexture(nil, 'BACKGROUND')
    tile:SetAtlas('_UI-Frame-DiamondMetal-Header-Tile')
    tile:SetHorizTile(true)
    tile:SetPoint('TOPLEFT', left, 'TOPRIGHT')
    tile:SetPoint('BOTTOMRIGHT', right, 'BOTTOMLEFT')

    return { left = left, right = right, tile = tile }
end
