local addonName, core = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

addon.Utils = {}

local _, _, _, interfaceVersion = GetBuildInfo()
local IS_WOW_FOREVER = interfaceVersion >= 16000 and interfaceVersion < 17000

---@alias WowFlavor 'retail'|'forever'|'classic'

--- Detects the running client flavor from its interface version.
--- Retail (mainline) builds use 100000+, WoW: Forever uses 16000-16999, and
--- the classic family uses lower numbers such as 11507.
---@param version number
---@return WowFlavor
local function detectFlavor(version)
    if version >= 16000 and version < 17000 then return 'forever' end
    if version >= 100000 then return 'retail' end
    return 'classic'
end

addon.Utils.INTERFACE_VERSION = interfaceVersion
addon.Utils.FLAVOR = detectFlavor(interfaceVersion)

--- Runs `fn` immediately when the current client flavor is one of `flavors`.
--- Accepts either a single flavor string or an array of them. Returns whatever
--- `fn` returns, or nil when the flavor does not match.
---@param flavors WowFlavor|WowFlavor[]
---@param fn fun(): any
---@return any
function addon.Utils.WhenFlavor(flavors, fn)
    if type(flavors) == 'string' then flavors = { flavors } end
    for i = 1, #flavors do
        if flavors[i] == addon.Utils.FLAVOR then return fn() end
    end
end

--- Alias for WhenFlavor, reading naturally at call sites: IfFlavor('retail', fn).
addon.Utils.IfFlavor = addon.Utils.WhenFlavor

--- Convenience predicate: is the current client this flavor?
---@param flavor WowFlavor
---@return boolean
function addon.Utils.IsFlavor(flavor)
    return addon.Utils.FLAVOR == flavor
end

--- Whether a value is secret and therefore unsafe to compare, measure, hash,
--- or otherwise inspect. Returns false on clients without the predicate.
---@param value any
---@return boolean
function addon.Utils.IsSecretValue(value)
    local isSecret = issecretvalue
    return isSecret ~= nil and isSecret(value)
end

--- Whether the client knows a given event. Uses the authoritative
--- C_EventUtils.IsEventValid when available; otherwise probes RegisterEvent on a
--- throwaway frame. Returns nil when validity cannot be determined.
---@param event string
---@return boolean?
function addon.Utils.EventExists(event)
    if type(event) ~= 'string' or event == '' then return false end
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event) == true
    end
    if type(CreateFrame) ~= 'function' then return nil end
    local probe = addon.Utils._eventProbe
    if not probe then
        probe = CreateFrame('Frame')
        addon.Utils._eventProbe = probe
    end
    local ok = pcall(probe.RegisterEvent, probe, event)
    if ok then pcall(probe.UnregisterEvent, probe, event) end
    return ok
end

--- Registers `event` only when the client supports it. When supplied, `handler`
--- is forwarded for AceEvent-3.0's embedded RegisterEvent method.
---@param frame any
---@param event string
---@param handler? string|fun(...)
---@return boolean registered
function addon.Utils.RegisterEventIfValid(frame, event, handler)
    if not frame then return false end
    local exists = addon.Utils.EventExists(event)
    if exists == false then return false end
    local ok
    if handler ~= nil then
        ok = pcall(frame.RegisterEvent, frame, event, handler)
    else
        ok = pcall(frame.RegisterEvent, frame, event)
    end
    return ok
end

---@param r number
---@param g number
---@param b number
---@return string
function addon.Utils.hexColor(r, g, b)
    return string.format("|cFF%02X%02X%02X", r * 255, g * 255, b * 255)
end

--- Splits a player's PvP display name into a title prefix, character name, and title suffix.
--- Forever adds surnames to the display name, so the text between the base name and a
--- comma-delimited title remains part of the character name.
---@param unit string
---@return string preTitle
---@return string characterName
---@return string postTitle
function addon.Utils.GetPlayerNameParts(unit)
    local baseName = UnitName(unit) or ""
    local pvpName = UnitPVPName(unit)
    if not pvpName or addon.Utils.IsSecretValue(pvpName) then
        return "", baseName, ""
    end

    local nameStart, nameEnd = pvpName:find(baseName, 1, true)
    if not nameStart then return "", baseName, "" end

    local preTitle = nameStart > 1 and pvpName:sub(1, nameStart - 1) or ""
    if IS_WOW_FOREVER then
        local titleStart = pvpName:find(",", nameEnd + 1, true)
        local characterEnd = titleStart and titleStart - 1 or #pvpName
        return preTitle, pvpName:sub(nameStart, characterEnd), titleStart and pvpName:sub(titleStart) or ""
    end

    return preTitle, baseName, nameEnd < #pvpName and pvpName:sub(nameEnd + 1) or ""
end

--- Returns whether a player unit belongs to the current player's guild.
--- UnitIsInMyGuild is the direct modern API; IsGuildMember accepts unit tokens
--- and keeps the check working on older clients.
---@param unit string
---@return boolean
function addon.Utils.IsUnitInPlayerGuild(unit)
    if not UnitIsPlayer(unit) then return false end
    if UnitIsInMyGuild then return UnitIsInMyGuild(unit) end
    return IsGuildMember and IsGuildMember(unit) or false
end

--- Makes AceConfigDialog's legacy tooltip calls work on clients that require
--- an explicit alpha argument before the wrap flag. This modifies only the
--- dialog's private tooltip object, never the bundled Ace source.
function addon.Utils.InstallAceConfigTooltipCompatibility()
    local dialog = LibStub("AceConfigDialog-3.0", true)
    local tooltip = dialog and dialog.tooltip
    if not tooltip or tooltip.CouchModeSetTextCompatibilityInstalled then return end

    -- Older clients accept (text, r, g, b, wrap); newer clients require
    -- (text, r, g, b, alpha, wrap). Test the installed API rather than a
    -- particular project/version so this works on WoW:Forever only when needed.
    local supportsLegacySignature = pcall(tooltip.SetText, tooltip, "", 1, 0.82, 0, true)
    tooltip:Hide()
    if supportsLegacySignature then return end

    local originalSetText = tooltip.SetText
    tooltip.SetText = function(self, text, r, g, b, wrap, ...)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" and type(wrap) == "boolean" then
            return originalSetText(self, text, r, g, b, 1, wrap, ...)
        end
        return originalSetText(self, text, r, g, b, wrap, ...)
    end
    tooltip.CouchModeSetTextCompatibilityInstalled = true
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
