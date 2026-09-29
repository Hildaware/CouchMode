--[[ ChatHistory.lua
The full-screen, controller-readable view of the accepted chat session.
It owns a second ChatFeed, so opening it never reparents or resizes live chat.
]]

local addonName, addon = ...
local chat = addon.Chat
local Sources = addon.ChatSources
local Input = addon.ChatInput

local FONT_SCALE = 1.25
local MAX_COLUMN_WIDTH = 1400
local COLUMN_FRACTION = 0.84
local WINDOW_INSET = 24
local WINDOW_TOP_MARGIN = 32
local WINDOW_BOTTOM_MARGIN = 12
local LEGEND_GAP = 12
local HEADER_HEIGHT = 112
local BOTTOM_MARGIN = WINDOW_INSET + 8
local ACTION_ROWS = 8
local HOLD_DELAY = 0.38
local HOLD_INTERVAL = 0.11
local OVERSIZED_STEP = 0.72
local HISTORY_FADE_DURATION = 0.25

local function db() return addon.db.profile.chat end

local function nativeGamepadEnabled()
    return _G.InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
        and _G.GamepadMode and GamepadMode.FrameControlsManager and _G.SmartNavigation
        and GamepadMode.CreateBindingGroup and GamepadMode.ActivateBindingGroup
end

local function callManager(method, manager, frame, popup)
    if not method then return end
    if securecallfunction then
        securecallfunction(method, manager, frame, popup)
    else
        method(manager, frame, popup)
    end
end

local function callGamepadBinding(method, group)
    if not method or not group then return end
    if securecallfunction then securecallfunction(method, group)
    else method(group) end
end

chat.historyFrame = nil
chat.historyFeed = nil
chat.historyFilterBtns = {}
chat.historySelection = nil
chat.historyHighlight = nil
chat.historyActions = nil
chat.historyActionIndex = 1
chat.historyActionFirst = 1
chat.historyHeldDirection = nil
chat.historyHoldRemaining = 0
chat.historyCopyOpen = false
chat.historyNativeBindings = nil
chat.historyNativeActive = false
chat.historySelectionRequest = 0
chat.historyStatusRequest = 0
chat.historyLegend = nil
chat.historyArea = nil
chat.historyFadeAnimation = nil
chat.historyClosing = false

local function fadeHistory(chatModule, targetAlpha, onComplete)
    if chatModule.historyFadeAnimation then
        chatModule.historyFadeAnimation:Cancel()
        chatModule.historyFadeAnimation = nil
    end

    chatModule.historyFadeAnimation = addon.Animations.FadeTo(
        chatModule.historyFrame,
        targetAlpha,
        HISTORY_FADE_DURATION,
        function()
            chatModule.historyFadeAnimation = nil
            if onComplete then onComplete() end
        end
    )
end

function chat:IsHistoryModeOpen()
    return self.historyFrame and self.historyFrame:IsShown() or false
end

function chat:SetHistoryStatus(message)
    self.historyStatusRequest = self.historyStatusRequest + 1
    if not self.historyStatus then return end
    self.historyStatus:SetText(message or '')
    if message and message ~= '' and C_Timer then
        local request = self.historyStatusRequest
        C_Timer.After(2.5, function()
            if chat.historyStatusRequest == request and chat.historyStatus then
                chat.historyStatus:SetText('')
            end
        end)
    end
end

function chat:RefreshHistoryLegend()
    if not self.historyLegend then return end
    local previousHeight = self.historyLegend:GetHeight()
    self.historyLegend:Refresh()
    if self:IsHistoryModeOpen() and math.abs(self.historyLegend:GetHeight() - previousHeight) > 1 then
        self:ApplyHistoryLayout()
    end
end

function chat:RefreshHistoryFilters()
    for key, button in pairs(self.historyFilterBtns) do
        local active = key == (db().filter or 'ALL')
        if active then
            button.label:SetTextColor(1, 0.82, 0, 1)
        else
            button.label:SetTextColor(0.65, 0.65, 0.65, 1)
        end
    end
end

function chat:HistoryFilterChanged()
    self:RefreshHistoryFilters()
    if not self:IsHistoryModeOpen() then return end
    self:CloseHistoryActions()
    self:HistoryToBottom()
end

