-- Profile-backed phrases, a curated emote wheel, and destination selection.
local _, addon = ...
local chat = addon.Chat
local Input = addon.ChatInput
local function db() return addon.db.profile.chat end

local defaults = {
    'Hello!', 'Thanks!', "You're welcome!", 'Yes', 'No', 'Sorry!',
    'One moment, please.', 'Ready!', 'Be right back.', 'No problem.', 'Goodbye!',
    'Good Job!', "I'm using a controller, so typing is slow.",
}
local emotes = {
    { 'WAVE', 'Wave' }, { 'THANK', 'Thanks' }, { 'CHEER', 'Cheer' }, { 'LAUGH', 'Laugh' },
    { 'NOD', 'Nod' }, { 'NO', 'No' }, { 'APOLOGIZE', 'Apologize' }, { 'BYE', 'Goodbye' },
    { 'SALUTE', 'Salute' }, { 'FLIRT', 'Flirt' }, { 'DANCE', 'Dance' },
    -- Blizzard's joke action is exposed through /silly; keep both requested names.
    { 'JOKE', 'Silly', label = 'Silly' }, { 'JOKE', 'Joke', label = 'Joke' },
    { 'FACEPALM', 'Facepalm' },
}
local validatedReplies

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
    for slot = 1, 12 do
        local index = slot
        local button = self:ComposerButton(page, '', 272, 44, function()
            chat.composer.replyIndex = chat.composer.replyFirst + index - 1
            chat:InsertComposerReply()
        end)
        button.label:SetFont(addon.Media.ResolveFont(db().msgFontFace), 17, '')
        if button.label.SetMaxLines then button.label:SetMaxLines(2) end
        button:SetPoint('TOPLEFT', ((slot - 1) % 3) * 278, -math.floor((slot - 1) / 3) * 50)
        frame.replyButtons[slot] = button
    end
    frame.replyEmpty = page:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    frame.replyEmpty:SetPoint('CENTER')
    frame.replyEmpty:SetText('No quick replies. Add phrases in Chat settings.')
    local previous = self:ComposerButton(page, PREVIOUS or 'Previous', 120, 25,
        function() chat:MoveComposerReply(0, -4) end)
    previous:SetPoint('BOTTOMLEFT')
    local nextButton = self:ComposerButton(page, NEXT or 'Next', 120, 25,
        function() chat:MoveComposerReply(0, 4) end)
    nextButton:SetPoint('BOTTOMRIGHT')
    frame.replyCount = page:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    frame.replyCount:SetPoint('BOTTOM', 0, 5)
    self:RefreshComposerReplies()
end

