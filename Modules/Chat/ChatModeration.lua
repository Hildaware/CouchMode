--[[ ChatModeration.lua
Local moderation actions and the per-message context menu.

Blocking is enforced entirely by ChatRules against CouchModeDB; this file only
adapts those rules to user actions (the group context menu, the moderation
options fields) and the copy dialog. "Ignore" uses Blizzard's own friend list.
]]

local addonName, addon = ...

local chat = addon.Chat
local Sources = addon.ChatSources
local Rules = addon.ChatRules

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

local isSecret = addon.Utils.IsSecretValue

--#region ── Moderation actions ─────────────────────────────────────────────────

function chat:BlockName(name)
    if Rules.AddName(db().blocks, name) then
        self:Recompute()
        self:NotifyChange()
    end
end

function chat:BlockGuild(guild)
    if Rules.AddGuild(db().blocks, guild) then
        self:Recompute()
        self:NotifyChange()
    end
end

local function safeText(text)
    if isSecret(text) then return '' end
    return text or ''
end

function chat:ShowCopyDialog(text)
    if not self.copyDialog then
        local f = CreateFrame('Frame', 'CouchModeChatCopy', UIParent, 'BasicFrameTemplateWithInset')
        f:SetSize(440, 220)
        f:SetPoint('CENTER')
        f:SetFrameStrata('DIALOG')
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag('LeftButton')
        f:SetScript('OnDragStart', f.StartMoving)
        f:SetScript('OnDragStop', f.StopMovingOrSizing)
        f.TitleText:SetText('Copy Message')

        local eb = CreateFrame('EditBox', nil, f, 'InputBoxTemplate')
        eb:SetMultiLine(true)
        eb:SetSize(410, 165)
        eb:SetPoint('TOPLEFT', f, 'TOPLEFT', 14, -40)
        eb:SetAutoFocus(true)
        eb:SetScript('OnChar', function() end) -- read-only: block edits, allow selection
        eb:SetScript('OnEscapePressed', function() f:Hide() end)
        f.edit = eb
        self.copyDialog = f
    end
    self.copyDialog.edit:SetText(safeText(text))
    self.copyDialog.edit:HighlightText()
    self.copyDialog:Show()
end

---@param g Frame
function chat:ShowGroupMenu(g)
    local group = g.groupData
    if not group or not MenuUtil then return end
    local msg = group.messages[1]
    local name = msg.sender
    MenuUtil.CreateContextMenu(g, function(_, root)
        root:CreateTitle(name or Sources.FilterLabel(msg.category))
        root:CreateButton('Copy message', function() chat:ShowCopyDialog(msg.text) end)
        if name and msg.category ~= 'SYSTEM' then
            root:CreateButton('Whisper', function()
                if ChatFrameUtil and ChatFrameUtil.OpenChat then
                    ChatFrameUtil.OpenChat(SLASH_SMART_WHISPER1 .. ' ' .. name .. ' ')
                else
                    chat:FocusInput()
                end
            end)
            root:CreateButton('Block ' .. name, function() chat:BlockName(name) end)
            if C_FriendList and C_FriendList.AddIgnore then
                root:CreateButton('Ignore ' .. name, function() C_FriendList.AddIgnore(name) end)
            end
        end
        local guild = msg.guild or chat:ResolveGuild(msg, msg.unitToken)
        if guild then
            root:CreateButton('Block guild ' .. guild, function() chat:BlockGuild(guild) end)
        end
    end)
end

--#endregion
