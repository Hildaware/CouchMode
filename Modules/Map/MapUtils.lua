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

-- Border helpers live in addon.Utils; keep aliases here for backward compatibility.
map.MapUtils.create_border_textures  = addon.Utils.create_border_textures
map.MapUtils.apply_border_textures   = addon.Utils.apply_border_textures

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
