local addonName, core = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

addon.Utils = {}

---@param r number
---@param g number
---@param b number
---@return string
function addon.Utils.hexColor(r, g, b)
    return string.format("|cFF%02X%02X%02X", r * 255, g * 255, b * 255)
end

--- Creates four border textures (T, B, L, R) parented to `parent` and anchored to `anchor`.
--- Call apply_border_textures to set size and color.
---@param parent Frame
---@param anchor Frame
---@return table borders  { T, B, L, R } textures
function addon.Utils.create_border_textures(parent, anchor)
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

--- Applies visibility, color, and thickness to a borders table from create_border_textures.
--- L/R are inset by `size` on the corners so they don't overlap the top/bottom strips.
---@param anchor  Frame
---@param borders table   { T, B, L, R } textures
---@param show    boolean
---@param size    number  thickness in pixels
---@param r       number
---@param g       number
---@param b       number
---@param a       number
function addon.Utils.apply_border_textures(anchor, borders, show, size, r, g, b, a)
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

function addon.Utils.apply_font_shadow(fontString)
    fontString:SetShadowOffset(2, -2)
    fontString:SetShadowColor(0, 0, 0, 1)
end

---@class CouchModePool
---@field acquire fun(...): any
---@field release fun(obj: any)
---@field flush   fun()

--- Creates a generic object/table pool to reuse tables or UI frames.
---@param createFunc fun(...): any Function that returns a newly constructed object.
---@param resetFunc? fun(obj: any) Optional function called when an object is released back to the pool.
---@return CouchModePool
function addon.Utils.CreatePool(createFunc, resetFunc)
    local pool = {}
    return {
        ---@return any
        acquire = function(...)
            local obj = table.remove(pool)
            if not obj then
                obj = createFunc(...)
            end
            return obj
        end,
        release = function(obj)
            if resetFunc then resetFunc(obj) end
            pool[#pool + 1] = obj
        end,
        flush = function()
            wipe(pool)
        end
    }
end

function addon.Utils.IsInInstance()
    if C_Garrison.IsOnGarrisonMap() then return true end
    local inInstance, instanceType = IsInInstance()
    if instanceType == "scenario" then return true end
    return inInstance
        and instanceType ~= "none"
        and instanceType ~= "neighborhood"
        and instanceType ~= "interior"
end
