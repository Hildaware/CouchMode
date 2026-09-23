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

--#region ── Helpers ───────────────────────────────────────────────────────────

local function resolveEditBox()
    return _G['ChatFrame1EditBox'] or (ChatFrame1 and ChatFrame1.editBox)
end

local function captureState(frame)
    local state = {
        parent = frame:GetParent(),
        strata = frame:GetFrameStrata(),
        level = frame:GetFrameLevel(),
        shown = frame:IsShown(),
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
    else
        frame:Show()
        frame:SetFocus()
    end
end

--- Clears focus and hides the input the way Blizzard would.
function Input:Deactivate()
    local frame = editBox or resolveEditBox()
    if not frame then return end
    if ChatFrameUtil and ChatFrameUtil.DeactivateChat then
        ChatFrameUtil.DeactivateChat(frame)
    else
        frame:ClearFocus()
    end
end

---@return boolean
function Input:HasFocus()
    local frame = editBox or resolveEditBox()
    return (frame and frame.HasFocus and frame:HasFocus()) or false
end

if addon then addon.ChatInput = Input end
return Input
