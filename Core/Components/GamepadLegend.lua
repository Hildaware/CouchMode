local addonName, addon = ...

addon.Components = addon.Components or {}
addon.Components.GamepadLegend = addon.Components.GamepadLegend or {}
local legendComponent = addon.Components.GamepadLegend

local ICON_SIZE = 24
local EDGE = 10
local ITEM_GAP = 15
local ROW_GAP = 11

local legendProto = {}

local function nativeAvailable()
    return _G.InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
        and _G.GamepadSharedUtility and GamepadSharedUtility.CreatePromptedBindingFooter
        and GamepadSharedUtility.CreatePromptedBinding
        and GamepadSharedUtility.CreateDoublePromptedBinding
        and _G.PromptedBindingMixin and _G.PromptedBindingFooterMixin
        and _G.GamepadMode and GamepadMode.CreateBindingGroup
        and _G.SmartNavigation and _G.EventRegistry
end

local function callFooter(method, footer)
    if securecallfunction then securecallfunction(method, footer)
    else method(footer) end
end

local function promptShown(prompt)
    return not prompt.show or prompt.show()
end

local function promptLabel(prompt)
    return type(prompt.label) == 'function' and prompt.label() or prompt.label or ''
end

local function fallbackKeys(keys)
    if #keys == 1 and keys[1] == 'DIRPADVERTICAL' then
        return { 'PADDUP', 'PADDDOWN' }
    end
    return keys
end

local function activeConsolePortDevice()
    local cp = _G.ConsolePort
    local data = cp and cp.GetData and cp:GetData()
    local gamepad = data and data.Gamepad
    return gamepad and gamepad.GetActiveDevice and gamepad:GetActiveDevice()
end

local GLYPHS = {
    PAD1 = 'A', PAD2 = 'B', PAD3 = 'X', PAD4 = 'Y',
    PADDUP = '↑', PADDDOWN = '↓', PADDLEFT = '←', PADDRIGHT = '→',
    PADLSHOULDER = 'L', PADRSHOULDER = 'R',
}

local function updateIcon(icon, key, device)
    local path, useAtlas
    if device and device.GetIconForButton then
        path, useAtlas = device:GetIconForButton(key, 32)
    end
    if path then
        icon.glyph:Hide()
        icon.texture:SetVertexColor(1, 1, 1, 1)
        icon.texture:SetTexCoord(0, 1, 0, 1)
        if useAtlas then
            icon.texture:SetAtlas(path)
        else
            icon.texture:SetTexture(path)
            icon.texture:SetTexCoord(0.25, 0.75, 0.25, 0.75)
        end
    else
        icon.texture:SetTexture('Interface\\CharacterFrame\\TempPortraitAlphaMask')
        icon.texture:SetTexCoord(0, 1, 0, 1)
        icon.texture:SetVertexColor(0.38, 0.36, 0.32, 1)
        icon.glyph:SetText(GLYPHS[key] or key)
        icon.glyph:Show()
    end
end

local function createFallbackIcon(parent, key, x)
    local icon = CreateFrame('Frame', nil, parent)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint('LEFT', parent, 'LEFT', x, 0)
    icon.key = key
    icon.texture = icon:CreateTexture(nil, 'ARTWORK')
    icon.texture:SetAllPoints(icon)
    icon.glyph = icon:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    icon.glyph:SetPoint('CENTER', icon, 'CENTER')
    return icon
end