function chat:UpdateHistoryScrollBar()
    local track, feed = self.historyScrollTrack, self.historyFeed
    if not track or not feed then return end
    local range = feed.scrollFrame:GetVerticalScrollRange() or 0
    track:SetShown(range > 1)
    if range <= 1 then return end
    local height = track:GetHeight() or 0
    if height <= 0 then return end
    local viewport = feed.viewportHeight or feed.scrollFrame:GetHeight() or 0
    local thumbHeight = math.min(height, math.max(30, height * viewport / (viewport + range)))
    local travel = height - thumbHeight
    local offset = math.max(0, math.min(feed:GetScrollOffset(), range))
    track.thumb:SetHeight(thumbHeight)
    track.thumb:ClearAllPoints()
    track.thumb:SetPoint('TOPLEFT', track, 'TOPLEFT', 0, -(offset / range) * travel)
    track.thumb:SetPoint('TOPRIGHT', track, 'TOPRIGHT', 0, -(offset / range) * travel)
end

function chat:ClearHistoryHighlight()
    if self.historyHighlight then self.historyHighlight:Hide() end
    self.historyHighlight = nil
end

function chat:ShowHistoryHighlight()
    self:ClearHistoryHighlight()
    local selected = self.historySelection
    local widget = selected and self.historyFeed and self.historyFeed.widgets[selected.group]
    local line = widget and widget.lines[selected.message]
    if not line or not line:IsShown() then return end
    if not widget.historyHighlight then
        local highlight = widget:CreateTexture(nil, 'BACKGROUND', nil, 1)
        highlight:SetColorTexture(0.22, 0.52, 0.68, 0.36)
        widget.historyHighlight = highlight
    end
    local highlight = widget.historyHighlight
    highlight:ClearAllPoints()
    highlight:SetPoint('TOPLEFT', line, 'TOPLEFT', -5, 4)
    highlight:SetPoint('BOTTOMRIGHT', line, 'BOTTOMRIGHT', 5, -4)
    highlight:Show()
    self.historyHighlight = highlight
end

local function historyLine(chatModule)
    local selected = chatModule.historySelection
    local widget = selected and chatModule.historyFeed and chatModule.historyFeed.widgets[selected.group]
    return widget and widget.lines[selected.message]
end

function chat:ScrollHistorySelectionIntoView(direction)
    local line = historyLine(self)
    local viewport = self.historyFeed and self.historyFeed.scrollFrame
    if not line or not viewport then return end
    local top, bottom = line:GetTop(), line:GetBottom()
    local viewTop, viewBottom = viewport:GetTop(), viewport:GetBottom()
    if not top or not bottom or not viewTop or not viewBottom then return end
    local padding = 10
    local height = viewTop - viewBottom - padding * 2
    local delta
    if top - bottom > height then
        if direction < 0 then
            delta = bottom > viewBottom + padding and bottom - (viewBottom + padding) or nil
        else
            delta = top < viewTop - padding and top - (viewTop - padding) or nil
        end
    elseif top > viewTop - padding then
        delta = top - (viewTop - padding)
    elseif bottom < viewBottom + padding then
        delta = -(viewBottom + padding - bottom)
    end
    if delta and math.abs(delta) > 0.5 then self.historyFeed:ScrollBy(delta) end
end

function chat:SetHistorySelection(groupIndex, messageIndex, direction)
    self.historySelectionRequest = self.historySelectionRequest + 1
    local group = self.groups[groupIndex]
    local message = group and group.messages[messageIndex]
    if not message then
        self.historySelection = nil
        self:ClearHistoryHighlight()
        self:RefreshHistoryLegend()
        return
    end
    self.historySelection = { group = groupIndex, message = messageIndex, value = message }
    self:RefreshHistoryLegend()
    self:ShowHistoryHighlight()
    if direction then
        self:ScrollHistorySelectionIntoView(direction)
        if C_Timer then
            local request = self.historySelectionRequest
            C_Timer.After(0, function()
                if chat.historySelectionRequest == request and chat:IsHistoryModeOpen() then
                    chat:ScrollHistorySelectionIntoView(direction)
                    chat:ShowHistoryHighlight()
                end
            end)
        end
    end
end

