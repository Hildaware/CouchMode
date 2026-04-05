local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips       = addon:GetModule('Tips')

local hexColor   = addon.Utils.hexColor

function tips.nameColor(unit)
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS[class]
        if c then return hexColor(c.r, c.g, c.b) end
    end
    if UnitCanAttack("player", unit) then
        local c = FACTION_BAR_COLORS[4]
        return c and hexColor(c.r, c.g, c.b) or "|cFFFFD200"
    end
    local reaction = UnitReaction(unit, "player")
    if reaction and reaction > 4 then return "|cFFFFFFFF" end
    local c = reaction and FACTION_BAR_COLORS[reaction]
    return c and hexColor(c.r, c.g, c.b) or "|cFFFFFFFF"
end

tips.CLASSIFICATION_ATLAS = {
    elite     = "nameplates-icon-elite-gold",
    rareelite = "nameplates-icon-rareelite",
    rare      = "nameplates-icon-elite-silver",
    worldboss = "nameplates-icon-elite-gold",
}

local subtitleCache = {}
local factionCache = {}

function tips.wipeSubtitleCache()
    wipe(subtitleCache)
    wipe(factionCache)
    addon.QuestUtils.wipeCache()
end

function tips.getSubtitle(unit)
    if UnitIsPlayer(unit) then
        return GetGuildInfo(unit)
    end

    -- GUIDs and tooltip text are secret strings in instances; pattern matching and
    -- table indexing on them are forbidden there.
    local _, instanceType = IsInInstance()
    if instanceType ~= "none" then return nil end

    local guid = UnitGUID(unit)
    if guid and subtitleCache[guid] ~= nil then
        return subtitleCache[guid] or nil
    end

    local tooltipData = C_TooltipInfo.GetUnit(unit)
    local subtitle
    if tooltipData and tooltipData.lines and tooltipData.lines[2] then
        local text = tooltipData.lines[2].leftText
        if text and text ~= "" and not text:match("^Level %d") and not text:match("^%?%?") then
            subtitle = text
        end
    end

    if guid then subtitleCache[guid] = subtitle or false end
    return subtitle
end

function tips.getFaction(unit)
    local _, instanceType = IsInInstance()
    if instanceType ~= "none" then return nil end

    local guid = UnitGUID(unit)
    if guid and factionCache[guid] ~= nil then
        return factionCache[guid] or nil
    end

    local faction
    local tooltipData = C_TooltipInfo.GetUnit(unit)
    if tooltipData and tooltipData.lines then
        local pastLevel = false
        for i = 2, #tooltipData.lines do
            local text = tooltipData.lines[i].leftText
            if text and text ~= "" then
                if text:match("^Level ") or text:match("^%?%?") then
                    pastLevel = true
                elseif pastLevel and not tips.CREATURE_TYPE_SET[text] then
                    faction = text
                    break
                end
            end
        end
    end

    if guid then factionCache[guid] = faction or false end
    return faction
end

