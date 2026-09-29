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

function chat:CopyMessage(text)
    text = safeText(text)
    if type(CopyToClipboard) == 'function' and text ~= '' then
        local ok, length = pcall(CopyToClipboard, text, true)
        if ok and type(length) == 'number' and length > 0 then
            self:SetHistoryStatus('Message copied')
            return
        end
    end
    self:ShowCopyDialog(text)
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
        f:SetScript('OnHide', function() chat:HistoryCopyDialogClosed() end)
        if f.EnableGamePadButton then
            f:EnableGamePadButton(true)
            f:SetScript('OnGamePadButtonDown', function(_, key)
                if key == 'PAD2' then f:Hide() end
            end)
        end

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
    if self:IsHistoryModeOpen() then
        self.copyDialog:SetFrameStrata('TOOLTIP')
        self:HistoryCopyDialogOpened()
    else
        self.copyDialog:SetFrameStrata('DIALOG')
    end
    self.copyDialog:Show()
end

--- Builds actions from the selected message, so mouse and controller menus
--- enforce the same moderation rules.
---@param msg ChatMessage
---@param includeLinks boolean?
---@return table[]
function chat:BuildMessageActions(msg, includeLinks)
    local actions = {}
    local function add(label, run)
        actions[#actions + 1] = { label = label, run = run }
    end

    if includeLinks and Sources.isSafe(msg.text) and type(msg.text) == 'string' then
        for link, label in msg.text:gmatch('|H([^|]+)|h(.-)|h') do
            local linkData, display = link, label
            add('Open ' .. (display ~= '' and display or linkData), function()
                if chat:IsHistoryModeOpen() then chat:CloseHistoryMode() end
                if SetItemRef then SetItemRef(linkData, display, 'LeftButton', chat.panel) end
            end)
        end
    end

    add('Copy message', function()
        if includeLinks then chat:CopyMessage(msg.text) else chat:ShowCopyDialog(msg.text) end
    end)

    local name = Sources.isSafe(msg.sender) and msg.sender or nil
    if type(name) == 'string' and name ~= '' and msg.category ~= 'SYSTEM' then
        add('Whisper ' .. name, function()
            if chat:IsHistoryModeOpen() then chat:CloseHistoryMode() end
            if ChatFrameUtil and ChatFrameUtil.OpenChat then
                ChatFrameUtil.OpenChat(SLASH_SMART_WHISPER1 .. ' ' .. name .. ' ')
            else
                chat:FocusInput()
            end
        end)
        add('Block ' .. name, function() chat:BlockName(name) end)
        if C_FriendList and C_FriendList.AddIgnore then
            add('Ignore ' .. name, function() C_FriendList.AddIgnore(name) end)
        end
    end
    local guild = msg.guild or chat:ResolveGuild(msg, msg.unitToken)
    if Sources.isSafe(guild) and type(guild) == 'string' and guild ~= '' then
        add('Block guild ' .. guild, function() chat:BlockGuild(guild) end)
    end
    return actions
end

---@param g Frame
function chat:ShowGroupMenu(g)
    local group = g.groupData
    if not group or not MenuUtil then return end
    local msg = group.messages[1]
    local name = Sources.isSafe(msg.sender) and msg.sender or nil
    MenuUtil.CreateContextMenu(g, function(_, root)
        root:CreateTitle(name or Sources.FilterLabel(msg.category))
        for _, action in ipairs(chat:BuildMessageActions(msg, false)) do
            root:CreateButton(action.label, action.run)
        end
    end)
end

--#endregion
