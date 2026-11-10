-- Fixed input capture: no native binding-stack records or combat-time rebinding.
local _, addon = ...
local chat = addon.Chat
local TAB = chat.COMPOSER_TABS
local Input = addon.ChatInput
local DELAY, INTERVAL = 0.35, 0.08
local KEYBOARD_DEADZONE = 0.16
local KEYBOARD_SMOOTH_TIME = 0.075
local KEYBOARD_POINTER_SPEED = 630 -- Keyboard-local pixels per second, on either axis.
local directions = {
    PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 },
    PADDUP = { 0, -1 }, PADDDOWN = { 0, 1 },
}

function chat:ResetComposerHeldInput(keepButtons)
    local frame = self.composer
    if not frame then return end
    if not keepButtons then frame.held = {} end
    frame.repeatAction = nil
    frame.leftDirection, frame.rightDirection = nil, nil
    frame.leftReady, frame.rightReady = false, false
    frame.shift = false
    frame.emoteStickActive = false
    frame.keyboardStickActive = false
    frame.keyboardMoveX, frame.keyboardMoveY = 0, 0
    frame.keyboardVelocityX, frame.keyboardVelocityY = 0, 0
    self:ResetComposerEmotePointer()
    if frame.keyboardRows then
        if frame.keyboardPointerActive == nil then frame.keyboardPointerActive = true end
        frame.keyboardPointerX = frame.keyboardPointerX or 0
        frame.keyboardPointerY = frame.keyboardPointerY or 0
        self:RefreshComposerKeyboard()
    end
end

local function mappedState()
    return C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.GetDeviceMappedState()
end

function chat:SeedComposerHeldInput()
    local frame, state = self.composer, mappedState()
    if not state then return end
    if C_GamePad.ButtonIndexToBinding then
        for i, down in ipairs(state.buttons or {}) do
            local key = C_GamePad.ButtonIndexToBinding(i - 1)
            if key and down then frame.held[key] = true end
        end
    end
    for i, stick in ipairs(state.sticks or {}) do
        local name = C_GamePad.StickIndexToConfigName and C_GamePad.StickIndexToConfigName(i - 1)
        if name == 'Left' then frame.leftReady = (stick.len or 0) < 0.3 end
        if name == 'Right' then frame.rightReady = (stick.len or 0) < 0.3 end
    end
end

local function neutral(state)
    if not state then return true end
    for _, down in ipairs(state.buttons or {}) do if down then return false end end
    for i, stick in ipairs(state.sticks or {}) do
        local name = C_GamePad.StickIndexToConfigName and C_GamePad.StickIndexToConfigName(i - 1)
        -- Gyro/Look readings are not thumbstick holds and must not strand capture.
        if (name == 'Left' or name == 'Right' or name == 'Movement' or name == 'Camera'
            or (not name and i <= 2)) and (stick.len or 0) >= 0.3 then return false end
    end
    return true
end

function chat:DrainComposerInput()
    -- Keep consuming the closing button and stick deflection until release,
    -- so returning to gameplay does not activate the held action or turn camera.
    local drain = self.composer.drain
    if not neutral(mappedState()) then drain:Show() end
end

function chat:BuildComposerController(parent)
    local capture = CreateFrame('Frame', nil, parent)
    capture:SetAllPoints()
    capture:SetFrameLevel(parent:GetFrameLevel() + 3)
    capture:EnableGamePadButton(true)
    capture:EnableGamePadStick(true)
    -- This property also controls gamepad propagation. Configure once while
    -- out of combat; only visibility changes as focus comes and goes.
    capture:SetPropagateKeyboardInput(false)
    capture:Hide()
    capture:SetScript('OnGamePadButtonDown', function(_, key) chat:ComposerGamepadButton(key, true) end)
    capture:SetScript('OnGamePadButtonUp', function(_, key) chat:ComposerGamepadButton(key, false) end)
    capture:SetScript('OnGamePadStick', function(_, stick, x, y)
        chat:ComposerGamepadStick(stick, x, y)
        -- Consume raw and virtual stick events, including camera/movement twins.
        return false
    end)
    parent.capture = capture
    local drain = CreateFrame('Frame', nil, UIParent)
    drain:SetFrameStrata('FULLSCREEN_DIALOG')
    drain:SetFrameLevel(capture:GetFrameLevel())
    drain:EnableGamePadButton(true)
    drain:EnableGamePadStick(true)
    drain:SetPropagateKeyboardInput(false)
    drain:SetScript('OnGamePadButtonDown', function() end)
    drain:SetScript('OnGamePadButtonUp', function() end)
    drain:SetScript('OnGamePadStick', function() return false end)
    drain:SetScript('OnUpdate', function(self)
        if neutral(mappedState()) then self:Hide() end
    end)
    drain:Hide()
    parent.drain = drain
    self:ResetComposerHeldInput()
