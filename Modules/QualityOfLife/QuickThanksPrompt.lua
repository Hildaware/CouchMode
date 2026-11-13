-- The prompt is an ordinary clickable card. It never captures controller
-- input or creates records in Blizzard's shared input-binding stack.
local _, addon = ...
local qol = addon.QualityOfLife
local Icons = addon.Components.GamepadIcons
local EditMode = addon.EditMode
local function db() return addon.db.profile.qualityOfLife.quickThanks end
local BINDING = 'COUCHMODE_CHAT_COMPOSER'
local PROMPT_DURATION = 5
local HEIGHT, TEXT_LEFT, PADDING, KEY_GAP = 68, 60, 12, 14
local FADE_IN, FADE_OUT, CONFIRM_DURATION = 0.12, 0.2, 0.65
local DEFAULT_POSITION = { point = 'BOTTOM', x = 0, y = 220 }

qol.quickThanksEditing = false

function qol:ApplyQuickThanksAnchor()
    local frame = self.quickThanksPrompt
    if not frame then return end
    local layout = EditMode:GetActiveLayoutName()
    local positions = db().positions
    local pos = layout and positions and positions[layout] or DEFAULT_POSITION
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

function qol:InitializeQuickThanksEditMode()
    if self.quickThanksEditRegistered or not self.quickThanksPrompt or not self:IsQuickThanksEnabled()
        or (InCombatLockdown and InCombatLockdown()) then return end
    local frame = self.quickThanksPrompt
    EditMode:RegisterFrame(frame, function(_, layoutName, point, x, y)
        local settings = db()
        settings.positions = settings.positions or {}
        settings.positions[layoutName] = { point = point, x = x, y = y }
    end, DEFAULT_POSITION, 'CouchMode Quick Thanks')
    EditMode:RegisterCallback('layout', function() qol:ApplyQuickThanksAnchor() end)
    EditMode:RegisterCallback('enter', function()
        qol.quickThanksEditing = true
        if qol:IsQuickThanksEnabled() then
            qol:DismissQuickThanks(false)
            qol:ShowQuickThanks('preview', 'Preview', true, 1243)
        end
    end)
    EditMode:RegisterCallback('exit', function()
        qol.quickThanksEditing = false
        qol:DismissQuickThanks(false)
    end)
    self.quickThanksEditRegistered = true
    self.quickThanksEditing = EditModeManagerFrame and EditModeManagerFrame:IsShown() or false
    if self.quickThanksEditing then self:ShowQuickThanks('preview', 'Preview', true, 1243) end
end

function qol:BuildQuickThanksPrompt()
    if self.quickThanksPrompt then return self.quickThanksPrompt end
    local frame = CreateFrame('Button', 'CouchModeQuickThanks', UIParent)
    frame:SetSize(320, HEIGHT)
    frame:SetPoint(DEFAULT_POSITION.point, UIParent, DEFAULT_POSITION.point,
        DEFAULT_POSITION.x, DEFAULT_POSITION.y)
    frame:RegisterForClicks('LeftButtonUp')
    frame:SetScript('OnClick', function() qol:SendQuickThanks() end)
    frame:SetScript('OnEnter', function()
        local active = qol.quickThanksActive
        if not active then return end
        GameTooltip:SetOwner(frame, 'ANCHOR_TOP')
        GameTooltip:SetText(active.preview and 'Quick Thanks preview' or (active.name .. ' buffed you'))
        GameTooltip:Show()
    end)
    frame:SetScript('OnLeave', function() GameTooltip:Hide() end)
    frame.background = frame:CreateTexture(nil, 'BACKGROUND')
    frame.background:SetAllPoints()
    frame.background:SetAtlas('themed-scenario-frame-2x')

    local iconBorder = frame:CreateTexture(nil, 'BORDER')
    iconBorder:SetSize(38, 38)
    iconBorder:SetPoint('LEFT', frame, 'LEFT', PADDING - 1, 1)
    iconBorder:SetColorTexture(0, 0, 0, 0.8)
    frame.spellIcon = frame:CreateTexture(nil, 'ARTWORK')
    frame.spellIcon:SetSize(36, 36)
    frame.spellIcon:SetPoint('CENTER', iconBorder, 'CENTER')
    frame.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.context = frame:CreateFontString(nil, 'ARTWORK')
    frame.context:SetPoint('TOPLEFT', frame, 'TOPLEFT', TEXT_LEFT, -13)
    frame.context:SetJustifyH('LEFT')
    frame.context:SetWordWrap(false)
    frame.context:SetTextColor(0.72, 0.72, 0.69)
    frame.label = frame:CreateFontString(nil, 'ARTWORK')
    frame.label:SetPoint('TOPLEFT', frame, 'TOPLEFT', TEXT_LEFT, -34)
    frame.label:SetJustifyH('LEFT')
    frame.label:SetWordWrap(false)
    frame.label:SetTextColor(1, 0.98, 0.92)

    frame.binding = Icons.CreateGroup(frame, { separator = '+' })
    frame.binding:SetPoint('RIGHT', frame, 'TOPRIGHT', -PADDING, -43)

    frame.bar = CreateFrame('StatusBar', nil, frame)
    frame.bar:EnableMouse(false)
    frame.bar:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', PADDING, 6)
    frame.bar:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -PADDING, 6)
    frame.bar:SetHeight(3)
    frame.bar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8')
    frame.bar:SetStatusBarColor(0.9, 0.72, 0.38)
    frame.bar:SetMinMaxValues(0, PROMPT_DURATION)
    local track = frame.bar:CreateTexture(nil, 'BACKGROUND')
    track:SetAllPoints()
    track:SetColorTexture(0.9, 0.72, 0.38, 0.12)

    frame:Hide()
    self.quickThanksPrompt = frame
    frame:SetScript('OnHide', function()
        if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
        qol:DismissQuickThanks(true)
    end)
    Icons.RegisterCallback(frame, function() qol:RefreshQuickThanksBinding() end)
    return frame
