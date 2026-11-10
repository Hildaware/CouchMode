-- All emotes on one surface, selected by a smoothed, center-relative pointer.
local _, addon = ...
local chat = addon.Chat
local function db() return addon.db.profile.chat end
local ICON_SHEET = 'Interface\\AddOns\\CouchMode\\Resources\\Media\\Emotes\\emote-icons-focused.tga'
local EXTRA_ICON_SHEET = 'Interface\\AddOns\\CouchMode\\Resources\\Media\\Emotes\\emote-icons-extra.tga'
local COLUMNS, COLUMN_GAP, ROW_GAP, LABEL_HEIGHT = 10, 4, 4, 22
local DEADZONE, SMOOTH_TIME = 0.16, 0.075
local emotes = {
    { 'WAVE', 'Wave' }, { 'THANK', 'Thanks' }, { 'CHEER', 'Cheer' }, { 'LAUGH', 'Laugh' },
    { 'NOD', 'Nod' }, { 'NO', 'No' }, { 'APOLOGIZE', 'Apologize' }, { 'BYE', 'Goodbye' },
    { 'SALUTE', 'Salute' }, { 'FLIRT', 'Flirt' }, { 'DANCE', 'Dance' },
    { 'JOKE', 'Silly', label = 'Silly' }, { 'JOKE', 'Joke', label = 'Joke' },
    { 'FACEPALM', 'Facepalm' },
    -- Companion atlas cells are zero-based, left to right, then top to bottom.
    { 'BOW', 'Bow', extraIcon = 0 }, { 'CLAP', 'Clap', extraIcon = 1 },
    { 'HUG', 'Hug', extraIcon = 2 }, { 'KISS', 'Kiss', extraIcon = 3 },
    { 'SHRUG', 'Shrug', extraIcon = 4 }, { 'CRY', 'Cry', extraIcon = 5 },
    { 'ROFL', 'ROFL', extraIcon = 6 }, { 'POINT', 'Point', extraIcon = 7 },
    { 'FLEX', 'Flex', extraIcon = 8 }, { 'CHICKEN', 'Chicken', extraIcon = 9 },
    { 'SLEEP', 'Sleep', extraIcon = 10 }, { 'SIT', 'Sit', extraIcon = 11 },
    { 'KNEEL', 'Kneel', extraIcon = 12 }, { 'SHY', 'Shy', extraIcon = 13 },
    { 'CONGRATULATE', 'Congratulations', extraIcon = 14 }, { 'TRAIN', 'Train', extraIcon = 15 },
}

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
    frame.emoteButtons = {}
    local surface = CreateFrame('Frame', nil, page)
    surface:SetPoint('TOPLEFT')
    surface:SetSize(page:GetWidth(), page:GetHeight() - LABEL_HEIGHT)
    frame.emoteSurface = surface
    local rows = math.ceil(#emotes / COLUMNS)
    local width = (surface:GetWidth() - (COLUMNS - 1) * COLUMN_GAP) / COLUMNS
    local height = (surface:GetHeight() - (rows - 1) * ROW_GAP) / rows
    for i, spec in ipairs(emotes) do
        local index = i
        local button = CreateFrame('Button', nil, surface, 'BackdropTemplate')
        button:SetSize(width, height)
        local x = ((i - 1) % COLUMNS) * (width + COLUMN_GAP)
        local y = math.floor((i - 1) / COLUMNS) * (height + ROW_GAP)
        button:SetPoint('TOPLEFT', x, -y)
        button.centerX, button.centerY = x + width / 2, y + height / 2
        button:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8',
            edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
        button.emoteName = spec.label or emoteLabel(spec[1], spec[2])
        button.icon = button:CreateTexture(nil, 'ARTWORK')
        local iconSize = math.min(50, width - 4, height - 4)
        button.icon:SetSize(iconSize, iconSize)
        button.icon:SetPoint('CENTER')
        button.icon:SetTexture(spec.extraIcon ~= nil and EXTRA_ICON_SHEET or ICON_SHEET)
        local cell = spec.extraIcon or (i - 1)
        local column, row = cell % 4, math.floor(cell / 4)
        local inset = 0.5 / 1024
        button.icon:SetTexCoord(column / 4 + inset, (column + 1) / 4 - inset,
            row / 4 + inset, (row + 1) / 4 - inset)
        button:SetScript('OnEnter', function()
            frame.emoteHover = index
            chat:RefreshComposerEmotes()
        end)
        button:SetScript('OnLeave', function()
            if frame.emoteHover == index then frame.emoteHover = nil end
            chat:RefreshComposerEmotes()
        end)
        button:RegisterForClicks('LeftButtonUp')
        button:SetScript('OnClick', function()
            if not chat.composerActive then chat:ResumeComposer() end
            frame.emotePointerActive, frame.emoteStickActive = false, false
            frame.leftReady = false
            frame.emoteIndex = index
            chat:PerformComposerEmote()
        end)
        frame.emoteButtons[i] = button
    end
    local bandOverlay = CreateFrame('Frame', nil, surface)
    bandOverlay:SetAllPoints()
    bandOverlay:SetFrameLevel(surface:GetFrameLevel() + 2)
    bandOverlay:EnableMouse(false)
    frame.emoteBand = bandOverlay:CreateLine(nil, 'OVERLAY')
    frame.emoteBand:SetThickness(1)
    frame.emoteBand:SetColorTexture(1, 0.78, 0.3, 0.45)
    frame.emoteBand:SetStartPoint('CENTER', surface, 0, 0)
    local origin = surface:CreateTexture(nil, 'OVERLAY')
    origin:SetSize(3, 3)
    origin:SetPoint('CENTER')
    origin:SetColorTexture(1, 0.78, 0.3, 0.5)
    local pointer = CreateFrame('Frame', nil, surface)
    pointer:SetSize(18, 18)
    pointer:SetFrameLevel(surface:GetFrameLevel() + 3)
    pointer:EnableMouse(false)
    for _, tick in ipairs({ { -6, 0, 5, 2 }, { 6, 0, 5, 2 },
        { 0, -6, 2, 5 }, { 0, 6, 2, 5 } }) do
        local outline = pointer:CreateTexture(nil, 'OVERLAY', nil, 0)
        outline:SetPoint('CENTER', tick[1], tick[2])
        outline:SetSize(tick[3] + 2, tick[4] + 2)
        outline:SetColorTexture(0, 0, 0, 1)
        local mark = pointer:CreateTexture(nil, 'OVERLAY', nil, 1)
        mark:SetPoint('CENTER', tick[1], tick[2])
        mark:SetSize(tick[3], tick[4])
        mark:SetColorTexture(1, 0.83, 0.35, 1)
    end
    frame.emotePointer = pointer
    frame.emoteLabel = page:CreateFontString(nil, 'OVERLAY')
    frame.emoteLabel:SetFont(addon.Media.ResolveFont(db().msgFontFace), 18, '')
    frame.emoteLabel:SetPoint('BOTTOMLEFT', 0, 0)
    frame.emoteLabel:SetPoint('BOTTOMRIGHT', 0, 0)
    frame.emoteLabel:SetHeight(18)
    frame.emoteLabel:SetTextColor(1, 0.83, 0.4)
    page:SetScript('OnHide', function() frame.emoteHover = nil end)
    self:ResetComposerEmotePointer()
end

function chat:DrawComposerEmotePointer()
    local frame = self.composer
    if not frame.emotePointer then return end
    local shown = frame.emotePointerActive and self.composerTab == 3
        and self.composerActive and not frame.channels:IsShown()
    frame.emotePointer:SetShown(shown)
    frame.emoteBand:SetShown(shown and (math.abs(frame.emotePointerX) + math.abs(frame.emotePointerY) > 0.001))
    if not shown then return end
    local buttons = frame.emoteButtons
    local halfWidth = (buttons[COLUMNS].centerX - buttons[1].centerX) / 2
    local halfHeight = (buttons[#buttons].centerY - buttons[1].centerY) / 2
    local x, y = frame.emotePointerX * halfWidth, frame.emotePointerY * halfHeight
    frame.emotePointer:ClearAllPoints()
    frame.emotePointer:SetPoint('CENTER', frame.emoteSurface, 'CENTER', x, y)
    frame.emotePointer:SetAlpha(frame.emoteStickActive and 1 or 0.5)
    frame.emoteBand:SetEndPoint('CENTER', frame.emoteSurface, x, y)
end

function chat:RefreshComposerEmotes()
    local frame = self.composer
    if not frame or not frame.emoteButtons then return end
    for i, button in ipairs(frame.emoteButtons) do
        if i == frame.emoteIndex or i == frame.emoteHover then
            button:SetBackdropColor(0.22, 0.16, 0.07, 0.96)
            button:SetBackdropBorderColor(1, 0.78, 0.3, 1)
        else
            button:SetBackdropColor(0.045, 0.05, 0.06, 0.88)
            button:SetBackdropBorderColor(0.4, 0.33, 0.2, 0.7)
        end
    end
    local selected = frame.emoteIndex or frame.emoteHover
    frame.emoteLabel:SetText(selected and frame.emoteButtons[selected].emoteName or 'Choose an emote')
    self:DrawComposerEmotePointer()
end

function chat:ResetComposerEmotePointer()
    local frame = self.composer
    frame.emotePointerX, frame.emotePointerY = 0, 0
    frame.emoteAimX, frame.emoteAimY = 0, 0
    frame.emotePointerActive, frame.emoteStickActive = true, false
    frame.emoteIndex, frame.emoteHover = nil, nil
    self:RefreshComposerEmotes()
end

function chat:MoveComposerEmote(dx, dy)
    local frame = self.composer
    frame.emotePointerActive, frame.emoteStickActive = false, false
    frame.leftReady = false
    local index = frame.emoteIndex or 1
    if frame.emoteIndex then
        if dy ~= 0 then
            local row = math.floor((index - 1) / COLUMNS)
            local column = (index - 1) % COLUMNS
            row = math.max(0, math.min(math.ceil(#emotes / COLUMNS) - 1, row + dy))
            index = math.min(#emotes, row * COLUMNS + column + 1)
        else
            local first = math.floor((index - 1) / COLUMNS) * COLUMNS + 1
            local count = math.min(COLUMNS, #emotes - first + 1)
            index = first + ((index - first + dx) % count)
        end
    end
    frame.emoteIndex, frame.emoteHover = index, nil
    self:RefreshComposerEmotes()
end

function chat:ComposerEmoteStick(x, y)
    local frame = self.composer
    local length = math.sqrt(x * x + y * y)
    if length < DEADZONE then
        frame.leftReady = true
        if frame.emoteStickActive then
            frame.emoteAimX, frame.emoteAimY = 0, 0
            frame.emoteStickActive = false
            frame.emoteIndex = nil
            self:RefreshComposerEmotes()
        end
        return
    end
    if not frame.leftReady then return end
    if not frame.emotePointerActive then
        frame.emotePointerX, frame.emotePointerY = 0, 0
    end
    local magnitude = math.min(1, (length - DEADZONE) / (1 - DEADZONE))
    local scale = magnitude / math.max(math.abs(x), math.abs(y))
    frame.emotePointerActive, frame.emoteStickActive = true, true
    frame.emoteAimX, frame.emoteAimY = x * scale, y * scale
    frame.emoteHover = nil
end

function chat:UpdateComposerEmotePointer(elapsed)
    local frame = self.composer
    if self.composerTab ~= 3 or frame.channels:IsShown() or not frame.emotePointerActive then
        self:DrawComposerEmotePointer()
        return
    end
    local blend = 1 - math.exp(-elapsed / SMOOTH_TIME)
    local x = frame.emotePointerX + (frame.emoteAimX - frame.emotePointerX) * blend
    local y = frame.emotePointerY + (frame.emoteAimY - frame.emotePointerY) * blend
    if math.abs(x - frame.emoteAimX) < 0.001 then x = frame.emoteAimX end
    if math.abs(y - frame.emoteAimY) < 0.001 then y = frame.emoteAimY end
    frame.emotePointerX, frame.emotePointerY = x, y
    local previous = frame.emoteIndex
    if frame.emoteStickActive then
        local rows = math.ceil(#emotes / COLUMNS)
        local row = math.max(0, math.min(rows - 1, math.floor((1 - y) * (rows - 1) / 2 + 0.5)))
        local column = math.max(0, math.min(COLUMNS - 1, math.floor((x + 1) * (COLUMNS - 1) / 2 + 0.5)))
        frame.emoteIndex = math.min(#emotes, row * COLUMNS + column + 1)
    else frame.emoteIndex = nil end
    if previous ~= frame.emoteIndex then self:RefreshComposerEmotes()
    else self:DrawComposerEmotePointer() end
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
