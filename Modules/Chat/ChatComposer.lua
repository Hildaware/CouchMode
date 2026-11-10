-- The composer owns a temporary presentation of the existing Blizzard edit box.
local _, addon = ...
local chat = addon.Chat
local Input = addon.ChatInput
local Metal = addon.Components.Metal
local function db() return addon.db.profile.chat end
local PAGE_TOP, PAGE_BOTTOM = 114, 16
local LEGEND_GAP = 16
local tabs = {
    { label = 'Keyboard', icon = 'gamepad-radial-icon-macros-down',
        pressedIcon = 'gamepad-radial-icon-macros-up',
        background = 'dragonflight-landingpage-renownbutton-niffen-hover' },
    { label = 'Shortcuts', icon = 'gamepad-radial-icon-viewbuffs-down',
        pressedIcon = 'gamepad-radial-icon-viewbuffs',
        background = 'dragonflight-landingpage-renownbutton-valdrakken-hover' },
    { label = 'Emotes', icon = 'gamepad-radial-icon-emotes-down',
        pressedIcon = 'gamepad-radial-icon-emotes-up',
        background = 'dragonflight-landingpage-renownbutton-valdrakken' },
}

local function refreshTabIcon(button)
    if not button.tabIcon then return end
    local enabled = button:IsEnabled()
    local atlas = enabled and (button.composerSelected or button.tabPressed)
        and button.tabDownIcon or button.tabUpIcon
    button.tabIcon:SetShown(atlas ~= nil)
    if atlas and button.tabCurrentIcon ~= atlas then
        button.tabIcon:SetAtlas(atlas)
        button.tabCurrentIcon = atlas
    end
    button.tabIcon:SetDesaturated(not enabled)
end

chat.composer = nil
chat.composerDraft = nil
chat.composerTab = 1
chat.composerActive = false
chat.composerClosing = false
chat.composerSubmitting = false
chat.composerAttached = false

function chat:IsComposerOpen()
    return self.composer and self.composer:IsShown() or false
end

function chat:ComposerButton(parent, label, width, height, action, tabStyle)
    local button = CreateFrame('Button', nil, parent)
    button:SetSize(width, height)
    if tabStyle then
        -- Renown artwork fills the complete tab, including its icon and label.
        -- Clients without these atlases still get a labeled, usable tab.
        local backgroundAtlas = C_Texture.GetAtlasInfo(tabStyle.background)
            and tabStyle.background or 'common-button-square-gray-up'
        local background = button:CreateTexture(nil, 'BACKGROUND')
        background:SetAllPoints(button)
        background:SetAtlas(backgroundAtlas)
        local highlight = button:CreateTexture(nil, 'HIGHLIGHT')
        highlight:SetAllPoints(background)
        highlight:SetAtlas(backgroundAtlas)
        highlight:SetBlendMode('ADD')
        highlight:SetAlpha(0.3)
        button:SetHighlightTexture(highlight)
        button.tabIcon = button:CreateTexture(nil, 'ARTWORK')
        button.tabIcon:SetSize(30, 30)
        button.tabIcon:SetPoint('LEFT', button, 'LEFT', 14, 0)
        button.tabUpIcon = C_Texture.GetAtlasInfo(tabStyle.icon) and tabStyle.icon or nil
        button.tabDownIcon = C_Texture.GetAtlasInfo(tabStyle.pressedIcon)
            and tabStyle.pressedIcon or button.tabUpIcon
        button:HookScript('OnMouseDown', function(self, mouseButton)
            if mouseButton == 'LeftButton' then self.tabPressed = true; refreshTabIcon(self) end
        end)
        button:HookScript('OnMouseUp', function(self)
            self.tabPressed = false
            refreshTabIcon(self)
        end)
        button:HookScript('OnHide', function(self)
            self.tabPressed = false
            refreshTabIcon(self)
        end)
    else
        addon.Components.NineSliceButton.Apply(button,
            'common-button-square-gray-up', 'common-button-square-gray-down')
    end
    button.label = button:CreateFontString(nil, 'ARTWORK')
    button.label:SetFont(addon.Media.ResolveFont(db().msgFontFace), 20, '')
    button.label:SetPoint('TOPLEFT', 5, -3)
    button.label:SetPoint('BOTTOMRIGHT', -5, 3)
    button.label:SetJustifyH('CENTER')
    button.label:SetJustifyV('MIDDLE')
    button.label:SetText(label)
    button:HookScript('OnEnable', function(self)
        chat:HighlightComposerButton(self, self.composerSelected)
    end)
    button:HookScript('OnDisable', function(self)
        chat:HighlightComposerButton(self, self.composerSelected)
    end)
    button:RegisterForClicks('LeftButtonUp')
    button:SetScript('OnClick', function()
        if not chat.composerActive then chat:ResumeComposer() end
        action()
    end)
    self:HighlightComposerButton(button, false)
    return button
