-- Profile-backed shortcut phrases and destination selection.
local _, addon = ...
local chat = addon.Chat
local TAB = chat.COMPOSER_TABS
local Input = addon.ChatInput
local function db() return addon.db.profile.chat end

local defaults = {
    'Hello!', 'Thanks!', "You're welcome!", 'Yes', 'No', 'Sorry!',
    'One moment, please.', 'Ready!', 'Be right back.', 'No problem.', 'Goodbye!',
    'Good Job!', "I'm using a controller, so typing is slow.",
}
local validatedReplies
local REPLY_COLUMNS, REPLIES_PER_PAGE = 3, 9

local function styleShortcut(button)
    local enabled = button:IsEnabled()
    local selected = enabled and button.composerSelected
    if selected then
        button:SetBackdropColor(0.20, 0.16, 0.08, 0.96)
        button:SetBackdropBorderColor(0.75, 0.59, 0.28, 0.9)
    elseif enabled and button.shortcutHovered then
        button:SetBackdropColor(0.13, 0.14, 0.17, 0.96)
        button:SetBackdropBorderColor(0.48, 0.46, 0.39, 0.8)
    else
        button:SetBackdropColor(0.065, 0.075, 0.095, 0.92)
        button:SetBackdropBorderColor(0.28, 0.29, 0.31, 0.65)
    end
    button.selectionMark:SetShown(selected)
    if not enabled then button.label:SetTextColor(DISABLED_FONT_COLOR:GetRGB())
    elseif selected then button.label:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    else button.label:SetTextColor(0.87, 0.84, 0.76) end
end

local function shortcutButton(parent, width, height, action)
    local button = CreateFrame('Button', nil, parent, 'BackdropTemplate')
    button:SetSize(width, height)
    button:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8',
        edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
    button.selectionMark = button:CreateTexture(nil, 'OVERLAY')
    button.selectionMark:SetColorTexture(1, 0.78, 0.3, 1)
    button.selectionMark:SetPoint('TOPLEFT', 2, -3)
    button.selectionMark:SetPoint('BOTTOMLEFT', 2, 3)
    button.selectionMark:SetWidth(2)
    button.label = button:CreateFontString(nil, 'ARTWORK')
    button.label:SetFont(addon.Media.ResolveFont(db().msgFontFace), 17, '')
    button.label:SetPoint('TOPLEFT', 10, -3)
    button.label:SetPoint('BOTTOMRIGHT', -8, 3)
    button.label:SetJustifyH('LEFT')
    button.label:SetJustifyV('MIDDLE')
    if button.label.SetMaxLines then button.label:SetMaxLines(2) end
    button:RegisterForClicks('LeftButtonUp')
    button:SetScript('OnClick', function()
        if not chat.composerActive then chat:ResumeComposer() end
        action()
    end)
    button:SetScript('OnEnter', function(self) self.shortcutHovered = true; styleShortcut(self) end)
    button:SetScript('OnLeave', function(self) self.shortcutHovered = false; styleShortcut(self) end)
    button:SetScript('OnHide', function(self) self.shortcutHovered = false end)
    button:SetScript('OnShow', styleShortcut)
    button:SetScript('OnEnable', styleShortcut)
    button:SetScript('OnDisable', styleShortcut)
    styleShortcut(button)
    return button
end

function chat:DefaultQuickReplies()
    local result = {}
    for i, text in ipairs(defaults) do result[i] = text end
    return result
end

function chat:GetQuickReplies()
    -- False is the AceDB default; an explicitly empty table must stay empty.
    if type(db().quickReplies) ~= 'table' then db().quickReplies = self:DefaultQuickReplies() end
    local replies = db().quickReplies
    if validatedReplies ~= replies then
        for i = #replies, 1, -1 do
            local text = replies[i]
            if type(text) ~= 'string' or not text:match('%S') or text:match('^%s*/')
                or text:find('[\r\n]') or #text > 255 then table.remove(replies, i) end
        end
        validatedReplies = replies
    end
    return replies
