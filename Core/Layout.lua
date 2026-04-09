local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class CouchModeLayout
---@field Container  fun(self: CouchModeLayout, parent: LayoutParent, opts?: LayoutContainerOpts): LayoutContainer
---@field VStack     fun(self: CouchModeLayout, parent: LayoutParent, opts?: LayoutContainerOpts): LayoutVStack
---@field HStack     fun(self: CouchModeLayout, parent: LayoutParent, opts?: LayoutContainerOpts): LayoutHStack
---@field FontString fun(self: CouchModeLayout, parent: LayoutParent, opts?: LayoutFontStringOpts): LayoutFontString
addon.Layout = {}
local Layout = addon.Layout

---@alias LayoutParent Frame|LayoutContainer|LayoutFontString|LayoutTexture

---@param v LayoutParent
---@return Frame
local function resolve(v)
    return (type(v) == "table" and v.frame) or v
end

-- Unwraps LayoutTexture (.tex), LayoutContainer (.frame), LayoutFontString (.region),
-- or passes through raw regions.
local function resolveAnchor(v)
    if type(v) ~= "table" then return v end
    return v.tex or v.frame or v.region or v
end

--#region ── Container ────────────────────────────────────────────────────────
-- Base class for all layout primitives. Creates a backing WoW Frame parented
-- to `parent` (which can be a WoW Frame or another Container).
-- All Stacks build on top of this.
--
-- Usage:
--   local c = Layout:Container(parent)
--   c.frame          -- the backing WoW Frame
--   c:Show() / c:Hide() / c:SetSize(w, h)

---@class LayoutContainerOpts
---@field frameLevel?      integer
---@field frameStrata?     FrameStrata
---@field width?           number
---@field height?          number
---@field movable?         boolean
---@field clampedToScreen? boolean
---@field enableMouse?     boolean
---@field registerForDrag? string|string[]
---@field spacing?         number

---@class LayoutBackgroundOpts
---@field layer?  DrawLayer
---@field alpha?  number
---@field width?  number
---@field insets? { left?: number, top?: number, right?: number, bottom?: number }

---@class LayoutTextureOpts
---@field atlas?   string
---@field texture? string
---@field size?    number|{ w: number, h: number }

---@class LayoutMaskOpts
---@field texture? string
---@field atlas?   string
---@field wrapH?   WrapMode
---@field wrapV?   WrapMode

---@class LayoutTexture: Texture
---@field tex Texture

---@class LayoutContainer: Frame
---@field frame         Frame
---@field Show          fun(self: LayoutContainer)
---@field Hide          fun(self: LayoutContainer)
---@field SetSize       fun(self: LayoutContainer, w: number, h: number)
---@field SetWidth      fun(self: LayoutContainer, w: number)
---@field SetHeight     fun(self: LayoutContainer, h: number)
---@field Movable       fun(self: LayoutContainer, onDragStart: function, onDragStop: function): LayoutContainer
---@field AddBackground fun(self: LayoutContainer, source: string, bgOpts?: LayoutBackgroundOpts): Texture
---@field SetPoint      fun(self: LayoutContainer, point: FramePoint, relativeTo: any, relativePoint: FramePoint, x?: number, y?: number)
---@field SetAllPoints  fun(self: LayoutContainer, relativeTo?: any)
---@field FontString    fun(self: LayoutContainer, opts?: LayoutFontStringOpts): LayoutFontString
---@field Texture       fun(self: LayoutContainer, drawLayer: DrawLayer, subLevel?: integer|LayoutTextureOpts, opts?: LayoutTextureOpts): LayoutTexture
---@field Mask          fun(self: LayoutContainer, textureToMask: Texture|LayoutTexture, opts: LayoutMaskOpts)

