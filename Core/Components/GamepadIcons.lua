-- Display-only controller glyphs. Input ownership stays with each caller.
local _, addon = ...
local M = {}
addon.Components.GamepadIcons = M
M.SIZE, M.SEPARATOR_SIZE = 32, 20
local widgets, callbacks = {}, {}
local eventFrame, nativeHooked, cpHooked
local fallback = {
    PAD1 = 'A', PAD2 = 'B', PAD3 = 'X', PAD4 = 'Y',
    PADLSHOULDER = 'LB', PADRSHOULDER = 'RB', PADLTRIGGER = 'LT', PADRTRIGGER = 'RT',
    PADLSTICK = 'LS', PADRSTICK = 'RS', PADFORWARD = 'Start', PADBACK = 'Back',
    PADDUP = '↑', PADDDOWN = '↓', PADDLEFT = '←', PADDRIGHT = '→',
}

local function consolePortDevice()
    local cp = _G.ConsolePort
    local data = cp and cp.GetData and cp:GetData()
    local gamepad = data and data.Gamepad
    return gamepad and gamepad.GetActiveDevice and gamepad:GetActiveDevice(), data
end

-- Returns a texture path/atlas and whether SetAtlas should be used.
function M.Resolve(key)
    local state = C_GamePad and C_GamePad.GetDeviceMappedState
        and C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID())
    local style = state and state.labelStyle
    local choices = addon.Components.GamepadIconAtlases[key]
    local atlas = choices and choices[style]
    if atlas and C_Texture and C_Texture.GetAtlasInfo(atlas) then return atlas, true end
    local utility = _G.InputIconTextureSetUtility
    if utility and utility.GetNormalActiveInputIconButtonTexture then
        local ok, result = pcall(utility.GetNormalActiveInputIconButtonTexture, key)
        if ok and result then return result, true end
    end
    local device = consolePortDevice()
    if device and device.GetIconForButton then return device:GetIconForButton(key, 32) end
end

local function refreshAll()
    for _, widget in ipairs(widgets) do widget:Refresh() end
    for _, callback in pairs(callbacks) do callback() end
end

local function initialize()
    if not eventFrame then
        eventFrame = CreateFrame('Frame')
        for _, event in ipairs({ 'GAME_PAD_ACTIVE_CHANGED', 'GAME_PAD_CONNECTED',
            'GAME_PAD_DISCONNECTED', 'UPDATE_BINDINGS', 'CVAR_UPDATE' }) do
            addon.Utils.RegisterEventIfValid(eventFrame, event)
        end
        eventFrame:SetScript('OnEvent', function(_, event, name)
            if event == 'CVAR_UPDATE' and not tostring(name):lower():find('gamepad', 1, true) then return end
            initialize()
            refreshAll()
        end)
    end
    local manager = _G.InputDeviceIconSetManager
    if not nativeHooked and manager and manager.RegisterActiveInputDeviceIconSetUpdatedCallback then
        manager:RegisterActiveInputDeviceIconSetUpdatedCallback(refreshAll, M)
        nativeHooked = true
    end
    local _, data = consolePortDevice()
    if not cpHooked and data and data.RegisterCallback then
        data:RegisterCallback('Gamepad/Active', refreshAll)
        cpHooked = true
    end
end

-- One layout callback per owner, after glyphs refresh for a device/binding change.
function M.RegisterCallback(owner, callback)
    callbacks[owner] = callback
    initialize()
end

local function draw(icon, key)
    icon.key = key
    icon.texture:Show()
    icon.texture:SetVertexColor(1, 1, 1, 1)
    icon.texture:SetTexCoord(0, 1, 0, 1)
    local path, atlas
    if key:match('^PAD') or key:match('^DIRPAD') then path, atlas = M.Resolve(key) end
    if path then
        if atlas then icon.texture:SetAtlas(path)
        else
            icon.texture:SetTexture(path)
            icon.texture:SetTexCoord(0.25, 0.75, 0.25, 0.75)
        end
        icon.glyph:Hide()
    else
        icon.texture:Hide()
        icon.glyph:SetText(fallback[key] or GetBindingText(key, 'KEY_'))
        icon.glyph:Show()
    end
end

