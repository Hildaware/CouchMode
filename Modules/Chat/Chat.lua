local addonName, addon = ...

---@class CouchMode: AceAddon
---@field ChatRouter table
---@field ChatSources table
---@field ChatRules table
---@field ChatGrouping table
---@field ChatInput table
---@field ChatFeedProto table
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class ChatModule: AceModule
local chat = addon:NewModule('Chat', 'AceEvent-3.0')
addon.Chat = chat

local Input = addon.ChatInput

--#region ── Constants ────────────────────────────────────────────────────────

-- Panel geometry defaults shared by the panel (ChatPanel) and ChatOptions.
chat.DEFAULT_WIDTH = 500
chat.DEFAULT_HEIGHT = 260

--#endregion

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

--#region ── Lifecycle ─────────────────────────────────────────────────────────

function chat:OnInitialize()
    addon.Chat = self
end

function chat:IsSubscriberEnabled()
    return db().enabled == true
end

--- Registers an event only when the running client defines it.
---@param event string
---@param handler string|fun(...)
---@return boolean registered
function chat:RegisterValidEvent(event, handler)
    return addon.Utils.RegisterEventIfValid(self, event, handler)
end

function chat:OnEnable()
    if not db().enabled then
        self:Disable(); return
    end

    self:BuildPanel()
    addon.ChatRouter:Subscribe(self)
    if self:HasQueuedMessages() then self:ScheduleMessageQueue(0) end

    self:RegisterValidEvent('UPDATE_CHAT_WINDOWS', 'ApplyBlizzardSuppression')
    self:RegisterValidEvent('PLAYER_ENTERING_WORLD', 'OnPlayerEnteringWorld')
    self:RegisterValidEvent('GUILD_ROSTER_UPDATE', function() self.guildRosterBuilt = false end)
    self:RegisterValidEvent('INSPECT_READY', 'OnInspectReady')
    self:RegisterValidEvent('PLAYER_REGEN_ENABLED', 'ProcessInspectQueue')
    self:RegisterValidEvent('PLAYER_LOGOUT', 'OnLogout')

    self:SuppressBlizzard()
    Input:Attach(self.panel, self.inputStrip)
    self.blockCheck = function(msg) return chat:ApplyBlockFilter(msg) end
    addon.ChatRouter.blockCheck = self.blockCheck
    self:InstallSuppressionHooks()
    -- Blizzard may (re)show frames during login; re-apply once the UI settles.
    C_Timer.After(1, function()
        if db().enabled then chat:SuppressBlizzard() end
    end)
    self:Touch()
end

--- Restores Blizzard's UI when the addon is unloaded (logout/reload).
function chat:OnLogout()
    Input:Detach()
    self:RestoreBlizzard()
end

function chat:OnDisable()
    self:StopMessageQueue()
    addon.ChatRouter:Unsubscribe(self)
    self:UnregisterEvent('UPDATE_CHAT_WINDOWS')
    self:UnregisterEvent('PLAYER_ENTERING_WORLD')
    self:UnregisterEvent('GUILD_ROSTER_UPDATE')
    self:UnregisterEvent('INSPECT_READY')
    self:UnregisterEvent('PLAYER_REGEN_ENABLED')
    self:UnregisterEvent('PLAYER_LOGOUT')

    Input:Detach()
    self:RestoreBlizzard()
    if addon.ChatRouter.blockCheck == self.blockCheck then
        addon.ChatRouter.blockCheck = nil
    end
    self.blockCheck = nil
    if self.panel then self.panel:Hide() end
    if self.borderFrame then self.borderFrame:Hide() end
end

function chat:OnPlayerEnteringWorld()
    self:ClearSession()
    if db().enabled then self:SuppressBlizzard() end
end

--#endregion

chat:Enable()
