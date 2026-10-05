local addonName, addon = ...
addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)
local toasts = addon.Toasts
local Sources = addon.ToastSources

local function db() return addon.db.profile.toasts end
local function now() return (type(GetTime) == 'function') and GetTime() or 0 end

--#region ── Testing / mock ───────────────────────────────────────────────────

function toasts:Notify(text)
    print('CouchMode: ' .. tostring(text))
end

--- Applies one mock reward through the same paths live rewards use.
---@param spec table
function toasts:MockEntry(spec)
    local timestamp = now()
    local entry

    if spec.kind == 'items' then
        self:OnLootMessage('CHAT_MSG_LOOT', spec.text)
        return
    elseif spec.kind == 'money' then
        entry = Sources.NormalizeMoney(spec.amount, spec.total, timestamp)
    elseif spec.kind == 'currency' then
        entry = Sources.NormalizeCurrency(spec.currencyID, spec.total, spec.amount, timestamp)
        if entry then
            entry.name = spec.name or entry.name
            entry.icon = spec.icon or entry.icon
            entry.quality = spec.quality or entry.quality
        end
    elseif spec.kind == 'reputation' then
        if spec.name and spec.amount then
            entry = Sources.NormalizeReputationFromParts(spec.name, spec.amount, timestamp, spec.text)
            if entry then
                local info = Sources.GetFactionReputation(spec.name)
                entry.reaction = spec.reaction or (info and info.reaction)
                entry.progress = spec.progress or (info and info.progress)
                entry.progressMax = spec.progressMax or (info and info.progressMax)
            end
        elseif spec.text and Sources.ParseReputationGain(spec.text) then
            self:OnReputationMessage('CHAT_MSG_COMBAT_FACTION_CHANGE', spec.text)
            return
        end
    elseif spec.kind == 'system' then
        local event = spec.event or 'CHAT_MSG_SYSTEM'
        if event == 'UI_ERROR_MESSAGE' or event == 'UI_INFO_MESSAGE' then
            self:OnUIMessage(event, nil, spec.text)
        else
            self:OnSystemMessage(event, spec.text)
        end
        return
    end

    if entry then self:AddEntry(entry) end
end

function toasts:RunMock(setName)
    local mock = addon.ToastMock
    if not mock then return end
    if not db().enabled then
        self:Notify('enable Toasts before running the mock.')
        return
    end

    local resolved = mock.Resolve(setName)
    if not resolved then
        self:Notify(('Unknown mock set "%s". Available: %s, all.')
            :format(tostring(setName), table.concat(mock.Names(), ', ')))
        return
    end

    local count = mock.Run(self, resolved)
    self:Notify(('Toasts mock: fired %d messages from "%s".'):format(count, resolved))
end

--- Entry point for `/cm toasts ...`.
---@param sub string
---@param arg string
function toasts:HandleCommand(sub, arg)
    sub = (sub or ''):lower()
    if sub == 'mock' or sub == 'test' then
        toasts:RunMock(arg)
    elseif sub == 'items' or sub == 'item' then
        -- Convenience shortcut for the item reward set.
        toasts:RunMock('item')
    elseif sub == 'clear' then
        toasts:ClearToasts()
        toasts:Notify('Active Toasts and queued rewards cleared.')
    elseif sub == 'sets' then
        toasts:Notify('Toasts mock sets: ' .. table.concat(addon.ToastMock.Names(), ', ') .. ', all')
    else
        toasts:Notify('CouchMode Toasts: /cm toasts items | /cm toasts mock [set] | /cm toasts sets | /cm toasts clear')
    end
end

--#endregion

--#region ── Bindings ──────────────────────────────────────────────────────────

function CouchMode_ToastsToggle() addon.Toasts:Toggle() end
function CouchMode_ToastsClose() addon.Toasts:ClosePanel() end

BINDING_NAME_COUCHMODE_TOASTS_TOGGLE = 'Toggle Toasts'
BINDING_NAME_COUCHMODE_TOASTS_CLOSE = 'Close Toasts'

--#endregion
