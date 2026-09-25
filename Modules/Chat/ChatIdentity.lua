--[[ ChatIdentity.lua
Identity for chat senders: unit tokens, class/race data, best-effort guild
lookup, and the throttled specialization-inspect pipeline.

Resolution is cached per GUID. Inspects only run out of combat and one at a time;
the Chat module's `OnEnable` wires the client's `INSPECT_READY` and
`PLAYER_REGEN_ENABLED` events to `OnInspectReady` and `ProcessInspectQueue`.
]]

local addonName, addon = ...

local chat = addon.Chat
local Sources = addon.ChatSources
local Rules = addon.ChatRules

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

local isSecret = addon.Utils.IsSecretValue

--#region ── State ─────────────────────────────────────────────────────────────

chat.identByGuid = {}     ---@type table<string, table>
chat.unitByGuid = {}      ---@type table<string, string>
chat.guildByName = {}     ---@type table<string, string>
chat.guildRosterBuilt = false
chat.inspectingGuid = nil ---@type string?
chat.inspectQueue = {}    ---@type {unit:string, guid:string}[]

--#endregion

--#region ── Identity ──────────────────────────────────────────────────────────

local function findUnitTokenByGUID(guid)
    if not guid then return nil end
    if UnitGUID('player') == guid then return 'player' end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local isRaid = IsInRaid and IsInRaid()
    for i = 1, n do
        local token = isRaid and ('raid' .. i) or ('party' .. i)
        if UnitGUID(token) == guid then return token end
    end
end

function chat:ResolveUnit(msg)
    if not msg.guid then return nil end
    local cached = self.unitByGuid[msg.guid]
    if cached ~= nil and cached ~= false then return cached end
    local token = findUnitTokenByGUID(msg.guid) or (UnitTokenFromGUID and UnitTokenFromGUID(msg.guid))
    self.unitByGuid[msg.guid] = token or false
    return token
end

function chat:ResolveIdentity(msg)
    if not msg.guid or isSecret(msg.guid) then return nil end
    local id = self.identByGuid[msg.guid]
    if id then return id end

    local localizedClass, classFile, localizedRace, raceFile, sex = GetPlayerInfoByGUID(msg.guid)
    if isSecret(localizedClass) then return nil end
    if not classFile then return nil end

    id = {
        class = localizedClass,
        classFile = classFile,
        race = localizedRace,
        raceFile = raceFile,
        sex = sex,
    }
    self.identByGuid[msg.guid] = id
    return id
end

function chat:BuildGuildRoster()
    if self.guildRosterBuilt then return end
    self.guildRosterBuilt = true
    if not (GetNumGuildMembers and GetGuildInfo) then return end
    local guild = GetGuildInfo('player')
    if not guild then return end
    local count = GetNumGuildMembers() or 0
    for i = 1, count do
        local name = GetGuildRosterInfo(i)
        if name then
            local base = Rules.SplitName(name)
            if base then self.guildByName[string.lower(base)] = guild end
        end
    end
end

--- Best-effort guild lookup for a message sender.
---@param msg ChatMessage
---@param unit string?
---@return string?
function chat:ResolveGuild(msg, unit)
    if unit and unit ~= 'player' and UnitIsPlayer and UnitIsPlayer(unit) and GetGuildInfo then
        local guild = GetGuildInfo(unit)
        if guild and not isSecret(guild) then return guild end
    end
    if not msg.sender or isSecret(msg.sender) then return nil end
    self:BuildGuildRoster()
    local base = Rules.SplitName(msg.sender)
    if base then return self.guildByName[string.lower(base)] end
end

--#endregion

--#region ── Enrichment / inspect ────────────────────────────────────────────────

function chat:Enrich(msg)
    if Sources.IsNpc(msg.event) then
        if not msg.npcId and msg.sender and not isSecret(msg.sender) and addon.BanterData then
            local id, displayId = addon.BanterData.GetByName(msg.sender)
            msg.npcId, msg.displayId = id, displayId
        end
        if not msg.displayId and msg.guid then
            msg.unitToken = self:ResolveUnit(msg)
        end
        return
    end

    if msg.guid then
        local id = self:ResolveIdentity(msg)
        if id then
            msg.classFile = id.classFile
            msg.class = id.class
            msg.raceFile = id.raceFile
            msg.sex = id.sex
        end
        msg.unitToken = self:ResolveUnit(msg)
    end
end

function chat:CanInspect(unit)
    if not unit then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    if CanInspect and not CanInspect(unit) then return false end
    return true
end

function chat:EnqueueInspect(unit, guid)
    if not db().specEnrichment or not unit or not guid then return end
    if not (NotifyInspect and GetInspectSpecialization) then return end
    local id = self.identByGuid[guid]
    if id and id.spec then return end
    if not self:CanInspect(unit) then return end
    if self.inspectingGuid then
        self.inspectQueue[#self.inspectQueue + 1] = { unit = unit, guid = guid }
        return
    end
    self.inspectingGuid = guid
    NotifyInspect(unit)
end

function chat:ProcessInspectQueue()
    if self.inspectingGuid then return end
    if not NotifyInspect then return end
    local nextEntry = table.remove(self.inspectQueue, 1)
    if nextEntry and self:CanInspect(nextEntry.unit) then
        self.inspectingGuid = nextEntry.guid
        NotifyInspect(nextEntry.unit)
    end
end

function chat:OnInspectReady(event, guid)
    if isSecret(guid) then self.inspectingGuid = nil; return end
    local unit = self.unitByGuid[guid] or (UnitTokenFromGUID and UnitTokenFromGUID(guid))
    if unit and guid == UnitGUID(unit) and GetInspectSpecialization and GetSpecializationInfoByID then
        local specID = GetInspectSpecialization(unit)
        local _, name, _, icon = GetSpecializationInfoByID(specID)
        if icon then
            local id = self.identByGuid[guid]
            if id then
                id.spec = { name = name, icon = icon }
                -- Class colors remain authoritative; only the badge refreshes.
                self:RefreshVisibleIcons()
            end
        end
    end
    self.inspectingGuid = nil
    C_Timer.After(0.1, function() self:ProcessInspectQueue() end)
end

--#endregion
