local addon_name = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MinimapModule: AceModule
local minimod = addon:GetModule('Minimap')

local _G = _G
local CreateFrame = _G.CreateFrame

minimod.MapUtils = {}

--- Creates four border textures (T, B, L, R) parented to `parent` and initially
--- anchored to `anchor` on the top/bottom edges. L/R anchors are set by apply_border_textures.
---@param parent Frame
---@param anchor Frame
---@return table @A table containing the T, B, L, and R textures.
function minimod.MapUtils.create_border_textures(parent, anchor)
    local borders = {}
    borders.T = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    borders.T:SetPoint("TOPLEFT", anchor, "TOPLEFT")
    borders.T:SetPoint("TOPRIGHT", anchor, "TOPRIGHT")
    borders.B = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    borders.B:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT")
    borders.B:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT")
    borders.L = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    borders.R = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    return borders
end

--- Applies border visibility, colour, and size to a set of four border textures.
--- L/R are inset by `size` on the corners so they don't overlap the top/bottom strips.
---@param anchor Frame  frame the L/R textures are anchored to
---@param borders table The table containing the T, B, L, and R textures
---@param show boolean  @param size number  @param r number  @param g number  @param b number  @param a number
function minimod.MapUtils.apply_border_textures(anchor, borders, show, size, r, g, b, a)
    local T, B, L, R = borders.T, borders.B, borders.L, borders.R
    T:SetShown(show)
    B:SetShown(show)
    L:SetShown(show)
    R:SetShown(show)

    if not show then return end

    T:SetColorTexture(r, g, b, a)
    B:SetColorTexture(r, g, b, a)
    L:SetColorTexture(r, g, b, a)
    R:SetColorTexture(r, g, b, a)
    T:SetHeight(size)
    B:SetHeight(size)
    L:SetWidth(size)
    R:SetWidth(size)

    L:ClearAllPoints()
    L:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -size)
    L:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, size)
    R:ClearAllPoints()
    R:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -size)
    R:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, size)
end

-- Toolbar button helper: 20x20 button with atlas icon and 1px white outline
function minimod.MapUtils.create_toolbar_button(parent, atlas, on_click)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas(atlas, false)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", btn, "CENTER")

    local borders = minimod.MapUtils.create_border_textures(btn, btn)
    minimod.MapUtils.apply_border_textures(btn, borders, true, 1, 1, 1, 1, 0.5)

    btn:SetScript("OnClick", on_click)
    return btn
end
