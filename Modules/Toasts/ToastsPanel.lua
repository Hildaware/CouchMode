local addonName, addon = ...
addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)
local toasts = addon.Toasts
local Sources = addon.ToastSources
local EditMode = addon.EditMode

local function db() return addon.db.profile.toasts end
local function now() return (type(GetTime) == 'function') and GetTime() or 0 end
local PAD = 8
local DEFAULT_WIDTH = toasts.DEFAULT_WIDTH
local DEFAULT_MAX_ITEMS = toasts.DEFAULT_MAX_ITEMS
local NEUTRAL = { r = 0.16, g = 0.16, b = 0.16 }
local MONEY = { r = 0.83, g = 0.68, b = 0.21 }
local REPUTATION = { r = 0.30, g = 0.58, b = 0.95 }
local SYSTEM = { r = 0.46, g = 0.79, b = 0.92 }
local QUEST = { r = 1, g = 0.82, b = 0 }
local QUEST_ICON_ATLAS = toasts.QUEST_ICON_ATLAS
local GOLD_ICON_ID = 901746
local REPUTATION_ICON = 'Interface\\Icons\\achievement_reputation_01'
local SYSTEM_ICON_ID = 4279397
local SYSTEM_EVENT_ICONS = {
    CHAT_MSG_COMBAT_XP_GAIN = 'Interface\\Icons\\XP_Icon',
    CHAT_MSG_COMBAT_HONOR_GAIN = 'Interface\\Icons\\Spell_Misc_HellifrePVPHonorHoldFavor',
    CHAT_MSG_SKILL = 'Interface\\Icons\\INV_Misc_Book_09',
}
local SYSTEM_EVENT_ICON_ATLASES = {
    CHAT_MSG_COLLECTED_APPEARANCE = 'transmog-nav-slot-head',
}
local ROW_BG_ALPHA = 0.5


local function fadeDuration(entry)
    local weight = 8 / 15
    if entry.kind == 'items' then
        local quality = Sources.SafeNumber(entry.quality)
        if quality and quality >= 4 then
            weight = 1
        elseif quality == 3 then
            weight = 12 / 15
        elseif quality == 2 then
            weight = 10 / 15
        end
    elseif entry.kind == 'currency' then
        weight = 12 / 15
    elseif entry.kind == 'reputation' then
        weight = 10 / 15
    end
    return math.max(db().fadeDelay or 15, 0) * weight
end

--- Reads an item quality's RGB from the client, tolerating older clients.
---@param quality any
---@return number? r
---@return number? g
---@return number? b
local function qualityColor(quality)
    if type(quality) ~= 'number' or Sources.isSecret(quality) then return nil end
    if not (C_Item and C_Item.GetItemQualityColor) then return nil end
    local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
    if ok and type(r) == 'number' and type(g) == 'number' and type(b) == 'number' then
        return r, g, b
    end
    return nil
end

--- Blizzard money formatting, preferring the coin-texture markup.
---@param amount any
---@return string
local function moneyString(amount)
    if type(amount) ~= 'number' then return '' end
    if type(GetCoinTextureString) == 'function' then
        local ok, text = pcall(GetCoinTextureString, amount)
        if ok and type(text) == 'string' then return text end
    end
    if type(GetMoneyString) == 'function' then
        local ok, text = pcall(GetMoneyString, amount)
        if ok and type(text) == 'string' then return text end
    end
    return tostring(amount)
end

--- Formats a plain numeric total with Blizzard's thousands separators when available.
---@param value any
---@return string
local function numberString(value)
    if type(value) ~= 'number' then return tostring(value) end
    if type(BreakUpLargeNumbers) == 'function' then
        local ok, text = pcall(BreakUpLargeNumbers, value)
        if ok and type(text) == 'string' then return text end
    end
    return tostring(value)
end

--- Renders a reputation tier as Blizzard's rep bar does, e.g. "1,000 / 6,000"
--- (or "1,000/6,000" when the localized format string is unavailable).
---@param progress number
---@param progressMax number
---@return string
local function reputationProgressString(progress, progressMax)
    local current = numberString(progress)
    local total = numberString(progressMax)
    local format = _G and _G.REPUTATION_PROGRESS_FORMAT
    if type(format) == 'string' and format ~= '' then
        local ok, text = pcall(string.format, format, current, total)
        if ok and type(text) == 'string' then return text end
    end
    return current .. '/' .. total
end

--- Resolves the localized standing label for a reaction index, using the same
--- gender-aware lookup as the reputation frame (FACTION_STANDING_LABEL<reaction>).
---@param reaction any
---@return string?
local function standingLabel(reaction)
    if type(reaction) ~= 'number' then return nil end
    local key = 'FACTION_STANDING_LABEL' .. reaction
    if type(GetText) == 'function' then
        local gender = (type(UnitSex) == 'function') and UnitSex('player') or 2
        local ok, text = pcall(GetText, key, gender)
        if ok and type(text) == 'string' and text ~= '' then return text end
    end
    local fallback = _G and _G[key]
    if type(fallback) == 'string' and fallback ~= '' then return fallback end
    return nil
