-- Preview the real bubble widgets without waiting for native NPC dialogue.
local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local bubbles = addon:GetModule('ChatBubbles')
local isSecret = addon.Utils.IsSecretValue

local function candidate(frame, unit)
    if not frame or frame:IsForbidden() or not frame:IsShown() then return end
    unit = frame.namePlateUnitToken or unit
    if isSecret(unit) or type(unit) ~= 'string' then return end
    local isPlayer, controlled = UnitIsPlayer(unit), UnitPlayerControlled(unit)
    if isSecret(isPlayer) or isSecret(controlled) or isPlayer or controlled then return end
    local name, guid = UnitName(unit), UnitGUID(unit)
    if isSecret(name) or isSecret(guid) or not name or not guid then return end
    return frame, unit, name, guid
end

local function findNpc()
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit or not C_NamePlate.GetNamePlates then return end
    for _, unit in ipairs({ 'target', 'mouseover', 'softinteract', 'softenemy', 'softfriend' }) do
        local frame, token, name, guid = candidate(C_NamePlate.GetNamePlateForUnit(unit), unit)
        if frame then return frame, token, name, guid end
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local frame, unit, name, guid = candidate(plate)
        if frame then return frame, unit, name, guid end
    end
end

function bubbles:PreviewNpcBubble()
    if not self:IsEnabled() then
        print('CouchMode: enable Chat Bubbles before previewing.')
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print('CouchMode: preview NPC bubbles outside combat.')
        return
    end
    local frame, unit, name, guid = findNpc()
    if not frame then
        print('CouchMode: no visible NPC nameplate found. Enable NPC nameplates and target a nearby NPC, then click Test.')
        return
    end
    if self.previewBubble then self:RemoveChatBubble(self.previewBubble, true) end

    local msg = {
        event = 'CHAT_MSG_MONSTER_SAY', type = 'MONSTER_SAY', category = 'NPC',
        sender = name, guid = guid, unitToken = unit,
        text = 'Stay a while, and listen. There is always another adventure waiting just beyond the road.',
    }
    self:EnrichNpc(msg)
    msg.unitToken = unit
    local bubble, duration = self:BuildBubble(msg)
    bubble.previewFrame = frame
    self.previewBubble = bubble
    -- Direct nameplate anchoring follows the NPC without measuring its position.
    bubble.widget:SetParent(UIParent)
    if not self:ShowBubble(bubble, duration) then
        print('CouchMode: this NPC nameplate position is unavailable for preview.')
        return
    end
    bubble.previewTicker = C_Timer.NewTicker(.1, function()
        local currentGUID = UnitGUID(unit)
        if (InCombatLockdown and InCombatLockdown()) or frame:IsForbidden() or not frame:IsShown()
            or isSecret(currentGUID) or currentGUID ~= guid then
            self:RemoveChatBubble(bubble, true)
            return
        end
        if self:ApplyBubblePosition(bubble) == false then
            self:RemoveChatBubble(bubble, true)
        end
    end)
end
