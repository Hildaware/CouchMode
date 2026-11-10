-- Quick-reply editing uses the existing AceConfig settings interface.
local _, addon = ...
local chat = addon.Chat
local function db() return addon.db.profile.chat end
chat.quickReplyOptionIndex = 1

local function validate(_, value)
    if not value:match('%S') then return 'Enter a phrase.' end
    if value:match('^%s*/') or value:find('[\r\n]') then return 'Use a single line of plain text, not a slash command.' end
    if #value > 255 then return 'This phrase is too long for a chat message.' end
    return true
end

function chat:QuickRepliesChanged()
    local replies = self:GetQuickReplies()
    self.quickReplyOptionIndex = math.max(1, math.min(#replies, self.quickReplyOptionIndex))
    if self.composer then self:RefreshComposerReplies() end
    self:NotifyChange()
end

function chat:BuildQuickRepliesOptions()
    local function selected() return chat:GetQuickReplies()[chat.quickReplyOptionIndex] end
    return {
        name = 'Quick Replies', type = 'group', order = 35,
        args = {
            description = { type = 'description', order = 0,
                name = 'Open Chat Composer through Key Bindings, or use the button below. Selecting a phrase inserts it into your draft; Send remains a separate action.' },
            open = { type = 'execute', name = 'Open Chat Composer', order = 1,
                func = function() chat:OpenComposer() end },
            selected = {
                type = 'select', name = 'Phrase', order = 2, width = 'full',
                values = function()
                    local values = {}
                    for i, text in ipairs(chat:GetQuickReplies()) do values[tostring(i)] = i .. '. ' .. text end
                    return values
                end,
                sorting = function()
                    local keys = {}
                    for i in ipairs(chat:GetQuickReplies()) do keys[i] = tostring(i) end
                    return keys
                end,
                get = function() return tostring(chat.quickReplyOptionIndex) end,
                set = function(_, value) chat.quickReplyOptionIndex = tonumber(value) or 1 end,
                disabled = function() return #chat:GetQuickReplies() == 0 end,
            },
            edit = {
                type = 'input', name = 'Edit Phrase', order = 3, width = 'full', validate = validate,
                get = function() return selected() or '' end,
                set = function(_, value)
                    chat:GetQuickReplies()[chat.quickReplyOptionIndex] = value
                    chat:QuickRepliesChanged()
                end,
                disabled = function() return not selected() end,
            },
            up = {
                type = 'execute', name = 'Move Up', order = 4,
                disabled = function() return chat.quickReplyOptionIndex <= 1 end,
                func = function()
                    local list, i = chat:GetQuickReplies(), chat.quickReplyOptionIndex
                    list[i], list[i - 1] = list[i - 1], list[i]
                    chat.quickReplyOptionIndex = i - 1
                    chat:QuickRepliesChanged()
                end,
            },
            down = {
                type = 'execute', name = 'Move Down', order = 5,
                disabled = function() return chat.quickReplyOptionIndex >= #chat:GetQuickReplies() end,
                func = function()
                    local list, i = chat:GetQuickReplies(), chat.quickReplyOptionIndex
                    list[i], list[i + 1] = list[i + 1], list[i]
                    chat.quickReplyOptionIndex = i + 1
                    chat:QuickRepliesChanged()
                end,
            },
            delete = {
                type = 'execute', name = DELETE or 'Delete', order = 6,
                disabled = function() return not selected() end,
                func = function()
                    table.remove(chat:GetQuickReplies(), chat.quickReplyOptionIndex)
                    chat:QuickRepliesChanged()
                end,
            },
            add = {
                type = 'input', name = 'Add Phrase', order = 7, width = 'full', validate = validate,
                get = function() return '' end,
                set = function(_, value)
                    local list = chat:GetQuickReplies()
                    list[#list + 1] = value
                    chat.quickReplyOptionIndex = #list
                    chat:QuickRepliesChanged()
                end,
            },
            reset = {
                type = 'execute', name = 'Restore Default Phrases', order = 8,
                confirm = true,
                func = function()
                    db().quickReplies = chat:DefaultQuickReplies()
                    chat.quickReplyOptionIndex = 1
                    chat:QuickRepliesChanged()
                end,
            },
        },
    }
end
