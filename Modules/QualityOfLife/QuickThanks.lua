-- Observe real aura changes, with optional combat-log correlation when the
-- aura has no readable caster. Login/zone snapshots never trigger prompts.
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
qol.quickThanksAuras = nil

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
    return type(auraReader()) == 'function' and Utils.EventExists('UNIT_AURA') ~= false
end

function qol:QuickThanksCombatLogAvailable()
    return type(combatLogReader()) == 'function'
        and bit and bit.band and bit.bor and combatFlag('TypePlayer') and combatFlag('AffiliationMine')
        and combatFlag('AffiliationParty') and combatFlag('AffiliationRaid')
        and Utils.EventExists('COMBAT_LOG_EVENT_UNFILTERED') ~= false
end

function qol:IsQuickThanksOutsider(guid, unit)
    if not safe(guid, 'string') or guid == UnitGUID('player') or self.quickThanksGroup[guid] then return false end
    if not guid:match('^Player%-') then return false end
    -- Check both memberships when a home party coexists with an instance
    -- group. Battleground teammates are in the instance party/raid. GUID
    -- membership also works when a stranger has no usable unit token.
    local inGroup = C_PartyInfo and C_PartyInfo.IsGUIDInGroup or IsGUIDInGroup
    for _, category in ipairs({ LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE }) do
        if inGroup then
            local member = inGroup(guid, category)
            if isSecret(member) or member then return false end
        elseif safe(unit, 'string') then
            local inParty, inRaid = UnitInParty(unit, category), UnitInRaid(unit, category)
            if isSecret(inParty) or isSecret(inRaid) or inParty or inRaid then return false end
        end
    end
    return true
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
    self.quickThanksAuras = nil
    if Utils.IsFlavor('forever') then
        self:RefreshQuickThanksGroup()
        self:MatchQuickThanksBuffs(false)
    end
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
        self.quickThanksEvents:SetScript('OnEvent', function(_, event, unit, updateInfo)
            if event == 'COMBAT_LOG_EVENT_UNFILTERED' then
                qol:OnQuickThanksCombatLog()
            elseif event == 'UNIT_AURA' then
                if not isSecret(unit) and unit == 'player' then
                    -- A full update establishes a baseline, rather than a new
                    -- cast. Older clients omit updateInfo and use snapshot diffs.
                    local fullUpdate = isSecret(updateInfo)
                        or (updateInfo and (isSecret(updateInfo.isFullUpdate) or updateInfo.isFullUpdate))
                    qol:MatchQuickThanksBuffs(not fullUpdate)
                end
            elseif event == 'GROUP_ROSTER_UPDATE' then
                qol:RefreshQuickThanksGroup()
                qol.quickThanksPending = {}
                local prompt = qol.quickThanksActive
                if prompt and not prompt.preview and not qol:IsQuickThanksOutsider(prompt.guid) then
                    qol:DismissQuickThanks(true)
                end
            else
                qol:RefreshQuickThanksBinding()
            end
        end)
    end
    local frame = self.quickThanksEvents
    for _, event in ipairs({ 'GROUP_ROSTER_UPDATE', 'UPDATE_BINDINGS', 'GAME_PAD_ACTIVE_CHANGED' }) do
        Utils.RegisterEventIfValid(frame, event)
    end
    if self:QuickThanksCombatLogAvailable() then
        Utils.RegisterEventIfValid(frame, 'COMBAT_LOG_EVENT_UNFILTERED')
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
        and self:IsQuickThanksOutsider(guid)
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
        if isSecret(aura) then break end
        if not aura then break end
        if safe(aura.spellId, 'number') and safe(aura.duration, 'number')
            and aura.duration >= MIN_DURATION and safe(aura.expirationTime, 'number') then
            local source = safe(aura.sourceUnit, 'string') and aura.sourceUnit or nil
            local guid
            if source then guid = UnitGUID(source) end
            local instanceID = safe(aura.auraInstanceID, 'number') and aura.auraInstanceID or nil
            if not safe(guid, 'string') and instanceID and C_UnitAuras and C_UnitAuras.GetAuraCasterGUID then
                local ok, caster = pcall(C_UnitAuras.GetAuraCasterGUID, 'player', instanceID)
                if ok and safe(caster, 'string') then guid = caster end
            end
            guid = safe(guid, 'string') and guid or nil
            buffs[#buffs + 1] = {
                spellID = aura.spellId, applied = aura.expirationTime - aura.duration,
                guid = guid, sourceUnit = source,
                key = instanceID or (tostring(aura.spellId) .. ':' .. (guid or 'unknown')),
                icon = (safe(aura.icon, 'number') or safe(aura.icon, 'string')) and aura.icon or nil,
            }
        end
    end
    return buffs
end

function qol:OfferQuickThanksBuff(guid, name, aura)
    if aura.notified or not self:IsQuickThanksOutsider(guid, aura.sourceUnit) then return end
    if (self.quickThanksCooldowns[guid] or 0) > GetTime() then return end
    if not safe(name, 'string') and safe(aura.sourceUnit, 'string') then name = UnitName(aura.sourceUnit) end
    if not safe(name, 'string') and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, casterName = pcall(GetPlayerInfoByGUID, guid)
        if ok then name = casterName end
    end
    aura.notified = true
    self:ShowQuickThanks(guid, safe(name, 'string') and name or 'Someone', false, aura.spellID, aura.icon)
end

function qol:MatchQuickThanksBuffs(detectChanges)
    if not self:IsQuickThanksEnabled() then return end
    local now = GetTime()
    for guid, expires in pairs(self.quickThanksCooldowns) do
        if expires <= now then self.quickThanksCooldowns[guid] = nil end
    end
    for i = #self.quickThanksPending, 1, -1 do
        if now - self.quickThanksPending[i].time > MATCH_WINDOW then table.remove(self.quickThanksPending, i) end
    end
    if Utils.CanReadAuras() then
        -- Some clients reject enumeration before returning secret fields.
        local ok, buffs = pcall(readBuffs)
        if ok then
            local previous, current = self.quickThanksAuras, {}
            for _, aura in ipairs(buffs) do
                local old = previous and previous[aura.key]
                local unchanged = old and old.guid == aura.guid and old.spellID == aura.spellID
                    and math.abs(old.applied - aura.applied) < 0.01
                aura.notified = unchanged and old.notified or false
                current[aura.key] = aura
                if detectChanges and previous and not unchanged
                    and math.abs(now - aura.applied) <= MATCH_WINDOW then
                    self:OfferQuickThanksBuff(aura.guid, nil, aura)
                end
            end
            self.quickThanksAuras = current
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
                                self:OfferQuickThanksBuff(record.guid, record.name, aura)
                                break
                            end
                        end
                    end
                end
            end
        else
            self.quickThanksAuras = nil
        end
    else
        self.quickThanksAuras = nil
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
    if GetTime() >= active.expires or (not active.preview and not self:IsQuickThanksOutsider(active.guid)) then
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