end

function qol:RefreshQuickThanksBinding()
    local frame, active = self.quickThanksPrompt, self.quickThanksActive
    if not frame or not active then return end
    local font = addon.Media.ResolveFont(db().fontFace)
    frame.context:SetFont(font, 13, '')
    frame.context:SetText(active.preview and 'Someone buffed you' or (active.name .. ' buffed you'))
    frame.label:SetFont(font, 18, '')
    frame.label:SetText(active.sent and 'Thanks!' or 'Say Thanks!')
    frame.binding:SetShown(not active.sent)
    frame.bar:SetShown(not active.sent)
    -- Confirmation keeps the existing card width so it does not jump on send.
    if active.sent then return end

    local first, second = GetBindingKey(BINDING)
    local binding = first
    if second and second:find('PAD', 1, true) then binding = second end
    frame.binding:SetFont(font, 13)
    frame.binding:SetBinding(binding)
    local width = frame.binding:GetWidth()
    frame:SetWidth(math.max(320, TEXT_LEFT + frame.label:GetStringWidth() + KEY_GAP + width + PADDING))
    frame.context:SetWidth(frame:GetWidth() - TEXT_LEFT - PADDING)
end

function qol:UpdateQuickThanksPrompt()
    local frame, active = self.quickThanksPrompt, self.quickThanksActive
    if not frame or not active then return end
    if self.quickThanksEditing then
        frame:SetAlpha(1)
        frame.bar:SetValue(PROMPT_DURATION)
        return
    end
    local now = GetTime()
    local remaining = active.expires - now
    if remaining <= 0 then self:DismissQuickThanks(true); return end
    frame:SetAlpha(math.min(1, (now - active.shownAt) / FADE_IN, remaining / FADE_OUT))
    if not active.sent then frame.bar:SetValue(remaining) end
end

function qol:ConfirmQuickThanks()
    local active = self.quickThanksActive
    if not active then return end
    self:ApplyQuickThanksCooldown()
    active.sent = true
    active.submitting = nil
    active.shownAt = GetTime() - FADE_IN
    active.expires = GetTime() + CONFIRM_DURATION
    self:RefreshQuickThanksBinding()
    self:UpdateQuickThanksPrompt()
end

function qol:ShowQuickThanks(guid, name, preview, spellID, spellIcon)
    if not self:IsQuickThanksEnabled() then return end
    if self.quickThanksEditing and not preview then return end
    local now = GetTime()
    local active = self.quickThanksActive
    if active and (active.sent or now >= active.expires or active.preview ~= (preview == true)) then
        self:DismissQuickThanks(true)
        active = nil
    end
    if not preview and (self.quickThanksCooldowns[guid] or 0) > now then return end
    if not active then
        if not spellIcon and spellID then
            local getTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
            if getTexture then spellIcon = getTexture(spellID) end
        end
        active = { guid = guid, name = name, participants = {}, preview = preview == true,
            spellIcon = spellIcon or 134400, shownAt = now }
        self.quickThanksActive = active
    end
    active.participants[guid] = true
    active.expires = now + PROMPT_DURATION
    local frame = self:BuildQuickThanksPrompt()
    self:RefreshQuickThanksBinding()
    frame.spellIcon:SetTexture(active.spellIcon)
    if self.quickThanksEditing then frame:SetScript('OnUpdate', nil)
    else frame:SetScript('OnUpdate', function() qol:UpdateQuickThanksPrompt() end) end
    self:UpdateQuickThanksPrompt()
    frame:Show()
end
