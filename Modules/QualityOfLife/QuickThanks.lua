-- Correlate real buff applications with readable player auras. Never infer a
-- new application from a login/zone aura snapshot or from an unidentified unit.
local _, addon = ...
local qol = addon.QualityOfLife
local Utils = addon.Utils
local isSecret = Utils.IsSecretValue
local function db() return addon.db.profile.qualityOfLife.quickThanks end
local MIN_DURATION, MATCH_WINDOW, MAX_PENDING = 300, 1.5, 64
local REPEAT_COOLDOWN = 60
local LEGACY_FLAGS = {
    TypePlayer = 'COMBATLOG_OBJECT_TYPE_PLAYER',
    AffiliationMine = 'COMBATLOG_OBJECT_AFFILIATION_MINE',
    AffiliationParty = 'COMBATLOG_OBJECT_AFFILIATION_PARTY',
    AffiliationRaid = 'COMBATLOG_OBJECT_AFFILIATION_RAID',
}

qol.quickThanksPending = {}
qol.quickThanksCooldowns = {}
qol.quickThanksGroup = {}

local function safe(value, kind)
    return not isSecret(value) and type(value) == kind
end

local function combatLogReader()
    return C_CombatLog and C_CombatLog.GetCurrentEventInfo or CombatLogGetCurrentEventInfo
end

local function auraReader()
    return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex or UnitBuff
end

local function combatFlag(name)
    local enum = Enum and Enum.CombatLogObject
    return enum and enum[name] or _G[LEGACY_FLAGS[name]]
end

function qol:IsQuickThanksEnabled()
    return Utils.IsFlavor('forever') and self:IsEnabled()
        and db().enabled == true
end

function qol:QuickThanksAvailable()
    return type(combatLogReader()) == 'function' and type(auraReader()) == 'function'
        and bit and bit.band and bit.bor and combatFlag('TypePlayer') and combatFlag('AffiliationMine')
        and combatFlag('AffiliationParty') and combatFlag('AffiliationRaid')
end

function qol:RefreshQuickThanksGroup()
    local group = {}
    for _, prefix in ipairs({ 'party', 'raid' }) do
        for i = 1, prefix == 'party' and 4 or 40 do
            local guid = UnitGUID(prefix .. i)
            if safe(guid, 'string') then group[guid] = true end
        end
    end
    self.quickThanksGroup = group
end

function qol:ResetQuickThanks()
    if self.quickThanksTimer then self.quickThanksTimer:Cancel(); self.quickThanksTimer = nil end
    self:DismissQuickThanks(false)
    self.quickThanksPending = {}
    self.quickThanksCooldowns = {}
    if Utils.IsFlavor('forever') then self:RefreshQuickThanksGroup() end
end

function qol:StopQuickThanks()
    if self.quickThanksEvents then self.quickThanksEvents:UnregisterAllEvents() end
    self:ResetQuickThanks()
end

function qol:ConfigureQuickThanks()
    self:StopQuickThanks()
    if not self:IsQuickThanksEnabled() then return end
    self:BuildQuickThanksPrompt()
    self:InitializeQuickThanksEditMode()
    self:ApplyQuickThanksAnchor()
    if self.quickThanksEditing then self:ShowQuickThanks('preview', 'Preview', true, 1243) end
    if not self:QuickThanksAvailable() then return end
    if not self.quickThanksEvents then
        self.quickThanksEvents = CreateFrame('Frame')
        self.quickThanksEvents:SetScript('OnEvent', function(_, event, unit)
            if event == 'COMBAT_LOG_EVENT_UNFILTERED' then
                qol:OnQuickThanksCombatLog()
            elseif event == 'UNIT_AURA' then
                if not isSecret(unit) and unit == 'player' then qol:ScheduleQuickThanksMatch() end
            elseif event == 'GROUP_ROSTER_UPDATE' then
                qol:RefreshQuickThanksGroup()
                qol.quickThanksPending = {}
                local prompt = qol.quickThanksActive
                if prompt and qol.quickThanksGroup[prompt.guid] then qol:DismissQuickThanks(true) end
            else
                qol:RefreshQuickThanksBinding()
            end
        end)
    end
    local frame = self.quickThanksEvents
    for _, event in ipairs({ 'COMBAT_LOG_EVENT_UNFILTERED',
        'GROUP_ROSTER_UPDATE', 'UPDATE_BINDINGS', 'GAME_PAD_ACTIVE_CHANGED' }) do
        Utils.RegisterEventIfValid(frame, event)
    end
    if Utils.EventExists('UNIT_AURA') == true then
        pcall(frame.RegisterUnitEvent, frame, 'UNIT_AURA', 'player')
    end
end

function qol:ScheduleQuickThanksMatch()
    if self.quickThanksTimer or #self.quickThanksPending == 0 then return end
    self.quickThanksTimer = C_Timer.NewTimer(0.05, function()
        qol.quickThanksTimer = nil
        qol:MatchQuickThanksBuffs()
    end)
end

