local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips       = addon:GetModule('Tips')

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

function tips.populateMountInfo(f, unit)
    local isPlayer = UnitIsPlayer(unit)
    if isPlayer then
        local mount = tips.getMountInfo(unit)
        if mount then
            f.mountDivider:Show()
            f.mountIcon:SetTexture(mount.icon)
            f.mountIconBorder:Show()
            f.mountIcon:Show()
            f.mountName:SetText(mount.name)
            f.mountSource:SetText(mount.source or "")
            f.mountCollected:SetAtlas(mount.isCollected and "VAS-icon-checkmark" or "common-icon-redx")
            f.mountCollected:Show()
        else
            f.mountDivider:Hide()
            f.mountIconBorder:Hide()
            f.mountIcon:Hide()
            f.mountName:SetText("")
            f.mountSource:SetText("")
            f.mountCollected:Hide()
        end
    else
        f.mountDivider:Hide()
        f.mountIconBorder:Hide()
        f.mountIcon:Hide()
        f.mountName:SetText("")
        f.mountSource:SetText("")
        f.mountCollected:Hide()
    end
end

function tips.buildMountInfo(f, overlay, subfont)
    -- Mount section
    f.mountDivider = overlay:CreateTexture(nil, "OVERLAY")
    f.mountDivider:SetAtlas("Adventure-MissionEnd-Line")
    f.mountDivider:SetHeight(8)
    f.mountDivider:Hide()

    f.mountIconBorder = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    f.mountIconBorder:SetAtlas("Relic-Wind-TraitBG")
    f.mountIconBorder:SetSize(tips.ICON_SIZE + 24, tips.ICON_SIZE + 24)
    f.mountIconBorder:Hide()

    f.mountIcon = overlay:CreateTexture(nil, "OVERLAY", nil, 0)
    f.mountIcon:SetSize(tips.ICON_SIZE - 2, tips.ICON_SIZE - 2)
    f.mountIcon:SetPoint("CENTER", f.mountIconBorder, "CENTER")
    f.mountIcon:Hide()

    local mountMask = overlay:CreateMaskTexture()
    mountMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE")
    mountMask:SetAllPoints(f.mountIcon)
    f.mountIcon:AddMaskTexture(mountMask)

    f.mountName      = tips.makeFontString(overlay, subfont, { 0.9, 0.85, 0.7 })
    f.mountSource    = tips.makeFontString(overlay, subfont, { 0.5, 0.5, 0.5 })
    f.mountCollected = overlay:CreateTexture(nil, "OVERLAY")
    f.mountCollected:SetSize(24, 24)
    f.mountCollected:Hide()
end

function tips.layoutMountInfo(f, y, height, fonts)
    if f.mountDivider:IsShown() then
        y = y - 8

        f.mountDivider:ClearAllPoints()
        f.mountDivider:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
        f.mountDivider:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
        local divH = f.mountDivider:GetHeight()
        y          = y - divH - tips.LINE_GAP
        height     = height + divH + tips.LINE_GAP

        -- Scale icon/border with TIP_W (same ratios as characteristics)
        local scaledBorderSz    = math.floor(tips.TIP_W * tips.ICON_X)
        local scaledIconSz      = math.floor(scaledBorderSz * (tips.ICON_SIZE - 2) / (tips.ICON_SIZE + 24))
        local scaledCollectedSz = math.floor(scaledBorderSz * 24 / (tips.ICON_SIZE + 24))

        f.mountIconBorder:SetSize(scaledBorderSz, scaledBorderSz)
        f.mountIcon:SetSize(scaledIconSz, scaledIconSz)
        f.mountCollected:SetSize(scaledCollectedSz, scaledCollectedSz)

        -- Icon on the left (same -2 x-offset as class icon border)
        f.mountIconBorder:ClearAllPoints()
        f.mountIconBorder:SetPoint("TOPLEFT", f, "TOPLEFT", tips.PADDING - 12, y + 8)

        -- Text starts at mountIcon's right edge + 10; derive available width from that
        local textLeftX  = -2 + math.floor(scaledBorderSz / 2) + math.floor(scaledIconSz / 2) + 10
        local mountTextW = tips.TIP_W - textLeftX - tips.PADDING

        f.mountName:SetFont(fonts.path, fonts.guildSize, fonts.flag)
        f.mountName:ClearAllPoints()
        f.mountName:SetWidth(math.max(mountTextW - scaledCollectedSz - tips.ICON_GAP, 20))
        f.mountName:SetPoint("TOPLEFT", f.mountIcon, "TOPRIGHT", 10, -4)

        f.mountSource:SetFont(fonts.path, fonts.guildSize, fonts.flag)
        f.mountSource:ClearAllPoints()
        f.mountSource:SetWidth(math.max(mountTextW, 20))
        f.mountSource:SetPoint("TOPLEFT", f.mountName, "BOTTOMLEFT", 0, -tips.LINE_GAP)

        f.mountCollected:ClearAllPoints()
        f.mountCollected:SetPoint("TOPLEFT", f.mountName, "TOPRIGHT", tips.ICON_GAP, 0)

        local nameH   = math.max(f.mountName:GetStringHeight(), 1)
        local sourceH = (f.mountSource:GetText() ~= "") and math.max(f.mountSource:GetStringHeight(), 1) or 0
        local rowH    = math.max(scaledIconSz, nameH + (sourceH > 0 and (tips.LINE_GAP + sourceH) or 0))
        y      = y - rowH - tips.LINE_GAP
        height = height + rowH + tips.LINE_GAP
    end
    return y, height
end