---@param parent LayoutParent
---@param opts?  LayoutContainerOpts
---@return LayoutContainer
function Layout:Container(parent, opts)
    local obj = {
        frame = CreateFrame("Frame", nil, resolve(parent) or UIParent),
    }

    -- Apply construction opts to the backing frame
    if opts then
        if opts.frameLevel then obj.frame:SetFrameLevel(opts.frameLevel) end
        if opts.frameStrata then obj.frame:SetFrameStrata(opts.frameStrata) end
        if opts.width then obj.frame:SetWidth(opts.width) end
        if opts.height then obj.frame:SetHeight(opts.height) end
        if opts.movable then obj.frame:SetMovable(true) end
        if opts.clampedToScreen then obj.frame:SetClampedToScreen(true) end
        if opts.enableMouse then obj.frame:EnableMouse(true) end
        if opts.registerForDrag then
            if type(opts.registerForDrag) == "table" then
                obj.frame:RegisterForDrag(unpack(opts.registerForDrag))
            else
                obj.frame:RegisterForDrag(opts.registerForDrag)
            end
        end
    end

    -- Forward unknown keys/calls to the backing frame
    setmetatable(obj, {
        __index = function(t, k)
            local frame = rawget(t, "frame")
            local v = frame and frame[k]
            if type(v) == "function" then
                return function(_, ...) return v(frame, ...) end
            end
            return v
        end,
    })

    function obj:SetPoint(point, relativeTo, relativePoint, x, y)
        self.frame:SetPoint(point, resolveAnchor(relativeTo), relativePoint, x, y)
    end

    function obj:SetAllPoints(relativeTo)
        self.frame:SetAllPoints(resolveAnchor(relativeTo))
    end

    function obj:Show() self.frame:Show() end

    function obj:Hide() self.frame:Hide() end

    function obj:SetSize(w, h) self.frame:SetSize(w, h) end

    function obj:SetWidth(w) self.frame:SetWidth(w) end

    function obj:SetHeight(h) self.frame:SetHeight(h) end

    function obj:Movable(onDragStart, onDragStop)
        self.frame:SetMovable(true)
        self.frame:SetClampedToScreen(true)
        self.frame:EnableMouse(true)
        self.frame:RegisterForDrag("LeftButton")
        self.frame:SetScript("OnDragStart", onDragStart)
        self.frame:SetScript("OnDragStop", onDragStop)
        return obj
    end

    -- Creates a texture anchored to this container's frame.
    -- source: atlas name, or texture path (detected by presence of \ or /).
    -- bgOpts: { layer, alpha, width, insets = { left, top, right, bottom } }
    --   insets map directly to TOPLEFT / BOTTOMRIGHT SetPoint offsets.
    --   Omitting insets uses SetAllPoints.
    function obj:AddBackground(source, bgOpts)
        local layer = bgOpts and bgOpts.layer or "BACKGROUND"
        local texture = self.frame:CreateTexture(nil, layer)

        if source:find("[/\\]") then
            texture:SetTexture(source)
        else
            texture:SetAtlas(source)
        end

        if bgOpts then
            if bgOpts.alpha then texture:SetAlpha(bgOpts.alpha) end
            if bgOpts.width then texture:SetWidth(bgOpts.width) end
            if bgOpts.vertexColor then texture:SetVertexColor(unpack(bgOpts.vertexColor)) end
            local ins = bgOpts.insets
            if ins then
                texture:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                    ins.left or 0, ins.top or 0)
                texture:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT",
                    ins.right or 0, ins.bottom or 0)
            else
                texture:SetAllPoints(self.frame)
            end
        else
            texture:SetAllPoints(self.frame)
        end

        return texture
    end

    function obj:FontString(fontOpts)
        return Layout:FontString(self, fontOpts)
    end

    function obj:Texture(drawLayer, subLevelOrOpts, texOpts)
        local subLevel = type(subLevelOrOpts) ~= "table" and subLevelOrOpts or nil
        local o = type(subLevelOrOpts) == "table" and subLevelOrOpts or texOpts
        local tex = self.frame:CreateTexture(nil, drawLayer, nil, subLevel)
        if o then
            if o.atlas then tex:SetAtlas(o.atlas) end
            if o.texture then tex:SetTexture(o.texture) end
            if o.size then
                if type(o.size) == "number" then
                    tex:SetSize(o.size, o.size)
                else
                    tex:SetSize(o.size.w, o.size.h)
                end
            end
        end
        local wrapper = { tex = tex }
        setmetatable(wrapper, {
            __index = function(t, k)
                local tx = rawget(t, "tex")
                local v = tx and tx[k]
                if type(v) == "function" then
                    return function(_, ...) return v(tx, ...) end
                end
                return v
            end,
        })
        function wrapper:SetPoint(point, relativeTo, relativePoint, x, y)
            tex:SetPoint(point, resolveAnchor(relativeTo), relativePoint, x, y)
        end

        function wrapper:SetAllPoints(relativeTo)
            tex:SetAllPoints(resolveAnchor(relativeTo))
        end

        return wrapper --[[@as LayoutTexture]]
    end

    function obj:Mask(textureToMask, maskOpts)
        local target = (type(textureToMask) == "table" and textureToMask.tex) or textureToMask
        local mask = self.frame:CreateMaskTexture()
        if maskOpts.atlas then
            mask:SetAtlas(maskOpts.atlas)
        else
            mask:SetTexture(maskOpts.texture, maskOpts.wrapH or "CLAMPTOBLACKADDITIVE",
                maskOpts.wrapV or "CLAMPTOBLACKADDITIVE")
        end
        mask:SetAllPoints(target)
        target:AddMaskTexture(mask)
    end

    return obj --[[@as LayoutContainer]]
