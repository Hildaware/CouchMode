local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

--#region ── Inspect cache ────────────────────────────────────────────────────

local INSPECT_THROTTLE = 1.5
local CACHE_TTL = 300

local inspectCache = {} -- [guid] = { specName, specIcon, time }
local lastInspect = 0

local function cacheSpec(guid, unit)
    local specID = GetInspectSpecialization(unit)
    if not specID or specID <= 0 then return end
    local _, specName, _, specIcon = GetSpecializationInfoByID(specID)
    if not specName then return end
    inspectCache[guid] = { specName = specName, specIcon = specIcon, time = GetTime() }
end

local function pruneCache()
    local now = GetTime()
    for guid, entry in pairs(inspectCache) do
        if now - entry.time > CACHE_TTL then
            inspectCache[guid] = nil
        end
    end
end

--#endregion

--#region ── Public API ───────────────────────────────────────────────────────

local function getSpecData(unit)
    -- Self: read directly, no inspect needed.
    if UnitIsUnit(unit, "player") then
        local idx = GetSpecialization()
        if idx then
            local _, name, _, icon = GetSpecializationInfo(idx)
            if name then return { specName = name, specIcon = icon } end
        end
        return nil
    end

    -- Others: look up the GUID cache populated by INSPECT_READY.
    local guid = UnitGUID(unit)
    return guid and inspectCache[guid] or nil
end

local function requestInspect(unit)
    if not UnitIsPlayer(unit) then return end
    if not CanInspect(unit) then return end
    local now = GetTime()
    if now - lastInspect < INSPECT_THROTTLE then return end
    lastInspect = now
    NotifyInspect(unit)
end

-- Called from TipsTracker's INSPECT_READY handler.
local function onInspectReady(guid, unit)
    cacheSpec(guid, unit)
    pruneCache()
end

-- Shared measurement FontString parented to UIParent, never shown.
-- Using a dedicated fs keeps taint from display FontStrings out of measurements.
local measureFs = UIParent:CreateFontString(nil, "ARTWORK")
measureFs:Hide()

local function measureWidth(fs)
    local text = fs:GetText()
    if not text or issecretvalue(text) then return 0 end
    local fontPath, fontSize, fontFlags = fs:GetFont()
    if not fontPath then return 0 end
    if fontPath then measureFs:SetFont(fontPath, fontSize, fontFlags) end
    measureFs:SetText(text)
    local w = measureFs:GetStringWidth()
    return (not issecretvalue(w)) and w or 0
end

addon.TipsUtils = {
    getSpecData = getSpecData,
    requestInspect = requestInspect,
    onInspectReady = onInspectReady,
    measureWidth = measureWidth,
}

--#endregion