end

function chat:MoveComposerSelection(dx, dy)
    local frame = self.composer
    if frame.channels:IsShown() then
        local count = #frame.destinations
        if count > 0 then frame.channelIndex = ((frame.channelIndex - 1 + (dy ~= 0 and dy or dx)) % count) + 1 end
        self:RefreshComposerChannels()
    elseif self.composerTab == TAB.KEYBOARD then self:MoveComposerKey(dx, dy)
    elseif self.composerTab == TAB.SHORTCUTS then self:MoveComposerReply(dx, dy)
    else self:MoveComposerEmote(dx, dy) end
end

function chat:RepeatComposerAction(action)
    if action == 'delete' then Input:Backspace()
    elseif action == 'caretLeft' then Input:MoveCaret(-1)
    elseif action == 'caretRight' then Input:MoveCaret(1)
    elseif directions[action] then self:MoveComposerSelection(unpack(directions[action])) end
end

function chat:StartComposerRepeat(action)
    self:RepeatComposerAction(action)
    self.composer.repeatAction = action
    self.composer.repeatRemaining = DELAY
end

function chat:ComposerGamepadButton(key, down)
    if not self.composerActive then return end
    local frame = self.composer
    if not down then
        frame.held[key] = nil
        if frame.repeatAction == key or (key == 'PAD3' and frame.repeatAction == 'delete') then
            frame.repeatAction = nil
        end
        if key == 'PADLTRIGGER' then frame.shift = false; self:RefreshComposerKeyboard() end
        return
    end
    if frame.held[key] then return end
    frame.held[key] = true
    if directions[key] then self:StartComposerRepeat(key)
    elseif key == 'PAD2' then self:ComposerBack()
    elseif key == 'PAD1' then
        if frame.channels:IsShown() then self:ChooseComposerChannel()
        elseif self.composerTab == TAB.KEYBOARD then self:PressComposerKey()
        elseif self.composerTab == TAB.SHORTCUTS then self:InsertComposerReply()
        else self:PerformComposerEmote() end
    elseif key == 'PADLSHOULDER' then self:SetComposerTab(self.composerTab - 1)
    elseif key == 'PADRSHOULDER' then self:SetComposerTab(self.composerTab + 1)
    elseif key == 'PADLSTICK' and self.composerTab ~= TAB.EMOTES then self:ToggleComposerChannels()
    elseif key == 'PADRSTICK' and self.composerTab == TAB.KEYBOARD and not frame.channels:IsShown() then
        frame.symbols = not frame.symbols
        self:RefreshComposerKeyboard()
    elseif not frame.channels:IsShown() and self.composerTab ~= TAB.EMOTES then
        if key == 'PADRTRIGGER' then self:SubmitComposer()
        elseif self.composerTab == TAB.KEYBOARD then
            if key == 'PAD3' then self:StartComposerRepeat('delete')
            elseif key == 'PAD4' then Input:InsertSpace()
            elseif key == 'PADLTRIGGER' then frame.shift = true; self:RefreshComposerKeyboard() end
        end
    end
end