function chat:RefreshComposerReplies()
    local frame = self.composer
    if not frame or not frame.replyButtons then return end
    local replies = self:GetQuickReplies()
    frame.replyIndex = math.max(1, math.min(#replies, frame.replyIndex))
    local row = math.floor((frame.replyIndex - 1) / 3)
    local firstRow = math.floor((frame.replyFirst - 1) / 3)
    if row < firstRow then firstRow = row
    elseif row >= firstRow + 4 then firstRow = row - 3 end
    frame.replyFirst = firstRow * 3 + 1
    for slot, button in ipairs(frame.replyButtons) do
        local index = frame.replyFirst + slot - 1
        button:SetShown(replies[index] ~= nil)
        button.label:SetText(replies[index] or '')
        self:HighlightComposerButton(button, index == frame.replyIndex)
    end
    frame.replyEmpty:SetShown(#replies == 0)
    frame.replyCount:SetText(#replies > 0 and (frame.replyIndex .. ' / ' .. #replies) or '')
end

function chat:MoveComposerReply(dx, dy)
    local frame, replies = self.composer, self:GetQuickReplies()
    local index = frame.replyIndex
    if dy ~= 0 then index = math.max(1, math.min(#replies, index + dy * 3))
    else
        local first = math.floor((index - 1) / 3) * 3 + 1
        local count = math.min(3, #replies - first + 1)
        if count > 0 then index = first + ((index - first + dx) % count) end
    end
    frame.replyIndex = index
    self:RefreshComposerReplies()
end

function chat:InsertComposerReply()
    local phrase = self:GetQuickReplies()[self.composer.replyIndex]
    if not phrase then return end
    Input:InsertPhrase(phrase)
    self:SetComposerTab(1)
end

local function emoteLabel(token, fallback)
    for i = 1, (MAXEMOTEINDEX or 0) do
        if _G['EMOTE' .. i .. '_TOKEN'] == token then
            return (_G['EMOTE' .. i .. '_CMD1'] or fallback):gsub('^/', '')
        end
    end
    return fallback
end

function chat:BuildComposerEmotes(page)
    local frame = self.composer
    -- PieMenu is ConsolePort's intrinsic visual template, not its secure ring
    -- header. We supply our own input and keep the same standalone behavior.
    if CPPieMenuMixin and CPFocusPoolMixin then
        local pie = CreateFrame('PieMenu', nil, page)
        pie:SetSize(220, 220)
        pie:SetPoint('CENTER')
        pie:EnableMouse(false)
        pie:Show()
        if pie.BG then pie.BG:SetVertexColor(0.35, 0.30, 0.20, 0.75) end
        frame.emotePie = pie
    end
    frame.emoteButtons = {}
    local step = math.pi * 2 / #emotes
    for i, spec in ipairs(emotes) do
        local index = i
        local label = spec.label or emoteLabel(spec[1], spec[2])
        local button = self:ComposerButton(page, label, 104, 28, function()
            chat.composer.emoteIndex = index
            chat:PerformComposerEmote()
        end)
        button.label:SetFont(addon.Media.ResolveFont(db().msgFontFace), 18, '')
        button.label:SetWordWrap(false)
        local angle = (i - 1) * step
        -- A wider wheel leaves room for all fourteen labels within the existing panel.
        button:SetPoint('CENTER', page, 'CENTER', math.sin(angle) * 330, math.cos(angle) * 98)
        frame.emoteButtons[i] = button
    end
    frame.emoteLabel = page:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    frame.emoteLabel:SetPoint('CENTER')
    frame.emoteLabel:SetWidth(190)
    frame.emoteLabel:SetText('Choose an emote\nA / Cross to perform')
end

function chat:RefreshComposerEmotes()
    local frame = self.composer
    if not frame or not frame.emoteButtons then return end
    for i, button in ipairs(frame.emoteButtons) do
        self:HighlightComposerButton(button, i == frame.emoteIndex)
    end
    local selected = frame.emoteIndex and frame.emoteButtons[frame.emoteIndex]
    frame.emoteLabel:SetText(selected and selected.label:GetText() or 'Choose an emote')
    if frame.emotePie and frame.emotePie.Arrow then
        if frame.emotePie.BG then
            frame.emotePie.BG:SetAlpha(1)
            frame.emotePie.BG:SetVertexColor(0.35, 0.30, 0.20, 0.75)
        end
        frame.emotePie.Arrow:SetAlpha(selected and 1 or 0)
        if selected then
            frame.emotePie.Arrow:SetRotation(-(frame.emoteIndex - 1) * math.pi * 2 / #frame.emoteButtons)
        end
    end
end

function chat:PerformComposerEmote()
    local spec = emotes[self.composer.emoteIndex or 0]
    if not spec then return end
    local perform = C_ChatInfo and C_ChatInfo.PerformEmote or DoEmote
    if not perform then self:SetComposerStatus('Emotes are unavailable on this client.'); return end
    local ok, success = pcall(perform, spec[1])
    if not ok then
        self:SetComposerStatus('Unable to perform this emote.')
        geterrorhandler()(success)
    elseif success == false then self:SetComposerStatus('This emote cannot be performed right now.')
    else self:CloseComposer() end
end

function chat:BuildComposerChannels()
    local frame = self.composer
    local panel = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
    panel:SetPoint('TOPLEFT', 16, -64)
    panel:SetSize(828, 272)
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
        local button = self:ComposerButton(panel, '', 796, 36, function()
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
