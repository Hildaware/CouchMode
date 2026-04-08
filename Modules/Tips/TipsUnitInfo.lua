local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips       = addon:GetModule('Tips')

local hexColor   = addon.Utils.hexColor

function tips.nameColor(unit)
    if UnitIsPlayer(unit) then
        local r, g, b = addon.TRPUtils.getRPColor(unit)
        if r then return hexColor(r, g, b) end
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
    local isPlayer  = UnitIsPlayer(unit)
    local baseName  = UnitName(unit) or ""
    local nameColor = tips.nameColor(unit)
    f._nameColor    = nameColor
    f._rawName      = baseName
    f.name:SetText(nameColor .. baseName .. "|r")

    if isPlayer then
        local rpFullName = addon.TRPUtils.getRPFullName(unit)

        if rpFullName then
            -- TRP3: First+Last as the main name; short title (TI) as pretitle.
            f._rawName = rpFullName
            f.name:SetText(nameColor .. rpFullName .. "|r")
            local rpTitle = addon.TRPUtils.getRPTitle(unit)
            f.pretitle:SetText(rpTitle or "")
            f.posttitle:SetText("")
        else
            -- No TRP3 data — existing WoW PvP title path.
            -- UnitName/UnitPVPName are secret strings in instances; string operations forbidden there.
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
        end
    else
        f.pretitle:SetText("")
        f.posttitle:SetText("")
    end

    -- SUBTITLE: TRP3 full title (FT) > guild (players) or NPC sub-name
    local subtitle = isPlayer
        and (addon.TRPUtils.getRPFullTitle(unit) or tips.getSubtitle(unit))
        or tips.getSubtitle(unit)
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