function chat:ComposerGamepadStick(stick, x, y)
    if not self.composerActive then return end
    -- Act only on raw sticks; their Movement/Camera twins are consumed but must
    -- not cause a second navigation step or a second emote selection.
    if stick ~= 'Left' and stick ~= 'Right' then return end
    local frame = self.composer
    local length = math.sqrt(x * x + y * y)
    local readyKey = stick == 'Left' and 'leftReady' or 'rightReady'
    local directionKey = stick == 'Left' and 'leftDirection' or 'rightDirection'
    local prior = frame[directionKey]
    if stick == 'Left' and self.composerTab == TAB.KEYBOARD and not frame.channels:IsShown() then
        if length < KEYBOARD_DEADZONE then
            frame.leftReady = true
            -- Brake immediately on release: smoothing must not cause drift.
            frame.keyboardMoveX, frame.keyboardMoveY = 0, 0
            frame.keyboardVelocityX, frame.keyboardVelocityY = 0, 0
            frame.keyboardStickActive = false
            return
        end
        if not frame.leftReady then return end
        -- Deflection controls speed, not position. Squaring the magnitude gives
        -- shallow holds fine control while keeping full-speed travel available.
        local magnitude = math.min(1, math.max(0,
            (length - KEYBOARD_DEADZONE) / (1 - KEYBOARD_DEADZONE)))
        local scale = magnitude * magnitude / length
        if not frame.keyboardPointerActive then
            self:PositionComposerPointerOnSelection()
            frame.keyboardVelocityX, frame.keyboardVelocityY = 0, 0
        end
        frame.keyboardStickActive = true
        frame.keyboardPointerActive = true
        frame.keyboardMoveX, frame.keyboardMoveY = x * scale, y * scale
        return
    end
    if stick == 'Left' and self.composerTab == TAB.EMOTES and not frame.channels:IsShown() then
        self:ComposerEmoteStick(x, y)
        return
    end
    if length < 0.3 then
        frame[readyKey] = true
        frame[directionKey] = nil
        if prior and frame.repeatAction == prior then frame.repeatAction = nil end
        return
    end
    if not frame[readyKey] or length < 0.5 then return end
    local action
    if stick == 'Left' then
        if math.abs(x) > math.abs(y) then action = x < 0 and 'PADDLEFT' or 'PADDRIGHT'
        else action = y > 0 and 'PADDUP' or 'PADDDOWN' end
    elseif self.composerTab == TAB.KEYBOARD and not frame.channels:IsShown() and math.abs(x) > math.abs(y) then
        action = x < 0 and 'caretLeft' or 'caretRight'
    end
    if action and action ~= prior then
        frame[directionKey] = action
        self:StartComposerRepeat(action)
    end
end

function chat:MoveComposerKeyboardPointer(elapsed)
    local frame = self.composer
    if self.composerTab ~= TAB.KEYBOARD or frame.channels:IsShown()
        or not frame.keyboardPointerActive or not frame.keyboardStickActive then return end
    -- Smooth velocity instead of chasing an absolute stick position. Integrate
    -- the exponential exactly so travel is independent of the frame rate.
    -- Cap hitch time so a stalled frame cannot throw the cursor across keys.
    local dt = math.max(0, math.min(elapsed, 0.05))
    local blend = 1 - math.exp(-dt / KEYBOARD_SMOOTH_TIME)
    local vx, vy = frame.keyboardVelocityX, frame.keyboardVelocityY
    local tx, ty = frame.keyboardMoveX, frame.keyboardMoveY
    local dx = tx * dt + (vx - tx) * KEYBOARD_SMOOTH_TIME * blend
    local dy = ty * dt + (vy - ty) * KEYBOARD_SMOOTH_TIME * blend
    frame.keyboardVelocityX = vx + (tx - vx) * blend
    frame.keyboardVelocityY = vy + (ty - vy) * blend
    local width, height = self:GetComposerKeyboardPointerSpan()
    local x = math.max(-1, math.min(1, frame.keyboardPointerX + dx * KEYBOARD_POINTER_SPEED * 2 / width))
    local y = math.max(-1, math.min(1, frame.keyboardPointerY + dy * KEYBOARD_POINTER_SPEED * 2 / height))
    self:SetComposerKeyboardPointer(x, y)
end

function chat:UpdateComposerHeldInput(elapsed)
    local frame = self.composer
    self:UpdateComposerEmotePointer(elapsed)
    self:MoveComposerKeyboardPointer(elapsed)
    if not frame.repeatAction then return end
    frame.repeatRemaining = frame.repeatRemaining - elapsed
    if frame.repeatRemaining > 0 then return end
    frame.repeatRemaining = INTERVAL
    self:RepeatComposerAction(frame.repeatAction)
end
