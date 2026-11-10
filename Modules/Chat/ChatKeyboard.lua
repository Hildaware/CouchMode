-- QWERTY layout and free pointer navigation. All buttons are allocated before combat.
local _, addon = ...
local chat = addon.Chat
local TAB = chat.COMPOSER_TABS
local Input = addon.ChatInput
local KEY_WIDTH, KEY_HEIGHT, COLUMN_GAP, ROW_GAP = 60, 36, 2, 0

local letters = {
    { '1','2','3','4','5','6','7','8','9','0' },
    { 'q','w','e','r','t','y','u','i','o','p' },
    { 'a','s','d','f','g','h','j','k','l' },
    { 'z','x','c','v','b','n','m',',','.','/' },
}
chat.COMPOSER_KEYBOARD_HEIGHT = #letters * KEY_HEIGHT + (#letters - 1) * ROW_GAP
chat.COMPOSER_KEYBOARD_WIDTH = #letters[1] * KEY_WIDTH + (#letters[1] - 1) * COLUMN_GAP
local symbols = {
    { '!','@','#','$','%','^','&','*','(',')' },
    { '-','_','=','+','[',']','{','}','\\','|' },
    { ';',':',"'",'"',',','.','<','>','/','?' },
    { '`','~','€','£','¥','©','®','°','×','÷' },
}
local shifted = { ['1']='!', ['2']='@', ['3']='#', ['4']='$', ['5']='%',
    ['6']='^', ['7']='&', ['8']='*', ['9']='(', ['0']=')', [',']='<', ['.']='>', ['/']='?' }

function chat:BuildComposerKeyboard(page)
    self.composer.keyboardRows = {}
    self.composer.keyRow, self.composer.keyColumn = 3, 5
    for row = 1, #letters do
        local entries = {}
        self.composer.keyboardRows[row] = entries
        for column = 1, 10 do
            local r, c = row, column
            local button = self:ComposerButton(page, '', KEY_WIDTH, KEY_HEIGHT, function()
                chat.composer.keyboardPointerActive = false
                chat.composer.keyboardStickActive = false
                chat.composer.leftReady = false
                chat.composer.keyRow, chat.composer.keyColumn = r, c
                chat:PressComposerKey()
            end)
            -- Center the line optically within the beveled face. Keep a shared
            -- baseline so descenders remain natural instead of shifting per key.
            button.label:ClearAllPoints()
            button.label:SetPoint('TOPLEFT', button, 'TOPLEFT', 5, -1)
            button.label:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', -5, 5)
            entries[column] = button
        end
    end
    -- Keep the center open so the reticle does not cover the character being
    -- aimed at. The dark outline remains visible over both keys and gaps.
    local pointer = CreateFrame('Frame', nil, page)
    pointer:SetSize(24, 24)
    pointer:SetFrameLevel(page:GetFrameLevel() + 2)
    pointer:EnableMouse(false)
    for _, tick in ipairs({ { -9, 0, 6, 2 }, { 9, 0, 6, 2 },
        { 0, -9, 2, 6 }, { 0, 9, 2, 6 } }) do
        local outline = pointer:CreateTexture(nil, 'OVERLAY', nil, 0)
        outline:SetPoint('CENTER', tick[1], tick[2])
        outline:SetSize(tick[3] + 2, tick[4] + 2)
        outline:SetColorTexture(0, 0, 0, 0.95)
        local mark = pointer:CreateTexture(nil, 'OVERLAY', nil, 1)
        mark:SetPoint('CENTER', tick[1], tick[2])
        mark:SetSize(tick[3], tick[4])
        mark:SetColorTexture(1, 0.85, 0.3, 1)
    end
    pointer:Hide()
    self.composer.keyboardPointer = pointer
    self:RefreshComposerKeyboard()
end

