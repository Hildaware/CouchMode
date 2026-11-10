--[[ ChatOptions.lua
Defaults and the AceConfig settings panel for the Chat module.

`GetDefaults` feeds AceDB (collected by Core/Options.lua) and `GetOptions` returns
the tab shown in settings. Dynamic lists (blocked players/guilds, aliases) are
rebuilt through `RebuildOptions` so saved values appear immediately on login.
]]

local addonName, addon = ...

local chat = addon.Chat
local Rules = addon.ChatRules

--#region ── Constants ────────────────────────────────────────────────────────

local PANEL_ORDER = 10

--#endregion

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

--#region ── Defaults ─────────────────────────────────────────────────────────

function chat:GetDefaults()
    return {
        chat = {
            enabled = true,
            -- Position (per Edit Mode layout)
            positions = {},
            -- Sizing / appearance
            width = chat.DEFAULT_WIDTH,
            growthDirection = 'bottom',
            maxLiveMessages = 6,
            historyHeight = chat.DEFAULT_HISTORY_HEIGHT,
            scale = 1,
            activeOpacity = 1,
            backgroundOpacity = 0,
            fadeEnabled = true,
            fadeDelay = 15,
            compactMode = false,
            -- Text (each field is independently configurable)
            channelFontFace = 'Friz Quadrata TT',
            channelFontSize = 12,
            nameFontFace = 'Arial Narrow',
            nameFontSize = 18,
            msgFontFace = 'Arial Narrow',
            msgFontSize = 14,
            -- Character-by-character reveal (same behaviour as Chat Bubbles)
            revealText = true,
            revealSpeed = 44,
            -- Seconds between feed updates after the first message in a burst.
            messagePace = 0.35,
            groupWindow = 60,
            filter = 'ALL',
            -- Identity
            specEnrichment = true,
            -- Moderation / cosmetics
            blocks = { names = {}, guilds = {} },
            aliases = {},
            -- Seed lazily; an explicitly empty list must remain empty.
            quickReplies = false,
        },
        -- Bumped by ChatMigration; a value below CURRENT_VERSION runs migration.
        schemaVersion = 1,
    }
end

--#endregion

--#region ── Options ──────────────────────────────────────────────────────────

function chat:NotifyChange()
    local registry = LibStub('AceConfigRegistry-3.0', true)
    if registry then registry:NotifyChange(addonName) end
end

function chat:BuildBlockedList()
    local values = {}
    local blocks = db().blocks
    for i = 1, #(blocks.names or {}) do
        local name = blocks.names[i]
        values['name:' .. name] = 'Unblock ' .. name
    end
    for i = 1, #(blocks.guilds or {}) do
        local guild = blocks.guilds[i]
        values['guild:' .. guild] = 'Unblock guild ' .. guild
    end
    if next(values) == nil then
        values['__none'] = 'No blocked players or guilds'
    end
    return values
end

function chat:ApplyBlockedList(_)
    -- (Re)build the dynamic dropdown entries.
    if not self.optionsArgs or not self.optionsArgs.moderation
        or not self.optionsArgs.moderation.args.blocking then return end
    local args = self.optionsArgs.moderation.args.blocking.args
    args.blocked.values = function() return chat:BuildBlockedList() end
    args.blocked.get = function() return '__none' end
    args.blocked.set = function(_, value)
        local kind, key = value:match('^(%a+):(.+)$')
        if kind == 'name' then
            Rules.RemoveName(db().blocks, key)
        elseif kind == 'guild' then
            Rules.RemoveGuild(db().blocks, key)
        end
        chat:Recompute()
        chat:NotifyChange()
    end
end

function chat:BuildAliasList()
    local values = {}
    local aliases = db().aliases
    local any = false
    for key, alias in pairs(aliases) do
        values[key] = alias .. '  (' .. key .. ')'
        any = true
    end
    if not any then values['__none'] = 'No channel aliases' end
    return values
end