end

function chat:BuildComposerReplies(page)
    local frame = self.composer
    frame.replyIndex, frame.replyFirst = 1, 1
    frame.replyButtons = {}
    local columnGap = 6
    local rowGap = 4
    local buttonWidth = (page:GetWidth() - (REPLY_COLUMNS - 1) * columnGap) / REPLY_COLUMNS
    local buttonHeight = (page:GetHeight() - 2 * rowGap) / 3
    for slot = 1, REPLIES_PER_PAGE do
        local index = slot
        local button = shortcutButton(page, buttonWidth, buttonHeight, function()
            chat.composer.replyIndex = chat.composer.replyFirst + index - 1
            chat:InsertComposerReply()
        end)
        button:SetPoint('TOPLEFT', ((slot - 1) % REPLY_COLUMNS) * (buttonWidth + columnGap),
            -math.floor((slot - 1) / REPLY_COLUMNS) * (buttonHeight + rowGap))
        frame.replyButtons[slot] = button
    end
    frame.replyEmpty = page:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    frame.replyEmpty:SetPoint('CENTER')
    frame.replyEmpty:SetText('No shortcuts. Add phrases in Chat settings.')
    frame.replyCount = frame.footer:CreateFontString(nil, 'ARTWORK')
    frame.replyCount:SetFont(addon.Media.ResolveFont(db().msgFontFace), 14, '')
    frame.replyCount:SetTextColor(0.75, 0.72, 0.65)
    frame.replyCount:SetPoint('TOPRIGHT')
    frame.replyCount:SetPoint('BOTTOMRIGHT')
    frame.replyCount:SetWidth(100)
    frame.replyCount:SetJustifyH('RIGHT')
    frame.replyCount:SetWordWrap(false)
    page:EnableMouseWheel(true)
    page:SetScript('OnMouseWheel', function(_, delta) chat:PageComposerReplies(delta > 0 and -1 or 1) end)
    self:RefreshComposerReplies()
end