end

--- Builds the parenthetical reputation detail: "Friendly 1,000 / 6,000", the
--- label alone for capped factions, the progress alone when no label is known,
--- or nil when nothing can be resolved.
---@param entry ToastEntry
---@return string?
local function reputationDetail(entry)
    local label = standingLabel(entry.reaction)
    local progress
    if entry.progress and entry.progressMax and entry.progressMax > 0 then
        progress = reputationProgressString(entry.progress, entry.progressMax)
    end
    if label and progress then return label .. ' ' .. progress end
    return label or progress
end


--#region ── Presentation ──────────────────────────────────────────────────────

--- Builds the feed's styling for one entry. Styling lives here (not in the
--- feed) so colors and labels stay in one place, mirroring the Chat module.
---@param entry ToastEntry
---@return table
function toasts:PresentEntry(entry)
    if entry.kind == 'items' then
        local quality = entry.quality
        local r, g, b = qualityColor(quality)
        if not r or not quality or quality < 2 then
            r, g, b = NEUTRAL.r, NEUTRAL.g, NEUTRAL.b
        end
        local isQuestItem = entry.isQuestItem == true
        if isQuestItem then
            r, g, b = QUEST.r, QUEST.g, QUEST.b
        end
        local text = entry.name or 'Item'
        if entry.count and entry.count > 0 then
            text = ('%s (%d)'):format(text, entry.count)
        end
        return {
            text = text,
            icon = entry.icon,
            questIconAtlas = isQuestItem and QUEST_ICON_ATLAS or nil,
            hyperlink = entry.hyperlink,
            bg = { r * 0.35, g * 0.35, b * 0.35, ROW_BG_ALPHA },
            border = { r, g, b },
            textColor = { 1, 1, 1 },
        }
    elseif entry.kind == 'money' then
        local text = '+' .. moneyString(entry.amount)
        if entry.total then text = text .. '   (' .. moneyString(entry.total) .. ')' end
        return {
            text = text,
            icon = GOLD_ICON_ID,
            bg = { 0.20, 0.15, 0.03, ROW_BG_ALPHA },
            border = { MONEY.r, MONEY.g, MONEY.b },
            textColor = { 1, 0.93, 0.62 },
        }
    elseif entry.kind == 'currency' then
        local r, g, b = qualityColor(entry.quality)
        if not r then r, g, b = 0.20, 0.60, 0.40 end
        local text = ('%s +%s'):format(entry.name or 'Currency', tostring(entry.amount))
        if entry.total then text = text .. (' (%s)'):format(tostring(entry.total)) end
        return {
            text = text,
            icon = entry.icon,
            hyperlink = entry.hyperlink,
            bg = { r * 0.30, g * 0.30, b * 0.30, ROW_BG_ALPHA },
            border = { r, g, b },
            textColor = { 1, 1, 1 },
        }
    elseif entry.kind == 'reputation' then
        local text
        if entry.name and entry.amount then
            text = ('%s +%d'):format(entry.name, entry.amount)
            local detail = reputationDetail(entry)
            if detail then text = text .. (' (%s)'):format(detail) end
        else
            -- Fall back to the original localized line when parsing is partial.
            text = entry.originalText or 'Reputation'
        end
        return {
            text = text,
            icon = REPUTATION_ICON,
            bg = { 0.06, 0.13, 0.26, ROW_BG_ALPHA },
            border = { REPUTATION.r, REPUTATION.g, REPUTATION.b },
            textColor = { 0.82, 0.91, 1 },
        }
    elseif entry.kind == 'system' then
        return {
            text = entry.originalText or '',
            icon = entry.icon or SYSTEM_EVENT_ICONS[entry.event] or SYSTEM_ICON_ID,
            iconAtlas = not entry.icon and (entry.iconAtlas or SYSTEM_EVENT_ICON_ATLASES[entry.event]) or nil,
            wrap = true,
            bg = { 0.07, 0.16, 0.21, 0.72 },
            border = { SYSTEM.r, SYSTEM.g, SYSTEM.b },
            textColor = { 0.86, 0.96, 1 },
        }
    end
    return { text = entry.originalText or '' }
end

--- Resolved font metrics for the feed label field.
---@return table
function toasts:FontMetrics()
    return {
        label = { face = addon.Media.ResolveFont(db().fontFace), size = db().fontSize },
    }
end

--#endregion

--#region ── Panel construction ─────────────────────────────────────────────────

