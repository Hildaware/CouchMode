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
local previewAuras = {
    fortitude = { spellID = 21562, icon = 'Interface\\Icons\\Spell_Holy_WordFortitude' },
    intellect = { spellID = 1459, icon = 'Interface\\Icons\\Spell_Holy_MagicalSentry' },
    renew = { spellID = 139, icon = 'Interface\\Icons\\Spell_Holy_Renew', duration = 15 },
    rejuvenation = { spellID = 774, icon = 'Interface\\Icons\\Spell_Nature_Rejuvenation', duration = 12 },
    shield = { spellID = 17, icon = 'Interface\\Icons\\Spell_Holy_PowerWordShield', duration = 30 },
    poison = { spellID = 2818, icon = 'Interface\\Icons\\Ability_Rogue_DualWeild', applications = 3,
        duration = 60, dispellable = true },
    slow = { spellID = 116, icon = 'Interface\\Icons\\Spell_Frost_FrostBolt02', duration = 45, dispellable = true },
    bleed = { spellID = 772, icon = 'Interface\\Icons\\Ability_Gouge', applications = 2, duration = 30 },
}
local previewMembers = {
    { name = 'Warrior', class = 'WARRIOR', role = 'TANK', leader = true, health = 100, power = 65, powerToken = 'RAGE',
        selected = true, raidMarker = 8, threat = 3, ready = 'ready', pvpFaction = 'Horde', absorb = 18,
        buffs = { previewAuras.fortitude, previewAuras.intellect, previewAuras.renew, previewAuras.shield },
        debuffs = { previewAuras.bleed } },
    { name = 'Priest', class = 'PRIEST', role = 'HEALER', health = 84, power = 72, powerToken = 'MANA',
        ready = 'waiting', summon = 'Pending', incomingHeal = 10, absorb = 8,
        buffs = { previewAuras.fortitude, previewAuras.intellect, previewAuras.shield }, debuffs = {} },
    { name = 'Mage', class = 'MAGE', role = 'DAMAGER', health = 52, power = 38, powerToken = 'MANA',
        raidMarker = 3, pvpFaction = 'Alliance', phased = true, outOfRange = true,
        incomingHeal = 20, absorb = 12, healAbsorb = 28,
        buffs = { previewAuras.fortitude, previewAuras.intellect },
        debuffs = { previewAuras.poison, previewAuras.slow } },
    { name = 'Rogue', class = 'ROGUE', role = 'DAMAGER', health = 0, power = 0, powerToken = 'ENERGY',
        state = 'dead', resurrection = true, summon = 'Pending', ready = 'waiting', raidMarker = 7,
        buffs = { previewAuras.rejuvenation },
        debuffs = { previewAuras.poison, previewAuras.bleed, previewAuras.slow } },
    { name = 'Druid', class = 'DRUID', role = 'DAMAGER', health = 67, power = 91, powerToken = 'MANA',
        state = 'offline', ready = 'notready',
        buffs = { previewAuras.fortitude, previewAuras.intellect, previewAuras.rejuvenation },
        debuffs = { previewAuras.slow } },
}

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
            frame:SetPreview(true, previewMembers[i])
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
        if event == 'UNIT_FLAGS' or event == 'UNIT_CONNECTION' then frame.status:Refresh() end
    elseif event == 'UNIT_POWER_UPDATE' or event == 'UNIT_MAXPOWER' or event == 'UNIT_DISPLAYPOWER' then
        frame:UpdatePower()
    elseif event == 'UNIT_AURA' then
        frame:UpdateAuras()
    elseif event == 'UNIT_HEAL_PREDICTION' or event == 'UNIT_ABSORB_AMOUNT_CHANGED'
        or event == 'UNIT_HEAL_ABSORB_AMOUNT_CHANGED' then
        if not frame.preview and not frame.healthStatus then frame.prediction:Refresh() end
    elseif event == 'UNIT_THREAT_SITUATION_UPDATE' then
        frame.status:UpdateThreat()
    elseif event == 'UNIT_PHASE' or event == 'UNIT_OTHER_PARTY_CHANGED'
        or event == 'INCOMING_RESURRECT_CHANGED' or event == 'INCOMING_SUMMON_CHANGED' then
        frame.status:UpdatePresence()
        frame.status:UpdateRange()
    elseif event == 'UNIT_IN_RANGE_UPDATE' then
        frame.status:UpdateRange()
    elseif event == 'UNIT_FACTION' then
        frame.status:UpdatePvP()
    else
        frame:UpdateIdentity()
    end