function chat:RefreshComposerKeyboard()
    local frame = self.composer
    if not frame then return end
    local layout = frame.symbols and symbols or letters
    for row, entries in ipairs(frame.keyboardRows) do
        local x = (frame.pages[TAB.KEYBOARD]:GetWidth() - (#layout[row] * (KEY_WIDTH + COLUMN_GAP) - COLUMN_GAP)) / 2
        for column, button in ipairs(entries) do
            local text = layout[row][column]
            button:SetShown(text ~= nil)
            if text then
                button:ClearAllPoints()
                button:SetPoint('TOPLEFT', x, -(row - 1) * (KEY_HEIGHT + ROW_GAP))
                button.centerX = x + KEY_WIDTH / 2
                if text:match('^[a-z]$') then
                    if (frame.caps == true) ~= (frame.shift == true) then text = text:upper() end
                elseif frame.shift then text = shifted[text] or text end
                button.text = text
                button.label:SetText(text)
                x = x + KEY_WIDTH + COLUMN_GAP
            end
        end
    end
    if frame.keyboardPointerActive then
        self:SelectComposerKeyAtPointer()
    else
        frame.keyColumn = math.min(frame.keyColumn, #layout[frame.keyRow])
    end
    self:HighlightComposerKeyboardSelection()
    self:UpdateComposerKeyboardPointer()
end

function chat:HighlightComposerKeyboardSelection()
    local frame = self.composer
    for row, entries in ipairs(frame.keyboardRows) do
        for column, button in ipairs(entries) do
            self:HighlightComposerButton(button, row == frame.keyRow and column == frame.keyColumn)
        end
    end
end

function chat:SelectComposerKeyAtPointer()
    local frame = self.composer
    local x, y = frame.keyboardPointerX or 0, frame.keyboardPointerY or 0
    local rowCount = #frame.keyboardRows
    local row = math.max(1, math.min(rowCount, math.floor((1 - y) * (rowCount - 1) / 2 + 1.5)))
    local entries = frame.keyboardRows[row]
    local count = #(frame.symbols and symbols[row] or letters[row])
    -- All rows share one coordinate surface. Crossing into the staggered row
    -- must not change horizontal aim or move the pointer sideways.
    local top = frame.keyboardRows[1]
    local targetX = top[1].centerX + (x + 1) / 2 * (top[10].centerX - top[1].centerX)
    local distance, nearest = math.huge, 1
    for column = 1, count do
        local delta = math.abs(entries[column].centerX - targetX)
        if delta < distance then
            distance, nearest = delta, column
        end
    end
    frame.keyRow, frame.keyColumn = row, nearest
end

function chat:GetComposerKeyboardPointerSpan()
    local top = self.composer.keyboardRows[1]
    return top[10].centerX - top[1].centerX, (#self.composer.keyboardRows - 1) * (KEY_HEIGHT + ROW_GAP)
end

function chat:PositionComposerPointerOnSelection()
    local frame = self.composer
    local button = frame.keyboardRows[frame.keyRow][frame.keyColumn]
    local width = self:GetComposerKeyboardPointerSpan()
    local x = (button.centerX - frame.keyboardRows[1][1].centerX) * 2 / width - 1
    local y = 1 - (frame.keyRow - 1) * 2 / (#frame.keyboardRows - 1)
    self:SetComposerKeyboardPointer(math.max(-1, math.min(1, x)), y)
end

function chat:UpdateComposerKeyboardPointer()
    local frame = self.composer
    local pointer = frame.keyboardPointer
    if not pointer then return end
    local shown = self.composerActive and frame.keyboardPointerActive
        and self.composerTab == TAB.KEYBOARD and not frame.channels:IsShown()
    pointer:SetShown(shown)
    if not shown then return end
    local top = frame.keyboardRows[1]
    local x = top[1].centerX + ((frame.keyboardPointerX or 0) + 1) / 2
        * (top[10].centerX - top[1].centerX)
    local _, height = self:GetComposerKeyboardPointerSpan()
    local y = KEY_HEIGHT / 2 + (1 - (frame.keyboardPointerY or 0)) * height / 2
    if pointer.positionX ~= x or pointer.positionY ~= y then
        pointer:ClearAllPoints()
        pointer:SetPoint('CENTER', frame.pages[TAB.KEYBOARD], 'TOPLEFT', x, -y)
        pointer.positionX, pointer.positionY = x, y
    end
end

function chat:SetComposerKeyboardPointer(x, y)
    local frame = self.composer
    local previousRow, previousColumn = frame.keyRow, frame.keyColumn
    frame.keyboardPointerActive = true
    frame.keyboardPointerX, frame.keyboardPointerY = x, y
    self:SelectComposerKeyAtPointer()
    if frame.keyRow ~= previousRow or frame.keyColumn ~= previousColumn then
        self:HighlightComposerKeyboardSelection()
    end
    self:UpdateComposerKeyboardPointer()
end

function chat:MoveComposerKey(dx, dy)
    local frame = self.composer
    -- D-pad navigation takes over until the stick is centered and moved again.
    frame.keyboardPointerActive, frame.keyboardStickActive = false, false
    frame.leftReady = false
    local rows = frame.keyboardRows
    local current = rows[frame.keyRow][frame.keyColumn]
    if dy ~= 0 then
        frame.keyRow = math.max(1, math.min(#rows, frame.keyRow + dy))
        local distance, nearest = math.huge, 1
        for column, button in ipairs(rows[frame.keyRow]) do
            if button:IsShown() then
                local delta = math.abs(button.centerX - current.centerX)
                if delta < distance then distance, nearest = delta, column end
            end
        end
        frame.keyColumn = nearest
    else
        local count = 0
        for _, button in ipairs(rows[frame.keyRow]) do
            if button:IsShown() then count = count + 1 end
        end
        frame.keyColumn = ((frame.keyColumn - 1 + dx) % count) + 1
    end
    self:RefreshComposerKeyboard()
end

function chat:PressComposerKey()
    local frame = self.composer
    local button = frame.keyboardRows[frame.keyRow][frame.keyColumn]
    if not button or not button:IsShown() then return end
    if button.text then Input:InsertText(button.text) end
    self:RefreshComposerKeyboard()
end