-- A mouse-transparent button glyph, refreshed automatically when the device changes.
function M.Create(parent, key, size)
    local icon = CreateFrame('Frame', nil, parent)
    icon:SetSize(size or M.SIZE, size or M.SIZE)
    icon:EnableMouse(false)
    icon.texture = icon:CreateTexture(nil, 'ARTWORK')
    icon.texture:SetAllPoints()
    icon.glyph = icon:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    icon.glyph:SetPoint('CENTER')
    function icon:SetKey(value) draw(self, value) end
    function icon:Refresh() draw(self, self.key) end
    icon:SetKey(key)
    widgets[#widgets + 1] = icon
    initialize()
    return icon
end

-- Keyboard-only chords stay text; gamepad chords resolve emulated modifiers.
function M.BindingKeys(binding)
    if not binding then return { 'Unbound' } end
    if not binding:find('PAD', 1, true) then return { binding } end
    local utility = _G.InputIconTextureSetUtility
    if utility and utility.GetInputIconNameFromBindingKey then
        return utility.GetInputIconNameFromBindingKey(binding)
    end
    local keys = { strsplit('-', binding) }
    local cvars = { CTRL = 'GamePadEmulateCtrl', SHIFT = 'GamePadEmulateShift', ALT = 'GamePadEmulateAlt' }
    for i, key in ipairs(keys) do
        if cvars[key] then
            local value = GetCVar(cvars[key])
            if value and value:match('^PAD') then keys[i] = value end
        end
    end
    return keys
end

-- A chord uses '+'. Alternative controls, such as previous/next tabs, use '/'.
function M.CreateGroup(parent, options)
    options = options or {}
    local group = CreateFrame('Frame', nil, parent)
    group.size = options.size or M.SIZE
    group.separator = options.separator or '+'
    group:SetSize(1, group.size)
    group:EnableMouse(false)
    group.icons, group.dividers, group.keys = {}, {}, {}
    function group:SetFont(font, size)
        self.font, self.fontSize = font, size
        self:Refresh()
    end
    function group:SetKeys(keys)
        self.binding = nil
        self.keys = keys
        self:Refresh()
    end
    function group:SetBinding(binding)
        self.binding = binding or false
        self.keys = M.BindingKeys(binding)
        self:Refresh()
    end
    function group:Refresh()
        if self.binding ~= nil then self.keys = M.BindingKeys(self.binding or nil) end
        for _, icon in ipairs(self.icons) do icon:Hide() end
        for _, divider in ipairs(self.dividers) do divider:Hide() end
        local width, previousPad = 0, false
        for i, key in ipairs(self.keys) do
            local pad = key:match('^PAD') ~= nil or key:match('^DIRPAD') ~= nil
            if i > 1 then
                local divider = self.dividers[i - 1]
                if not divider then
                    divider = self:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
                    self.dividers[i - 1] = divider
                end
                local atlas = self.separator == '+' and 'gamepad-switch-128x-plus-normal' or 'gamepad-symbols-slash'
                local size = math.floor(self.size * M.SEPARATOR_SIZE / M.SIZE + 0.5)
                width = width + (previousPad and -self.size * 6 / 32 or 2)
                divider:ClearAllPoints()
                divider:SetPoint('LEFT', self, 'LEFT', width, 0)
                if C_Texture and C_Texture.GetAtlasInfo(atlas) then
                    divider:SetText(('|A:%s:%d:%d|a'):format(atlas, size, size))
                else divider:SetText(self.separator) end
                divider:Show()
                width = width + size + (pad and -self.size * 6 / 32 or 2)
            end
            local icon = self.icons[i]
            if not icon then icon = M.Create(self, key, self.size); self.icons[i] = icon end
            icon:SetKey(key)
            if self.font then icon.glyph:SetFont(self.font, self.fontSize, '') end
            icon:SetWidth(pad and self.size or icon.glyph:GetStringWidth() + 4)
            icon:ClearAllPoints()
            icon:SetPoint('LEFT', self, 'LEFT', width, 0)
            icon:Show()
            width, previousPad = width + icon:GetWidth(), pad
        end
        self:SetWidth(math.max(1, width))
    end
    widgets[#widgets + 1] = group
    initialize()
    return group
end
