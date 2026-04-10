-- LibModels.lua
-- Simple in-game model viewer. Open with /cm mv
-- Loaded before ModelPaths.lua so we can guarantee the WeakAuras namespace exists.
WeakAuras = WeakAuras or {}

LibModels = {}

--#region ── Data ──────────────────────────────────────────────────────────────

local allEntries -- populated lazily on first open

-- Only include top-level categories that start with "spell"
local CATEGORY_FILTER = 'spell'

local function flattenTree(nodes, out, prefix)
    for _, node in ipairs(nodes) do
        if node.children then
            local cat = prefix and (prefix .. '/' .. node.text) or node.text
            -- At the top level (prefix == nil), skip non-spell categories
            if prefix ~= nil or cat:lower():find(CATEGORY_FILTER, 1, true) == 1 then
                flattenTree(node.children, out, cat)
            end
        elseif node.fileId then
            out[#out + 1] = {
                fileId = tonumber(node.fileId),
                name = node.text or node.value or '',
                category = prefix or '',
            }
        end
    end
end

local function getAll()
    if not allEntries then
        allEntries = {}
        flattenTree(WeakAuras.ModelPaths, allEntries, nil)
    end
    return allEntries
end

--#endregion

--#region ── Viewer state ──────────────────────────────────────────────────────

local ROW_H = 20
local FRAME_W = 740
local FRAME_H = 520
local LIST_W = 270

local v = {}         -- frame handles
local filtered = nil -- current filtered list
local rows = {}      -- reusable row buttons

