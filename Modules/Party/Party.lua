local addonName = ...

local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local EditMode = addon.EditMode
local isSecret = addon.Utils.IsSecretValue

---@class PartyModule: AceModule
local party = addon:NewModule('Party', 'AceEvent-3.0')
---@cast party +AceEvent-3.0

local UNITS = { 'player', 'party1', 'party2', 'party3', 'party4' }
local ROW_HEIGHT = 88
local ROW_GAP = 10
local DEFAULT_WIDTH = 430
local DEFAULT_POINT = 'TOPLEFT'
local DEFAULT_X = 38
local DEFAULT_Y = -180
local VISIBILITY_RULE = '[group:party] show; hide'
local SOLO_VISIBILITY_RULE = '[group:raid] hide; [group:party] show; show'
local previewNames = { 'Player', 'Party member 1', 'Party member 2', 'Party member 3', 'Party member 4' }

local function db() return addon.db.profile.party end

local pendingFrame = CreateFrame('Frame')
pendingFrame:SetScript('OnEvent', function(self)
    self:UnregisterEvent('PLAYER_REGEN_ENABLED')
    party:ApplyProtectedState()
end)

local function inspectSpecIcon(unit)
    if unit ~= 'player' then
        local guid = UnitGUID(unit)
        if isSecret(guid) then return nil end
    end
    local info = addon.TipsUtils and addon.TipsUtils.getSpecData(unit)
    return info and info.specIcon
end

function party:ApplyAnchor()
    if not self.frame then return end
    if InCombatLockdown and InCombatLockdown() then
        self:DeferProtectedState()
        return
    end
    local layout = EditMode:GetActiveLayoutName()
    local position = layout and db().positions and db().positions[layout]
    self.frame:ClearAllPoints()
    if position then
        self.frame:SetPoint(position.point, UIParent, position.point, position.x, position.y)
    else
        self.frame:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, DEFAULT_X, DEFAULT_Y)
    end
end

function party:ApplyLayout()
    if not self.frame then return end
    if InCombatLockdown and InCombatLockdown() then
        self:DeferProtectedState()
        return
    end
    local settings = db()
    self.frame:SetSize(settings.width, #UNITS * ROW_HEIGHT + (#UNITS - 1) * ROW_GAP)
    self.frame:SetScale(settings.scale)
    for i, frame in ipairs(self.frames) do
        frame:ApplyLayout(settings.width, ROW_HEIGHT)
        frame:ClearAllPoints()
        frame:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, -(i - 1) * (ROW_HEIGHT + ROW_GAP))
    end
end

function party:CreateUI()
    if self.frame then return true end
    if InCombatLockdown and InCombatLockdown() then return false end
    local container = CreateFrame('Frame', 'CouchModePartyFrame', UIParent)
    container:SetFrameStrata('MEDIUM')
    self.frame = container
    self.frames = {}
    self.framesByUnit = {}
    for i, unit in ipairs(UNITS) do
        local frame = addon.UnitFrame.Create(container, unit, {
            width = db().width,
            height = ROW_HEIGHT,
            resolveSpecIcon = inspectSpecIcon,
        })
        frame:Hide()
        self.frames[i] = frame
        self.framesByUnit[unit] = frame
    end
    self:ApplyAnchor()
    self:ApplyLayout()
    container:Hide()

    EditMode:RegisterFrame(container, function(_, layoutName, point, x, y)
        if not layoutName then return end
        local positions = db().positions
        positions[layoutName] = { point = point, x = x, y = y }
    end, { point = DEFAULT_POINT, x = DEFAULT_X, y = DEFAULT_Y }, 'CouchMode Party')

    EditMode:RegisterFrameSettings(container, {
        {
            kind = EditMode.SettingType.Slider,
            name = 'Width',
            desc = 'Width of each party row in pixels.',
            default = DEFAULT_WIDTH,
            minValue = 360,
            maxValue = 620,
            valueStep = 5,
            get = function() return db().width end,
            set = function(_, value, fromReset)
                db().width = fromReset and DEFAULT_WIDTH or value
                party:ApplyLayout()
            end,
        },
        {
            kind = EditMode.SettingType.Slider,
            name = 'Scale',
            desc = 'Overall party frame scale.',
            default = 1,
            minValue = 0.75,
            maxValue = 1.5,
            valueStep = 0.05,
            get = function() return db().scale end,
            set = function(_, value, fromReset)
                db().scale = fromReset and 1 or value
                party:ApplyLayout()
            end,
        },
    })

    EditMode:RegisterCallback('layout', function() party:ApplyAnchor() end)
    EditMode:RegisterCallback('enter', function()
        if party:IsEnabled() then
            party.editModePreview = true
            party:QueueProtectedState()
        end
    end)
    EditMode:RegisterCallback('exit', function()
        party.editModePreview = false
        party:QueueProtectedState()
    end)
    return true