end

function chat:HighlightComposerButton(button, selected)
    button.composerSelected = selected
    if not button:IsEnabled() then
        button:UnlockHighlight()
        button.label:SetTextColor(DISABLED_FONT_COLOR:GetRGB())
    elseif selected then
        button:LockHighlight()
        button.label:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    else
        button:UnlockHighlight()
        button.label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    end
    refreshTabIcon(button)
end

function chat:ApplyComposerLayout()
    local frame = self.composer
    if not frame then return end
    local resuming = frame.resume and frame.resume:IsShown()
    local status = frame.status and frame.status:GetText()
    local pageHeight = frame.pages[self.composerTab]:GetHeight()
    local height = PAGE_TOP + pageHeight + PAGE_BOTTOM
        + ((resuming or (status and status ~= '')) and 32 or 0)
    local legendHeight = frame.legend and frame.legend:GetHeight() or 44
    local totalHeight = height + LEGEND_GAP + legendHeight + Metal.BORDER_OUTSET
    local scale = math.min(1, UIParent:GetWidth() * 0.94 / frame:GetWidth(),
        UIParent:GetHeight() * 0.55 / totalHeight)
    frame:SetHeight(height)
    frame:SetScale(scale)
    frame:ClearAllPoints()
    -- Reserve the floating legend's measured height so its bottom stays on screen.
    frame:SetPoint('BOTTOM', UIParent, 'BOTTOM', 0, 20 / scale + LEGEND_GAP + legendHeight)
    if frame.status then frame.status:SetShown(not resuming) end
end

function chat:SetComposerStatus(text)
    if self.composer then self.composer.status:SetText(text or '') end
    self:ApplyComposerLayout()
end