end

function party:OnIdentityChanged()
    self:RefreshAll()
end

function party:OnLeaderChanged()
    if not self.frames then return end
    for _, frame in ipairs(self.frames) do frame:UpdateLeader() end
end

function party:OnTargetChanged()
    if not self.frames then return end
    for _, frame in ipairs(self.frames) do
        frame:UpdatePercentVisibility()
        frame.status:UpdateTarget()
    end
end

function party:OnStatusChanged()
    if not self.frames then return end
    for _, frame in ipairs(self.frames) do frame.status:Refresh() end
end

function party:OnReadyCheck(event)
    if not self.frames then return end
    for _, frame in ipairs(self.frames) do
        if event == 'READY_CHECK' then frame.status:BeginReadyCheck()
        elseif event == 'READY_CHECK_FINISHED' then frame.status:FinishReadyCheck()
        else frame.status:UpdateReadyCheck() end
    end
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
    addon.Utils.RegisterEventIfValid(self, 'PARTY_LEADER_CHANGED', 'OnLeaderChanged')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_ENTERING_WORLD', 'OnRosterChanged')
    addon.Utils.RegisterEventIfValid(self, 'INSPECT_READY', 'OnInspectReady')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_SPECIALIZATION_CHANGED', 'OnIdentityChanged')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_LEVEL_UP', 'OnIdentityChanged')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_TARGET_CHANGED', 'OnTargetChanged')
    addon.Utils.RegisterEventIfValid(self, 'ROLE_CHANGED_INFORM', 'OnIdentityChanged')
    addon.Utils.RegisterEventIfValid(self, 'PLAYER_ROLES_ASSIGNED', 'OnIdentityChanged')
    addon.Utils.RegisterEventIfValid(self, 'SPELLS_CHANGED', 'OnIdentityChanged')
    for _, event in ipairs({ 'RAID_TARGET_UPDATE', 'PLAYER_FLAGS_CHANGED', 'PVP_TIMER_UPDATE' }) do
        addon.Utils.RegisterEventIfValid(self, event, 'OnStatusChanged')
    end
    for _, event in ipairs({ 'READY_CHECK', 'READY_CHECK_CONFIRM', 'READY_CHECK_FINISHED' }) do
        addon.Utils.RegisterEventIfValid(self, event, 'OnReadyCheck')
    end
    for _, event in ipairs({ 'UNIT_HEALTH', 'UNIT_MAXHEALTH', 'UNIT_POWER_UPDATE', 'UNIT_MAXPOWER',
        'UNIT_DISPLAYPOWER', 'UNIT_AURA', 'UNIT_NAME_UPDATE', 'UNIT_LEVEL', 'UNIT_CONNECTION',
        'UNIT_FLAGS', 'UNIT_PORTRAIT_UPDATE', 'UNIT_MODEL_CHANGED', 'UNIT_HEAL_PREDICTION',
        'UNIT_ABSORB_AMOUNT_CHANGED', 'UNIT_HEAL_ABSORB_AMOUNT_CHANGED', 'UNIT_THREAT_SITUATION_UPDATE',
        'UNIT_PHASE', 'UNIT_OTHER_PARTY_CHANGED', 'UNIT_IN_RANGE_UPDATE', 'UNIT_FACTION',
        'INCOMING_RESURRECT_CHANGED', 'INCOMING_SUMMON_CHANGED' }) do
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
