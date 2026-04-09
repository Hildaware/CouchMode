local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips = addon:GetModule('Tips')

function tips.getMountInfo(unit)
    if not C_MountJournal or not C_UnitAuras then return nil end
    local i = 1
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not auraData then break end
        local spellID = auraData.spellId
        if spellID then
            local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
            if ok and mountID then
                local mOk, mName, _, mIcon, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID,
                    mountID)
                if mOk and mName then
                    local eOk, _, _, source = pcall(C_MountJournal.GetMountInfoExtraByID, mountID)
                    return { name = mName, icon = mIcon, isCollected = isCollected, source = eOk and source or nil }
                end
            end
        end
        i = i + 1
    end
    return nil
end

--#region ── Section build ────────────────────────────────────────────────────

function tips.buildMountInfo()
    ---@type MountSection
    local container = addon.Layout:VStack(UIParent, { spacing = 8 })
    local divH = 8

    -- Divider row
    local dividerRow = addon.Layout:Container(container)
    dividerRow:SetHeight(divH)
    container.mountDivider = dividerRow:AddBackground("Adventure-MissionEnd-Line")
    container:AddChild(dividerRow)

    -- Content row
    local contentRow = addon.Layout:HStack(container, { spacing = 4 })

    local iconStack = addon.Layout:Container(contentRow)
    container.mountIconBorder = iconStack:Texture("OVERLAY", 1, { atlas = "Relic-Wind-TraitBG" })
    container.mountIconBorder:SetAllPoints(iconStack)
    container.mountIconBorder:Hide()

    container.mountIcon = iconStack:Texture("OVERLAY", 0)
    container.mountIcon:SetPoint("CENTER", container.mountIconBorder, "CENTER")
    container.mountIcon:Hide()

    iconStack:Mask(container.mountIcon, { texture = "Interface\\CharacterFrame\\TempPortraitAlphaMask" })

    contentRow:AddChild(iconStack, { valign = "CENTER" })

    local fontPath, baseSize, fontFlag = tips.currentFont()
    local guildSize = math.max(8, math.floor(baseSize * 0.60))
    local guildFont = function() return fontPath, guildSize, fontFlag end
    container.mountFontSize = guildSize

    local textStack = addon.Layout:VStack(contentRow, { spacing = tips.LINE_GAP })
    container.mountName = textStack:FontString({ font = guildFont, color = { 0.9, 0.85, 0.7 }, justifyH = "LEFT" })
    container.mountSource = textStack:FontString({ font = guildFont, color = { 0.5, 0.5, 0.5 }, justifyH = "LEFT" })
    textStack:AddChild(container.mountName, { fillWidth = true, widthOffset = -(tips.ICON_SIZE + tips.ICON_GAP) })
    textStack:AddChild(container.mountSource, { fillWidth = true })
    contentRow:AddChild(textStack, { valign = "CENTER" })

    container.mountCollected = contentRow:Texture("OVERLAY")
    container.mountCollected:Hide()

    container:AddChild(contentRow)

    container.hasData = false

    --#region populate

    function container:populate(unit)
        if not UnitIsPlayer(unit) then
            self.hasData = false
            return
        end
        local mount = tips.getMountInfo(unit)
        if mount then
            self.mountIcon:SetTexture(mount.icon)
            self.mountIconBorder:Show()
            self.mountIcon:Show()
            self.mountName:SetText(mount.name)
            self.mountSource:SetText(mount.source or "")
            self.mountCollected:SetAtlas(mount.isCollected and "VAS-icon-checkmark" or "common-icon-redx")
            self.mountCollected:Show()
            self.hasData = true
        else
            self.hasData = false
        end
    end

    --#endregion

    --#region draw

    function container:naturalWidth()
        local scaledBorderSz    = math.floor(tips.TIP_W * tips.ICON_X)
        local scaledCollectedSz = math.floor(scaledBorderSz * 24 / (tips.ICON_SIZE + 24))
        local nameW   = self.mountName:GetStringWidth()
        local sourceW = self.mountSource:GetStringWidth()
        return math.ceil(scaledBorderSz + math.max(nameW + scaledCollectedSz + tips.ICON_GAP, sourceW) + tips.PADDING + 4)
    end

    function container:draw(w)
        if not self.hasData then
            self:SetHeight(0)
            return
        end

        local scaledBorderSz    = math.floor(w * tips.ICON_X)
        local scaledIconSz      = math.floor(scaledBorderSz * (tips.ICON_SIZE - 2) / (tips.ICON_SIZE + 24))
        local scaledCollectedSz = math.floor(scaledBorderSz * 24 / (tips.ICON_SIZE + 24))

        dividerRow:SetWidth(w)

        iconStack:SetSize(scaledBorderSz, scaledBorderSz)
        self.mountIcon:SetSize(scaledIconSz, scaledIconSz)
        self.mountCollected:SetSize(scaledCollectedSz, scaledCollectedSz)

        local textW = w - scaledBorderSz - tips.PADDING - 4
        textStack:SetWidth(textW)
        self.mountName:SyncHeight()
        self.mountSource:SyncHeight()
        textStack:Layout()

        local rowH = math.max(scaledIconSz, textStack:GetTotalHeight())
        contentRow:SetHeight(rowH)
        contentRow:Layout()

        self:Layout(-6)
        self:SetWidth(w)

        self.mountCollected:SetPoint("TOPRIGHT", self, "TOPRIGHT", -8, -20)
    end

    --#endregion

    --#region reset

    function container:reset()
        self.hasData = false
        self.mountIconBorder:Hide()
        self.mountIcon:Hide()
        self.mountName:SetText("");   self.mountName:SetWidth(0)
        self.mountSource:SetText(""); self.mountSource:SetWidth(0)
        self.mountCollected:Hide()
        self:SetHeight(0)
    end

    --#endregion

    return container
end

--#endregion
