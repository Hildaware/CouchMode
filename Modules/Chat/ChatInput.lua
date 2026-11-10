--[[ ChatInput.lua
Embeds Blizzard's own ChatFrame1EditBox inside the CouchMode Chat panel.

We never replace Blizzard's parser or send path: slash commands, sticky
channels, whispers, language selection, autocomplete, history, item-link
insertion, OPENCHAT and OPENCHATSLASH all keep working because they still run
through the very same edit box. Reparenting is recorded so the frame can be
returned to exactly where it started when Chat is disabled or the addon unloads.
]]

local addonName, addon = ...
local addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)

local Input = {}

local editBox = nil
local saved = nil
local headerHooked = false
local focusBorderHooked = false
local aliasProvider = nil
local composerSaved = nil
local composerSendHooked = false
local composerSubmitted = false
local composerInputShown = nil

--#region ── Helpers ───────────────────────────────────────────────────────────

local function resolveEditBox()
    return _G['ChatFrame1EditBox'] or (ChatFrame1 and ChatFrame1.editBox)
end

local function captureState(frame)
    local mouse
    if frame.IsMouseEnabled then mouse = frame:IsMouseEnabled() end
    local state = {
        parent = frame:GetParent(),
        strata = frame:GetFrameStrata(),
        level = frame:GetFrameLevel(),
        shown = frame:IsShown(),
        mouse = mouse,
        width = frame:GetWidth(),
        height = frame:GetHeight(),
        points = {},
    }
    local count = (frame.GetNumPoints and frame:GetNumPoints()) or 0
    for i = 1, count do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
        state.points[i] = { point, relativeTo, relativePoint, x, y }
    end
    return state
end

local function restoreState(frame, state)
    frame:ClearAllPoints()
    for i = 1, #state.points do
        local p = state.points[i]
        frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
    frame:SetParent(state.parent)
    if state.strata then frame:SetFrameStrata(state.strata) end
    if state.level then frame:SetFrameLevel(state.level) end
    if state.width and state.height then frame:SetSize(state.width, state.height) end
    if state.mouse ~= nil and frame.EnableMouse then frame:EnableMouse(state.mouse) end
    frame:SetShown(state.shown)
end

local function setBordersShown(frame, shown)
    local name = frame:GetName()
    if not name then return end
    for _, suffix in ipairs({ 'Left', 'Right', 'Mid', 'FocusLeft', 'FocusRight', 'FocusMid' }) do
        local tex = _G[name .. suffix]
        if tex and tex.SetShown then tex:SetShown(shown) end
    end
end

--#endregion

--#region ── Input header aliases ──────────────────────────────────────────────

local function installHeaderHook(frame)
    if headerHooked then return end
    headerHooked = true

    hooksecurefunc(frame, 'UpdateHeader', function(self)
        local alias = aliasProvider and aliasProvider()
        if not alias or not self.header then return end
        self.header:SetText(alias)
    end)
end

local function installFocusBorderHook(frame)
    if focusBorderHooked or not frame.SetFocusRegionsShown then return end
    focusBorderHooked = true

    -- Blizzard shows these textures again whenever chat input is activated.
    -- The embedded input uses the Diamond Metal strip as its chrome instead.
    hooksecurefunc(frame, 'SetFocusRegionsShown', function(self)
        if editBox == self then setBordersShown(self, false) end
    end)
end

---@param provider fun(): string?
function Input:SetAliasProvider(provider)
    aliasProvider = provider
end

--#endregion

--#region ── Attach / detach ────────────────────────────────────────────────────

--- Embeds the edit box into `parent`. `anchor` positions it.
---@param parent Frame
---@param anchor Frame  the input strip frame
---@return Frame? editBox
function Input:Attach(parent, anchor)
    local frame = resolveEditBox()
    if not frame then return nil end
    editBox = frame

    if not saved then
        saved = captureState(frame)
    end

    installHeaderHook(frame)
    installFocusBorderHook(frame)
    if not composerSendHooked then
        local function submitted()
            if composerSaved then composerSubmitted = true end
        end
        if type(frame.SendText) == 'function' then
            hooksecurefunc(frame, 'SendText', submitted)
            composerSendHooked = true
        elseif type(ChatEdit_SendText) == 'function' then
            hooksecurefunc('ChatEdit_SendText', function(target)
                if target == editBox then submitted() end
            end)
            composerSendHooked = true
        end
    end

    frame:SetParent(anchor or parent)
    frame:ClearAllPoints()
    frame:SetPoint('TOPLEFT', anchor or parent, 'TOPLEFT', 0, 0)
    frame:SetPoint('BOTTOMRIGHT', anchor or parent, 'BOTTOMRIGHT', 0, 0)
    frame:SetHeight((anchor or parent):GetHeight())
    frame:SetFrameStrata('DIALOG')
    setBordersShown(frame, false)

    return frame
end