function chat:RefreshComposerReplies()
    local frame = self.composer
    if not frame or not frame.replyButtons then return end
    local replies = self:GetQuickReplies()
    frame.replyIndex = math.max(1, math.min(#replies, frame.replyIndex))
    local pageIndex = math.floor((frame.replyIndex - 1) / REPLIES_PER_PAGE)
    local pageCount = math.ceil(#replies / REPLIES_PER_PAGE)
    frame.replyFirst = pageIndex * REPLIES_PER_PAGE + 1
    for slot, button in ipairs(frame.replyButtons) do
        local index = frame.replyFirst + slot - 1
        button:SetShown(replies[index] ~= nil)
        button.label:SetText(replies[index] or '')
        button.composerSelected = index == frame.replyIndex
        styleShortcut(button)
    end
    frame.replyEmpty:SetShown(#replies == 0)
    frame.replyCount:SetText(pageCount > 0 and ('Page ' .. (pageIndex + 1) .. ' / ' .. pageCount) or '')
    frame.replyCount:SetShown(self.composerTab == TAB.SHORTCUTS and pageCount > 0)
end

function chat:PageComposerReplies(direction)
    local frame, replies = self.composer, self:GetQuickReplies()
    if #replies == 0 then return end
    local pageIndex = math.floor((frame.replyIndex - 1) / REPLIES_PER_PAGE)
    local target = (pageIndex + direction) % math.ceil(#replies / REPLIES_PER_PAGE)
    local slot = (frame.replyIndex - 1) % REPLIES_PER_PAGE
    frame.replyIndex = math.min(#replies, target * REPLIES_PER_PAGE + slot + 1)
    self:RefreshComposerReplies()
end

function chat:MoveComposerReply(dx, dy)
    local frame, replies = self.composer, self:GetQuickReplies()
    if #replies == 0 then return end
    local index = frame.replyIndex
    if dy ~= 0 then
        local rowCount = math.ceil(#replies / REPLY_COLUMNS)
        local row = (math.floor((index - 1) / REPLY_COLUMNS) + dy) % rowCount
        local column = (index - 1) % REPLY_COLUMNS
        index = math.min(#replies, row * REPLY_COLUMNS + column + 1)
    else
        local first = math.floor((index - 1) / REPLY_COLUMNS) * REPLY_COLUMNS + 1
        local count = math.min(REPLY_COLUMNS, #replies - first + 1)
        if count > 0 then index = first + ((index - first + dx) % count) end
    end
    frame.replyIndex = index
    self:RefreshComposerReplies()
end

function chat:InsertComposerReply()
    local phrase = self:GetQuickReplies()[self.composer.replyIndex]
    if not phrase then return end
    Input:InsertPhrase(phrase)
    self:SetComposerTab(TAB.KEYBOARD)
end

function chat:BuildComposerChannels()
    local frame = self.composer
    local panel = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
    panel:SetPoint('BOTTOMLEFT', frame.footer, 'TOPLEFT', 0, 8)
    panel:SetSize(frame.pages[TAB.KEYBOARD]:GetWidth(), 272)
    panel:SetFrameLevel(frame:GetFrameLevel() + 5)
    panel:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8',
        edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
    panel:SetBackdropColor(0.035, 0.045, 0.065, 1)
    panel:SetBackdropBorderColor(0.65, 0.54, 0.32, 1)
    panel:EnableMouse(true)
    panel:Hide()
    frame.channels = panel
    frame.channelButtons = {}
    frame.channelIndex, frame.channelFirst = 1, 1
    for slot = 1, 6 do
        local index = slot
        local button = self:ComposerButton(panel, '', panel:GetWidth() - 32, 36, function()
            chat.composer.channelIndex = chat.composer.channelFirst + index - 1
            chat:ChooseComposerChannel()
        end)
        button:SetPoint('TOPLEFT', 16, -12 - (slot - 1) * 42)
        frame.channelButtons[slot] = button
    end
    panel:SetScript('OnMouseWheel', function(_, delta) chat:MoveComposerSelection(0, -delta) end)
    panel:EnableMouseWheel(true)
end

function chat:ToggleComposerChannels()
    if self.composerTab == TAB.EMOTES then return end
    local frame = self.composer
    if frame.channels:IsShown() then frame.channels:Hide(); return end
    self:ResetComposerHeldInput(true)
    frame.destinations = Input:GetDestinations()
    frame.channelIndex, frame.channelFirst = 1, 1
    self:RefreshComposerChannels()
    frame.channels:Show()
end

function chat:RefreshComposerChannels()
    local frame = self.composer
    if frame.channelIndex < frame.channelFirst then frame.channelFirst = frame.channelIndex end
    if frame.channelIndex >= frame.channelFirst + 6 then frame.channelFirst = frame.channelIndex - 5 end
    for slot, button in ipairs(frame.channelButtons) do
        local index = frame.channelFirst + slot - 1
        local entry = frame.destinations[index]
        button:SetShown(entry ~= nil)
        button.label:SetText(entry and entry.label or '')
        self:HighlightComposerButton(button, index == frame.channelIndex)
    end
end

function chat:ChooseComposerChannel()
    local entry = self.composer.destinations[self.composer.channelIndex]
    if not entry then return end
    -- Recheck availability; group/channel membership can change while choosing.
    local available = false
    for _, current in ipairs(Input:GetDestinations()) do
        if current.chatType == entry.chatType and current.target == entry.target and current.channel == entry.channel then
            available = true; break
        end
    end
    if not available then self:SetComposerStatus('That destination is no longer available.'); return end
    Input:SelectDestination(entry)
    self.composer.channels:Hide()
    self:SetComposerStatus('')
end