end

function party:InstallSuppressionHooks()
    if self.suppressionHooked or not PartyFrame then return end
    self.suppressionHooked = true
    PartyFrame:HookScript('OnShow', function()
        if party.suppressed then party:QueueProtectedState() end
    end)
    if UpdateRaidAndPartyFrames then
        hooksecurefunc('UpdateRaidAndPartyFrames', function()
            if party:IsEnabled() then party:QueueProtectedState() end
        end)
    end
end

function party:SuppressBlizzard()
    if not PartyFrame then return end
    if not self.suppressed then
        self.blizzardWasShown = PartyFrame:IsShown()
        self.suppressed = true
    end
    PartyFrame:Hide() -- also contains Blizzard's compact, raid-style party frame
end

function party:RestoreBlizzard()
    if not self.suppressed or not PartyFrame then return end
    self.suppressed = false
    if self.blizzardWasShown then PartyFrame:Show() else PartyFrame:Hide() end
    self.blizzardWasShown = nil
    if UpdateRaidAndPartyFrames then UpdateRaidAndPartyFrames() end
end

function party:DeferProtectedState()
    pendingFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
end

function party:QueueProtectedState()
    if InCombatLockdown and InCombatLockdown() then
        self:DeferProtectedState()
    else
        self:ApplyProtectedState()
    end
end

function party:TogglePreview()
    self.manualPreview = not self.manualPreview
    self:QueueProtectedState()
end

function party:RemoveVisibilityDriver()
    if self.visibilityDriven then
        UnregisterStateDriver(self.frame, 'visibility')
        self.visibilityDriven = false
    end
    self.visibilityRule = nil
end

function party:ApplyVisibilityDriver()
    local rule = db().showWhileSolo and SOLO_VISIBILITY_RULE or VISIBILITY_RULE
    if self.visibilityDriven and self.visibilityRule ~= rule then
        UnregisterStateDriver(self.frame, 'visibility')
        self.visibilityDriven = false
    end
    if not self.visibilityDriven then
        RegisterStateDriver(self.frame, 'visibility', rule)
        self.visibilityDriven = true
        self.visibilityRule = rule
    end
end

function party:ApplyProtectedState()
    if InCombatLockdown and InCombatLockdown() then
        self:DeferProtectedState()
        return
    end
    local enabled = self:IsEnabled() and db().enabled
    if enabled then self:InstallSuppressionHooks() end
    if enabled and not self:CreateUI() then return end
    local container = self.frame
    if not container then
        self:RestoreBlizzard()
        return
    end
    local preview = self.manualPreview or self.editModePreview
    if enabled and preview then
        self:RemoveVisibilityDriver()
        if self.unitWatching then
            for _, frame in ipairs(self.frames) do UnregisterUnitWatch(frame) end
            self.unitWatching = false
        end
        for i, frame in ipairs(self.frames) do
            frame:SetPreview(true, previewNames[i])
            frame:Show()
        end
        container:Show()
        self:SuppressBlizzard()
    elseif enabled then
        if self.previewApplied then
            for _, frame in ipairs(self.frames) do frame:SetPreview(false) end
        end
        if not self.unitWatching then
            for _, frame in ipairs(self.frames) do RegisterUnitWatch(frame) end
            self.unitWatching = true
        end
        self:ApplyVisibilityDriver()
        if IsInGroup() and not IsInRaid() then
            self:SuppressBlizzard()
        else
            self:RestoreBlizzard()
        end
    else
        self:RemoveVisibilityDriver()
        if self.unitWatching then
            for _, frame in ipairs(self.frames) do UnregisterUnitWatch(frame) end
            self.unitWatching = false
        end
        container:Hide()
        self:RestoreBlizzard()
    end
    self.previewApplied = enabled and preview or false
    self:ApplyLayout()