--- Restores the edit box to its original parent, anchors, strata and state.
function Input:Detach()
    self:EndComposer()
    local frame = editBox or resolveEditBox()
    if not frame then return end
    setBordersShown(frame, true)
    if saved then
        restoreState(frame, saved)
        saved = nil
    end
    editBox = nil
end

---@return Frame?
function Input:GetEditBox()
    return editBox
end

--- Focuses the input, opening Blizzard chat if necessary.
function Input:Focus()
    local frame = editBox or resolveEditBox()
    if not frame then return end
    if ChatFrameUtil and ChatFrameUtil.ActivateChat then
        ChatFrameUtil.ActivateChat(frame)
    elseif ChatEdit_ActivateChat then
        ChatEdit_ActivateChat(frame)
    else
        frame:Show()
        frame:SetFocus()
    end
    self:KeepComposerLayer()
end

function Input:KeepComposerLayer()
    if not composerSaved or not editBox then return end
    -- ActivateChat always assigns DIALOG and raises the edit box, including
    -- when focus is obtained by clicking instead of through Input:Focus.
    local parent = editBox:GetParent()
    if editBox:GetFrameStrata() ~= parent:GetFrameStrata() then
        editBox:SetFrameStrata(parent:GetFrameStrata())
    end
    if editBox:GetFrameLevel() ~= parent:GetFrameLevel() + 1 then
        editBox:SetFrameLevel(parent:GetFrameLevel() + 1)
    end
end

--- Clears focus and hides the input the way Blizzard would.
function Input:Deactivate()
    local frame = editBox or resolveEditBox()
    if not frame then return end
    if ChatFrameUtil and ChatFrameUtil.DeactivateChat then
        ChatFrameUtil.DeactivateChat(frame)
    elseif ChatEdit_DeactivateChat then
        ChatEdit_DeactivateChat(frame)
    else
        frame:ClearFocus()
    end
end

---@return boolean
function Input:HasFocus()
    local frame = editBox or resolveEditBox()
    return (frame and frame.HasFocus and frame:HasFocus()) or false
end

--- Keeps the inactive embedded edit box from intercepting the live feed.
function Input:SetMouseEnabled(enabled)
    if composerSaved then return end
    local frame = editBox
    if frame and frame.EnableMouse and frame.IsMouseEnabled
        and frame:IsMouseEnabled() ~= (enabled == true) then
        frame:EnableMouse(enabled == true)
    end
end

-- Preserve the embedded input independently of its original Blizzard placement.
function Input:BeginComposer(anchor, onEnter, onEscape)
    if composerSaved or not editBox then return false end
    local frame = editBox
    composerSaved = captureState(frame)
    composerInputShown = nil
    composerSaved.hidekeyboard = frame:GetAttribute('hidekeyboard')
    composerSaved.enter = frame:GetScript('OnEnterPressed')
    composerSaved.escape = frame:GetScript('OnEscapePressed')
    frame:SetAttribute('hidekeyboard', true)
    -- Its observer only reacts when the focused frame changes. Explicitly
    -- dismiss a keyboard that already owns this same edit box.
    if ConsolePortKeyboard and ConsolePortKeyboard.focusFrame == frame
        and ConsolePortKeyboard.OnFocusChanged then
        ConsolePortKeyboard:OnFocusChanged(nil)
    end
    frame:SetParent(anchor)
    frame:ClearAllPoints()
    frame:SetPoint('TOPLEFT', anchor, 'TOPLEFT', 8, -4)
    frame:SetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT', -8, 4)
    frame:SetFrameStrata(anchor:GetFrameStrata())
    frame:SetFrameLevel(anchor:GetFrameLevel() + 1)
    frame:EnableMouse(true)
    frame:SetScript('OnEnterPressed', onEnter)
    frame:SetScript('OnEscapePressed', onEscape)
    return true
end

-- Non-keyboard composer pages keep the draft but release native text focus.
function Input:SetComposerInputShown(shown)
    if not composerSaved or not editBox or composerInputShown == shown then return end
    composerInputShown = shown
    local draft = self:CaptureDraft()
    if not shown then self:Deactivate() end
    editBox:GetParent():SetShown(shown)
    -- Native deactivation and OnShow can change text and the sticky channel.
    self:RestoreDraft(draft)
end

function Input:GetNativeEnterHandler()
    return composerSaved and composerSaved.enter
end

function Input:ResetSubmission()
    composerSubmitted = false
end

function Input:DidSubmit()
    return composerSubmitted, composerSendHooked
end

function Input:EndComposer()
    if not composerSaved or not editBox then return end
    local frame, state = editBox, composerSaved
    composerSaved = nil
    composerInputShown = nil
    frame:SetScript('OnEnterPressed', state.enter)
    frame:SetScript('OnEscapePressed', state.escape)
    frame:SetAttribute('hidekeyboard', state.hidekeyboard)
    restoreState(frame, state)
end

if addon then addon.ChatInput = Input end
return Input
