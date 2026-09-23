local addon_name  = ...

---@class CouchMode: AceAddon
local addon       = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MapModule: AceModule
local map         = addon:GetModule('Minimap')

local _G          = _G
local math_floor  = math.floor
local math_max    = math.max
local CreateFrame = _G.CreateFrame
local pairs       = pairs

map.MapUtils      = {}

-- GenericMetal2 is authored at 64px. These values control its displayed
-- dimensions in CouchMode. Keep the outset at least as large as the texture
-- size so the source art's transparent outer padding remains outside the map.
map.MapUtils.WOW_BORDER_SIZE = 24
map.MapUtils.WOW_BORDER_OUTSET = 6

---@param shape "square"|"rectangle"
---@param size number
---@return number w, number h
function map.MapUtils.size_for_shape(shape, size)
    if shape == "rectangle" then
        return size, math_floor(size * (2 / 3))
    end
    return size, size
end

-- Border helpers live in addon.Utils; keep aliases here for backward compatibility.
map.MapUtils.create_border_textures = addon.Utils.create_border_textures
map.MapUtils.apply_border_textures  = addon.Utils.apply_border_textures

-- The GenericMetal2 panel is authored at 64px. It is high-resolution source
-- art, so the displayed size is deliberately controlled separately below.
local WOW_BORDER_PIECES = {
    TL = { atlas = "UI-Frame-DiamondMetal-CornerTopLeft",     corner = true },
    TR = { atlas = "UI-Frame-DiamondMetal-CornerTopRight",    corner = true },
    BL = { atlas = "UI-Frame-DiamondMetal-CornerBottomLeft",  corner = true },
    BR = { atlas = "UI-Frame-DiamondMetal-CornerBottomRight", corner = true },
    T  = { atlas = "_UI-Frame-DiamondMetal-EdgeTop",          horizontal = true },
    B  = { atlas = "_UI-Frame-DiamondMetal-EdgeBottom",       horizontal = true },
    L  = { atlas = "!UI-Frame-DiamondMetal-EdgeLeft",         vertical = true },
    R  = { atlas = "!UI-Frame-DiamondMetal-EdgeRight",        vertical = true },
}

--- Sets the displayed thickness of a GenericMetal2 border without changing its anchors.
---@param borders table
---@param size number
function map.MapUtils.set_wow_border_size(borders, size)
    size = math_max(1, size)
    for key, piece in pairs(WOW_BORDER_PIECES) do
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

--- Anchors an unclipped chrome host around a frame. `outset` preserves the
--- transparent padding authored around the outside of the border art.
---@param frame Frame
---@param anchor Frame
---@param outset number
function map.MapUtils.position_wow_border_frame(frame, anchor, outset)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", -outset, outset)
    frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", outset, -outset)
end

--- Creates Blizzard's eight-piece GenericMetal2 panel border around `anchor`.
---@param parent Frame
---@param anchor Frame
---@return table borders { TL, TR, BL, BR, T, B, L, R } textures
function map.MapUtils.create_wow_border_textures(parent, anchor)
    local borders = {}

    for key, piece in pairs(WOW_BORDER_PIECES) do
        local tex = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetAtlas(piece.atlas, true)
        if piece.horizontal then tex:SetHorizTile(true) end
        if piece.vertical then tex:SetVertTile(true) end
        borders[key] = tex
    end

    borders.TL:SetPoint("TOPLEFT", anchor, "TOPLEFT")
    borders.TR:SetPoint("TOPRIGHT", anchor, "TOPRIGHT")
    borders.BL:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT")
    borders.BR:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT")

    borders.T:SetPoint("TOPLEFT", borders.TL, "TOPRIGHT")
    borders.T:SetPoint("TOPRIGHT", borders.TR, "TOPLEFT")
    borders.B:SetPoint("BOTTOMLEFT", borders.BL, "BOTTOMRIGHT")
    borders.B:SetPoint("BOTTOMRIGHT", borders.BR, "BOTTOMLEFT")
    borders.L:SetPoint("TOPLEFT", borders.TL, "BOTTOMLEFT")
    borders.L:SetPoint("BOTTOMLEFT", borders.BL, "TOPLEFT")
    borders.R:SetPoint("TOPRIGHT", borders.TR, "BOTTOMRIGHT")
    borders.R:SetPoint("BOTTOMRIGHT", borders.BR, "TOPRIGHT")

    map.MapUtils.set_wow_border_size(borders, map.MapUtils.WOW_BORDER_SIZE)
    return borders
end

--- Applies visibility and the existing user-selected tint to a WoW panel border.
---@param borders table
---@param show boolean
---@param r number
---@param g number
---@param b number
---@param a number
---@param size number
function map.MapUtils.apply_wow_border_textures(borders, show, r, g, b, a, size)
    map.MapUtils.set_wow_border_size(borders, size)
    for _, tex in pairs(borders) do
        tex:SetShown(show)
        if show then tex:SetVertexColor(r, g, b, a) end
    end
end

local BUTTON_GOLD                   = "Interface\\AddOns\\CouchMode\\Resources\\Media\\button_gold.blp"
local BUTTON_SILVER                 = "Interface\\AddOns\\CouchMode\\Resources\\Media\\button_silver.blp"

--- Toolbar button helper: 20x20 button with atlas icon.
--- btn.selected_bg (button_silver.blp) can be shown/hidden to indicate selected state.
--- If tooltip is provided, shows a GameTooltip with that text on hover.
---@param parent Frame
---@param atlas string
---@param on_click fun()
---@param tooltip string|nil
function map.MapUtils.create_toolbar_button(parent, atlas, on_click, tooltip)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)

    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetAllPoints(btn)
    bg:SetTexture(BUTTON_GOLD)

    local selected_bg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    selected_bg:SetAllPoints(btn)
    selected_bg:SetTexture(BUTTON_SILVER)
    selected_bg:Hide()
    btn.selected_bg = selected_bg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas(atlas, false)
    icon:SetSize(14, 14)
    icon:SetPoint("CENTER", btn, "CENTER")

    btn:SetHighlightTexture(BUTTON_SILVER)

    btn:SetScript("OnClick", on_click)

    if tooltip then
        btn:SetScript("OnEnter", function()
            _G.GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            _G.GameTooltip:SetText(tooltip, 1, 1, 1)
            _G.GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            _G.GameTooltip:Hide()
        end)
    end

    return btn
end
