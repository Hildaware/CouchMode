local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips = addon:GetModule('Tips')

local hexColor = addon.Utils.hexColor
local measureWidth = addon.TipsUtils.measureWidth

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
    elite = "nameplates-icon-elite-gold",
    rareelite = "nameplates-icon-rareelite",
    rare = "nameplates-icon-elite-silver",
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

--#region ── Section build ────────────────────────────────────────────────────

function tips.buildUnitInfo()
    ---@type UnitInfoSection
    local container = addon.Layout:HStack(UIParent, {
        spacing = 4,
        height = math.floor(tips.TIP_W * tips.HEADER_ASPECT),
    })

    container.headerBg = container:AddBackground("StoryHeader-BG")

    container.badgeContainer = addon.Layout:Container(container)

    local levelBadge = container.badgeContainer:Texture("OVERLAY", 0,
        { atlas = "housing-dashboard-tasks-listitem-flag", size = { w = tips.BADGE_W, h = tips.BADGE_H } })
    levelBadge:SetAllPoints(container.badgeContainer)
    levelBadge:Hide()
    container.levelBadge = levelBadge

    local level = container.badgeContainer:FontString(
        { font = tips.currentSubFont, justifyH = "CENTER", justifyV = "MIDDLE", wordWrap = false,
          shadow = tips.tipsDB().shadowEnabled })
    level:SetWidth(tips.BADGE_W)
    level:SetPoint("CENTER", container.levelBadge, "CENTER", -1, 2)
    container.level = level

    container:AddChild(container.badgeContainer, { valign = "TOP" })

    container.nameBlock = addon.Layout:VStack(container, { spacing = 1 })

    local fontPath, baseSize, fontFlag = tips.currentFont()
    local titleSize = math.max(8, math.floor(baseSize * 0.75))
    local guildSize = math.max(8, math.floor(baseSize * 0.60))
    local titleFont = function() return fontPath, titleSize, fontFlag end
    local guildFont = function() return fontPath, guildSize, fontFlag end

    local c = FACTION_BAR_COLORS[4]
    local shadow = tips.tipsDB().shadowEnabled
    container.pretitle = container.nameBlock:FontString(
        { font = titleFont, color = { c.r, c.g, c.b }, justifyH = "LEFT", shadow = shadow })
    container.name = container.nameBlock:FontString(
        { font = tips.currentFont, maxLines = 1, justifyH = "LEFT", shadow = shadow })
    container.posttitle = container.nameBlock:FontString(
        { font = titleFont, color = { c.r, c.g, c.b }, justifyH = "LEFT", shadow = shadow })
    container.subtitle = container.nameBlock:FontString(
        { font = guildFont, color = { 0.7, 0.7, 0.7 }, wrap = false, maxLines = 1, justifyH = "LEFT", shadow = shadow })
    container.faction = container.nameBlock:FontString({ font = guildFont, justifyH = "LEFT", shadow = shadow })

    container.nameBlock:AddChild(container.pretitle)
    container.nameBlock:AddChild(container.name)
    container.nameBlock:AddChild(container.posttitle)
    container.nameBlock:AddChild(container.subtitle)
    container.nameBlock:AddChild(container.faction)

    container:AddChild(container.nameBlock, { valign = "CENTER" })

    container.classIconContainer = addon.Layout:Container(container)
    container.classIconContainer.frame:SetSize(30, 30)
    container.classificationIcon = container.classIconContainer:Texture("OVERLAY", 0, { size = { w = 30, h = 30 } })
    container.classificationIcon:SetPoint("LEFT", container.classIconContainer, "LEFT", -8, 8)
    container.classificationIcon:Hide()

    container:AddChild(container.classIconContainer, { valign = "CENTER" })

    -- Data fields
    container.rawName = nil
    container.nameColor = nil

    --#region populate

    function container:populate(unit, name, headerAtlas)
        self.headerBg:SetAtlas(headerAtlas, true)

        if unit then
            -- Unit path
            local isPlayer = UnitIsPlayer(unit)
            local baseName = UnitName(unit) or ""
            local nameColor = tips.nameColor(unit)
            self.nameColor = nameColor
            self.rawName = baseName
            self.name:SetText(nameColor .. baseName .. "|r")

            if isPlayer then
                local rpFullName = addon.TRPUtils.getRPFullName(unit)
                if rpFullName then
                    self.rawName = rpFullName
                    self.name:SetText(nameColor .. rpFullName .. "|r")
                    local rpTitle = addon.TRPUtils.getRPTitle(unit)
                    self.pretitle:SetText(rpTitle or "")
                    self.posttitle:SetText("")
                else
                    local _, instanceType = IsInInstance()
                    local pvpName = UnitPVPName(unit)
                    if pvpName and not issecretvalue(pvpName) and pvpName ~= baseName and instanceType == "none" then
                        local s2, e = pvpName:find(baseName, 1, true)
                        self.pretitle:SetText(s2 and s2 > 1 and pvpName:sub(1, s2 - 1):match("^%s*(.-)%s*$") or "")
                        self.posttitle:SetText(e and e < #pvpName and pvpName:sub(e + 1):match("^[%s,]*(.-)%s*$") or "")
                    else
                        self.pretitle:SetText("")
                        self.posttitle:SetText("")
                    end
                end
            else
                self.pretitle:SetText("")
                self.posttitle:SetText("")
            end

            -- Subtitle
            local subtitle = isPlayer
                and (addon.TRPUtils.getRPFullTitle(unit) or tips.getSubtitle(unit))
                or tips.getSubtitle(unit)
            if subtitle then
                self.subtitle:SetText(subtitle)
                if isPlayer then
                    local gc = ChatTypeInfo["GUILD"]
                    self.subtitle:SetVertexColor(gc.r, gc.g, gc.b)
                else
                    self.subtitle:SetVertexColor(0.7, 0.7, 0.7)
                end
            else
                self.subtitle:SetText("")
            end

            -- Level badge / faction
            local isFriendlyNPC = not isPlayer and not UnitCanAttack("player", unit)
            if isFriendlyNPC then
                self.level:SetText("")
                self.levelBadge:Hide()
                self.classificationIcon:Hide()
                local faction = tips.getFaction(unit)
                if faction then
                    local reaction = UnitReaction(unit, "player")
                    local fc = reaction and FACTION_BAR_COLORS[reaction]
                    self.faction:SetVertexColor(fc and fc.r or 0.7, fc and fc.g or 0.7, fc and fc.b or 0.7)
                    self.faction:SetText(faction)
                else
                    self.faction:SetText("")
                end
            else
                local lvl = UnitLevel(unit)
                local lvlStr = (lvl and lvl > 0) and tostring(lvl) or "??"
                self.level:SetText(lvlStr)
                self.levelBadge:Show()
                self.faction:SetText("")
                local cl = UnitClassification(unit)
                local atlas = cl and tips.CLASSIFICATION_ATLAS[cl]
                if atlas then
                    self.classificationIcon:SetAtlas(atlas)
                    self.classificationIcon:Show()
                else
                    self.classificationIcon:Hide()
                end
            end
        else
            -- Object path (name only, no unit token)
            self.rawName = name
            self.nameColor = "|cFFFFFFFF"
            self.name:SetText("|cFFFFFFFF" .. (name or "") .. "|r")
            self.pretitle:SetText("")
            self.posttitle:SetText("")
            self.subtitle:SetText("")
            self.faction:SetText("")
            self.level:SetText("")
            self.levelBadge:Hide()
            self.classificationIcon:Hide()
        end
    end

    --#endregion

    --#region draw

    function container:naturalWidth()
        local badgeShown = self.levelBadge:IsShown()
        local classShown = self.classificationIcon:IsShown()
        local scaledBadgeW = math.floor(tips.TIP_W * tips.BADGE_X)
        local badgeW = badgeShown and scaledBadgeW or 0
        local classW = classShown and 24 or 0
        local startX = tips.PADDING / 2 + (badgeShown and 0 or 8)
        local spacing = 4
        local numGaps = (badgeShown and 1 or 0) + (classShown and 1 or 0)
        local textW = math.max(
            measureWidth(self.pretitle),
            measureWidth(self.name),
            measureWidth(self.posttitle),
            measureWidth(self.subtitle),
            measureWidth(self.faction)
        )
        return math.ceil(startX + badgeW + classW + (numGaps * spacing) + textW + startX)
    end

    function container:draw(w)
        -- Badge sizing
        local scaledBadgeW = math.floor(w * tips.BADGE_X)
        local scaledBadgeH = math.floor(scaledBadgeW * tips.BADGE_H / tips.BADGE_W)
        local badgeShown = self.levelBadge:IsShown()

        if badgeShown then
            self.badgeContainer:SetSize(scaledBadgeW, scaledBadgeH)
            self.level:SetWidth(scaledBadgeW)
        else
            self.badgeContainer:SetSize(0, 0)
        end

        local classShown = self.classificationIcon:IsShown()
        self.classIconContainer:SetSize(classShown and 24 or 0, classShown and 24 or 0)

        local badgeW = badgeShown and scaledBadgeW or 0
        local classW = classShown and 24 or 0
        local startX = tips.PADDING / 2 + (badgeShown and 0 or 8)
        local spacing = 4
        local numGaps = (badgeShown and 1 or 0) + (classShown and 1 or 0)
        local textW = w - startX - badgeW - classW - (numGaps * spacing) - startX

        self.nameBlock:SetWidth(textW)
        self.name:SetWidth(textW)
        self.pretitle:SetWidth(textW)
        self.posttitle:SetWidth(textW)
        self.subtitle:SetWidth(textW)
        self.faction:SetWidth(textW)

        self.name:SetTruncatedColorText(self.rawName, self.nameColor, textW)
        self.pretitle:SetTruncatedText(self.pretitle:GetText(), textW)
        self.posttitle:SetTruncatedText(self.posttitle:GetText(), textW)
        self.faction:SetTruncatedText(self.faction:GetText(), textW)

        local subtitleRaw = self.subtitle:GetText()
        if (self.pretitle:GetText() or "") ~= "" or (self.posttitle:GetText() or "") ~= "" then
            self.subtitle:SetWordWrap(false)
            self.subtitle:SetMaxLines(1)
            self.subtitle:SetTruncatedText(subtitleRaw, textW)
        else
            self.subtitle:SetWordWrap(true)
            self.subtitle:SetMaxLines(2)
            self.subtitle:SetText(subtitleRaw or "")
        end

        self.pretitle:SyncHeight()
        self.name:SyncHeight()
        self.posttitle:SyncHeight()
        self.subtitle:SyncHeight()
        self.faction:SyncHeight()

        self.nameBlock:Layout()
        self:Layout(startX, 0)
        self:SetWidth(w - 8)
    end

    --#endregion

    --#region reset

    function container:reset()
        self.rawName = nil
        self.nameColor = nil
        self.pretitle:SetText(""); self.pretitle:SetWidth(0); self.pretitle:SetHeight(0)
        self.name:SetText(""); self.name:SetWidth(0); self.name:SetHeight(0)
        self.posttitle:SetText(""); self.posttitle:SetWidth(0); self.posttitle:SetHeight(0)
        self.subtitle:SetText(""); self.subtitle:SetWidth(0); self.subtitle:SetHeight(0)
        self.faction:SetText(""); self.faction:SetWidth(0); self.faction:SetHeight(0)
        self.level:SetText("")
        self.levelBadge:Hide()
        self.classificationIcon:Hide()
        self:SetHeight(math.floor(tips.TIP_W * tips.HEADER_ASPECT))
    end

    --#endregion

    return container
end

--#endregion