end

--#endregion

--#region ── VStack ────────────────────────────────────────────────────────────
-- Stacks children top-to-bottom inside self.frame.
-- Children can be WoW regions or other Containers (resolved via .frame).
-- ClearAllPoints is always called on every child so stale anchors don't persist.
--
-- Usage:
--   local s = Layout:VStack(parent, { spacing = N })
--   s:AddChild(item [, { xOffset, yOffset }])
--   local blockH = s:GetTotalHeight()     -- query before Layout for centering
--   local totalH, finalY = s:Layout([x [, startY]])

---@class LayoutChildOpts
---@field xOffset?      number
---@field yOffset?      number
---@field fillWidth?    boolean  -- stretch child to stack width
---@field widthOffset?  number   -- subtracted from stack width when fillWidth=true

---@class LayoutVStack: LayoutContainer
---@field AddChild       fun(self: LayoutVStack, item: LayoutParent, childOpts?: LayoutChildOpts)
---@field ClearChildren  fun(self: LayoutVStack)
---@field GetTotalHeight fun(self: LayoutVStack): number
---@field Layout         fun(self: LayoutVStack, x?: number, startY?: number): number, number

---@param parent LayoutParent
---@param opts?  LayoutContainerOpts
---@return LayoutVStack
function Layout:VStack(parent, opts)
    local obj = self:Container(parent, opts) --[[@as LayoutVStack]]
    local spacing = (opts and opts.spacing) or 0
    local children = {}

    function obj:AddChild(item, childOpts)
        children[#children + 1] = {
            region      = resolve(item),
            xOffset     = childOpts and childOpts.xOffset or 0,
            yOffset     = childOpts and childOpts.yOffset or 0,
            fillWidth   = childOpts and childOpts.fillWidth or false,
            widthOffset = childOpts and childOpts.widthOffset or 0,
        }
    end

    function obj:GetTotalHeight()
        local total = 0
        local first = true
        for _, child in ipairs(children) do
            local h = child.region:GetHeight()
            if h and h > 0 then
                if not first then total = total + spacing end
                total = total + h
                first = false
            end
        end
        return total
    end

    function obj:ClearChildren()
        children = {}
    end

    -- Positions all children relative to self.frame TOPLEFT.
    -- x: horizontal offset within self.frame (default 0).
    -- startY: negative offset from top (default 0 = flush with top edge).
    -- Returns: totalH, finalY.
    function obj:Layout(x, startY)
        local y = startY or 0
        local totalH = 0
        local first = true
        local frameW = self.frame:GetWidth()
        for _, child in ipairs(children) do
            if child.fillWidth and frameW and frameW > 0 then
                child.region:SetWidth(math.max(frameW + (child.widthOffset or 0), 1))
            end
            local h = child.region:GetHeight()
            child.region:ClearAllPoints()
            if h and h > 0 then
                if not first then
                    y = y - spacing
                    totalH = totalH + spacing
                end
                child.region:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                    (x or 0) + child.xOffset, y + child.yOffset)
                y = y - h
                totalH = totalH + h
                first = false
            end
        end
        if totalH > 0 then self.frame:SetHeight(totalH) end
        return totalH, y
    end

    return obj --[[@as LayoutVStack]]