-- Truncates text to fit maxWidth pixels, appending "..." if needed.
-- Requires the fontstring to already have its font set.
local function applyTruncatedText(fs, text, maxWidth)
    if not text or text == "" then return end
    fs:SetText(text)
    if fs:GetStringWidth() <= maxWidth then return end
    local lo, hi = 0, #text
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        fs:SetText(text:sub(1, mid) .. "...")
        if fs:GetStringWidth() <= maxWidth then lo = mid else hi = mid - 1 end
    end
    fs:SetText(text:sub(1, lo) .. "...")
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
    f.subtitle:SetWordWrap(false)
    f.subtitle:SetMaxLines(1)

    f.name:SetMaxLines(1)

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
    -- Scaled badge dimensions
    local scaledBadgeW = math.floor(tips.TIP_W * tips.BADGE_X)
    local scaledBadgeH = math.floor(scaledBadgeW * tips.BADGE_H / tips.BADGE_W)

    local badgeShown   = f.levelBadge:IsShown()
    local textX        = (tips.PADDING / 2) + (badgeShown and (scaledBadgeW + tips.BADGE_GAP) or 8)
    local headerH      = math.floor(tips.TIP_W * tips.HEADER_ASPECT)
    local textW        = tips.TIP_W - textX - (tips.PADDING / 2)

    -- Update badge to scaled size each layout
    if badgeShown then
        f.levelBadge:SetSize(scaledBadgeW, scaledBadgeH)
        f.level:SetWidth(scaledBadgeW)
    end

    -- Fonts must be set before GetStringWidth calls below
    f.name:SetFont(fonts.path, fonts.baseSize, fonts.flag)
    f.pretitle:SetFont(fonts.path, fonts.titleSize, fonts.flag)
    f.posttitle:SetFont(fonts.path, fonts.titleSize, fonts.flag)
    f.subtitle:SetFont(fonts.path, fonts.guildSize, fonts.flag)
    f.faction:SetFont(fonts.path, fonts.guildSize, fonts.flag)

    -- Widths (dynamic — badge size changes textW at different TIP_W values)
    f.name:SetWidth(textW)
    f.pretitle:SetWidth(textW)
    f.posttitle:SetWidth(textW)
    f.subtitle:SetWidth(textW)
    f.faction:SetWidth(textW)

    -- Name truncation: raw text stored without color codes to avoid mangling escapes
    if f._rawName then
        local truncated = f._rawName
        f.name:SetText(truncated)
        if f.name:GetStringWidth() > textW then
            local lo, hi = 0, #truncated
            while lo < hi do
                local mid = math.ceil((lo + hi) / 2)
                f.name:SetText(truncated:sub(1, mid) .. "...")
                if f.name:GetStringWidth() <= textW then lo = mid else hi = mid - 1 end
            end
            truncated = truncated:sub(1, lo) .. "..."
        end
        f.name:SetText((f._nameColor or "") .. truncated .. "|r")
    end

    -- Truncation for plain-text fields
    applyTruncatedText(f.pretitle, f.pretitle:GetText(), textW)
    applyTruncatedText(f.posttitle, f.posttitle:GetText(), textW)
    applyTruncatedText(f.faction, f.faction:GetText(), textW)

    -- Re-read after truncation for positioning decisions
    local pretitle    = f.pretitle:GetText()
    local posttitle   = f.posttitle:GetText()
    local faction     = f.faction:GetText()

    -- Subtitle: wrap up to 2 lines when no pre/posttitle; otherwise truncate to 1
    local subtitleRaw = f.subtitle:GetText()
    local subtitleLines
    if pretitle or posttitle then
        f.subtitle:SetWordWrap(false)
        f.subtitle:SetMaxLines(1)
        applyTruncatedText(f.subtitle, subtitleRaw, textW)
        subtitleLines = subtitleRaw and subtitleRaw ~= "" and 1 or 0
    else
        f.subtitle:SetWordWrap(true)
        f.subtitle:SetMaxLines(2)
        f.subtitle:SetText(subtitleRaw or "")
        subtitleLines = subtitleRaw and subtitleRaw ~= "" and 2 or 0
    end
    local subtitle   = f.subtitle:GetText()

    local cleanName  = not pretitle and not posttitle and not subtitle and not faction
    local titleLineH = fonts.titleSize + tips.LINE_GAP
    local guildLineH = fonts.guildSize + tips.LINE_GAP
    local aboveH     = pretitle and titleLineH or 0
    local belowH     = (posttitle and titleLineH or 0)
        + (subtitle and guildLineH * subtitleLines or 0)
        + (faction and guildLineH or 0)

    local nameY      = math.floor((belowH - aboveH) / 2) + 4

    if not badgeShown then
        nameY = (cleanName and nameY - 1) or nameY - 8
    end

    -- Clear and re-anchor everything
    f.name:ClearAllPoints()
    f.pretitle:ClearAllPoints()
    f.posttitle:ClearAllPoints()
    f.subtitle:ClearAllPoints()
    f.faction:ClearAllPoints()

    f.name:SetPoint("LEFT", f.headerFrame, "LEFT", textX, nameY)

    if pretitle then
        f.pretitle:SetPoint("BOTTOMLEFT", f.name, "TOPLEFT", 0, 1)
    end
    if posttitle then
        f.posttitle:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -1)
    end

    local guildParent = (posttitle and f.posttitle) or f.name
    local isNpcTitled = subtitle and faction
    if isNpcTitled then
        f.subtitle:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -1)
        f.faction:SetPoint("TOPLEFT", f.subtitle, "BOTTOMLEFT", 0, -1)
    elseif subtitle then
        f.subtitle:SetPoint("TOPLEFT", guildParent, "BOTTOMLEFT", 0, -1)
    elseif faction then
        f.faction:SetPoint("TOPLEFT", guildParent, "BOTTOMLEFT", 0, -1)
    end

    if badgeShown then
        f.levelBadge:ClearAllPoints()
        f.levelBadge:SetPoint("TOPLEFT", f.headerFrame, "TOPLEFT", tips.PADDING / 2, 2)
        f.level:ClearAllPoints()
        f.level:SetPoint("CENTER", f.levelBadge, "CENTER", -1, 2)
    end

    return -headerH, headerH
end