local function applyFilter(text)
    local all = getAll()
    if not text or text == '' then
        filtered = all
    else
        local lo = text:lower()
        filtered = {}
        for _, e in ipairs(all) do
            if e.name:lower():find(lo, 1, true) or e.category:lower():find(lo, 1, true) then
                filtered[#filtered + 1] = e
            end
        end
    end
    v.count:SetText(#filtered .. ' models')
end

local function refreshRows()
    local list = filtered or {}
    local n = #list
    local maxOffset = math.max(0, n - #rows)
    v.offset = math.max(0, math.min(maxOffset, v.offset or 0))

    if v.scrollBar then
        v.scrollBar:SetMinMaxValues(0, maxOffset)
        v.scrollBar:SetValue(v.offset)
    end

    for i, row in ipairs(rows) do
        local idx = v.offset + i
        local entry = list[idx]
        if entry then
            row.label:SetText(entry.name)
            row.entry = entry
            row.idx = idx
            if idx == v.selected then
                row.selTex:Show()
            else
                row.selTex:Hide()
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

local function loadModel(entry)
    if not entry then return end
    v.actor:SetModelByFileID(entry.fileId)
    v.actor:SetAnimation(0)
    v.actor:SetPosition(0, 0, 0)
    v.camAngle = 0
    v.camPitch = 0
    v.camDist = 6
    v.updateCamera()

    -- Wait a frame for the model to finish loading, then read its bounding box
    -- and re-center the actor so the visual midpoint lands at the camera target (origin).
    C_Timer.After(0.1, function()
        if not v.actor or not v.actor.GetActiveBoundingBox then return end
        local x0, y0, z0, x1, y1, z1 = v.actor:GetActiveBoundingBox()
        if not z0 then return end
        local centerZ = (z0 + z1) / 2
        local size = math.max(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
        v.actor:SetPosition(0, 0, -centerZ)
        v.camDist = math.max(2, math.min(15, size * 1.5))
        v.updateCamera()
    end)
    v.infoName:SetText(entry.category ~= '' and (entry.category .. '/' .. entry.name) or entry.name)
    v.infoId:SetText('FileID: ' .. tostring(entry.fileId))
end

--#endregion

--#region ── Build UI ──────────────────────────────────────────────────────────

local function build()
    local f = CreateFrame('Frame', 'LibModelsViewerFrame', UIParent, 'BasicFrameTemplateWithInset')
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint('CENTER')
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart', f.StartMoving)
    f:SetScript('OnDragStop', f.StopMovingOrSizing)
    f:SetFrameStrata('DIALOG')
    f:SetClampedToScreen(true)
    f.TitleText:SetText('Model Viewer')
    v.frame = f

    -- TOP = title bar (~28px), sides/bottom = 10px
    local PAD_TOP = 32
    local PAD = 10

    -- Search box
    local search = CreateFrame('EditBox', nil, f, 'SearchBoxTemplate')
    search:SetSize(LIST_W - 4, 22)
    search:SetPoint('TOPLEFT', f, 'TOPLEFT', PAD, -PAD_TOP)
    search:SetScript('OnTextChanged', function(self)
        applyFilter(self:GetText())
        v.selected = nil
        v.offset = 0
        refreshRows()
    end)
    v.search = search

    -- Model count label
    local count = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    count:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', PAD, PAD)
    count:SetTextColor(0.5, 0.5, 0.5)
    v.count = count

    -- List container: rows are fixed children; clipped so they don't overflow
    local SCROLLBAR_W = 16
    local listHolder = CreateFrame('Frame', nil, f)
    listHolder:SetPoint('TOPLEFT', search, 'BOTTOMLEFT', 0, -2)
    listHolder:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', PAD, PAD + 16)
    listHolder:SetWidth(LIST_W - 4 - SCROLLBAR_W - 2)
    listHolder:SetClipsChildren(true)
    v.listHolder = listHolder

    -- Scrollbar (Slider)
    local bar = CreateFrame('Slider', nil, f, 'UIPanelScrollBarTemplate')
    bar:SetPoint('TOPLEFT', listHolder, 'TOPRIGHT', 2, -16)
    bar:SetPoint('BOTTOMLEFT', listHolder, 'BOTTOMRIGHT', 2, 16)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    bar:SetScript('OnValueChanged', function(_, val)
        v.offset = math.floor(val + 0.5)
        refreshRows()
    end)
    v.scrollBar = bar

    -- Mouse wheel on the list area
    listHolder:EnableMouseWheel(true)
    listHolder:SetScript('OnMouseWheel', function(_, delta)
        v.offset = v.offset or 0
        local list = filtered or {}
        local max = math.max(0, #list - #rows)
        v.offset = math.max(0, math.min(max, v.offset - delta * 3))
        refreshRows()
    end)

    -- Row button pool
    local numRows = math.floor((FRAME_H - 100) / ROW_H) + 2
    for i = 1, numRows do
        local row = CreateFrame('Button', nil, listHolder)
        row:SetSize(LIST_W - 24, ROW_H)
        row:SetPoint('TOPLEFT', 0, -(i - 1) * ROW_H)

        local hl = row:CreateTexture(nil, 'HIGHLIGHT')
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)
        row:SetHighlightTexture(hl)

        local sel = row:CreateTexture(nil, 'BACKGROUND')
        sel:SetAllPoints()
        sel:SetColorTexture(0.2, 0.55, 1, 0.25)
        sel:Hide()
        row.selTex = sel

        local lbl = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
        lbl:SetPoint('LEFT', 2, 0)
        lbl:SetPoint('RIGHT', -2, 0)
        lbl:SetJustifyH('LEFT')
        lbl:SetWordWrap(false)
        row.label = lbl

        row:SetScript('OnClick', function(self)
            if not self.entry then return end
            v.selected = self.idx
            loadModel(self.entry)
            refreshRows()
        end)

        rows[i] = row
    end

    -- Divider
    local div = f:CreateTexture(nil, 'BACKGROUND')
    div:SetPoint('TOPLEFT', f, 'TOPLEFT', LIST_W + PAD + 8, -PAD_TOP)
    div:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', LIST_W + PAD + 8, PAD)
    div:SetWidth(1)
    div:SetColorTexture(0.25, 0.25, 0.25, 1)

    -- ModelScene + actor: SetModelByFileID lives on ModelSceneActor in TWW
    local scene = CreateFrame('ModelScene', nil, f)
    scene:SetPoint('TOPLEFT', f, 'TOPLEFT', LIST_W + PAD + 14, -PAD_TOP)
    scene:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -PAD, PAD + 36)
    scene:EnableMouseWheel(true)
    scene:EnableMouse(true)

    if scene.SetCameraFieldOfView then scene:SetCameraFieldOfView(0.7) end
    if scene.SetLightDirection then scene:SetLightDirection(0.7, -0.7, 0.7) end
    if scene.SetLightAmbientColor then scene:SetLightAmbientColor(0.5, 0.5, 0.5) end
    if scene.SetLightDiffuseColor then scene:SetLightDiffuseColor(0.9, 0.9, 0.9) end

    local actor = scene:CreateActor() ---@type any
    actor:SetPosition(0, 0, 0)
    v.actor = actor
    v.scene = scene
    v.camAngle = 0
    v.camPitch = 0
    v.camDist = 6

    local function updateCamera()
        local hDist = v.camDist * math.cos(v.camPitch)
        local x = math.sin(v.camAngle) * hDist
        local y = -math.cos(v.camAngle) * hDist
        local z = v.camDist * math.sin(v.camPitch)
        scene:SetCameraPosition(x, y, z)

        if v.inputX and not v.inputX:HasFocus() then v.inputX:SetText(string.format("%.2f", x)) end
        if v.inputY and not v.inputY:HasFocus() then v.inputY:SetText(string.format("%.2f", y)) end
        if v.inputZ and not v.inputZ:HasFocus() then v.inputZ:SetText(string.format("%.2f", z)) end
        if v.inputZoom and not v.inputZoom:HasFocus() then v.inputZoom:SetText(string.format("%.2f", v.camDist)) end
    end
    v.updateCamera = updateCamera
    updateCamera()

    scene:SetScript('OnMouseWheel', function(_, delta)
        v.camDist = math.max(1, math.min(20, v.camDist - delta * 0.5))
        updateCamera()
    end)
    scene:SetScript('OnMouseDown', function(self, button)
        if button == 'LeftButton' then
            self._drag = true
            self._lastX, self._lastY = GetCursorPosition()
        end
    end)
    scene:SetScript('OnMouseUp', function(self) self._drag = false end)
    scene:SetScript('OnUpdate', function(self)
        if self._drag then
            local x, y = GetCursorPosition()
            v.camAngle = v.camAngle + (self._lastX - x) * 0.01
            v.camPitch = math.max(-1.4, math.min(1.4, v.camPitch + (self._lastY - y) * 0.01))
            updateCamera()
            self._lastX, self._lastY = x, y
        end
    end)

    -- Info bar below model
    local infoName = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    infoName:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', LIST_W + PAD + 14, PAD + 20)
    infoName:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -PAD, PAD + 20)
    infoName:SetJustifyH('LEFT')
    infoName:SetWordWrap(false)
    v.infoName = infoName

    local infoId = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    infoId:SetPoint('TOPLEFT', infoName, 'BOTTOMLEFT', 0, -1)
    infoId:SetTextColor(0.5, 0.5, 0.5)
    v.infoId = infoId

    local function applyXYZ()
        local nx, ny, nz = tonumber(v.inputX:GetText()) or 0, tonumber(v.inputY:GetText()) or 0,
            tonumber(v.inputZ:GetText()) or 0
        local dist3d = math.sqrt(nx * nx + ny * ny + nz * nz)
        if dist3d > 0.001 then
            v.camDist = dist3d
            v.camPitch = math.asin(math.max(-1, math.min(1, nz / dist3d)))
            v.camAngle = math.atan2(nx, -ny)
        end
        v.updateCamera()
    end

    local function applyZoom()
        local nzoom = tonumber(v.inputZoom:GetText())
        if nzoom then v.camDist = math.max(0.01, nzoom) end
        v.updateCamera()
    end

    local function createInput(relativeTo, offsetX, labelText, onEnter)
        local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        box:SetSize(45, 20)
        box:SetPoint("RIGHT", relativeTo, "LEFT", offsetX, 0)
        box:SetAutoFocus(false)
        box:SetFontObject("ChatFontNormal")
        box:SetScript("OnEscapePressed", function(self)
            self:ClearFocus(); v.updateCamera()
        end)
        box:SetScript("OnEnterPressed", function(self)
            self:ClearFocus(); onEnter(self)
        end)

        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("RIGHT", box, "LEFT", -5, 0)
        label:SetText(labelText)
        label:SetTextColor(0.5, 0.5, 0.5)

        return label, box
    end

    local zoomLabel, zoomBox = createInput(infoName, 0, "Zoom:", applyZoom)
    zoomBox:ClearAllPoints()
    zoomBox:SetPoint('TOPRIGHT', infoName, 'BOTTOMRIGHT', -5, -2)
    v.inputZoom = zoomBox
    local zLabel, zBox = createInput(zoomLabel, -15, "Z:", applyXYZ)
    v.inputZ = zBox
    local yLabel, yBox = createInput(zLabel, -15, "Y:", applyXYZ)
    v.inputY = yBox
    local xLabel, xBox = createInput(yLabel, -15, "X:", applyXYZ)
    v.inputX = xBox

    v.updateCamera() -- force initial text populate

    f:Hide()
end

--#endregion

--#region ── Public API ────────────────────────────────────────────────────────

function LibModels.Open()
    if not v.actor then
        v.frame = nil -- discard any partial build
        build()
    end
    if v.frame:IsShown() then
        v.frame:Hide()
    else
        v.frame:Show()
        applyFilter(v.search and v.search:GetText() or '')
        v.offset = 0
        refreshRows()
    end
end

--#endregion
