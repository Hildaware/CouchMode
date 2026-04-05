local addonName, core = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

--#region ── TRP3 Utilities ───────────────────────────────────────────────────
-- Provides a safe, nil-guarded bridge to TotalRP3 APIs.
-- All functions return nil when TRP3 is absent, the unit is not a player,
-- the GUID is secret (instances), or the player has no TRP3 profile.

local function isAvailable()
    return AddOn_TotalRP3 ~= nil and TRP3_API ~= nil
end

local function getPlayer(unit)
    if not isAvailable() then return nil end
    if not UnitIsPlayer(unit) then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    -- GUIDs are secret strings in instances; CreateFromGUID would get garbage data.
    if issecretvalue and issecretvalue(guid) then return nil end
    local ok, player = pcall(AddOn_TotalRP3.Player.CreateFromGUID, guid)
    if not ok or not player then return nil end
    return player
end

local function getPlayerWithProfile(unit)
    local player = getPlayer(unit)
    if not player or not player:GetProfileID() then return nil end
    return player
end

-- ---------------------------------------------------------------------------

addon.TRPUtils = {
    isAvailable = isAvailable,
}

--- Returns the full formatted RP name string, or nil.
--- TRP3_API.r.name() falls back to UnitName when the player has no profile;
--- comparing against UnitName lets callers detect "no TRP3 data" cleanly.
---@param unit string
---@return string|nil
function addon.TRPUtils.getRPName(unit)
    if not isAvailable() then return nil end
    if not UnitIsPlayer(unit) then return nil end
    local baseName = UnitName(unit)
    if not baseName then return nil end
    local rpName = TRP3_API.r.name(unit)
    if not rpName or rpName == baseName then return nil end
    return rpName
end

--- Returns just the RP first name (characteristics.FN), or nil.
---@param unit string
---@return string|nil
function addon.TRPUtils.getRPFirstName(unit)
    local player = getPlayerWithProfile(unit)
    if not player then return nil end
    return player:GetFirstName() or nil
end

--- Returns TRP3 First + Last combined (e.g. "Brandon Fairwind"), or nil.
---@param unit string
---@return string|nil
function addon.TRPUtils.getRPFullName(unit)
    local player = getPlayerWithProfile(unit)
    if not player then return nil end
    return player:GetFullName() or nil
end

--- Returns TRP3 short title/honorific (TI field, e.g. "Lord"), or nil.
---@param unit string
---@return string|nil
function addon.TRPUtils.getRPTitle(unit)
    local player = getPlayerWithProfile(unit)
    if not player then return nil end
    return player:GetTitle() or nil
end

--- Returns TRP3 full descriptive title (FT field, e.g. "Knight of the Silver Hand"), or nil.
---@param unit string
---@return string|nil
function addon.TRPUtils.getRPFullTitle(unit)
    local player = getPlayerWithProfile(unit)
    if not player then return nil end
    return player:GetFullTitle() or nil
end

--- Returns the TRP3 custom icon name (e.g. "inv_inscription_scroll"), or nil.
---@param unit string
---@return string|nil
function addon.TRPUtils.getRPIcon(unit)
    local player = getPlayerWithProfile(unit)
    if not player then return nil end
    return player:GetCustomIcon() or nil
end

--- Returns r, g, b (0–1 floats) from the player's TRP3 custom color, or nil.
---@param unit string
---@return number|nil r
---@return number|nil g
---@return number|nil b
function addon.TRPUtils.getRPColor(unit)
    local player = getPlayerWithProfile(unit)
    if not player then return nil end
    local color = player:GetCustomColorForDisplay()
    if not color then return nil end
    return color:GetRGB()
end

--- Returns the TRP3 custom race string, or nil.
---@param unit string
---@return string|nil
function addon.TRPUtils.getRPRace(unit)
    local player = getPlayerWithProfile(unit)
    if not player then return nil end
    return player:GetCustomRace() or nil
end

--- Returns the TRP3 custom class string, or nil.
---@param unit string
---@return string|nil
function addon.TRPUtils.getRPClass(unit)
    local player = getPlayerWithProfile(unit)
    if not player then return nil end
    return player:GetCustomClass() or nil
end

--- Returns true if the unit is currently playing music via the Musician addon.
---@param unit string
---@return boolean
function addon.TRPUtils.isPlayingMusic(unit)
    ---@diagnostic disable-next-line: undefined-global
    if not Musician or not Musician.songs or not Musician.Utils then return false end
    if not UnitIsPlayer(unit) then return false end
    local unitName = GetUnitName(unit, true)
    if not unitName then return false end
    if issecretvalue and issecretvalue(unitName) then return false end
    ---@diagnostic disable-next-line: undefined-global
    local song = Musician.songs[Musician.Utils.NormalizePlayerName(unitName)]
    return song ~= nil and song:IsPlaying()
end

-- Live-update callbacks: registered by consumer modules, fired when TRP3
-- broadcasts REGISTER_DATA_UPDATED (profile changes, data received over network).
local dataUpdatedCallbacks = {}

function addon.TRPUtils.registerDataUpdatedCallback(fn)
    table.insert(dataUpdatedCallbacks, fn)
end

-- Register the TRP3 callback once CouchMode itself has finished loading.
-- totalRP3 is listed in OptionalDeps so it loads before CouchMode — its
-- ADDON_LOADED fires before we even register any handlers. Listening for
-- CouchMode's own ADDON_LOADED guarantees all OptionalDeps are fully ready.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    ---@diagnostic disable-next-line: undefined-global
    if TRP3_API and TRP3_Addon then
        ---@diagnostic disable-next-line: undefined-global
        TRP3_API.RegisterCallback(TRP3_Addon, "REGISTER_DATA_UPDATED", function()
            for _, fn in ipairs(dataUpdatedCallbacks) do fn() end
        end)
    end
end)

--#endregion
