local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips = addon:GetModule('Tips')

tips.CREATURE_TYPE_SET = {
    ["Beast"] = true,
    ["Dragonkin"] = true,
    ["Demon"] = true,
    ["Elemental"] = true,
    ["Giant"] = true,
    ["Undead"] = true,
    ["Humanoid"] = true,
    ["Critter"] = true,
    ["Mechanical"] = true,
    ["Not specified"] = true,
    ["Totem"] = true,
    ["Non-combat Pet"] = true,
    ["Gas Cloud"] = true,
    ["Wild Pet"] = true,
    ["Aberration"] = true,
}

--#region ── Section build ────────────────────────────────────────────────────

function tips.buildCharacteristics()
    ---@type CharSection
    local container = addon.Layout:HStack(UIParent, { spacing = 0 })

    local iconStack = addon.Layout:Container(container, { width = tips.ICON_SIZE + 24 })

    local classIconBorder = iconStack:Texture("OVERLAY", 1, { atlas = "Relic-Fire-TraitBG" })
    classIconBorder:SetAllPoints(iconStack)
    classIconBorder:Hide()
    container.classIconBorder = classIconBorder

    local classIcon = iconStack:Texture("OVERLAY", 0, { size = { w = tips.ICON_SIZE - 2, h = tips.ICON_SIZE - 2 } })
    classIcon:SetPoint("CENTER", classIconBorder, "CENTER")
    classIcon:Hide()
    container.classIcon = classIcon

    iconStack:Mask(classIcon,
        {
            atlas = "CircleMaskScalable",
            wrapH = "CLAMPTOBLACKADDITIVE",
            wrapV =
            "CLAMPTOBLACKADDITIVE"
        })

    container:AddChild(iconStack, { valign = "CENTER" })

    -- Info line
    local _, baseSize = tips.currentFont()
    container.charFontSize = baseSize
    container.info = addon.Layout:FontString(container,
        { font = tips.currentFont, color = { 0.6, 0.6, 0.6 }, wrap = true, maxLines = 2, justifyH = "LEFT" })

    container:AddChild(container.info, { valign = "CENTER" })

    -- Data fields
    container.hasData = false

    --#region populate

    function container:populate(unit)
        local isPlayer = UnitIsPlayer(unit)
        if isPlayer then
            local rpRace = addon.TRPUtils.getRPRace(unit)
            local rpClass = addon.TRPUtils.getRPClass(unit)

            if rpRace or rpClass then
                local parts = {}
                if rpRace then parts[#parts + 1] = rpRace end
                if rpClass then parts[#parts + 1] = rpClass end
                self.info:SetText(table.concat(parts, " "))
                local r, g, b = addon.TRPUtils.getRPColor(unit)
                if r then
                    self.info:SetVertexColor(r, g, b)
                else
                    local _, classToken = UnitClass(unit)
                    local cc = classToken and RAID_CLASS_COLORS[classToken]
                    if cc then self.info:SetVertexColor(cc.r, cc.g, cc.b) end
                end
                local rpIcon = addon.TRPUtils.getRPIcon(unit)
                if rpIcon then
                    self.classIcon:SetTexture("Interface/icons/" .. rpIcon)
                else
                    self.classIcon:SetTexture("Interface/AddOns/totalRP3/Resources/trp3logo")
                end
                self.classIcon:Show()
                self.classIconBorder:Show()
                self.hasData = true
            else
                local className, classToken = UnitClass(unit)
                local cc = classToken and RAID_CLASS_COLORS[classToken]
                local specInfo = addon.TipsUtils and addon.TipsUtils.getSpecData(unit)
                if cc then self.info:SetVertexColor(cc.r, cc.g, cc.b) end
                self.classIconBorder:Show()
                if specInfo then
                    self.classIcon:SetTexture(specInfo.specIcon)
                    self.info:SetText(specInfo.specName .. " " .. (className or ""))
                else
                    self.classIcon:SetAtlas("BfAMission-Icon-Normal")
                    self.info:SetText(className or "")
                end
                self.classIcon:Show()
                self.hasData = (className ~= nil) or (specInfo ~= nil)
            end
        else
            self.classIconBorder:Hide()
            self.classIcon:Hide()
            local creatureType = UnitCreatureType(unit)
            self.info:SetText(creatureType or "")
            self.info:SetTextColor(1, 1, 1)
            self.hasData = (creatureType ~= nil)
        end
    end

    --#endregion

    --#region draw

    function container:naturalWidth()
        local borderShown    = self.classIconBorder:IsShown()
        local scaledBorderSz = math.floor(tips.TIP_W * tips.ICON_X)
        return math.ceil((borderShown and scaledBorderSz + 4 or 0) + self.info:GetStringWidth() + tips.PADDING)
    end

    function container:draw(w)
        if not self.hasData then
            self:SetHeight(0)
            return
        end

        local borderShown    = self.classIconBorder:IsShown()
        local scaledBorderSz = math.floor(w * tips.ICON_X)
        local scaledIconSz   = math.floor(scaledBorderSz * (tips.ICON_SIZE - 2) / (tips.ICON_SIZE + 24))
        local scaledEffectH  = math.floor(scaledBorderSz * (tips.ICON_SIZE + 4) / (tips.ICON_SIZE + 24))

        if borderShown then
            iconStack:SetSize(scaledBorderSz, scaledBorderSz)
            self.classIcon:SetSize(scaledIconSz, scaledIconSz)
        else
            iconStack:SetSize(0, 0)
        end

        local textH = self.charFontSize * 2 + tips.LINE_GAP
        local infoW = w - (borderShown and scaledBorderSz + 4 or 0) - tips.PADDING
        self.info:SetWidth(math.max(infoW, 20))
        self.info:SetHeight(textH)

        self:SetHeight(math.max(borderShown and scaledEffectH or 0, textH, 1) + tips.LINE_GAP)
        self:Layout(borderShown and -6 or tips.PADDING)
        self:SetWidth(w)
    end

    --#endregion

    --#region reset

    function container:reset()
        self.hasData = false
        self.classIcon:Hide()
        self.classIconBorder:Hide()
        self.info:SetText("")
        self.info:SetWidth(0)
        self:SetHeight(0)
    end

    --#endregion

    return container
end

--#endregion