function tips.populateUnitInfo(f, unit)
    local isPlayer = UnitIsPlayer(unit)
    local baseName = UnitName(unit) or ""
    f.name:SetText(tips.nameColor(unit) .. baseName .. "|r")

    if isPlayer then
        -- Split PvP title from name: may be prefix ("Private Brandon") or suffix ("Brandon the Explorer").
        -- UnitName/UnitPVPName are secret strings in instances — string operations on them are forbidden there.
        local _, instanceType = IsInInstance()
        local pvpName = UnitPVPName(unit) or baseName
        if pvpName ~= baseName and instanceType == "none" then
            local s, e = pvpName:find(baseName, 1, true)
            f.pretitle:SetText(s and s > 1 and pvpName:sub(1, s - 1):match("^%s*(.-)%s*$") or "")
            f.posttitle:SetText(e and e < #pvpName and pvpName:sub(e + 1):match("^[%s,]*(.-)%s*$") or "")
        else
            f.pretitle:SetText("")
            f.posttitle:SetText("")
        end
    else
        f.pretitle:SetText("")
        f.posttitle:SetText("")
    end

    -- SUBTITLE: guild (players) or NPC sub-name
    local subtitle = tips.getSubtitle(unit)
    if subtitle then
        f.subtitle:SetText(subtitle)
        if isPlayer then
            local gc = ChatTypeInfo["GUILD"]
            f.subtitle:SetVertexColor(gc.r, gc.g, gc.b)
        else
            f.subtitle:SetVertexColor(0.7, 0.7, 0.7)
        end
    else
        f.subtitle:SetText("")
    end

    -- LEVEL BADGE / FACTION
    local isFriendlyNPC = not isPlayer and not UnitCanAttack("player", unit)
    if isFriendlyNPC then
        f.level:SetText("")
        f.levelBadge:Hide()
        f.classificationIcon:Hide()
        local faction = tips.getFaction(unit)
        if faction then
            local reaction = UnitReaction(unit, "player")
            local fc = reaction and FACTION_BAR_COLORS[reaction]
            f.faction:SetVertexColor(fc and fc.r or 0.7, fc and fc.g or 0.7, fc and fc.b or 0.7)
            f.faction:SetText(faction)
        else
            f.faction:SetText("")
        end
    else
        local lvl    = UnitLevel(unit)
        -- Just the number (or "??"), no "Level" prefix — badge provides the context.
        local lvlStr = (lvl and lvl > 0) and tostring(lvl) or "??"
        f.level:SetText(lvlStr)
        f.levelBadge:Show()
        f.faction:SetText("")
        local cl    = UnitClassification(unit)
        local atlas = cl and tips.CLASSIFICATION_ATLAS[cl]
        if atlas then
            f.classificationIcon:SetAtlas(atlas)
            f.classificationIcon:Show()
        else
            f.classificationIcon:Hide()
        end
    end
end

function tips.buildUnitInfo(f, headerOverlay, subfont)
    local c     = FACTION_BAR_COLORS[4]
    -- Pre-title (prefix before name, e.g. "Private ")
    f.pretitle  = tips.makeFontString(headerOverlay, subfont, { c.r, c.g, c.b })
    -- Name (large, class/faction colored)
    f.name      = tips.makeFontString(headerOverlay, tips.currentFont)
    -- Post-title (suffix after name, e.g. " the Explorer")
    f.posttitle = tips.makeFontString(headerOverlay, subfont, { c.r, c.g, c.b })
    -- Guild (players) or NPC sub-title
    f.subtitle  = tips.makeFontString(headerOverlay, subfont, { 0.7, 0.7, 0.7 })

    f.name:SetWidth(tips.TIP_W - (tips.PADDING * 4))

    -- Level badge texture (housing-dashboard-tasks-listitem-flag, 68x69)
    f.levelBadge = headerOverlay:CreateTexture(nil, "OVERLAY")
    f.levelBadge:SetAtlas("housing-dashboard-tasks-listitem-flag", true)
    f.levelBadge:SetSize(tips.BADGE_W, tips.BADGE_H)
    f.levelBadge:Hide()

    -- Level number centered inside the badge
    f.level = headerOverlay:CreateFontString(nil, "OVERLAY")
    f.level:SetFont(tips.currentSubFont())
    f.level:SetJustifyH("CENTER")
    f.level:SetJustifyV("MIDDLE")
    f.level:SetWordWrap(false)
    f.level:SetWidth(tips.BADGE_W)

    f.faction = tips.makeFontString(headerOverlay, subfont)

    -- Classification icon (elite / rare / etc.) anchored to the right of the header
    f.classificationIcon = headerOverlay:CreateTexture(nil, "OVERLAY")
    f.classificationIcon:SetSize(24, 24)
    f.classificationIcon:SetPoint("TOPRIGHT", f.headerFrame, "TOPRIGHT", -2, 2)
    f.classificationIcon:Hide()
end

function tips.layoutUnitInfo(f, fonts)
    local badgeShown = f.levelBadge:IsShown()
    local textX      = tips.PADDING + (badgeShown and (tips.BADGE_W + tips.BADGE_GAP) or 0)
    local headerH    = math.floor(tips.TIP_W * tips.HEADER_ASPECT)

    f.name:SetFont(fonts.path, fonts.baseSize, fonts.flag)
    f.pretitle:SetFont(fonts.path, fonts.titleSize, fonts.flag)
    f.posttitle:SetFont(fonts.path, fonts.titleSize, fonts.flag)
    f.subtitle:SetFont(fonts.path, fonts.guildSize, fonts.flag)
    f.faction:SetFont(fonts.path, fonts.guildSize, fonts.flag)

    local pretitle    = f.pretitle:GetText()
    local posttitle   = f.posttitle:GetText()
    local subtitle    = f.subtitle:GetText()
    local faction     = f.faction:GetText()
    local hasTitle    = pretitle or posttitle
    local hasGuild    = subtitle or faction
    local guildParent = f.name
    local isNpcTitled = subtitle and faction

    if pretitle then
        f.pretitle:SetPoint("BOTTOMLEFT", f.name, "TOPLEFT", 0, -1)
    elseif posttitle then
        guildParent = f.posttitle
        f.posttitle:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -1)
    end

    if subtitle then
        f.subtitle:SetPoint("TOPLEFT", guildParent, "BOTTOMLEFT", 0, -1)
    elseif faction then
        f.faction:SetPoint("TOPLEFT", guildParent, "BOTTOMLEFT", 0, -1)
    end

    if isNpcTitled then
        f.subtitle:SetPoint("TOPLEFT", f.name, 'BOTTOMLEFT', 0, -1)
        f.faction:SetPoint("TOPLEFT", f.subtitle, 'BOTTOMLEFT', 0, -1)
    end

    local nameY
    if hasGuild and pretitle then
        nameY = 4
    elseif hasGuild and posttitle then
        nameY = 16
    elseif not hasGuild and posttitle then
        nameY = 10
    elseif not hasGuild and pretitle then
        nameY = -2
    elseif hasGuild then
        nameY = 10
    else
        nameY = 4
    end

    f.name:SetPoint("LEFT", f.headerFrame, "LEFT", textX, nameY)

    if badgeShown then
        f.levelBadge:ClearAllPoints()
        f.levelBadge:SetPoint("TOPLEFT", f.headerFrame, "TOPLEFT", tips.PADDING, 0)
        f.level:ClearAllPoints()
        f.level:SetPoint("CENTER", f.levelBadge, "CENTER", -2, 2)
    end

    return -headerH, headerH
end