function toasts:BuildPanel()
    if self.panel then
        self.panel:Show()
        return
    end

    local frame = CreateFrame('Frame', 'CouchModeToasts', UIParent)
    frame:SetSize(db().width or DEFAULT_WIDTH, PAD * 2 + 1)
    frame:SetFrameStrata('LOW')
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    local scrollArea = CreateFrame('Frame', nil, frame)
    scrollArea:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, -PAD)
    scrollArea:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PAD, PAD)
    self.scrollArea = scrollArea

    self.feed = addon.ToastFeedProto.New(scrollArea)
    self.feed.presenter = function(entry) return toasts:PresentEntry(entry) end
    self.feed.durationForEntry = fadeDuration

    -- Rows enable the mouse for tooltips, so hover is tracked on the padding
    -- regions here and per-row inside the feed.
    local function onEnter() self.feed:NoteHover(1) end
    local function onLeave() self.feed:NoteHover(-1) end
    for _, region in ipairs({ frame, scrollArea }) do
        region:EnableMouse(true)
        region:SetScript('OnEnter', onEnter)
        region:SetScript('OnLeave', onLeave)
    end

    frame:SetScript('OnUpdate', function(_, dt) toasts:UpdateFade(dt) end)

    EditMode:RegisterFrame(frame, function(_, layoutName, point, x, y)
        -- Position callbacks cannot be persisted until the active layout is known.
        if not layoutName then return end
        local settings = db()
        settings.positions = settings.positions or {}
        settings.positions[layoutName] = { point = point, x = x, y = y }
    end, { point = 'BOTTOMRIGHT', x = -40, y = 40 }, 'CouchMode Toasts')

    EditMode:RegisterFrameSettings(frame, {
        {
            kind = EditMode.SettingType.Slider,
            name = 'Width', desc = 'Feed width in pixels.',
            default = DEFAULT_WIDTH, minValue = 200, maxValue = 900, valueStep = 10,
            get = function() return db().width end,
            set = function(_, value, fromReset)
                db().width = (fromReset and DEFAULT_WIDTH or value)
                toasts:ApplyLayout()
            end,
        },
    })

    EditMode:RegisterCallback('layout', function(layoutName)
        local pos = db().positions[layoutName]
        frame:ClearAllPoints()
        if pos then
            frame:SetPoint(pos.point, pos.x, pos.y)
        else
            frame:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', -40, 40)
        end
    end)

    frame:Show()
    self.panel = frame
    self:ApplyFont()
    self:ApplyLayout()
end

function toasts:ApplyFont()
    if not self.feed then return end
    self.feed:SetFonts(self:FontMetrics())
    self:ApplyLayout()
end

--#endregion

--#region ── Layout ─────────────────────────────────────────────────────────────

function toasts:ApplyLayout()
    local frame = self.panel
    if not frame then return end

    local width = db().width or DEFAULT_WIDTH

    if self.feed then
        self.feed:SetWidth(width - PAD * 2)
        local viewportHeight = self.feed:GetTailHeight(db().maxItems or DEFAULT_MAX_ITEMS)
        frame:SetSize(width, viewportHeight + PAD * 2)
        self.feed:SetViewportHeight(viewportHeight)
    else
        frame:SetSize(width, PAD * 2 + 1)
    end
end

--#endregion

--#region ── Fade / activity ──────────────────────────────────────────────────

function toasts:Touch()
    self.lastActivity = now()
end

function toasts:UpdateFade(dt)
    if not self.panel then return end

    local currentTime = now()
    local hasVisible = true
    if self.feed then
        hasVisible = self.feed:UpdateRowFade(currentTime)
        if self.feed:RemoveExpiredRows(currentTime) > 0 then
            self:ApplyLayout()
            if self:HasQueuedEntries() then self:SchedulePresentationQueue(0) end
        end
    end

    local hovered = self.feed and self.feed.hovering
    local target = db().activeOpacity or 1
    if not hovered and not hasVisible then
        target = 0
    end

    local current = self.fadeAlpha or 0
    local diff = target - current
    local nextAlpha
    if math.abs(diff) < 0.01 then
        nextAlpha = target
    else
        nextAlpha = current + diff * math.min(dt * 6, 1)
    end
    if nextAlpha ~= current then
        self.fadeAlpha = nextAlpha
        self.panel:SetAlpha(nextAlpha)
    end
end

--#endregion

--#region ── Panel controls ─────────────────────────────────────────────────────

function toasts:Toggle()
    if not self.panel then return end
    if self.panel:IsShown() then
        self.panel:Hide()
    else
        self.panel:Show()
        self:Touch()
    end
end

function toasts:ClosePanel()
    if self.panel then self.panel:Hide() end
end

function toasts:ClearToasts()
    self:ClearPresentationQueue()
    if self.feed then self.feed:Clear() end
    self:ApplyLayout()
end

--#endregion
