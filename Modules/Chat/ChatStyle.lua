--[[ ChatStyle.lua
Styling callbacks the Chat feed invokes for each group and line.

Colors, fonts, portraits and the specialization badge are decided here. The feed
owns layout and measurement and calls back into these methods, so all identity
presentation stays on the Chat module in one place.
]]

local addonName, addon = ...

local chat = addon.Chat
local Sources = addon.ChatSources
local Rules = addon.ChatRules

--#region ── Constants ────────────────────────────────────────────────────────

local DEFAULT_TEXT_COLOR = { r = 1, g = 0.82, b = 0 }

local CATEGORY_PLACEHOLDER_ICONS = {
    SYSTEM = 136235,
    GUILD = 135026,
    GROUP = 134149,
    WHISPER = 134148,
    NPC = 512617,
    PUBLIC = 134330,
}
local TOTAL_FALLBACK_ICON = 134400

--#endregion

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

--#region ── Helpers ──────────────────────────────────────────────────────────

local isSecret = addon.Utils.IsSecretValue

local function chatTypeColor(event)
    local key = Sources.ChatTypeKey(event)
    local info = ChatTypeInfo and ChatTypeInfo[key]
    if info then return info.r, info.g, info.b, 1 end
    local d = DEFAULT_TEXT_COLOR
    return d.r, d.g, d.b, 1
end

local function classColor(classFile)
    if not classFile then return nil end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
end

local function raceAtlas(raceFile, sex)
    if not raceFile or not GetRaceAtlas then return nil end
    local race = string.lower(raceFile):gsub('[^%a]', '')
    local gender = (sex == 3) and 'female' or 'male'
    local ok, atlas = pcall(GetRaceAtlas, race, gender, true)
    if ok then return atlas end
end

local function classAtlasCoords(classFile)
    if not classFile or not CLASS_ICON_TCOORDS then return nil end
    return CLASS_ICON_TCOORDS[classFile]
end

--#endregion

--#region ── Styling (called by the feed) ────────────────────────────────────────

---@param group ChatGroup
---@return boolean
function chat:GroupShowsIdentity(group)
    return true
end

--- Applies the group's identity (name, channel, icon).
---@param g Frame
---@param msg ChatMessage
---@param feed table?
---@return boolean hasIcon  whether an icon was drawn
function chat:StyleIdentity(g, msg, feed)
    local name = msg.sender or (msg.category == 'SYSTEM' and 'System') or msg.type or ''
    self:SetTextPlain(g.name, name)
    local nameFont = feed and feed.fonts and feed.fonts.name
    local channelFont = feed and feed.fonts and feed.fonts.channel
    g.name:SetFont(nameFont and nameFont.face or addon.Media.ResolveFont(db().nameFontFace),
        nameFont and nameFont.size or db().nameFontSize, 'OUTLINE')

    local identity
    if msg.guid and not isSecret(msg.guid) then
        identity = self.identByGuid[msg.guid] or self:ResolveIdentity(msg)
    end
    local class = msg.classFile or (identity and identity.classFile)
    local cc = classColor(class)
    if cc then
        g.name:SetTextColor(cc.r, cc.g, cc.b, 1)
    else
        local r, gg, b = chatTypeColor(msg.event)
        g.name:SetTextColor(r, gg, b, 1)
    end

    local alias = Rules.ResolveAlias(db().aliases, Sources.ChatTypeKey(msg.event), msg.channelBase)
    local r, gg, b = chatTypeColor(msg.event)
    self:SetTextPlain(g.channel, alias or (msg.category == 'SYSTEM' and ''
        or (msg.channelBase or Sources.DisplayType(msg.event))))
    g.channel:SetFont(channelFont and channelFont.face or addon.Media.ResolveFont(db().channelFontFace),
        channelFont and channelFont.size or db().channelFontSize, 'OUTLINE')
    g.channel:SetTextColor(r, gg, b, 0.85)

    -- 2D icon selection only: no 3D models in the feed.
    g.icon:Hide()
    g.iconBorder:Hide()
    g.spec:Hide()

    local unit = msg.unitToken or (msg.guid and self:ResolveUnit(msg))
    local displayId = msg.displayId

    -- Resolve which 2D image to show, and a cache key so repeated rebuilds do
    -- not re-render the same portrait every time.
    local iconKey, apply
    if msg.category == 'NPC' then
        if displayId and displayId > 0 and SetPortraitTextureFromCreatureDisplayID then
            iconKey = 'd:' .. displayId
            apply = function() SetPortraitTextureFromCreatureDisplayID(g.icon, displayId) end
        elseif unit and SetPortraitTexture then
            iconKey = 'u:' .. unit
            apply = function() SetPortraitTexture(g.icon, unit) end
        end
    elseif unit and SetPortraitTexture then
        iconKey = 'u:' .. unit
        apply = function() SetPortraitTexture(g.icon, unit) end
    else
        local atlas = raceAtlas(msg.raceFile or (identity and identity.raceFile), msg.sex)
        if atlas then
            iconKey = 'a:' .. atlas
            apply = function() g.icon:SetAtlas(atlas) end
        else
            local coords = classAtlasCoords(class)
            if coords then
                iconKey = 'k:' .. class
                apply = function()
                    g.icon:SetTexture('Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes')
                    g.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                end
            end
        end
    end

    -- Every source category gets a recognizable icon when no identity portrait
    -- is available. Keep a generic final fallback for unknown future sources.
    if not iconKey then
        local fileID = CATEGORY_PLACEHOLDER_ICONS[msg.category] or TOTAL_FALLBACK_ICON
        iconKey = 'f:' .. fileID
        apply = function()
            g.icon:SetTexture(fileID)
            g.icon:SetTexCoord(0, 1, 0, 1)
        end
    end

    local shown = false
    if iconKey then
        if g._iconKey ~= iconKey then
            apply()
            g._iconKey = iconKey
        end
        g.icon:Show()
        g.iconBorder:Show()
        shown = true
    else
        g._iconKey = nil
    end

    -- Keep specialization/class art in the small corner badge. The primary
    -- icon remains the unit/race portrait (or the NPC creature portrait).
    local specIcon = identity and identity.spec and identity.spec.icon
    if shown and specIcon then
        g.spec:SetTexture(specIcon)
        g.spec:SetTexCoord(0, 1, 0, 1)
        g.spec:Show()
    elseif shown then
        local coords = classAtlasCoords(class)
        if coords then
            g.spec:SetTexture('Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes')
            g.spec:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            g.spec:Show()
        end
    end

    if unit then
        self:EnqueueInspect(unit, msg.guid)
    end

    return shown
end

---@param fs FontString
---@param msg ChatMessage
---@param isFirst boolean
function chat:StyleLine(fs, msg, isFirst)
    local r, g, b = chatTypeColor(msg.event)
    -- Rebuilds re-style every line; skip the engine call when the color is
    -- unchanged (chat-type colors are stable per event).
    if fs._colorR ~= r or fs._colorG ~= g or fs._colorB ~= b then
        fs:SetTextColor(r, g, b, 1)
        fs._colorR, fs._colorG, fs._colorB = r, g, b
    end
end

function chat:RefreshVisibleIcons()
    if self.panel and self.feed then self:Recompute() end
end

--#endregion
