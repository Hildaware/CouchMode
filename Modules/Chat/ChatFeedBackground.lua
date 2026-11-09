-- One rounded, feathered background behind the entire chat group.
-- Horizontal trapezoids tile each contour without overlapping seams.
local _, addon = ...
local M = {}
local LAYERS = 16
local OUTSET = 8
local INSET = 20
local RIGHT_OUTSET = 48
local RIGHT_INSET = 32
local CORNER_RADIUS = 18
local CURVE_SEGMENTS = 4
local OPACITY = .35
local PAD = 4
local proto = {}
proto.__index = proto

local function smoothstep(t) return t * t * (3 - 2 * t) end

function proto:GetAlpha() return self.alpha end

local function layerAlpha(index, alpha)
    local t = (index - 1) / (LAYERS - 1)
    local previousT = math.max(index - 2, 0) / (LAYERS - 1)
    local previous = OPACITY * alpha * smoothstep(previousT)
    local opacity = OPACITY * alpha * smoothstep(t)
    return (opacity - previous) / (1 - previous)
end

function proto:SetAlpha(alpha)
    if self.alpha == alpha then return end
    self.alpha = alpha
    for i, layer in ipairs(self.layers) do
        local opacity = layerAlpha(i, alpha)
        for _, texture in ipairs(layer) do texture:SetAlpha(opacity) end
    end
end

local function acquireBand(background, index, bandIndex)
    local layer = background.layers[index]
    local texture = layer[bandIndex]
    if not texture then
        texture = background.parent:CreateTexture(nil, 'BACKGROUND')
        texture:SetColorTexture(0, 0, 0, 1)
        texture:SetAlpha(layerAlpha(index, background.alpha))
        layer[bandIndex] = texture
    end
    return texture
end

local function drawBand(texture, parent, top, bottom, leftTop, rightTop, leftBottom, rightBottom)
    local left = math.min(leftTop, leftBottom)
    local right = math.max(rightTop, rightBottom)
    texture:ClearAllPoints()
    texture:SetPoint('TOPLEFT', parent, 'TOPLEFT', left, -top)
    texture:SetSize(math.max(right - left, .01), bottom - top)
    texture:SetVertexOffset(UPPER_LEFT_VERTEX, leftTop - left, 0)
    texture:SetVertexOffset(LOWER_LEFT_VERTEX, leftBottom - left, 0)
    texture:SetVertexOffset(UPPER_RIGHT_VERTEX, rightTop - right, 0)
    texture:SetVertexOffset(LOWER_RIGHT_VERTEX, rightBottom - right, 0)
    texture:Show()
end

function proto:SetShape(headerRight, headerBottom, bodyTop, bodyRight, bottom, hasIcon)
    local previous = self.shape
    if previous and previous[1] == headerRight and previous[2] == headerBottom
        and previous[3] == bodyTop and previous[4] == bodyRight
        and previous[5] == bottom and previous[6] == hasIcon then return end
    self.shape = { headerRight, headerBottom, bodyTop, bodyRight, bottom, hasIcon }
    local baseLeft = hasIcon and -12 or -PAD
    for i, layer in ipairs(self.layers) do
        local progress = (i - 1) / (LAYERS - 1)
        -- The right edges trail much further past the header and message text.
        local outset = OUTSET - (OUTSET + INSET) * progress
        local rightOutset = RIGHT_OUTSET - (RIGHT_OUTSET + RIGHT_INSET) * progress
        local baseTop = headerRight and 0 or bodyTop
        outset = math.max(outset, -(bottom - baseTop + PAD * 2 - 1) / 2)
        local left = baseLeft - outset
        local top = baseTop - PAD - outset
        local finish = bottom + PAD + outset
        local right = math.max(math.max(headerRight or 0, bodyRight) + PAD + rightOutset, left + 1)
        local radius = math.max(0, math.min(CORNER_RADIUS + outset,
            (finish - top) / 2, (right - left) / 2))

        local function circleInset(distance, r)
            if r <= 0 or distance >= r then return 0 end
            local dy = r - math.max(distance, 0)
            return r - math.sqrt(math.max(r * r - dy * dy, 0))
        end

        local function bounds(y)
            local inset = circleInset(math.min(y - top, finish - y), radius)
            return left + inset, math.max(right - inset, left + inset + .01)
        end

        local cuts = { top, finish }
        for segment = 1, CURVE_SEGMENTS do
            local offset = radius * segment / CURVE_SEGMENTS
            cuts[#cuts + 1] = top + offset
            cuts[#cuts + 1] = finish - offset
        end
        table.sort(cuts)
        local used = 0
        for j = 2, #cuts do
            local y1, y2 = cuts[j - 1], cuts[j]
            if y2 - y1 > .001 then
                local l1, r1 = bounds(y1)
                local l2, r2 = bounds(y2)
                used = used + 1
                drawBand(acquireBand(self, i, used), self.parent, y1, y2, l1, r1, l2, r2)
            end
        end
        for j = used + 1, #layer do layer[j]:Hide() end
    end
end

function proto:SetHeight(height)
    if not self.shape then return end
    local s = self.shape
    self:SetShape(s[1], s[2], s[3], s[4], height, s[6])
end

function M.Create(parent)
    local background = setmetatable({ parent = parent, layers = {} }, proto)
    for i = 1, LAYERS do background.layers[i] = {} end
    background:SetAlpha(1)
    return background
end

addon.ChatFeedBackground = M
