-- Display-only footer labels and the controller-driven language/channel picker.
local _, addon = ...
local chat = addon.Chat
local Input = addon.ChatInput
local TAB = chat.COMPOSER_TABS
local function db() return addon.db.profile.chat end
local ROWS = 6

local function footerLabel(parent)
    local label = parent:CreateFontString(nil, 'ARTWORK')
    label:SetFont(addon.Media.ResolveFont(db().msgFontFace), 16, '')
    label:SetTextColor(0.87, 0.84, 0.76)
    label:SetJustifyH('LEFT')
    label:SetWordWrap(false)
    return label
end

function chat:BuildComposerSelectors()
    local frame = self.composer
    frame.language = footerLabel(frame.footer)
    frame.destination = footerLabel(frame.footer)
    -- Keep the destination's existing weight and channel color.
    frame.destination:SetShadowColor(0.87, 0.84, 0.76, 1)
    frame.destination:SetShadowOffset(0.65, 0)

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
    -- Retain this shared popup reference for keyboard/pointer input suppression.
    frame.channels = panel
    frame.selectorTabs = {}
    local tabWidth = (panel:GetWidth() - 92) / 2
    for index, kind in ipairs({ 'language', 'channel' }) do
        local selectorKind = kind
        local tab = self:ComposerButton(panel, kind == 'language' and (LANGUAGE or 'Language') or (CHANNEL or 'Channel'),
            tabWidth, 28, function() chat:SetComposerSelectorKind(selectorKind) end)
        tab:SetPoint('TOPLEFT', 16 + (index - 1) * (tabWidth + 60), -8)
        frame.selectorTabs[kind] = tab
    end
    panel.tabHint = addon.Components.GamepadIcons.CreateGroup(panel, { size = 22, separator = '/' })
    panel.tabHint:SetPoint('TOP', 0, -11)
    panel.tabHint:SetKeys({ 'PADDLEFT', 'PADDRIGHT' })
    frame.channelButtons = {}
    frame.channelIndex, frame.channelFirst = 1, 1
    for slot = 1, ROWS do
        local index = slot
        local button = self:ComposerButton(panel, '', panel:GetWidth() - 32, 32, function()
            chat.composer.channelIndex = chat.composer.channelFirst + index - 1
            chat:ChooseComposerChannel()
        end)
        button.label:SetFont(addon.Media.ResolveFont(db().msgFontFace), 18, '')
        button:SetPoint('TOPLEFT', 16, -44 - (slot - 1) * 36)
        frame.channelButtons[slot] = button
    end
    panel:SetScript('OnMouseWheel', function(_, delta) chat:MoveComposerSelection(0, -delta) end)
    panel:EnableMouseWheel(true)

    -- Native language lists can change through spells and faction/race changes.
    panel:SetScript('OnEvent', function()
        if not chat:IsComposerOpen() then return end
        if panel:IsShown() then chat:SetComposerSelectorKind(frame.selectorKind) end
        chat:RefreshComposerFooter()
    end)
    for _, event in ipairs({ 'LANGUAGE_LIST_CHANGED', 'CAN_PLAYER_SPEAK_LANGUAGE_CHANGED' }) do
        addon.Utils.RegisterEventIfValid(panel, event)
    end
    self:RefreshComposerFooter()
end

function chat:RefreshComposerFooter()
    local frame = self.composer
    local name, id = Input:GetLanguage()
    local languageText = self:LanguageIcon(id, 18) .. ' ' .. (name or LANGUAGE or 'Language')
    if languageText ~= frame.languageText then
        frame.languageText = languageText
        frame.language:SetText(languageText)
        local width = frame.language:GetUnboundedStringWidth()
        frame.language:SetWidth(math.min(frame.footer:GetWidth() * 0.4, math.max(1, width)))
    end
    frame.destination:SetText('Channel: ' .. Input:GetDestinationLabel())
    local r, g, b = Input:GetDestinationColor()
    frame.destination:SetTextColor(r, g, b)
    frame.destination:SetShadowColor(r, g, b, 1)
end

function chat:SetComposerSelectorKind(kind)
    local frame = self.composer
    self:ResetComposerHeldInput(true)
    frame.selectorKind = kind
    frame.destinations = kind == 'language' and Input:GetLanguages() or Input:GetDestinations()
    frame.channelIndex, frame.channelFirst = 1, 1
    local draft = Input:CaptureDraft()
    local _, languageID = Input:GetLanguage()
    for index, entry in ipairs(frame.destinations) do
        if (kind == 'language' and entry.id == languageID)
            or (kind == 'channel' and draft and entry.chatType == draft.chatType
                and entry.target == draft.target and entry.channel == draft.channel) then
            frame.channelIndex = index
            break
        end
    end
    for selectorKind, tab in pairs(frame.selectorTabs) do
        self:HighlightComposerButton(tab, kind == selectorKind)
    end
    self:RefreshComposerChannels()
end

function chat:ToggleComposerSelector(kind)
    if self.composerTab == TAB.EMOTES then return end
    local frame = self.composer
    if frame.channels:IsShown() and frame.selectorKind == kind then frame.channels:Hide(); return end
    self:SetComposerSelectorKind(kind)
    frame.channels:Show()
end

function chat:ToggleComposerChannels()
    self:ToggleComposerSelector('channel')
end

function chat:RefreshComposerChannels()
    local frame = self.composer
    if frame.channelIndex < frame.channelFirst then frame.channelFirst = frame.channelIndex end
    if frame.channelIndex >= frame.channelFirst + ROWS then frame.channelFirst = frame.channelIndex - ROWS + 1 end
    for slot, button in ipairs(frame.channelButtons) do
        local index = frame.channelFirst + slot - 1
        local entry = frame.destinations[index]
        button:SetShown(entry ~= nil)
        local icon = entry and frame.selectorKind == 'language' and (self:LanguageIcon(entry.id, 20) .. ' ') or ''
        button.label:SetText(entry and (icon .. entry.label) or '')
        self:HighlightComposerButton(button, index == frame.channelIndex)
    end
end

function chat:ChooseComposerChannel()
    local frame = self.composer
    local entry = frame.destinations[frame.channelIndex]
    if not entry then return end
    if frame.selectorKind == 'language' then
        if not Input:SelectLanguage(entry) then
            self:SetComposerStatus('That language is no longer available.')
            self:SetComposerSelectorKind('language')
            return
        end
    else
        -- Recheck availability; group/channel membership can change while choosing.
        local available = false
        for _, current in ipairs(Input:GetDestinations()) do
            if current.chatType == entry.chatType and current.target == entry.target and current.channel == entry.channel then
                available = true; break
            end
        end
        if not available then self:SetComposerStatus('That destination is no longer available.'); return end
        Input:SelectDestination(entry)
    end
    frame.channels:Hide()
    self:RefreshComposerFooter()
    self:SetComposerStatus('')
end