function chat:SelectNewestHistoryMessage()
    for groupIndex = #self.groups, 1, -1 do
        local messages = self.groups[groupIndex].messages
        if #messages > 0 then
            self:SetHistorySelection(groupIndex, #messages)
            return
        end
    end
    self:SetHistorySelection(0, 0)
end

function chat:MoveHistorySelection(direction)
    if not self:IsHistoryModeOpen() then return end
    if self.historyActions then
        self:MoveHistoryAction(direction)
        return
    end
    if self.historyCopyOpen then return end
    local selected = self.historySelection
    if not selected then
        self:SelectNewestHistoryMessage()
        return
    end

    -- A single message may be taller than the viewport. Reveal all of it
    -- before moving to its neighbor so controller readers cannot skip text.
    local line = historyLine(self)
    local viewport = self.historyFeed.scrollFrame
    local top, bottom = line and line:GetTop(), line and line:GetBottom()
    local viewTop, viewBottom = viewport:GetTop(), viewport:GetBottom()
    if top and bottom and viewTop and viewBottom then
        local remaining = direction < 0 and (top - viewTop + 10) or (viewBottom + 10 - bottom)
        if remaining > 2 and top - bottom > viewTop - viewBottom - 20 then
            self.historyFeed:ScrollBy(direction < 0
                and math.min(remaining, (viewTop - viewBottom) * OVERSIZED_STEP)
                or -math.min(remaining, (viewTop - viewBottom) * OVERSIZED_STEP))
            return
        end
    end

    local groupIndex, messageIndex = selected.group, selected.message + direction
    if direction < 0 and messageIndex < 1 then
        groupIndex = groupIndex - 1
        while groupIndex >= 1 and #self.groups[groupIndex].messages == 0 do
            groupIndex = groupIndex - 1
        end
        messageIndex = self.groups[groupIndex] and #self.groups[groupIndex].messages or 0
    elseif direction > 0 and messageIndex > #self.groups[groupIndex].messages then
        groupIndex = groupIndex + 1
        while groupIndex <= #self.groups and #self.groups[groupIndex].messages == 0 do
            groupIndex = groupIndex + 1
        end
        messageIndex = 1
    end
    if self.groups[groupIndex] and self.groups[groupIndex].messages[messageIndex] then
        self:SetHistorySelection(groupIndex, messageIndex, direction)
    end
end

function chat:HistoryToBottom()
    if not self.historyFeed then return end
    self:SelectNewestHistoryMessage()
    self.historyFeed:ScrollToBottom(true)
    self:UpdateHistoryScrollBar()
end

function chat:HistoryShouldFollowBottom()
    if not self:IsHistoryModeOpen() or not self.historyFeed or not self.historyFeed:IsAtBottom() then
        return false
    end
    local lastGroup = self.groups[#self.groups]
    local lastMessage = lastGroup and lastGroup.messages[#lastGroup.messages]
    return not lastMessage or (self.historySelection and self.historySelection.value == lastMessage) or false
end

function chat:HistoryAppendGroup(group, followBottom)
    if not self:IsHistoryModeOpen() then return end
    self.historyFeed:AppendGroup(group, followBottom)
    if followBottom then self:SelectNewestHistoryMessage() end
    self:RefreshHistoryEmptyState()
    self:RefreshHistoryLegend()
    self:UpdateHistoryScrollBar()
end

function chat:HistoryRefreshLastGroup(group, followBottom)
    if not self:IsHistoryModeOpen() then return end
    self.historyFeed:RefreshLastGroup(group, followBottom)
    if followBottom then self:SelectNewestHistoryMessage() end
    self:RefreshHistoryLegend()
    self:UpdateHistoryScrollBar()
end

function chat:RebuildHistoryView(groups)
    if not self:IsHistoryModeOpen() then return end
    local previous = self.historySelection and self.historySelection.value
    local offset = self.historyFeed:GetScrollOffset()
    local followBottom = self.historyFeed:IsAtBottom()
    self:ClearHistoryHighlight()
    self.historyFeed:SetFonts(self:FontMetrics(FONT_SCALE))
    self.historyFeed:Rebuild(groups)
    local found
    if previous then
        for i, group in ipairs(groups) do
            for j, msg in ipairs(group.messages) do
                if msg == previous then found = { i, j }; break end
            end
            if found then break end
        end
    end
    if found then self:SetHistorySelection(found[1], found[2])
    else self:SelectNewestHistoryMessage() end
    if followBottom then self.historyFeed:ScrollToBottom(true)
    else self.historyFeed:RestoreScrollOffset(offset) end
    self:RefreshHistoryEmptyState()
    self:UpdateHistoryScrollBar()
end

function chat:ClearHistoryView()
    if not self.historyFeed then return end
    self:CloseHistoryActions()
    self:ClearHistoryHighlight()
    self.historySelection = nil
    self.historyFeed:Clear()
    self:RefreshHistoryEmptyState()
    self:RefreshHistoryLegend()
    self:UpdateHistoryScrollBar()
end

function chat:RefreshHistoryEmptyState()
    if self.historyEmpty then self.historyEmpty:SetShown(#self.groups == 0) end
end

function chat:ApplyHistoryLayout()
    if not self.historyFrame then return end
    local width = math.min(MAX_COLUMN_WIDTH, self.historyFrame:GetWidth() * COLUMN_FRACTION)
    self.historyLegend:SetMaxWidth(width - 2 * WINDOW_INSET)
    local height = math.max(180, self.historyFrame:GetHeight() - WINDOW_TOP_MARGIN
        - self.historyLegend:GetHeight() - LEGEND_GAP
        - addon.Components.Metal.BORDER_OUTSET - WINDOW_BOTTOM_MARGIN)
    self.historyColumn:SetSize(width, height)
    local filterWidth = math.max(30, math.min(100,
        (width - 2 * WINDOW_INSET - 24 - (#Sources.FILTERS - 1) * 4) / #Sources.FILTERS))
    for _, filter in ipairs(Sources.FILTERS) do
        self.historyFilterBtns[filter.key]:SetWidth(filterWidth)
    end
    self.historyActionPanel:SetWidth(math.min(560, math.max(280, width - 2 * WINDOW_INSET - 32)))
    self.historyArea:ClearAllPoints()
    self.historyArea:SetPoint('TOPLEFT', self.historyColumn, 'TOPLEFT', WINDOW_INSET, -HEADER_HEIGHT)
    self.historyArea:SetPoint('BOTTOMRIGHT', self.historyColumn, 'BOTTOMRIGHT', -WINDOW_INSET - 18, BOTTOM_MARGIN)
    local viewportHeight = math.max(40, height - HEADER_HEIGHT - BOTTOM_MARGIN)
    local feedWidth = math.max(100, width - 2 * WINDOW_INSET - 32)
    local widthChanged = self.historyFeed.width ~= feedWidth
    local offset = self.historyFeed:GetScrollOffset()
    local followBottom = self.historyFeed:IsAtBottom()
    self.historyFeed:SetWidth(feedWidth)
    self.historyFeed:SetViewportHeight(viewportHeight)
    if widthChanged and #self.historyFeed.groups > 0 then
        self:RebuildHistoryView(self.groups)
        if not followBottom then self.historyFeed:RestoreScrollOffset(offset) end
    end
    self:UpdateHistoryScrollBar()
end

function chat:CloseHistoryActions()
    self.historyActions = nil
    if self.historyActionPanel then self.historyActionPanel:Hide() end
    self:RefreshHistoryLegend()
end

function chat:RenderHistoryActions()
    local actions = self.historyActions
    if not actions then return end
    local first = math.max(1, math.min(self.historyActionFirst,
        math.max(1, #actions - ACTION_ROWS + 1)))
    self.historyActionFirst = first
    local rows = math.min(ACTION_ROWS, #actions)
    self.historyActionPanel:SetHeight(72 + rows * 30)
    for row, button in ipairs(self.historyActionButtons) do
        local index = first + row - 1
        local action = actions[index]
        button:SetShown(action ~= nil and row <= rows)
        if action then
            button.actionIndex = index
            button.label:SetText(action.label)
            local selected = index == self.historyActionIndex
            if selected then
                button.label:SetTextColor(1, 0.82, 0)
                button.bg:SetColorTexture(0.35, 0.25, 0.08, 0.55)
            else
                button.label:SetTextColor(0.9, 0.9, 0.9)
                button.bg:SetColorTexture(0, 0, 0, 0)
            end
        end
    end
    self.historyActionCount:SetText(('%d / %d'):format(self.historyActionIndex, #actions))
end

function chat:MoveHistoryAction(direction)
    if not self.historyActions then return end
    self.historyActionIndex = math.max(1,
        math.min(#self.historyActions, self.historyActionIndex + direction))
    if self.historyActionIndex < self.historyActionFirst then
        self.historyActionFirst = self.historyActionIndex
    elseif self.historyActionIndex >= self.historyActionFirst + ACTION_ROWS then
        self.historyActionFirst = self.historyActionIndex - ACTION_ROWS + 1
    end
    self:RenderHistoryActions()
end

function chat:RunHistoryAction(index)
    local action = self.historyActions and self.historyActions[index]
    if not action then return end
    self:CloseHistoryActions()
    action.run()
end

function chat:OpenHistoryActions()
    if self.historyCopyOpen then return end
    local message = self.historySelection and self.historySelection.value
    if not message then return end
    self.historyActions = self:BuildMessageActions(message, true)
    self.historyActionIndex = 1
    self.historyActionFirst = 1
    self.historyActionPanel:Show()
    self:RenderHistoryActions()
    self:RefreshHistoryLegend()
end

function chat:HistoryCopyDialogOpened()
    self.historyCopyOpen = true
    self:RefreshHistoryLegend()
end

function chat:HistoryCopyDialogClosed()
    self.historyCopyOpen = false
    self:RefreshHistoryLegend()
end

function chat:HistoryGamepadButton(key, isDown)
    if not self:IsHistoryModeOpen() then return false end
    if key == 'PADDUP' or key == 'PADDDOWN' then
        if isDown then
            local direction = key == 'PADDUP' and -1 or 1
            self:MoveHistorySelection(direction)
            self.historyHeldDirection = direction
            self.historyHoldRemaining = HOLD_DELAY
        elseif self.historyHeldDirection == (key == 'PADDUP' and -1 or 1) then
            self.historyHeldDirection = nil
        end
        return true
    end
    if not isDown then return key == 'PADLSHOULDER' or key == 'PADRSHOULDER'
        or key == 'PAD1' or key == 'PAD2' end
    if key == 'PADLSHOULDER' then
        if not self.historyActions and not self.historyCopyOpen then self:CycleFilter(-1) end
    elseif key == 'PADRSHOULDER' then
        if not self.historyActions and not self.historyCopyOpen then self:CycleFilter(1) end
    elseif key == 'PAD1' then
        if self.historyActions then self:RunHistoryAction(self.historyActionIndex)
        elseif not self.historyCopyOpen then self:OpenHistoryActions() end
    elseif key == 'PAD2' then
        if self.historyCopyOpen and self.copyDialog then self.copyDialog:Hide()
        elseif self.historyActions then self:CloseHistoryActions()
        else self:CloseHistoryMode() end
    else
        return false
    end
    return true
end

function chat:UpdateHistoryHold(elapsed)
    if not self.historyHeldDirection then return end
    self.historyHoldRemaining = self.historyHoldRemaining - elapsed
    if self.historyHoldRemaining > 0 then return end
    self.historyHoldRemaining = HOLD_INTERVAL
    self:MoveHistorySelection(self.historyHeldDirection)
end

function chat:RefreshHistoryNativeFocus()
    local manager = _G.GamepadMode and GamepadMode.FrameControlsManager
    local focused = manager and manager.isUIFocused and manager.GetActiveFrame
        and manager:GetActiveFrame() == self.historyFrame
    if focused == self.historyNativeActive then return end
    if focused and self.historyNativeBindings then
        callGamepadBinding(GamepadMode.ActivateBindingGroup, self.historyNativeBindings)
        self.historyNativeActive = true
        self.historyLegend:Show()
        self:ApplyHistoryLayout()
    elseif self.historyNativeActive then
        self.historyLegend:Hide()
        callGamepadBinding(GamepadMode.DeactivateBindingGroup, self.historyNativeBindings)
        self.historyNativeActive = false
        self.historyHeldDirection = nil
    end
end

function chat:CreateHistoryNativeBindings()
    if self.historyNativeBindings or not nativeGamepadEnabled() then return end
    local group = GamepadMode.CreateBindingGroup('CouchModeChatHistory')
    for _, key in ipairs({ 'PADDUP', 'PADDDOWN' }) do
        local buttonKey = key
        group:AddFunctionBinding(buttonKey, function(isDown)
            chat:HistoryGamepadButton(buttonKey, isDown)
        end, GAMEPAD_BUTTON_ANY_DOWN_OR_UP)
    end
    for _, key in ipairs({ 'PADLSHOULDER', 'PADRSHOULDER', 'PAD1', 'PAD2' }) do
        local buttonKey = key
        group:AddFunctionBinding(buttonKey, function() chat:HistoryGamepadButton(buttonKey, true) end)
    end
    self.historyNativeBindings = group
end

function chat:ActivateHistoryController()
    local frame = self.historyFrame
    if nativeGamepadEnabled() then
        self:CreateHistoryNativeBindings()
        frame.useCustomNavigation = true
        if _G.EventRegistry then
            EventRegistry:RegisterCallback('Gamepad.RefreshFrameFocus', self.RefreshHistoryNativeFocus, self)
        end
        local manager = GamepadMode.FrameControlsManager
        callManager(manager.FrameShown, manager, frame, true)
        self:RefreshHistoryNativeFocus()
    elseif _G.ConsolePort and _G.ConsolePortInputHandler and not InCombatLockdown() then
        for _, key in ipairs({ 'PADDUP', 'PADDDOWN', 'PADLSHOULDER',
            'PADRSHOULDER', 'PAD1', 'PAD2' }) do
            ConsolePortInputHandler:SetCommand(key, frame, true, 'LeftButton', 'UIControl', nil)
        end
    end
    if not nativeGamepadEnabled() then
        self.historyLegend:Show()
        self:ApplyHistoryLayout()
    end
end

function chat:DeactivateHistoryController()
    self.historyHeldDirection = nil
    if self.historyLegend then self.historyLegend:Hide() end
    if self.historyNativeActive and self.historyNativeBindings then
        callGamepadBinding(GamepadMode.DeactivateBindingGroup, self.historyNativeBindings)
        self.historyNativeActive = false
    end
    if _G.EventRegistry then EventRegistry:UnregisterCallback('Gamepad.RefreshFrameFocus', self) end
    local manager = _G.GamepadMode and GamepadMode.FrameControlsManager
    if manager and manager.FrameHidden then callManager(manager.FrameHidden, manager, self.historyFrame) end
    if _G.ConsolePortInputHandler then ConsolePortInputHandler:Release(self.historyFrame) end
end

function chat:BuildHistoryMode()
    if self.historyFrame then return end
    local frame = CreateFrame('Frame', 'CouchModeChatHistory', UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata('FULLSCREEN_DIALOG')
    frame:EnableMouse(true)
    if frame.EnableKeyboard then frame:EnableKeyboard(true) end
    if frame.EnableGamePadButton then frame:EnableGamePadButton(true) end
    if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end
    if not InCombatLockdown() then
        if frame.SetPropagateMouseClicks then frame:SetPropagateMouseClicks(false) end
        if frame.SetPropagateMouseMotion then frame:SetPropagateMouseMotion(false) end
    end
    frame:Hide()
    frame.useCustomNavigation = true
    frame.SmartNavigationCloseHandler = function()
        chat:CloseHistoryMode()
        return true
    end
    table.insert(UISpecialFrames, frame:GetName())

    -- This transparent button covers the entire screen and consumes empty-area
    -- mouse input, preventing clicks and hover from reaching the game UI below.
    local blocker = CreateFrame('Button', nil, frame)
    blocker:SetAllPoints(frame)
    blocker:SetFrameLevel(frame:GetFrameLevel() + 1)
    blocker:EnableMouse(true)
    blocker:EnableMouseWheel(true)
    if blocker.EnableMouseMotion and not InCombatLockdown() then blocker:EnableMouseMotion(true) end
    blocker:RegisterForClicks('AnyDown', 'AnyUp')
    blocker:SetScript('OnClick', function()
        if chat.historyActionPanel and chat.historyActionPanel:IsShown() then
            chat:CloseHistoryActions()
        end
    end)
    blocker:SetScript('OnMouseDown', function() end)
    blocker:SetScript('OnMouseUp', function() end)
    blocker:SetScript('OnMouseWheel', function() end)
    blocker:SetScript('OnEnter', function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    if not InCombatLockdown() then
        if blocker.SetPropagateMouseClicks then blocker:SetPropagateMouseClicks(false) end
        if blocker.SetPropagateMouseMotion then blocker:SetPropagateMouseMotion(false) end
    end
    self.historyMouseBlocker = blocker

    local column = CreateFrame('Frame', nil, frame)
    column:SetPoint('TOP', frame, 'TOP', 0, -WINDOW_TOP_MARGIN)
    column:SetFrameLevel(frame:GetFrameLevel() + 2)
    local background = column:CreateTexture(nil, 'BACKGROUND')
    background:SetAllPoints(column)
    background:SetColorTexture(0, 0, 0, 0.65)
    column.background = background
    self.historyColumn = column

    local borderFrame = CreateFrame('Frame', nil, frame)
    borderFrame:SetFrameStrata(frame:GetFrameStrata())
    borderFrame:SetFrameLevel(column:GetFrameLevel() + 20)
    borderFrame:EnableMouse(false)
    addon.Components.Metal.PositionBorderFrame(
        borderFrame, column, addon.Components.Metal.BORDER_OUTSET)
    local borders = addon.Components.Metal.CreateBorderTextures(borderFrame, borderFrame)
    addon.Components.Metal.ApplyBorderTextures(
        borders, true, 1, 1, 1, 1, addon.Components.Metal.BORDER_SIZE)
    self.historyBorderFrame = borderFrame
    self.historyBorders = borders

    local title = column:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
    title:SetPoint('TOPLEFT', column, 'TOPLEFT', WINDOW_INSET, -20)
    title:SetText('Chat History')

    local filterBar = CreateFrame('Frame', nil, column)
    filterBar:SetPoint('TOPLEFT', column, 'TOPLEFT', WINDOW_INSET, -58)
    filterBar:SetPoint('TOPRIGHT', column, 'TOPRIGHT', -WINDOW_INSET, -58)
    filterBar:SetHeight(34)
    addon.Components.Metal.CreateHeader(filterBar)
    local previous
    for _, filter in ipairs(Sources.FILTERS) do
        local button = CreateFrame('Button', nil, filterBar)
        button:SetSize(100, 30)
        if previous then button:SetPoint('LEFT', previous, 'RIGHT', 4, 0)
        else button:SetPoint('LEFT', filterBar, 'LEFT', 12, 0) end
        button:RegisterForClicks('LeftButtonUp')
        button:SetScript('OnClick', function() chat:SetFilter(filter.key) end)
        local label = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
        label:SetPoint('CENTER')
        label:SetText(filter.label)
        button.label = label
        button:SetScript('OnEnter', function() label:SetTextColor(1, 1, 1, 1) end)
        button:SetScript('OnLeave', function() chat:RefreshHistoryFilters() end)
        self.historyFilterBtns[filter.key] = button
        previous = button
    end

    local area = CreateFrame('Frame', nil, column)
    area:SetPoint('TOPLEFT', column, 'TOPLEFT', WINDOW_INSET, -HEADER_HEIGHT)
    area:SetPoint('BOTTOMRIGHT', column, 'BOTTOMRIGHT', -WINDOW_INSET - 18, BOTTOM_MARGIN)
    area:EnableMouse(true)
    self.historyArea = area
    local feed = addon.ChatFeedProto.New(area, { historyOnly = true })
    feed:SetFonts(self:FontMetrics(FONT_SCALE))
    feed:SetCompactMode(false)
    feed.onScrollChanged = function() chat:UpdateHistoryScrollBar() end
    self.historyFeed = feed

    local track = CreateFrame('Frame', nil, column)
    track:SetWidth(7)
    track:SetPoint('TOPLEFT', area, 'TOPRIGHT', 5, 0)
    track:SetPoint('BOTTOMLEFT', area, 'BOTTOMRIGHT', 5, 0)
    track:EnableMouse(true)
    local trackBg = track:CreateTexture(nil, 'BACKGROUND')
    trackBg:SetAllPoints(track)
    trackBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    local thumb = track:CreateTexture(nil, 'ARTWORK')
    thumb:SetColorTexture(0.9, 0.9, 0.9, 1)
    track.thumb = thumb
    track:SetScript('OnMouseDown', function(self)
        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local top = self:GetTop() * scale
        local fraction = math.max(0, math.min(1, (top - cursorY) / (self:GetHeight() * scale)))
        local range = feed.scrollFrame:GetVerticalScrollRange() or 0
        feed.scrollFrame:SetVerticalScroll(range * fraction)
        chat:UpdateHistoryScrollBar()
    end)
    self.historyScrollTrack = track

    local empty = column:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
    empty:SetPoint('CENTER', area, 'CENTER')
    empty:SetText('No chat messages yet')
    empty:SetTextColor(0.7, 0.7, 0.7, 1)
    self.historyEmpty = empty

    local status = column:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    status:SetPoint('TOPRIGHT', column, 'TOPRIGHT', -WINDOW_INSET, -22)
    status:SetText('')
    self.historyStatus = status

    self.historyLegend = addon.Components.GamepadLegend.Create(column, {
        name = 'CouchModeChatHistoryLegend',
        x = WINDOW_INSET,
        gap = LEGEND_GAP,
        prompts = {
            {
                keys = { 'PAD1' },
                label = function() return chat.historyActions and 'Select' or 'Actions' end,
                show = function()
                    return not chat.historyCopyOpen
                        and (chat.historyActions ~= nil or chat.historySelection ~= nil)
                end,
            },
            {
                keys = { 'DIRPADVERTICAL' },
                label = function() return chat.historyActions and 'Actions' or 'Messages' end,
                show = function()
                    return not chat.historyCopyOpen
                        and (chat.historyActions ~= nil or chat.historySelection ~= nil or #chat.groups > 0)
                end,
            },
            {
                keys = { 'PADLSHOULDER', 'PADRSHOULDER' },
                label = 'Filters',
                show = function() return not chat.historyActions and not chat.historyCopyOpen end,
            },
            {
                keys = { 'PAD2' },
                label = function() return chat.historyActions and 'Back' or 'Close' end,
            },
        },
    })

    local actionPanel = CreateFrame('Frame', nil, frame, 'PortraitFrameFlatTemplate')
    actionPanel:SetSize(560, 300)
    actionPanel:SetPoint('CENTER', frame, 'CENTER')
    actionPanel:SetFrameStrata('FULLSCREEN_DIALOG')
    actionPanel:SetFrameLevel(frame:GetFrameLevel() + 30)
    actionPanel:EnableMouse(true)
    actionPanel:Hide()
    if not actionPanel.TitleText and actionPanel.TitleContainer then
        actionPanel.TitleText = actionPanel.TitleContainer.TitleText
    end
    if actionPanel.SetTitle then
        actionPanel:SetTitle('Message actions')
    elseif actionPanel.TitleText then
        actionPanel.TitleText:SetText('Message actions')
    end
    if actionPanel.SetPortraitToAsset then
        actionPanel:SetPortraitToAsset('Interface\\Icons\\INV_Misc_Note_02')
    end
    if actionPanel.CloseButton then actionPanel.CloseButton:Hide() end
    local actionCount = actionPanel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    actionCount:SetPoint('TOPRIGHT', actionPanel, 'TOPRIGHT', -16, -36)
    self.historyActionCount = actionCount
    self.historyActionButtons = {}
    for i = 1, ACTION_ROWS do
        local button = CreateFrame('Button', nil, actionPanel)
        button:SetHeight(28)
        button:SetPoint('TOPLEFT', actionPanel, 'TOPLEFT', 14, -54 - (i - 1) * 30)
        button:SetPoint('TOPRIGHT', actionPanel, 'TOPRIGHT', -14, -54 - (i - 1) * 30)
        button:RegisterForClicks('LeftButtonUp')
        button:SetScript('OnClick', function(self) chat:RunHistoryAction(self.actionIndex) end)
        button:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight', 'ADD')
        local bg = button:CreateTexture(nil, 'BACKGROUND')
        bg:SetAllPoints(button)
        button.bg = bg
        local label = button:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
        label:SetPoint('LEFT', button, 'LEFT', 8, 0)
        label:SetPoint('RIGHT', button, 'RIGHT', -8, 0)
        label:SetJustifyH('LEFT')
        label:SetWordWrap(false)
        button.label = label
        self.historyActionButtons[i] = button
    end
    self.historyActionPanel = actionPanel

    frame:SetScript('OnUpdate', function(_, elapsed) chat:UpdateHistoryHold(elapsed) end)
    frame:HookScript('OnShow', function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame:SetScript('OnHide', function() chat:HistoryOnHide() end)
    frame:SetScript('OnKeyDown', function(self, key)
        if key == 'ESCAPE' then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            chat:CloseHistoryMode()
        elseif self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end)
    if frame.EnableGamePadButton then
        frame:SetScript('OnGamePadButtonDown', function(self, key)
            if chat.historyNativeActive then return end
            local handled = chat:HistoryGamepadButton(key, true)
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(not handled) end
        end)
        frame:SetScript('OnGamePadButtonUp', function(self, key)
            if chat.historyNativeActive then return end
            chat:HistoryGamepadButton(key, false)
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        end)
    end

    self.historyFrame = frame
    self:RefreshHistoryFilters()
    self:ApplyHistoryLayout()
    self:RefreshHistoryEmptyState()
end

function chat:OpenHistoryMode()
    if not db().enabled or not self.panel then return end
    if self:IsHistoryModeOpen() then
        if self.historyClosing then
            self.historyClosing = false
            fadeHistory(self, 1)
        end
        return
    end
    self:BuildHistoryMode()
    Input:Deactivate()
    self.historyFeed:SetFonts(self:FontMetrics(FONT_SCALE))
    if self.historyFrame.SetPropagateKeyboardInput then
        self.historyFrame:SetPropagateKeyboardInput(true)
    end
    self.historyClosing = false
    self.historyFrame:SetAlpha(0)
    self.historyFrame:Show()
    self:ApplyHistoryLayout()
    self.historyFeed:Rebuild(self.groups)
    self:HistoryToBottom()
    self:RefreshHistoryFilters()
    self:RefreshHistoryEmptyState()
    self:SetHistoryStatus('')
    self:ActivateHistoryController()
    fadeHistory(self, 1)
end

function chat:HistoryOnHide()
    self.historyClosing = false
    if self.historyFadeAnimation then
        self.historyFadeAnimation:Cancel()
        self.historyFadeAnimation = nil
    end
    if self.historyFrame then self.historyFrame:SetAlpha(1) end
    self.historySelectionRequest = self.historySelectionRequest + 1
    self:CloseHistoryActions()
    if self.copyDialog and self.historyCopyOpen then self.copyDialog:Hide() end
    self:DeactivateHistoryController()
    self:ClearHistoryHighlight()
    self.historySelection = nil
    if self.feed then self.feed:ScrollToBottom() end
    self:ApplyLayout()
    self:OnFeedChanged()
end

function chat:CloseHistoryMode()
    local frame = self.historyFrame
    if not frame or not frame:IsShown() or self.historyClosing then return end
    self.historyClosing = true
    fadeHistory(self, 0, function()
        if self.historyFrame == frame and self.historyClosing and frame:IsShown() then
            frame:Hide()
        end
    end)
end

function chat:ToggleHistoryMode()
    if self:IsHistoryModeOpen() then
        if self.historyClosing then self:OpenHistoryMode()
        else self:CloseHistoryMode() end
    else self:OpenHistoryMode() end
end
