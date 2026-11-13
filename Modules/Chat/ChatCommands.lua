--[[ ChatCommands.lua
Chat's external entry points: the `/cm chat` subcommands, the mock runner used for
manual testing, and the key-binding globals declared in Bindings.xml.

`Notify` routes feedback through the real router so it appears as a system line in
the feed even while Blizzard chat is suppressed.
]]

local addonName, addon = ...

local chat = addon.Chat

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

--#region ── Testing / mock ──────────────────────────────────────────────────────

--- Pushes a message through the router so it lands in the feed like a real
--- system line. Used for feedback that would otherwise be hidden by the
--- Blizzard chat suppression.
---@param text string
function chat:Notify(text)
    if not db().enabled then print('CouchMode: ' .. tostring(text)); return end
    addon.ChatRouter:OnSyntheticEvent('CHAT_MSG_SYSTEM', text, '', '', '', '', '', 0, 0, '', 0, nil, nil)
end

--- Fires a set of representative mock messages through the real router.
---@param setName string?  'all' or one of addon.ChatMock.Names()
function chat:RunMock(setName)
    if not db().enabled then
        print('CouchMode: enable Chat before running the mock.')
        return
    end
    local mock = addon.ChatMock
    if not mock then return end

    setName = (setName == nil or setName == '') and 'all' or setName
    if setName ~= 'all' and not mock.SETS[setName] then
        chat:Notify(('Unknown mock set "%s". Available: %s, all.')
            :format(setName, table.concat(mock.Names(), ', ')))
        return
    end

    local count = mock.Run(addon.ChatRouter, setName)
    chat:Notify(('Chat mock: fired %d messages from "%s".'):format(count, setName))
end

--- Entry point for `/cm chat ...`.
---@param sub string
---@param arg string
function chat:HandleCommand(sub, arg)
    sub = (sub or ''):lower()
    if sub == 'mock' or sub == 'test' then
        chat:RunMock(arg)
    elseif sub == 'clear' then
        chat:ClearSession()
        chat:Notify('Chat history cleared.')
    elseif sub == 'sets' then
        chat:Notify('Chat mock sets: ' .. table.concat(addon.ChatMock.Names(), ', ') .. ', all')
    else
        chat:Notify('CouchMode Chat: /cm chat mock [set] | /cm chat sets | /cm chat clear')
    end
end

--#endregion

--#region ── Bindings ──────────────────────────────────────────────────────────

function CouchMode_ChatHistoryToggle() addon.Chat:ToggleHistoryMode() end
function CouchMode_ChatComposer()
    if chat:IsComposerOpen() then chat:CloseComposer(); return end
    local qol = addon.QualityOfLife
    if qol and qol:IsQuickThanksShown() then qol:SendQuickThanks()
    else chat:ToggleComposer() end
end
BINDING_NAME_COUCHMODE_CHAT_HISTORY_TOGGLE = 'Chat History' ---@diagnostic disable-line: lowercase-global
BINDING_NAME_COUCHMODE_CHAT_COMPOSER = 'Chat Composer' ---@diagnostic disable-line: lowercase-global

--#endregion