end

--#endregion

--#region ── HStack ────────────────────────────────────────────────────────────
-- Stacks children left-to-right inside self.frame.
-- Children can be WoW regions or other Containers.
-- ClearAllPoints is always called on every child.
--
-- Usage:
--   local s = Layout:HStack(parent, { spacing = N })
--   s:AddChild(item, { xOffset, yOffset, valign = "TOP"|"CENTER" })
--     valign = "TOP":    align to the top of self.frame (default).
--     valign = "CENTER": auto-center vertically within self.frame:GetHeight()
--                        at Layout time; combined with any explicit yOffset.
--   local totalW = s:Layout([startX [, y]])

---@class LayoutHChildOpts: LayoutChildOpts
---@field valign? "TOP"|"CENTER"

---@class LayoutHStack: LayoutContainer
---@field AddChild fun(self: LayoutHStack, item: LayoutParent, childOpts?: LayoutHChildOpts)
---@field Layout   fun(self: LayoutHStack, startX?: number, y?: number): number

---@param parent LayoutParent
---@param opts?  LayoutContainerOpts
---@return LayoutHStack
function Layout:HStack(parent, opts)
    local obj = self:Container(parent, opts) --[[@as LayoutHStack]]
    local spacing = (opts and opts.spacing) or 0
    local children = {}

    function obj:AddChild(item, childOpts)
        children[#children + 1] = {
            region = resolve(item),
            xOffset = childOpts and childOpts.xOffset or 0,
            yOffset = childOpts and childOpts.yOffset or 0,
            valign = childOpts and childOpts.valign,
        }
    end

    -- Positions all children relative to self.frame TOPLEFT.
    -- startX: initial x offset (default 0).
    -- y: baseline vertical offset for all children (default 0).
    -- Children with valign = "CENTER" are auto-centered vertically within
    -- self.frame:GetHeight(); any explicit yOffset is applied on top.
    -- Returns: totalW.
    function obj:Layout(startX, y)
        local x = startX or 0
        local totalW = 0
        local first = true
        local frameH = self.frame:GetHeight()
        for _, child in ipairs(children) do
            local w = child.region:GetWidth()
            child.region:ClearAllPoints()
            if w and w > 0 then
                if not first then
                    x = x + spacing
                    totalW = totalW + spacing
                end
                local autoY = 0
                if child.valign == "CENTER" and frameH and frameH > 0 then
                    local h = child.region:GetHeight()
                    autoY = -math.floor((frameH - (h or 0)) / 2)
                end
                child.region:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                    x + child.xOffset, (y or 0) + child.yOffset + autoY)
                x = x + w
                totalW = totalW + w
                first = false
            end
        end
        if totalW > 0 then self.frame:SetWidth(totalW) end
        return totalW
    end

    return obj --[[@as LayoutHStack]]
end

--#endregion

--#region ── FontString ───────────────────────────────────────────────────────
-- Creates a FontString on `parent` (WoW Frame or Container). Unknown method
-- calls forward to the backing WoW FontString.
--
-- opts fields (all optional):
--   font     : zero-arg fn → (path, size, flags)  passed to SetFont
--   color    : { r, g, b }                         passed to SetVertexColor
--   justifyH : "LEFT"|"CENTER"|"RIGHT"             passed to SetJustifyH
--   justifyV : "TOP"|"MIDDLE"|"BOTTOM"             passed to SetJustifyV
--   wrap     : true|false                          passed to SetWordWrap
--   maxLines : N                                   passed to SetMaxLines
--
-- Usage:
--   local fs = Layout:FontString(frame, { font = myFontFn, color = { 1, 0.82, 0 }, justifyH = "LEFT" })
--   fs:SetTruncatedText(text, maxWidth)              -- truncate plain text with "..."
--   fs:SetTruncatedColorText(raw, colorPrefix, maxW) -- truncate then wrap in color code
--   fs:SyncHeight()                                  -- set height to string height, or 0 if empty

