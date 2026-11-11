local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)
local isSecretValue = addon.Utils.IsSecretValue

--#region ── Inspect cache ────────────────────────────────────────────────────

local INSPECT_THROTTLE = 1.5
local CACHE_TTL = 300

local inspectCache = {} -- [guid] = { specName, specIcon, talentPoints, time }
local lastInspect = 0
local isForever = addon.Utils.IsFlavor('forever')

local function hasTalentPointData()
    return C_Traits and C_Traits.GetConfigInfo and C_Traits.GetGroupDisplayInfoByTreeID
        and C_Traits.GetGroupCurrencyInfo and C_ClassTalents and C_ClassTalents.GetActiveConfigID
end

local function getTalentPointData(isInspect)
    if not hasTalentPointData() then return end
    local configID
    if isInspect then
        configID = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    else
        configID = C_ClassTalents.GetActiveConfigID()
        if not configID and C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup
            and C_SpecializationInfo.GetActiveSpecGroup then
            configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(C_SpecializationInfo.GetActiveSpecGroup())
        end
    end
    if not configID or isSecretValue(configID) then return end
    local config = C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return end

    -- Use the same group order and spent currency as Forever's talent tree headers.
    local displays = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
    if not displays or #displays == 0 then return end
    local groupIDs = {}
    for i, display in ipairs(displays) do
        groupIDs[i] = display.groupID
    end
    local groups = C_Traits.GetGroupCurrencyInfo(configID, groupIDs)
    if not groups then return end
    local spentByGroup = {}
    for _, group in ipairs(groups) do
        local currency = group.currencyInfos and group.currencyInfos[1]
        local spent = currency and currency.spent or 0
        if isSecretValue(spent) then return end
        spentByGroup[group.traitNodeGroupID] = spent
    end

    local points, icon, mostSpent = {}, nil, -1
    for i, display in ipairs(displays) do
        local spent = spentByGroup[display.groupID] or 0
        points[i] = tostring(spent)
        if spent > mostSpent then
            mostSpent, icon = spent, display.icon
        end
    end
    return { talentPoints = table.concat(points, "/"), specIcon = icon }
end

local function getPlayerSpecializationIndex()
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        return C_SpecializationInfo.GetSpecialization()
    end
    if GetSpecialization then return GetSpecialization() end
end

local function getSpecializationInfo(index)
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        return C_SpecializationInfo.GetSpecializationInfo(index)
    end
    if GetSpecializationInfo then return GetSpecializationInfo(index) end
end

local function getInspectSpecialization(unit)
    if C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization then
        return C_SpecializationInfo.GetInspectSpecialization(unit)
    end
    if GetInspectSpecialization then return GetInspectSpecialization(unit) end
end

local function hasInspectSpecialization()
    return (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization) or GetInspectSpecialization
end

local function cacheSpec(guid, unit)
    if isForever then
        local data = getTalentPointData(true)
        if data then
            data.time = GetTime()
            inspectCache[guid] = data
        end
        return
    end
    if not hasInspectSpecialization() or not GetSpecializationInfoByID then return end
    local specID = getInspectSpecialization(unit)
    if isSecretValue(specID) or not specID or specID <= 0 then return end
    local _, specName, _, specIcon = GetSpecializationInfoByID(specID)
    if not specName then return end
    inspectCache[guid] = { specName = specName, specIcon = specIcon, time = GetTime() }
end

local function pruneCache(now)
    now = now or GetTime()
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
    if unit == "player" or (UnitIsUnit and UnitIsUnit(unit, "player")) then
        if isForever then return getTalentPointData(false) end
        local idx = getPlayerSpecializationIndex()
        if idx then
            local _, name, _, icon = getSpecializationInfo(idx)
            if name then return { specName = name, specIcon = icon } end
        end
        return nil
    end

    -- Others: look up the GUID cache populated by INSPECT_READY.
    local guid = UnitGUID(unit)
    if isSecretValue(guid) or not guid then return nil end
    return inspectCache[guid]
end

local function requestInspect(unit)
    if not NotifyInspect then return end
    if isForever then
        if not hasTalentPointData() then return end
    elseif not (hasInspectSpecialization() and GetSpecializationInfoByID) then
        return
    end
    if not UnitIsPlayer(unit) then return end
    if UnitIsUnit(unit, "player") then return end
    if CanInspect and not CanInspect(unit) then return end
    local now = GetTime()
    local guid = UnitGUID(unit)
    if isSecretValue(guid) or not guid then return end
    local cached = inspectCache[guid]
    if cached and now - cached.time <= CACHE_TTL then return end
    if now - lastInspect < INSPECT_THROTTLE then return end
    pruneCache(now)
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
    if not text or isSecretValue(text) then return 0 end
    local fontPath, fontSize, fontFlags = fs:GetFont()
    if not fontPath then return 0 end
    if fontPath then measureFs:SetFont(fontPath, fontSize, fontFlags) end
    measureFs:SetText(text)
    local w = measureFs:GetStringWidth()
    return (not isSecretValue(w)) and w or 0
end

addon.TipsUtils = {
    getSpecData = getSpecData,
    requestInspect = requestInspect,
    onInspectReady = onInspectReady,
    measureWidth = measureWidth,
}

--#endregion
