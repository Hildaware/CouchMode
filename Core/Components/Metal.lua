local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

addon.Components = addon.Components or {}
addon.Components.Metal = addon.Components.Metal or {}
local metal = addon.Components.Metal

local mathMax = math.max
local pairs = pairs

--- Adds the continuous Diamond Metal header background to a frame.
---@param parent Frame
---@return table parts Corner and tile textures, for callers that need to adjust them.
function metal.CreateHeader(parent)
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

-- GenericMetal2 is authored at 64px; these values control its displayed size.
metal.BORDER_SIZE = 24
metal.BORDER_OUTSET = 6

local BORDER_PIECES = {
    TL = { atlas = 'UI-Frame-DiamondMetal-CornerTopLeft',     corner = true },
    TR = { atlas = 'UI-Frame-DiamondMetal-CornerTopRight',    corner = true },
    BL = { atlas = 'UI-Frame-DiamondMetal-CornerBottomLeft',  corner = true },
    BR = { atlas = 'UI-Frame-DiamondMetal-CornerBottomRight', corner = true },
    T  = { atlas = '_UI-Frame-DiamondMetal-EdgeTop',          horizontal = true },
    B  = { atlas = '_UI-Frame-DiamondMetal-EdgeBottom',       horizontal = true },
    L  = { atlas = '!UI-Frame-DiamondMetal-EdgeLeft',         vertical = true },
    R  = { atlas = '!UI-Frame-DiamondMetal-EdgeRight',        vertical = true },
}

--- Sets the displayed thickness of a GenericMetal2 border without changing its anchors.
---@param borders table
---@param size number
function metal.SetBorderSize(borders, size)
    size = mathMax(1, size)
    for key, piece in pairs(BORDER_PIECES) do
        local tex = borders[key]
        if piece.corner then
            tex:SetSize(size, size)
        elseif piece.horizontal then
            tex:SetHeight(size)
        else
            tex:SetWidth(size)
        end
    end
end

--- Anchors an unclipped chrome host around a frame. Outset preserves transparent outer padding.
---@param frame Frame
---@param anchor Frame
---@param outset number
function metal.PositionBorderFrame(frame, anchor, outset)
    frame:ClearAllPoints()
    frame:SetPoint('TOPLEFT', anchor, 'TOPLEFT', -outset, outset)
    frame:SetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT', outset, -outset)
end

--- Creates Blizzard's eight-piece GenericMetal2 panel border around `anchor`.
---@param parent Frame
---@param anchor Frame
---@return table borders { TL, TR, BL, BR, T, B, L, R } textures
function metal.CreateBorderTextures(parent, anchor)
    local borders = {}

    for key, piece in pairs(BORDER_PIECES) do
        local tex = parent:CreateTexture(nil, 'OVERLAY', nil, 7)
        tex:SetAtlas(piece.atlas, true)
        if piece.horizontal then tex:SetHorizTile(true) end
        if piece.vertical then tex:SetVertTile(true) end
        borders[key] = tex
    end

    borders.TL:SetPoint('TOPLEFT', anchor, 'TOPLEFT')
    borders.TR:SetPoint('TOPRIGHT', anchor, 'TOPRIGHT')
    borders.BL:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT')
    borders.BR:SetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT')

    borders.T:SetPoint('TOPLEFT', borders.TL, 'TOPRIGHT')
    borders.T:SetPoint('TOPRIGHT', borders.TR, 'TOPLEFT')
    borders.B:SetPoint('BOTTOMLEFT', borders.BL, 'BOTTOMRIGHT')
    borders.B:SetPoint('BOTTOMRIGHT', borders.BR, 'BOTTOMLEFT')
    borders.L:SetPoint('TOPLEFT', borders.TL, 'BOTTOMLEFT')
    borders.L:SetPoint('BOTTOMLEFT', borders.BL, 'TOPLEFT')
    borders.R:SetPoint('TOPRIGHT', borders.TR, 'BOTTOMRIGHT')
    borders.R:SetPoint('BOTTOMRIGHT', borders.BR, 'TOPRIGHT')

    metal.SetBorderSize(borders, metal.BORDER_SIZE)
    return borders
end

--- Applies visibility and tint to a GenericMetal2 panel border.
---@param borders table
---@param show boolean
---@param r number
---@param g number
---@param b number
---@param a number
---@param size number
function metal.ApplyBorderTextures(borders, show, r, g, b, a, size)
    metal.SetBorderSize(borders, size)
    for _, tex in pairs(borders) do
        tex:SetShown(show)
        if show then tex:SetVertexColor(r, g, b, a) end
    end
end