local function createFallback(parent, prompts, x, gap)
    local frame = CreateFrame('Frame', nil, parent)
    frame:SetPoint('TOPLEFT', parent, 'BOTTOMLEFT', x, -gap)
    frame:SetSize(1, 44)
    frame:SetFrameLevel(parent:GetFrameLevel() + 5)
    frame:Hide()

    local background = frame:CreateTexture(nil, 'BACKGROUND')
    background:SetAllPoints(frame)
    local border = frame:CreateTexture(nil, 'BORDER')
    border:SetAllPoints(frame)
    local atlasInfo = _G.C_Texture and C_Texture.GetAtlasInfo
    if atlasInfo and C_Texture.GetAtlasInfo('gamepad-footer-slot-bg')
        and C_Texture.GetAtlasInfo('gamepad-footer-slot-frameneutral') then
        background:SetAtlas('gamepad-footer-slot-bg', true)
        border:SetAtlas('gamepad-footer-slot-frameneutral', true)
    else
        background:SetColorTexture(0.07, 0.06, 0.06, 0.96)
        border:Hide()
        for _, edge in ipairs({ 'TOP', 'BOTTOM', 'LEFT', 'RIGHT' }) do
            local line = frame:CreateTexture(nil, 'BORDER')
            line:SetColorTexture(0.42, 0.38, 0.31, 1)
            if edge == 'TOP' or edge == 'BOTTOM' then
                line:SetHeight(2)
                line:SetPoint(edge .. 'LEFT', frame, edge .. 'LEFT')
                line:SetPoint(edge .. 'RIGHT', frame, edge .. 'RIGHT')
            else
                line:SetWidth(2)
                line:SetPoint('TOP' .. edge, frame, 'TOP' .. edge)
                line:SetPoint('BOTTOM' .. edge, frame, 'BOTTOM' .. edge)
            end
        end
    end

    local items = {}
    for i, prompt in ipairs(prompts) do
        local item = CreateFrame('Frame', nil, frame)
        item:SetHeight(ICON_SIZE)
        item.icons = {}
        local keys = fallbackKeys(prompt.keys)
        for j, key in ipairs(keys) do
            local offset = (j - 1) * (ICON_SIZE + 14)
            if j > 1 then
                local divider = item:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
                divider:SetPoint('LEFT', item, 'LEFT', offset - 12, 0)
                divider:SetText('/')
            end
            item.icons[j] = createFallbackIcon(item, key, offset)
        end
        item.label = item:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
        item.label:SetPoint('LEFT', item.icons[#item.icons], 'RIGHT', 4, 0)
        item.label:SetJustifyH('LEFT')
        item.label:SetWordWrap(false)
        items[i] = item
    end
    return frame, items
end

function legendProto:RefreshFallback()
    local device = activeConsolePortDevice()
    local maxWidth = math.max(44, self.maxWidth or self.parent:GetWidth() - 8)
    local x, y = EDGE, -EDGE
    local rows, usedWidth, visible = 1, 0, 0
    for i, prompt in ipairs(self.prompts) do
        local item = self.fallbackItems[i]
        local shown = promptShown(prompt)
        item:SetShown(shown)
        if shown then
            visible = visible + 1
            item.label:SetText(promptLabel(prompt))
            for _, icon in ipairs(item.icons) do updateIcon(icon, icon.key, device) end
            local iconWidth = #item.icons * ICON_SIZE + (#item.icons - 1) * 14
            local width = iconWidth + 4 + item.label:GetStringWidth()
            item:SetWidth(width)
            if x > EDGE and x + width + EDGE > maxWidth then
                x, y = EDGE, y - ICON_SIZE - ROW_GAP
                rows = rows + 1
            end
            item:ClearAllPoints()
            item:SetPoint('TOPLEFT', self.fallback, 'TOPLEFT', x, y)
            usedWidth = math.max(usedWidth, x + width + EDGE)
            x = x + width + ITEM_GAP
        end
    end
    local height = visible > 0 and (EDGE * 2 + rows * ICON_SIZE + (rows - 1) * ROW_GAP) or 0
    self.fallback:SetSize(math.min(maxWidth, math.max(1, usedWidth)), math.max(1, height))
    self.fallbackVisible = visible > 0
    if self.backend == 'fallback' then self.fallback:SetShown(self.active and self.fallbackVisible) end
end

function legendProto:CreateNative()
    if self.nativeFooter or not nativeAvailable() then return end
    local footer = GamepadSharedUtility.CreatePromptedBindingFooter(self.parent, self.name)
    footer:SetOverflowType(PromptedBindingFooterMixin.OVERFLOW_TYPE.EXPAND)
    for _, prompt in ipairs(self.prompts) do
        local keys = prompt.keys
        local binding
        if #keys == 2 then
            binding = GamepadSharedUtility.CreateDoublePromptedBinding(
                keys[1], keys[2], nil, nil, promptLabel(prompt))
        else
            binding = GamepadSharedUtility.CreatePromptedBinding(keys[1], nil, promptLabel(prompt))
        end
        if type(prompt.label) == 'function' then binding:SetLabelFunction(prompt.label) end
        if prompt.show then
            binding:AddCondition(prompt.show)
            binding:SetVisibilityType(PromptedBindingMixin.VISIBILITY_TYPE.ONLY_IF_USABLE)
        end
        footer:AddPromptedBinding(binding)
    end
    footer:Finalize()
    self.nativeFooter = footer
end

function legendProto:AnchorNative()
    local footer = self.nativeFooter
    if not footer or not footer.inputLegend then return end
    footer:SetAnchorOffsets(self.x, -self.gap)
end

function legendProto:Refresh()
    self:RefreshFallback()
    if self.active and nativeAvailable() then
        self:CreateNative()
        self.fallback:Hide()
        local footer = self.nativeFooter
        if footer then
            if not self.nativeShown then
                callFooter(footer.ShowAndActivateBindings, footer)
                self.nativeShown = true
            else
                footer:SetAnchorOffsets(self.x, -self.gap)
                callFooter(footer.Refresh, footer)
            end
            self.backend = 'native'
            self:AnchorNative()
            return
        end
    end
    if self.nativeShown then
        callFooter(self.nativeFooter.HideAndDeactivateBindings, self.nativeFooter)
        self.nativeShown = false
    end
    self.backend = 'fallback'
    self.fallback:SetShown(self.active and self.fallbackVisible)
end

function legendProto:SetMaxWidth(width)
    width = math.max(44, width or self.parent:GetWidth() - 8)
    if self.maxWidth == width then return end
    self.maxWidth = width
    self:Refresh()
end

function legendProto:GetHeight()
    if self.backend == 'native' and self.nativeFooter and self.nativeFooter.inputLegend then
        return self.nativeFooter.inputLegend:GetHeight()
    end
    return self.fallback:GetHeight()
end

function legendProto:Show()
    self.active = true
    self:Refresh()
end

function legendProto:Hide()
    self.active = false
    if self.nativeShown then
        callFooter(self.nativeFooter.HideAndDeactivateBindings, self.nativeFooter)
        self.nativeShown = false
    end
    self.fallback:Hide()
    self.backend = nil
end

--- Creates a visual legend; button handling stays with the caller.
--- Prompts contain keys={gamepadKey[, gamepadKey]}, label=string|function,
--- and optional show=function returning whether the prompt is available.
--- The legend sits below the parent frame; `gap` controls their separation.
function legendComponent.Create(parent, options)
    local instance = setmetatable({
        parent = parent,
        name = options.name or 'CouchModeGamepadLegend',
        prompts = options.prompts,
        x = options.x or 0,
        gap = options.gap or 12,
        active = false,
        nativeShown = false,
    }, { __index = legendProto })
    instance.fallback, instance.fallbackItems = createFallback(
        parent, instance.prompts, instance.x, instance.gap)
    instance:RefreshFallback()
    local cp = _G.ConsolePort
    local data = cp and cp.GetData and cp:GetData()
    if data and data.RegisterCallback then
        data:RegisterCallback('Gamepad/Active', function() instance:Refresh() end)
    end
    return instance
end