function chat:BuildComposer()
    if self.composer then return true end
    -- Propagation flags are restricted in combat. Never create a partially
    -- configured capture frame; OnEnable schedules initialization after combat.
    if InCombatLockdown() then return false end
    local contentWidth = self.COMPOSER_KEYBOARD_WIDTH
    local frame = CreateFrame('Frame', 'CouchModeChatComposer', UIParent, 'BackdropTemplate')
    frame:SetSize(contentWidth + 32, PAGE_TOP + self.COMPOSER_KEYBOARD_HEIGHT + 6 + PAGE_BOTTOM)
    frame:SetFrameStrata('FULLSCREEN_DIALOG')
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8' })
    frame:SetBackdropColor(0.025, 0.035, 0.055, 0.50)
    frame:EnableMouse(true)
    frame:Hide()
    self.composer = frame

    local border = CreateFrame('Frame', nil, frame)
    border:SetFrameLevel(frame:GetFrameLevel() + 2)
    border:EnableMouse(false)
    Metal.PositionBorderFrame(border, frame, Metal.BORDER_OUTSET)
    frame.borders = Metal.CreateBorderTextures(border, border)
    Metal.ApplyBorderTextures(frame.borders, true, 1, 1, 1, 1, Metal.BORDER_SIZE)

    local destination = self:ComposerButton(frame, '', 120, 38, function() chat:ToggleComposerChannels() end)
    destination:SetPoint('TOPLEFT', 16, -16)
    destination.label:SetFont(addon.Media.ResolveFont(db().msgFontFace), 18, '')
    destination.label:SetWordWrap(false)
    destination:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_TOP')
        GameTooltip:SetText(Input:GetDestinationLabel())
        GameTooltip:Show()
    end)
    destination:SetScript('OnLeave', function() GameTooltip:Hide() end)
    frame.destination = destination
    local close = self:ComposerButton(frame, '×', 32, 38, function() chat:CloseComposer() end)
    close:SetPoint('TOPRIGHT', -16, -16)
    close:SetFrameLevel(frame:GetFrameLevel() + 4)
    close:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_TOP')
        GameTooltip:SetText(CLOSE or 'Close')
        GameTooltip:Show()
    end)
    close:SetScript('OnLeave', function() GameTooltip:Hide() end)

    frame.inputAnchor = CreateFrame('Frame', nil, frame)
    frame.inputAnchor:SetPoint('TOPLEFT', destination, 'TOPRIGHT', 12, 0)
    frame.inputAnchor:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -60, -16)
    frame.inputAnchor:SetHeight(38)
    local inputBG = frame.inputAnchor:CreateTexture(nil, 'BACKGROUND')
    inputBG:SetAllPoints()
    inputBG:SetColorTexture(0.12, 0.13, 0.16, 1)

    frame.tabs, frame.pages = {}, {}
    local tabGap = 8
    local tabWidth = (contentWidth - 2 * tabGap) / 3
    for index, style in ipairs(tabs) do
        local tabIndex = index
        local tab = self:ComposerButton(frame, style.label, tabWidth, 40,
            function() chat:SetComposerTab(tabIndex) end, style)
        tab:SetPoint('TOPLEFT', 16 + (index - 1) * (tabWidth + tabGap), -64)
        frame.tabs[index] = tab
        local page = CreateFrame('Frame', nil, frame)
        page:SetPoint('TOPLEFT', 16, -PAGE_TOP)
        page:SetSize(contentWidth, self.COMPOSER_KEYBOARD_HEIGHT + 6)
        page:Hide()
        frame.pages[index] = page
    end
    self:BuildComposerKeyboard(frame.pages[1])
    self:BuildComposerReplies(frame.pages[2])
    self:BuildComposerEmotes(frame.pages[3])
    self:BuildComposerChannels()

    frame.status = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    frame.status:SetPoint('BOTTOMLEFT', 20, 20)
    frame.status:SetPoint('BOTTOMRIGHT', -20, 20)
    frame.status:SetTextColor(1, 0.80, 0.35)
    frame.resume = self:ComposerButton(frame, 'Resume controller input', 360, 30,
        function() chat:ResumeComposer() end)
    frame.resume:SetPoint('BOTTOM', 0, 12)
    frame.resume:Hide()

    frame.legend = addon.Components.GamepadLegend.Create(frame, {
        name = 'CouchModeComposerLegend', displayOnly = true, centered = true, singleRow = true, gap = LEGEND_GAP,
        prompts = {
            { keys = { 'PAD1' }, label = function() return chat.composerTab == 3 and 'Perform' or 'Select' end,
                sizingLabels = { 'Select', 'Perform' } },
            { keys = { 'PAD2' }, label = CLOSE or 'Close' },
            { keys = { 'PAD3' }, label = 'Delete', show = function() return chat.composerTab ~= 3 end },
            { keys = { 'PAD4' }, label = 'Space', show = function() return chat.composerTab ~= 3 end },
            { keys = { 'PADLSHOULDER', 'PADRSHOULDER' }, label = 'Tabs' },
            { keys = { 'PADLTRIGGER' }, label = 'Shift', show = function() return chat.composerTab == 1 end },
            { keys = { 'PADRTRIGGER' }, label = 'Send', show = function() return chat.composerTab ~= 3 end },
            { keys = { 'PADLSTICK' }, label = 'Channel' },
            { keys = { 'PADRSTICK' }, label = 'Symbols', show = function() return chat.composerTab == 1 end },
        },
    })
    frame.legend:SetMaxWidth(contentWidth)
    self:BuildComposerController(frame)
    frame:SetScript('OnUpdate', function(_, elapsed) chat:UpdateComposer(elapsed) end)
    frame:SetScript('OnHide', function()
        if not chat.composerClosing then chat:CloseComposer() end
    end)
    self:ApplyComposerLayout()
    return true
end

function chat:SetComposerTab(index)
    self.composerTab = ((index - 1) % 3) + 1
    self:ResetComposerHeldInput(true)
    self.composer.channels:Hide()
    for i, page in ipairs(self.composer.pages) do
        page:SetShown(i == self.composerTab)
        self:HighlightComposerButton(self.composer.tabs[i], i == self.composerTab)
    end
    self.composer.emoteIndex = nil
    if self.composerTab == 2 then self:RefreshComposerReplies() end
    self:RefreshComposerEmotes()
    self.composer.legend:Refresh()
    self:SetComposerStatus('')
end