function chat:OpenBlizzardChatFiltering()
    local frame = _G.ChatConfigFrame
    if not frame then return end

    if ShowUIPanel then ShowUIPanel(frame) else frame:Show() end
    if frame.ChatTabManager and frame.ChatTabManager.UpdateSelection then
        frame.ChatTabManager:UpdateSelection(1)
    else
        _G.CURRENT_CHAT_FRAME_ID = 1
    end
    if ChatConfigCategory_OnClick and _G.ChatConfigCategoryFrameButton1 then
        ChatConfigCategory_OnClick(_G.ChatConfigCategoryFrameButton1)
    end
end

function chat:BuildArgs()
    local args = {
        description = {
            name = 'A full chat replacement: scrollback, filters, identity icons, moderation and channel aliases. '
                .. 'Disabling restores Blizzard chat exactly as it was.',
            type = 'description',
            order = 1,
        },
        enabled = {
            name = 'Enable',
            desc = 'Replace Blizzard chat with the CouchMode Chat feed.',
            type = 'toggle',
            order = 2,
            get = function() return db().enabled end,
            set = function(_, value)
                db().enabled = value
                if value then chat:Enable() else chat:Disable() end
            end,
        },
        appearance = {
            name = 'Appearance',
            type = 'group',
            order = 10,
            args = {
                width = {
                    name = 'Width', desc = 'Panel width in pixels.',
                    type = 'range', min = 240, max = 1200, step = 10, order = 1,
                    get = function() return db().width end,
                    set = function(_, v) db().width = v; chat:ApplyLayout(true) end,
                },
                growthDirection = {
                    name = 'Growth Direction',
                    desc = 'Choose the fixed edge that live chat grows away from.',
                    type = 'select', order = 2,
                    values = { bottom = 'Bottom', top = 'Top' },
                    get = function() return db().growthDirection or 'bottom' end,
                    set = function(_, v) db().growthDirection = v; chat:ApplyLayout() end,
                },
                maxLiveMessages = {
                    name = 'Live Messages',
                    desc = 'Maximum number of unfaded messages shown in live chat.',
                    type = 'range', min = 1, max = 20, step = 1, order = 3,
                    get = function() return db().maxLiveMessages or 6 end,
                    set = function(_, v) db().maxLiveMessages = v; chat:ApplyLayout() end,
                },
                historyHeight = {
                    name = 'History Height',
                    desc = 'Total panel height while browsing history, including visible controls.',
                    type = 'range', min = 200, max = 900, step = 10, order = 4,
                    get = function() return db().historyHeight or chat.DEFAULT_HISTORY_HEIGHT end,
                    set = function(_, v) db().historyHeight = v; chat:ApplyLayout() end,
                },
                scale = {
                    name = 'Scale', desc = 'Overall panel scale.',
                    type = 'range', min = 0.5, max = 2, step = 0.05, order = 5,
                    get = function() return db().scale end,
                    set = function(_, v) db().scale = v; chat:ApplyLayout() end,
                },
                activeOpacity = {
                    name = 'Active Opacity', desc = 'Panel opacity while at least one message is visible.',
                    type = 'range', min = 0.1, max = 1, step = 0.05, order = 6,
                    get = function() return db().activeOpacity end,
                    set = function(_, v) db().activeOpacity = v; chat:Touch() end,
                },
                backgroundOpacity = {
                    name = 'Background Opacity', desc = 'Panel opacity after all visible messages fade.',
                    type = 'range', min = 0, max = 1, step = 0.05, order = 7,
                    get = function() return db().backgroundOpacity end,
                    set = function(_, v) db().backgroundOpacity = v; chat:ApplyPanelBackgroundOpacity() end,
                },
                fadeEnabled = {
                    name = 'Auto-fade', desc = 'Fade each message after its delay, then fade the panel when none remain.',
                    type = 'toggle', order = 8,
                    get = function() return db().fadeEnabled end,
                    set = function(_, v) db().fadeEnabled = v; chat:Touch() end,
                },
                fadeDelay = {
                    name = 'Fade Delay', desc = 'Seconds each message remains visible before fading.',
                    type = 'range', min = 0, max = 60, step = 1, order = 9,
                    get = function() return db().fadeDelay end,
                    set = function(_, v) db().fadeDelay = v; chat:Touch() end,
                },
                compactMode = {
                    name = 'Compact Mode',
                    desc = 'Place the speaker name beside the channel, move messages directly below the header, and halve identity icon sizing.',
                    type = 'toggle', order = 10,
                    get = function() return db().compactMode end,
                    set = function(_, v) db().compactMode = v; chat:Recompute() end,
                },
                channelHeader = { name = 'Channel', type = 'header', order = 11 },
                channelFont = {
                    name = 'Font', desc = 'Font for the channel label.',
                    type = 'select', style = 'dropdown', order = 12,
                    values = addon.Media.GetFontOptions(),
                    get = function() return db().channelFontFace end,
                    set = function(_, v) db().channelFontFace = v; chat:Recompute() end,
                },
                channelSize = {
                    name = 'Font Size', desc = 'Channel label size.',
                    type = 'range', min = 6, max = 28, step = 1, order = 13,
                    get = function() return db().channelFontSize end,
                    set = function(_, v) db().channelFontSize = v; chat:Recompute() end,
                },
                nameHeader = { name = 'Name', type = 'header', order = 14 },
                nameFont = {
                    name = 'Font', desc = 'Font for the speaker name.',
                    type = 'select', style = 'dropdown', order = 15,
                    values = addon.Media.GetFontOptions(),
                    get = function() return db().nameFontFace end,
                    set = function(_, v) db().nameFontFace = v; chat:Recompute() end,
                },
                nameSize = {
                    name = 'Font Size', desc = 'Speaker name size.',
                    type = 'range', min = 6, max = 32, step = 1, order = 16,
                    get = function() return db().nameFontSize end,
                    set = function(_, v) db().nameFontSize = v; chat:Recompute() end,
                },
                msgHeader = { name = 'Message', type = 'header', order = 17 },
                msgFont = {
                    name = 'Font', desc = 'Font for message text.',
                    type = 'select', style = 'dropdown', order = 18,
                    values = addon.Media.GetFontOptions(),
                    get = function() return db().msgFontFace end,
                    set = function(_, v) db().msgFontFace = v; chat:Recompute() end,
                },
                msgSize = {
                    name = 'Font Size', desc = 'Message text size.',
                    type = 'range', min = 8, max = 28, step = 1, order = 19,
                    get = function() return db().msgFontSize end,
                    set = function(_, v) db().msgFontSize = v; chat:Recompute() end,
                },
                revealText = {
                    name = 'Reveal Text',
                    desc = 'Message text reveals character-by-character; the channel and name fade in.',
                    type = 'toggle', order = 20,
                    get = function() return db().revealText end,
                    set = function(_, v) db().revealText = v; chat:Recompute() end,
                },
                revealSpeed = {
                    name = 'Reveal Speed', desc = 'Characters revealed per second.',
                    type = 'range', min = 5, max = 120, step = 1, order = 21,
                    disabled = function() return not db().revealText end,
                    get = function() return db().revealSpeed end,
                    set = function(_, v) db().revealSpeed = v; chat:Recompute() end,
                },
                messagePace = {
                    name = 'Message Pace',
                    desc = 'Seconds between messages displayed during a burst. Messages remain queued and are shown in order. Set to 0 for the fastest possible display.',
                    type = 'range', min = 0, max = 1, step = 0.05, order = 22,
                    get = function() return db().messagePace end,
                    set = function(_, v)
                        db().messagePace = v
                        chat:UpdateMessageQueuePace()
                    end,
                },
                specEnrichment = {
                    name = 'Specialization Badges',
                    desc = 'Throttled, out-of-combat inspects add a specialization badge to player icons.',
                    type = 'toggle',
                    order = 23,
                    get = function() return db().specEnrichment end,
                    set = function(_, v) db().specEnrichment = v end,
                },
            },
        },
        moderation = {
            name = 'Moderation',
            type = 'group',
            order = 30,
            args = {
                blocking = {
                    name = 'Blocking',
                    type = 'group',
                    inline = true,
                    order = 1,
                    args = {
                        blockName = {
                            name = 'Block Player', desc = 'Name or Name-Realm. A bare name matches any realm.',
                            type = 'input', width = 1, order = 1,
                            get = function() return '' end,
                            set = function(_, v)
                                if v and v ~= '' then chat:BlockName(v) end
                            end,
                        },
                        blockGuild = {
                            name = 'Block Guild', desc = 'Guild name. Best effort: requires known membership.',
                            type = 'input', width = 1, order = 2,
                            get = function() return '' end,
                            set = function(_, v)
                                if v and v ~= '' then chat:BlockGuild(v) end
                            end,
                        },
                        blocked = {
                            name = 'Blocked', desc = 'Locally blocked players and guilds.',
                            type = 'select', style = 'dropdown', width = 'full', order = 3,
                            values = function() return chat:BuildBlockedList() end,
                            get = function() return '__none' end,
                            set = function() end,
                        },
                    },
                },
                aliases = {
                    name = 'Aliases',
                    type = 'group',
                    inline = true,
                    order = 4,
                    args = {
                        aliasKey = {
                            name = 'Alias Channel', desc = 'Canonical chat type or public channel base name.',
                            type = 'input', width = 1, order = 1,
                            get = function() return '' end,
                            set = function(_, v) db()._pendingAliasKey = v end,
                        },
                        aliasName = {
                            name = 'Alias Name', desc = 'Cosmetic label to show for that channel.',
                            type = 'input', width = 1, order = 2,
                            get = function() return '' end,
                            set = function(_, v)
                                local key = db()._pendingAliasKey
                                if key and key ~= '' and v and v ~= '' then
                                    db().aliases[key] = v
                                    chat:NotifyChange()
                                end
                            end,
                        },
                        aliasList = {
                            name = 'Aliases', desc = 'Configured cosmetic channel aliases.',
                            type = 'select', style = 'dropdown', width = 'full', order = 3,
                            values = function() return chat:BuildAliasList() end,
                            get = function() return '__none' end,
                            set = function(_, value)
                                if db().aliases[value] then
                                    db().aliases[value] = nil
                                    chat:NotifyChange()
                                end
                            end,
                        },
                    },
                },
            },
        },
        misc = {
            name = 'Misc',
            type = 'group',
            order = 99,
            args = {
                clear = {
                    name = 'Clear History', desc = 'Clear the current login\'s message history.',
                    type = 'execute', order = 1,
                    func = function() chat:ClearSession() end,
                },
                testMessages = {
                    name = 'Test Messages',
                    desc = 'Fire mock messages for every source into the feed.\n\nAlso available in chat as /cm chat mock [set] and /cm chat sets.',
                    type = 'execute', order = 2,
                    func = function() chat:RunMock('all') end,
                },
            },
        },
        filtering = {
            name = 'Filtering',
            type = 'group',
            order = 40,
            args = {
                openBlizzardFiltering = {
                    name = 'Open Blizzard Chat Filtering',
                    desc = 'Configure the General chat window. Changes affect new CouchMode Chat messages.',
                    type = 'execute',
                    order = 1,
                    func = function() chat:OpenBlizzardChatFiltering() end,
                },
            },
        },
    }
    args.quickReplies = self:BuildQuickRepliesOptions()
    return args
end

function chat:GetOptions()
    self.optionsArgs = self.optionsArgs or self:BuildArgs()
    return 'chat', {
        name = 'Chat',
        type = 'group',
        order = PANEL_ORDER,
        childGroups = 'tab',
        args = self.optionsArgs,
    }
end

function chat:RebuildOptions()
    self:ApplyBlockedList()
end

--#endregion
