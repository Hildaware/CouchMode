-- QWERTY layout and spatial navigation. All buttons are allocated before combat.
local _, addon = ...
local chat = addon.Chat
local Input = addon.ChatInput
local KEY_HEIGHT, ROW_GAP = 40, 2
chat.COMPOSER_KEYBOARD_HEIGHT = 5 * KEY_HEIGHT + 4 * ROW_GAP

local letters = {
    { '1','2','3','4','5','6','7','8','9','0' },
    { 'q','w','e','r','t','y','u','i','o','p' },
    { 'a','s','d','f','g','h','j','k','l' },
    { 'z','x','c','v','b','n','m',',','.','/' },
}
local symbols = {
    { '!','@','#','$','%','^','&','*','(',')' },
    { '-','_','=','+','[',']','{','}','\\','|' },
    { ';',':',"'",'"',',','.','<','>','/','?' },
    { '`','~','€','£','¥','©','®','°','×','÷' },
}
local shifted = { ['1']='!', ['2']='@', ['3']='#', ['4']='$', ['5']='%',
    ['6']='^', ['7']='&', ['8']='*', ['9']='(', ['0']=')', [',']='<', ['.']='>', ['/']='?' }
local controls = {
    { label = 'Symbols', action = 'symbols', width = 110 },
    { label = 'Caps', action = 'caps', width = 80 },
    { label = SPACE or 'Space', action = 'space', width = 260 },
    { label = "'", text = "'", width = 60 },
    { label = '@', text = '@', width = 60 },
    { label = BACKSPACE or 'Delete', action = 'delete', width = 110 },
    { label = 'Send', action = 'send', width = 100 },
}

function chat:BuildComposerKeyboard(page)
    self.composer.keyboardRows = {}
    self.composer.keyRow, self.composer.keyColumn = 3, 5
    for row = 1, 5 do
        local entries = {}
        self.composer.keyboardRows[row] = entries
        for column = 1, (row == 5 and #controls or 10) do
            local r, c = row, column
            local button = self:ComposerButton(page, '', 76, KEY_HEIGHT, function()
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
    self:RefreshComposerKeyboard()
end

function chat:RefreshComposerKeyboard()
    local frame = self.composer
    if not frame then return end
    local layout = frame.symbols and symbols or letters
    for row, entries in ipairs(frame.keyboardRows) do
        local x = row == 5 and 6 or (828 - (#(layout[row] or {}) * 82 - 6)) / 2
        for column, button in ipairs(entries) do
            local spec = row == 5 and controls[column] or nil
            local text = not spec and layout[row][column]
            button:SetShown(spec ~= nil or text ~= nil)
            if spec or text then
                local width = spec and spec.width or 76
                button:ClearAllPoints()
                button:SetPoint('TOPLEFT', x, -(row - 1) * (KEY_HEIGHT + ROW_GAP))
                button:SetWidth(width)
                button.centerX = x + width / 2
                button.action = spec and spec.action
                button.text = spec and spec.text or text
                if text and text:match('^[a-z]$') then
                    if (frame.caps == true) ~= (frame.shift == true) then text = text:upper() end
                elseif text and frame.shift then text = shifted[text] or text end
                if text then button.text = text end
                local label = spec and spec.label or text
                if spec and spec.action == 'symbols' and frame.symbols then label = 'ABC' end
                if spec and spec.action == 'caps' and frame.caps then label = 'CAPS' end
                button.label:SetText(label)
                self:HighlightComposerButton(button, row == frame.keyRow and column == frame.keyColumn)
                x = x + width + 6
            end
        end
    end
end

function chat:MoveComposerKey(dx, dy)
    local frame = self.composer
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
    local action = button.action
    if action == 'symbols' then
        frame.symbols = not frame.symbols
    elseif action == 'caps' then
        frame.caps = not frame.caps
    elseif action == 'space' then Input:InsertSpace()
    elseif action == 'delete' then Input:Backspace()
    elseif action == 'send' then self:SubmitComposer()
    elseif button.text then Input:InsertText(button.text) end
    self:RefreshComposerKeyboard()
end