function chat:OpenComposer()
    if not db().enabled or not self.panel then return end
    if self:IsComposerOpen() then self:ResumeComposer(); return end
    if not self:BuildComposer() then
        print('CouchMode: the chat composer will be available after combat ends.')
        return
    end
    -- Finish history dismissal now so its capture cannot compete with typing.
    if self.historyFrame then self.historyFrame:Hide() end
    local draft = Input:CaptureDraft()
    if not draft then return end
    if draft.text == '' and self.composerDraft then draft = self.composerDraft end
    if not Input:BeginComposer(self.composer.inputAnchor,
        function() chat:SubmitComposer() end, function() chat:ComposerBack() end) then return end
    self.composerAttached = true
    self.composerClosing = false
    self.composer:Show()
    self.composer.keyRow, self.composer.keyColumn = 3, 5
    self.composer.keyboardPointerActive = true
    self.composer.keyboardPointerX, self.composer.keyboardPointerY = 0, 0
    self:SetComposerTab(1)
    Input:Focus()
    Input:RestoreDraft(draft)
    self:ResumeComposer()
    self.composer.legend:Show()
    self:Touch()
end

function chat:ResumeComposer()
    if not self:IsComposerOpen() then return end
    Input:Focus()
    self.composerActive = true
    self.composer.resumeRequired = false
    self.composer.resume:Hide()
    self:ResetComposerHeldInput()
    self:SeedComposerHeldInput()
    self.composer.drain:Hide()
    self.composer.capture:Show()
    self:SetComposerStatus('')
end

function chat:SuspendComposer(requireResume)
    if not self.composer then return end
    self.composerActive = false
    self.composer.resumeRequired = requireResume == true
    self:ResetComposerHeldInput()
    self.composer.capture:Hide()
    self.composer.resume:Show()
    self:ApplyComposerLayout()
end

function chat:CloseComposer(discardDraft)
    if not self.composer or self.composerClosing then return end
    if not self.composerAttached then return end
    self.composerClosing = true
    if not discardDraft then self.composerDraft = Input:CaptureDraft() end
    self.composerActive = false
    self:ResetComposerHeldInput()
    self.composer.capture:Hide()
    self.composer.channels:Hide()
    self.composer.legend:Hide()
    self.composer.caps, self.composer.symbols = false, false
    local editBox = Input:GetEditBox()
    if editBox then editBox:SetText('') end
    Input:Deactivate()
    Input:EndComposer()
    self.composerAttached = false
    self.composer:Hide()
    self:DrainComposerInput()
    self.composerClosing = false
    self:Touch()
end

function chat:ToggleComposer()
    if self:IsComposerOpen() then self:CloseComposer() else self:OpenComposer() end
end

function chat:ComposerBack()
    if self.composer.channels:IsShown() then self.composer.channels:Hide()
    else self:CloseComposer() end
end

function chat:SubmitComposer()
    if not self:IsComposerOpen() or self.composerSubmitting then return end
    if self.composer.channels:IsShown() then return end
    local editBox = Input:GetEditBox()
    if not editBox or not editBox:GetText():match('%S') then return end
    if not Input:DestinationAvailable() then
        self:SetComposerStatus('This destination is unavailable. Choose a channel before sending.')
        return
    end
    local handler = Input:GetNativeEnterHandler()
    if not handler then return end
    local draft = Input:CaptureDraft()
    Input:ResetSubmission()
    self.composerSubmitting = true
    -- Sending stays within the hardware-event callback; never defer it to a timer.
    local ok, err = pcall(handler, editBox)
    self.composerSubmitting = false
    if not ok then
        Input:RestoreDraft(draft)
        self:SetComposerStatus('Unable to send. Your draft has been kept.')
        geterrorhandler()(err)
        return
    end
    -- Smart-whisper autocomplete can clear the text when it selects a recipient.
    -- Observe the native send path rather than treating an empty box as a send.
    local submitted, tracked = Input:DidSubmit()
    if tracked and not submitted then Input:Focus(); return end
    if editBox:GetText() ~= '' then return end
    self.composerDraft = nil
    self:CloseComposer(true)
end

function chat:UpdateComposer(elapsed)
    if self.composerSubmitting or self.composerClosing then return end
    Input:KeepComposerLayer()
    if self.composerActive and not Input:HasFocus() then self:SuspendComposer() end
    if not self.composerActive and not self.composer.resumeRequired and Input:HasFocus() then
        self:ResumeComposer()
    end
    if self.composerActive then self:UpdateComposerHeldInput(elapsed) end
    self:UpdateComposerKeyboardPointer()
    self.composer.destination.label:SetText(Input:GetDestinationLabel(true))
end

function chat:OnComposerProfileChanged()
    self:CloseComposer()
    self.composerDraft = nil
    self.quickReplyOptionIndex = 1
    if self.composer then self:RefreshComposerReplies() end
end
