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
    addon.ChatRouter:OnEvent('CHAT_MSG_SYSTEM', text, '', '', '', '', '', 0, 0, '', 0, nil, nil)
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

function CouchMode_ChatToggle() addon.Chat:Toggle() end
function CouchMode_ChatFocus() addon.Chat:FocusInput() end
function CouchMode_ChatFilterNext() addon.Chat:CycleFilter(1) end
function CouchMode_ChatFilterPrev() addon.Chat:CycleFilter(-1) end
function CouchMode_ChatScrollUp() addon.Chat:ScrollUp() end
function CouchMode_ChatScrollDown() addon.Chat:ScrollDown() end
function CouchMode_ChatBottom() addon.Chat:ScrollToBottom() end
function CouchMode_ChatClose() addon.Chat:ClosePanel() end

--#endregion