end

function party:RefreshAll()
    if not self.frames then return end
    for _, frame in ipairs(self.frames) do frame:Refresh() end
end

function party:ScheduleInspects()
    self.inspectGeneration = (self.inspectGeneration or 0) + 1
    local generation = self.inspectGeneration
    if not (IsInGroup() and not IsInRaid()) then return end
    if not addon.TipsUtils or not C_Timer then return end
    for i = 2, #UNITS do
        local unit = UNITS[i]
        C_Timer.After((i - 2) * 1.7, function()
            if generation ~= party.inspectGeneration or not party:IsEnabled() then return end
            if InCombatLockdown and InCombatLockdown() then return end
            if UnitExists(unit) then
                local guid = UnitGUID(unit)
                if not isSecret(guid) and guid then addon.TipsUtils.requestInspect(unit) end
            end
        end)
    end
end

function party:OnRosterChanged()
    self:RefreshAll()
    self:ScheduleInspects()
    self:QueueProtectedState()
end

function party:OnUnitEvent(event, unit)
    if isSecret(unit) or not unit or not self.framesByUnit then return end
    local frame = self.framesByUnit[unit]
    if not frame then return end
    if event == 'UNIT_HEALTH' or event == 'UNIT_MAXHEALTH' or event == 'UNIT_CONNECTION' or event == 'UNIT_FLAGS' then
        frame:UpdateHealth()
        if event == 'UNIT_FLAGS' then frame:UpdateCombat() end
    elseif event == 'UNIT_POWER_UPDATE' or event == 'UNIT_MAXPOWER' or event == 'UNIT_DISPLAYPOWER' then
        frame:UpdatePower()
    elseif event == 'UNIT_AURA' then
        frame:UpdateAuras()
    else
        frame:UpdateIdentity()
    end
end

function party:OnIdentityChanged()
    self:RefreshAll()
end

function party:OnTargetChanged()
    if not self.frames then return end
    for _, frame in ipairs(self.frames) do frame:UpdatePercentVisibility() end
end

function party:OnInspectReady(_, guid)
    if isSecret(guid) or not guid or not self.frames then return end
    for _, frame in ipairs(self.frames) do
        local unit = frame.unit
        if UnitExists(unit) then
            local unitGuid = UnitGUID(unit)
            if not isSecret(unitGuid) and unitGuid and unitGuid == guid then
                if addon.TipsUtils then addon.TipsUtils.onInspectReady(guid, unit) end
                frame:UpdateIdentity()
                return
            end
        end
    end
end

function party:OnEnable()
    if not db().enabled then self:Disable(); return end
    addon.Utils.RegisterEventIfValid(self, 'GROUP_ROSTER_UPDATE', 'OnRosterChanged')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_ENTERING_WORLD', 'OnRosterChanged')
    addon.Utils.RegisterEventIfValid(self, 'INSPECT_READY', 'OnInspectReady')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_SPECIALIZATION_CHANGED', 'OnIdentityChanged')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_LEVEL_UP', 'OnIdentityChanged')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_TARGET_CHANGED', 'OnTargetChanged')
    addon.Utils.RegisterEventIfValid(self, 'ROLE_CHANGED_INFORM', 'OnIdentityChanged')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_ROLES_ASSIGNED', 'OnIdentityChanged')
    for _, event in ipairs({ 'UNIT_HEALTH', 'UNIT_MAXHEALTH', 'UNIT_POWER_UPDATE', 'UNIT_MAXPOWER',
        'UNIT_DISPLAYPOWER', 'UNIT_AURA', 'UNIT_NAME_UPDATE', 'UNIT_LEVEL', 'UNIT_CONNECTION',
        'UNIT_FLAGS', 'UNIT_PORTRAIT_UPDATE', 'UNIT_MODEL_CHANGED' }) do
        addon.Utils.RegisterEventIfValid(self, event, 'OnUnitEvent')
    end
    self:QueueProtectedState()
    self:RefreshAll()
    self:ScheduleInspects()
end

function party:OnDisable()
    self:UnregisterAllEvents()
    self.inspectGeneration = (self.inspectGeneration or 0) + 1
    self.manualPreview = false
    self.editModePreview = false
    self:QueueProtectedState()
end

party:Enable()
