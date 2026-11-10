-- Stretch a square button atlas while preserving its corner and border sizes.
local _, addon = ...
addon.Components = addon.Components or {}
local nineSliceButton = {}
addon.Components.NineSliceButton = nineSliceButton

local atlasCache = {}
local function atlasInfo(name)
    if not atlasCache[name] then atlasCache[name] = C_Texture.GetAtlasInfo(name) end
    return atlasCache[name]
end

-- Explicit crops keep corner geometry independent of client atlas shader behavior.
local function createPieces(button, layer, highlight)
    local pieces = {}
    for row = 1, 3 do
        for column = 1, 3 do
            local texture = button:CreateTexture(nil, layer)
            if highlight then
                texture:SetBlendMode('ADD')
                texture:SetAlpha(0.4)
            end
            pieces[#pieces + 1] = texture
        end
    end
    return pieces
end

local function setAtlas(pieces, atlas)
    local info = atlasInfo(atlas)
    -- Capture the full bevel in each corner. Stretch only the narrow, flat
    -- middle strip; a quarter-width cut lets part of the chamfer stretch too.
    local insetX = math.floor(info.width * 0.45) / info.width
    local insetY = math.floor(info.height * 0.45) / info.height
    local u = { 0, insetX, 1 - insetX, 1 }
    local v = { 0, insetY, 1 - insetY, 1 }
    local du, dv = info.rightTexCoord - info.leftTexCoord, info.bottomTexCoord - info.topTexCoord
    local source = info.file or info.filename
    for row = 1, 3 do
        for column = 1, 3 do
            local texture = pieces[(row - 1) * 3 + column]
            -- Use the underlying texture directly, as Blizzard's cropped border
            -- helper does. Atlas-level slice data must not affect these crops.
            if source then texture:SetTexture(source) else texture:SetAtlas(atlas) end
            if texture.ClearTextureSlice then texture:ClearTextureSlice() end
            texture:SetHorizTile(false)
            texture:SetVertTile(false)
            -- SetTexCoord addresses the packed texture, not atlas-relative UVs.
            texture:SetTexCoord(info.leftTexCoord + u[column] * du,
                info.leftTexCoord + u[column + 1] * du,
                info.topTexCoord + v[row] * dv, info.topTexCoord + v[row + 1] * dv)
        end
    end
end

local function layoutPieces(button, pieces, margin)
    local width, height = button:GetWidth(), button:GetHeight()
    local corner = math.min(margin, width / 2, height / 2)
    local x, y = { 0, corner, width - corner, width }, { 0, corner, height - corner, height }
    for row = 1, 3 do
        for column = 1, 3 do
            local texture = pieces[(row - 1) * 3 + column]
            texture:ClearAllPoints()
            texture:SetPoint('TOPLEFT', button, 'TOPLEFT', x[column], -y[row])
            texture:SetPoint('BOTTOMRIGHT', button, 'TOPLEFT', x[column + 1], -y[row + 1])
        end
    end
end

local function applySlices(button, upAtlas, downAtlas, margin, nativeTextures)
    -- Native texture state handling is replaced by the cropped regions below.
    for _, texture in ipairs(nativeTextures) do texture:SetAlpha(0) end
    local face = createPieces(button, 'BACKGROUND', false)
    local highlight = createPieces(button, 'BORDER', true)
    setAtlas(highlight, upAtlas)
    local selected, hovered, pressed, currentAtlas = false, false, false, nil
    local currentEnabled, highlightShown
    local function refresh()
        local enabled = button:IsEnabled()
        local atlas = enabled and pressed and downAtlas or upAtlas
        if currentAtlas ~= atlas then
            setAtlas(face, atlas)
            currentAtlas = atlas
        end
        if currentEnabled ~= enabled then
            for _, texture in ipairs(face) do
                texture:SetDesaturated(not enabled)
                local tint = enabled and 1 or 0.5
                texture:SetVertexColor(tint, tint, tint)
            end
            currentEnabled = enabled
        end
        local showHighlight = enabled and (selected or hovered)
        if highlightShown ~= showHighlight then
            for _, texture in ipairs(highlight) do texture:SetShown(showHighlight) end
            highlightShown = showHighlight
        end
    end
    local function layout()
        layoutPieces(button, face, margin)
        layoutPieces(button, highlight, margin)
    end
    button:HookScript('OnSizeChanged', layout)
    button:HookScript('OnEnter', function() hovered = true; refresh() end)
    button:HookScript('OnLeave', function() hovered = false; refresh() end)
    button:HookScript('OnMouseDown', function(_, mouseButton)
        if mouseButton == 'LeftButton' then pressed = true; refresh() end
    end)
    button:HookScript('OnMouseUp', function() pressed = false; refresh() end)
    button:HookScript('OnEnable', refresh)
    button:HookScript('OnDisable', function() pressed = false; refresh() end)
    button:HookScript('OnHide', function() hovered, pressed = false, false end)
    button:HookScript('OnShow', refresh)
    hooksecurefunc(button, 'LockHighlight', function() selected = true; refresh() end)
    hooksecurefunc(button, 'UnlockHighlight', function() selected = false; refresh() end)
    layout()
    refresh()
end

--- Apply a square atlas as a resizable button skin, retaining native button APIs.
--- cornerSize controls the displayed corners in UI units, independently of source crops.
function nineSliceButton.Apply(button, upAtlas, downAtlas, cornerSize)
    button:SetNormalAtlas(upAtlas)
    button:SetPushedAtlas(downAtlas)
    button:SetDisabledAtlas(upAtlas)
    button:SetHighlightAtlas(upAtlas)
    local normal, pushed = button:GetNormalTexture(), button:GetPushedTexture()
    local disabled, highlight = button:GetDisabledTexture(), button:GetHighlightTexture()
    disabled:SetDesaturated(true)
    disabled:SetVertexColor(0.5, 0.5, 0.5)
    highlight:SetBlendMode('ADD')
    highlight:SetAlpha(0.4)

    local up, down = atlasInfo(upAtlas), atlasInfo(downAtlas)
    if not up or not down then return end
    local margin = math.max(1, cornerSize or 12)
    applySlices(button, upAtlas, downAtlas, margin, { normal, pushed, disabled, highlight })
end
