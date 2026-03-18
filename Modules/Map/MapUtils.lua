local addon_name = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MapModule: AceModule
local map = addon:GetModule('Minimap')

local _G          = _G
local math_floor  = math.floor
local CreateFrame = _G.CreateFrame

map.MapUtils = {}

---@param shape "square"|"rectangle"
---@param size number
---@return number w, number h
function map.MapUtils.size_for_shape(shape, size)
    if shape == "rectangle" then
        return size, math_floor(size * (2 / 3))
    end
    return size, size
end

--- Creates four border textures (T, B, L, R) parented to `parent` and initially
--- anchored to `anchor` on the top/bottom edges. L/R anchors are set by apply_border_textures.
---@param parent Frame
---@param anchor Frame
---@return table @A table containing the T, B, L, and R textures.
function map.MapUtils.create_border_textures(parent, anchor)
    local borders = {}
    for _, pos in ipairs({ "T", "B", "L", "R" }) do
        borders[pos] = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    end
    borders.T:SetPoint("TOPLEFT", anchor, "TOPLEFT")
    borders.T:SetPoint("TOPRIGHT", anchor, "TOPRIGHT")
    borders.B:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT")
    borders.B:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT")
    return borders
end

--- Applies border visibility, colour, and size to a set of four border textures.
--- L/R are inset by `size` on the corners so they don't overlap the top/bottom strips.
---@param anchor Frame  frame the L/R textures are anchored to
---@param borders table The table containing the T, B, L, and R textures
---@param show boolean  @param size number  @param r number  @param g number  @param b number  @param a number
function map.MapUtils.apply_border_textures(anchor, borders, show, size, r, g, b, a)
    for _, pos in ipairs({ "T", "B", "L", "R" }) do
        local tex = borders[pos]
        tex:SetShown(show)
        if show then tex:SetColorTexture(r, g, b, a) end
    end

    if not show then return end

    borders.T:SetHeight(size)
    borders.B:SetHeight(size)
    borders.L:SetWidth(size)
    borders.R:SetWidth(size)

    borders.L:ClearAllPoints()
    borders.L:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -size)
    borders.L:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, size)
    borders.R:ClearAllPoints()
    borders.R:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -size)
    borders.R:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, size)
end

local BUTTON_GOLD   = "Interface\\AddOns\\ConsoleTools\\Media\\button_gold.blp"
local BUTTON_SILVER = "Interface\\AddOns\\ConsoleTools\\Media\\button_silver.blp"

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