---@class LayoutFontStringOpts
---@field font?     fun(): string, number, string
---@field color?    number[]
---@field justifyH? "LEFT"|"CENTER"|"RIGHT"
---@field justifyV? "TOP"|"MIDDLE"|"BOTTOM"
---@field wrap?     boolean
---@field maxLines? integer

---@class LayoutFontString: FontString
---@field fs                    FontString
---@field region                FontString
---@field SetTruncatedText      fun(self: LayoutFontString, text: string, maxWidth: number)
---@field SetTruncatedColorText fun(self: LayoutFontString, text: string, colorPrefix: string, maxWidth: number)
---@field SyncHeight            fun(self: LayoutFontString)
---@field SetPoint              fun(self: LayoutFontString, point: FramePoint, relativeTo: any, relativePoint: FramePoint, x?: number, y?: number)
---@field SetAllPoints          fun(self: LayoutFontString, relativeTo?: any)

---@param parent LayoutParent
---@param opts?  LayoutFontStringOpts
---@return LayoutFontString
function Layout:FontString(parent, opts)
    local fs = resolve(parent):CreateFontString(nil, "OVERLAY")
    if opts then
        if opts.font then fs:SetFont(opts.font()) end
        if opts.color then fs:SetVertexColor(unpack(opts.color)) end
        if opts.justifyH then fs:SetJustifyH(opts.justifyH) end
        if opts.justifyV then fs:SetJustifyV(opts.justifyV) end
        if opts.wrap ~= nil then fs:SetWordWrap(opts.wrap) end
        if opts.maxLines then fs:SetMaxLines(opts.maxLines) end
    end

    local obj = { fs = fs, region = fs }

    setmetatable(obj, {
        __index = function(t, k)
            local fontstr = rawget(t, "fs")
            local v = fontstr and fontstr[k]
            if type(v) == "function" then
                return function(_, ...) return v(fontstr, ...) end
            end
            return v
        end,
    })

    -- Truncates text to fit maxWidth pixels, appending "..." if needed.
    -- Requires the fontstring to already have its font set.
    function obj:SetTruncatedText(text, maxWidth)
        if not text or text == "" then return end
        self:SetText(text)
        if self:GetStringWidth() <= maxWidth then return end
        local lo, hi = 0, #text
        while lo < hi do
            local mid = math.ceil((lo + hi) / 2)
            self:SetText(text:sub(1, mid) .. "...")
            if self:GetStringWidth() <= maxWidth then lo = mid else hi = mid - 1 end
        end
        self:SetText(text:sub(1, lo) .. "...")
    end

    -- Like SetTruncatedText but wraps the result in colorPrefix...|r.
    -- Use when the raw text must be stored separately from its color code (e.g. to
    -- measure string width without color escape overhead).
    function obj:SetTruncatedColorText(text, colorPrefix, maxWidth)
        if not text or text == "" then return end
        local truncated = text
        self:SetText(truncated)
        if self:GetStringWidth() > maxWidth then
            local lo, hi = 0, #text
            while lo < hi do
                local mid = math.ceil((lo + hi) / 2)
                self:SetText(text:sub(1, mid) .. "...")
                if self:GetStringWidth() <= maxWidth then lo = mid else hi = mid - 1 end
            end
            truncated = text:sub(1, lo) .. "..."
        end
        self:SetText((colorPrefix or "") .. truncated .. "|r")
    end

    -- Sets height to the rendered string height when non-empty, or 0 when empty.
    -- Keeps VStack measurement accurate for fontstrings that may have no text.
    function obj:SyncHeight()
        local t = self:GetText()
        self:SetHeight((t and t ~= "") and math.max(self:GetStringHeight(), 1) or 0)
    end

    function obj:SetPoint(point, relativeTo, relativePoint, x, y)
        fs:SetPoint(point, resolveAnchor(relativeTo), relativePoint, x, y)
    end

    function obj:SetAllPoints(relativeTo)
        fs:SetAllPoints(resolveAnchor(relativeTo))
    end

    return obj --[[@as LayoutFontString]]
end

--#endregion
