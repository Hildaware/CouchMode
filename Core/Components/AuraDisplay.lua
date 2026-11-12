local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

-- Configure Blizzard's secure aura renderer; never inspect its live buttons,
-- aura counts, or visibility. Only initialize visuals before access is locked.
local AuraDisplay = {}
addon.AuraDisplay = AuraDisplay
local secondsFormatter

local function getSecondsFormatter()
    if not secondsFormatter then
        secondsFormatter = C_StringUtil.CreateNumericRuleFormatter()
        -- Match the old %.0f countdown without sampling restricted durations.
        secondsFormatter:AddBreakpoint({ threshold = 0, format = '%.0f' })
    end
    return secondsFormatter
end

function AuraDisplay.IsSupported()
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo('CustomAuraContainerTemplate') and true or false
end

local function styleText(text, options)
    text:SetFont(options.font())
    local shadow = options.shadow
    if type(shadow) == 'function' then shadow = shadow() end
    if shadow then addon.Utils.apply_font_shadow(text) else text:SetShadowOffset(0, 0) end
end

local function initializeButton(button, options, row, dispellable)
    button:SetSize(options.width, options.height)
    button:SetMouseMotionEnabled(options.tooltips == true)
    button:SetMouseClickEnabled(false)
    button:SetCancelAuraButtons(nil)
    button:SetTooltipAnchorPoint('ANCHOR_RIGHT')

    local texture = button:CreateTexture(nil, 'ARTWORK')
    texture:SetAllPoints(button)
    local crop = (1 - options.height / options.width) / 2 * 0.84
    texture:SetTexCoord(0.08, 0.92, 0.08 + crop, 0.92 - crop)
    button:SetIcon(texture)

    if options.innerBorder then
        local borders = addon.Utils.create_border_textures(button, button)
        addon.Utils.apply_border_textures(button, borders, true, 1, 0, 0, 0, 1)
    else
        local border = button:CreateTexture(nil, 'BACKGROUND')
        border:SetColorTexture(options.debuff and 1 or 0, 0, 0, 1)
        border:SetPoint('TOPLEFT', button, 'TOPLEFT', -1, 1)
        border:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', 1, -1)
    end

    local cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate')
    cooldown:SetAllPoints(button)
    cooldown:SetDrawEdge(false)
    cooldown:SetReverse(true)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:EnableMouse(false)
    if options.timer then cooldown:SetDrawSwipe(false) end
    button:SetDurationCooldown(cooldown)

    local labels = CreateFrame('Frame', nil, button)
    labels:SetAllPoints(button)
    labels:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    labels:EnableMouse(false)
    if options.showCount ~= false then
        local count = labels:CreateFontString(nil, 'OVERLAY')
        styleText(count, options)
        count:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', options.countOffsetX or 0, options.countOffsetY or 0)
        count:SetJustifyH('RIGHT')
        button:SetApplicationCount(count)
        row.texts[#row.texts + 1] = count
    end
    if dispellable then
        local cue = labels:CreateTexture(nil, 'OVERLAY')
        cue:SetColorTexture(0.3, 0.85, 1, 1)
        cue:SetSize(5, 5)
        cue:SetPoint('TOPLEFT', button, 'TOPLEFT', 1, -1)
    end
    if options.timer then
        local timer = labels:CreateFontString(nil, 'OVERLAY')
        styleText(timer, options)
        local anchor = options.timerAnchor or 'CENTER'
        timer:SetPoint(anchor, button, anchor, 0, options.timerOffsetY or 0)
        timer:SetJustifyH('CENTER')
        button:SetDurationText(timer, { textFormatter = getSecondsFormatter() })
        row.texts[#row.texts + 1] = timer
    end
end

function AuraDisplay.Create(parent, options)
    if not AuraDisplay.IsSupported() then return nil end
    -- The fixed viewport caps the combined groups without reading how many
    -- secure aura buttons are shown. Groups use mutually exclusive filters.
    local row = CreateFrame('Frame', nil, parent)
    row.texts = {}
    row.options = options
    local stripWidth = options.maxCount * options.width + (options.maxCount - 1) * options.gap
    row:SetSize(options.anchorWidth or stripWidth, options.height)
    -- Keep the old anchoring width independently of the clipping viewport.
    -- Padding leaves room for stack text, its shadow, and the icon borders.
    local padding = 6
    -- Multiple groups can produce additional buttons beyond the row limit.
    -- Keep their leading border outside the right edge of the viewport.
    local rightPadding = #options.filters > 1 and math.min(padding, options.gap - 1) or padding
    local viewport = CreateFrame('Frame', nil, row)
    viewport:SetPoint('TOPLEFT', row, 'TOPLEFT', -padding, padding)
    viewport:SetSize(stripWidth + padding + rightPadding, options.height + padding * 2)
    viewport:SetClipsChildren(true)
    local container = CreateFrame('AuraContainer', nil, viewport, 'CustomAuraContainerTemplate')
    row.container = container
    container:SetSize(1, 1)
    container:SetPoint('TOPLEFT', viewport, 'TOPLEFT', padding, -padding)
    container:SetEnabled(false)
    container:SetEditModePreviewEnabled(false)
    container:SetFlowLayoutAnchorPoint('TOPLEFT')
    container:SetFlowLayoutMaximumLineSize(math.huge)
    for index, filter in ipairs(options.filters) do
        container:AddAuraGroup('group' .. index, filter, {
            maxFrameCount = options.maxCount,
            -- Native containers have no Unsorted mode. Instance order avoids
            -- their default caster/importance priorities and is the closest
            -- available equivalent to the former enumeration order.
            sortMethod = AuraContainerSortMethod.AuraInstanceIDOnly,
            initializeFrame = function(button)
                initializeButton(button, options, row, options.debuff and filter == 'HARMFUL|RAID')
            end,
            layout = {
                elementWidth = options.width,
                elementHeight = options.height,
                elementSpacing = options.gap,
                groupSpacing = options.gap,
            },
        })
    end
    row:Hide()
    return row
end

function AuraDisplay.RefreshStyle(row)
    row.styleDirty = true
    if not addon.Utils.CanReadAuras() then return end
    for _, text in ipairs(row.texts) do styleText(text, row.options) end
    row.styleDirty = nil
end

function AuraDisplay.SetUnit(row, unit)
    if not unit then
        row.container:SetEnabled(false)
        row:Hide()
        row.unit = nil
        return
    end
    if row.unit ~= unit then
        row.container:SetUnit(unit)
        row.unit = unit
    end
    row.container:SetEnabled(true)
    if row.styleDirty then AuraDisplay.RefreshStyle(row) end
    row:Show()
end