function qol:OnQuickThanksCombatLog()
    if not self:IsQuickThanksEnabled() then return end
    if C_CombatLog and C_CombatLog.IsCombatLogRestricted and C_CombatLog.IsCombatLogRestricted() then return end
    local ok, _, event, _, guid, name, flags, _, destination, _, _, _, spellID, _, _, auraType =
        pcall(combatLogReader())
    if not ok or not safe(event, 'string') or not safe(auraType, 'string')
        or (event ~= 'SPELL_AURA_APPLIED' and event ~= 'SPELL_AURA_REFRESH') or auraType ~= 'BUFF'
        or not safe(destination, 'string') or destination ~= UnitGUID('player')
        or not safe(guid, 'string') or not safe(name, 'string') or not safe(flags, 'number')
        or not safe(spellID, 'number') then return end
    local now = GetTime()
    -- Retain ineligible casters too: a simultaneous group/self application of
    -- the same spell must not be attributed to an unrelated stranger.
    local eligible = bit.band(flags, combatFlag('TypePlayer')) ~= 0
        and bit.band(flags, bit.bor(combatFlag('AffiliationMine'), combatFlag('AffiliationParty'),
            combatFlag('AffiliationRaid'))) == 0
        and guid ~= UnitGUID('player') and not self.quickThanksGroup[guid]
    for i = #self.quickThanksPending, 1, -1 do
        local record = self.quickThanksPending[i]
        if now - record.time > MATCH_WINDOW then
            table.remove(self.quickThanksPending, i)
        elseif record.guid == guid and record.spellID == spellID then
            table.remove(self.quickThanksPending, i)
        end
    end
    if #self.quickThanksPending >= MAX_PENDING then return end
    self.quickThanksPending[#self.quickThanksPending + 1] = {
        guid = guid, name = name, spellID = spellID, eligible = eligible, time = now,
    }
    self:ScheduleQuickThanksMatch()
end

local function readBuffs()
    local buffs = {}
    local structured = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 255 do
        local aura
        if structured then
            aura = structured('player', i, 'HELPFUL')
        else
            local name, icon, _, _, duration, expiration, source, _, _, spellID = UnitBuff('player', i)
            if name then
                aura = { spellId = spellID, icon = icon, duration = duration,
                    expirationTime = expiration, sourceUnit = source }
            end
        end
        if not aura then break end
        if not isSecret(aura) and not isSecret(aura.sourceUnit)
            and safe(aura.spellId, 'number') and safe(aura.duration, 'number')
            and aura.duration >= MIN_DURATION and safe(aura.expirationTime, 'number') then
            local guid
            if safe(aura.sourceUnit, 'string') then guid = UnitGUID(aura.sourceUnit) end
            buffs[#buffs + 1] = {
                spellID = aura.spellId, applied = aura.expirationTime - aura.duration,
                guid = safe(guid, 'string') and guid or nil,
                icon = (safe(aura.icon, 'number') or safe(aura.icon, 'string')) and aura.icon or nil,
            }
        end
    end
    return buffs
end

function qol:MatchQuickThanksBuffs()
    if not self:IsQuickThanksEnabled() then return end
    local now = GetTime()
    for guid, expires in pairs(self.quickThanksCooldowns) do
        if expires <= now then self.quickThanksCooldowns[guid] = nil end
    end
    for i = #self.quickThanksPending, 1, -1 do
        if now - self.quickThanksPending[i].time > MATCH_WINDOW then table.remove(self.quickThanksPending, i) end
    end
    if #self.quickThanksPending == 0 then return end
    if Utils.CanReadAuras() then
        -- Some clients reject enumeration before returning secret fields.
        local ok, buffs = pcall(readBuffs)
        if ok then
            for _, record in ipairs(self.quickThanksPending) do
                if record.eligible and not record.handled and not self.quickThanksGroup[record.guid] then
                    for _, aura in ipairs(buffs) do
                        if aura.spellID == record.spellID and math.abs(aura.applied - record.time) <= MATCH_WINDOW then
                            local matched = aura.guid == record.guid
                            if not aura.guid then
                                matched = true
                                for _, other in ipairs(self.quickThanksPending) do
                                    if other.spellID == record.spellID and other.guid ~= record.guid then
                                        matched = false; break
                                    end
                                end
                            end
                            if matched then
                                record.handled = true
                                if not self.quickThanksCooldowns[record.guid] then
                                    self:ShowQuickThanks(record.guid, record.name, false, aura.spellID, aura.icon)
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    -- Only a short, bounded retry window; no permanent aura polling.
    self:ScheduleQuickThanksMatch()
end

function qol:ApplyQuickThanksCooldown()
    local active = self.quickThanksActive
    if active and not active.preview and not active.sent then
        for guid in pairs(active.participants) do
            self.quickThanksCooldowns[guid] = GetTime() + REPEAT_COOLDOWN
        end
    end
end

function qol:DismissQuickThanks(cooldown)
    if cooldown then self:ApplyQuickThanksCooldown() end
    self.quickThanksActive = nil
    if self.quickThanksPrompt then
        self.quickThanksPrompt:SetScript('OnUpdate', nil)
        self.quickThanksPrompt:Hide()
    end
end

function qol:IsQuickThanksShown()
    local active = self.quickThanksActive
    return self:IsQuickThanksEnabled() and not self.quickThanksEditing and active ~= nil
        and self.quickThanksPrompt ~= nil and self.quickThanksPrompt:IsVisible()
        and GetTime() < active.expires
end

function qol:SendQuickThanks()
    local active = self.quickThanksActive
    if self.quickThanksEditing or not active or active.sent or active.submitting
        or not self:IsQuickThanksEnabled() then return end
    if GetTime() >= active.expires or self.quickThanksGroup[active.guid] then
        self:DismissQuickThanks(true); return
    end
    if active.preview then self:ConfirmQuickThanks(); return end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if not send then return end
    -- Send only in the binding/click hardware callback; guard repeated input
    -- while sending and while the confirmation remains visible.
    active.submitting = true
    local ok, err = pcall(send, 'Thanks!', 'SAY')
    active.submitting = nil
    if not ok or err == false then
        print('CouchMode: Quick Thanks could not send the message.')
        if not ok then geterrorhandler()(err) end
        return
    end
    if self.quickThanksActive == active then self:ConfirmQuickThanks() end
end
