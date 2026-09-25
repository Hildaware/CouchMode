--[[ ChatSuppression.lua
Hides Blizzard's visible chat while CouchMode Chat is enabled and restores every
frame it touched when Chat is disabled or the addon unloads.

Suppression never edits Blizzard's saved window settings: each frame's original
alpha and mouse state are recorded once and replayed verbatim on restore.
]]

local addonName, addon = ...

local chat = addon.Chat

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

--#region ── Blizzard suppression ───────────────────────────────────────────────

chat.suppressed = nil     ---@type table<Frame, table>?

local function iterSuppressedFrames()
    local frames = {}
    local count = NUM_CHAT_WINDOWS or 10
    for i = 1, count do
        local frame = _G['ChatFrame' .. i]
        if frame then
            frames[#frames + 1] = frame
            frames[#frames + 1] = _G['ChatFrame' .. i .. 'Tab']
            frames[#frames + 1] = _G['ChatFrame' .. i .. 'ButtonFrame']
            frames[#frames + 1] = _G['ChatFrame' .. i .. 'Minimized']
            frames[#frames + 1] = _G['ChatFrame' .. i .. 'ScrollToBottomButton']
        end
    end
    frames[#frames + 1] = _G['GeneralDockManager']
    frames[#frames + 1] = _G['ChatFrameMenuButton']
    frames[#frames + 1] = _G['QuickJoinToastButton']
    frames[#frames + 1] = _G['ChatMenu']

    local filtered = {}
    for i = 1, #frames do
        if frames[i] then filtered[#filtered + 1] = frames[i] end
    end
    return filtered
end

--- Hides Blizzard's visible chat without touching its saved window settings.
function chat:SuppressBlizzard()
    self.suppressed = self.suppressed or {}
    for _, frame in ipairs(iterSuppressedFrames()) do
        if not self.suppressed[frame] then
            self.suppressed[frame] = {
                alpha = frame:GetAlpha(),
                mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or false,
            }
        end
        frame:SetAlpha(0)
        if frame.EnableMouse then frame:EnableMouse(false) end
    end
end
chat.ApplyBlizzardSuppression = chat.SuppressBlizzard

--- Restores every frame previously suppressed to its saved state.
function chat:RestoreBlizzard()
    if not self.suppressed then return end
    for frame, state in pairs(self.suppressed) do
        if frame.SetAlpha then frame:SetAlpha(state.alpha) end
        if frame.EnableMouse then frame:EnableMouse(state.mouse) end
    end
    self.suppressed = nil
end

--- Reapplies suppression whenever Blizzard pops up a new chat window.
function chat:InstallSuppressionHooks()
    if self.suppressionHooked then return end
    self.suppressionHooked = true
    if FCF_OpenTemporaryWindow then
        hooksecurefunc('FCF_OpenTemporaryWindow', function()
            C_Timer.After(0, function()
                if db().enabled then chat:SuppressBlizzard() end
            end)
        end)
    end
end

--#endregion
