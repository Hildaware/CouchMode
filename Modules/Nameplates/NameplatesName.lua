local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class NameplatesModule: AceModule
local nameplates = addon:GetModule('Nameplates')

--#region ── Name colors ──────────────────────────────────────────────────────

local COLOR_END = "|r"
local COLOR_RARE = "|cFFFFD200"
local titleColorCache

local hexColor = addon.Utils.hexColor

local function titleColor()
    if not titleColorCache then
        local c = FACTION_BAR_COLORS[4]
        titleColorCache = c and hexColor(c.r, c.g, c.b) or "|cFFFFD200"
    end
    return titleColorCache
end

local function nameColor(unit)
    if UnitIsPlayer(unit) then
        local r, g, b = addon.TRPUtils.getRPColor(unit)
        if r then return hexColor(r, g, b) end
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS[class]
        if c then return hexColor(c.r, c.g, c.b) end
    end
    local reaction = UnitReaction(unit, "player")
    local c = reaction and FACTION_BAR_COLORS[reaction]
    return c and hexColor(c.r, c.g, c.b) or "|cFFFFFFFF"
end

--#endregion

--#region ── Quest detection ──────────────────────────────────────────────────
local subtitleCache = {}
local subtitleCacheCount = 0
local SUBTITLE_CACHE_MAX = 256

function nameplates.isQuestUnit(unit)
    if nameplates.isInInstance() then return false end
    return addon.QuestUtils.isQuestUnit(unit)
end

function nameplates.wipeQuestCache()
    addon.QuestUtils.wipeCache()
    wipe(subtitleCache)
    subtitleCacheCount = 0
end

local partyGUIDs = {}

function nameplates.rebuildPartyGUIDs()
    wipe(partyGUIDs)
    local n = GetNumGroupMembers()
    local isRaid = IsInRaid()
    for i = 1, n do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        local guid = UnitGUID(unit)
        if guid then partyGUIDs[guid] = true end
    end
end

function nameplates.shouldShowName(unit)
    if nameplates.isInInstance() then return true end
    if addon.db.profile.nameplates.alwaysShowParty then
        local guid = UnitGUID(unit)
        if guid and partyGUIDs[guid] then return true end
    end
    local showPlayers = addon.db.profile.nameplates.alwaysShowPlayers
    if showPlayers == 'always' and UnitIsPlayer(unit) then return true end
    if showPlayers == 'cities' and UnitIsPlayer(unit) and nameplates.isInCity() then return true end
    if addon.db.profile.nameplates.alwaysShowImportant then
        local class = UnitClassification(unit)
        if class == "rare" or class == "rareelite" or class == "worldboss" then return true end
    end
    if UnitIsUnit(unit, "target") then return true end
    if UnitIsUnit(unit, "softtarget") then return true end
    if UnitIsUnit(unit, "mouseover") then return true end
    if not nameplates.inCombat and UnitIsUnit(unit, "softfriend") then return true end
    if UnitIsUnit(unit, "softenemy") then return true end
    if UnitIsUnit(unit, "softinteract") then return true end
    if UnitIsQuestBoss(unit) then return true end
    return false
end

--#endregion

--#region ── Name & guild display ─────────────────────────────────────────────

local getZonePVPInfo = C_PvP and C_PvP.GetZonePVPInfo

function nameplates.isInCity()
    if not getZonePVPInfo then return false end

    local pvpType = getZonePVPInfo()
    return pvpType == "sanctuary" or pvpType == "friendly"
end

function nameplates.isInInstance()
    return addon.Utils.IsInInstance()
end

function nameplates.buildNameFrame(f, overlay)
    local currentFont, fontSize, fontFlag = nameplates.currentFont()
    f.name = overlay:CreateFontString(nil, "OVERLAY")
    f.name:SetFont(currentFont, fontSize, fontFlag)
    f.name:SetWordWrap(false)
    f.name:SetPoint("BOTTOM", f, "TOP", 0, 0)
    f.name:SetJustifyH("CENTER")

    f.questIcon = overlay:CreateTexture(nil, "OVERLAY")
    f.questIcon:SetSize(fontSize + 4, fontSize + 4)
    f.questIcon:SetAtlas("QuestNormal")
    f.questIcon:SetPoint("RIGHT", f.name, "LEFT", -4, 1)
    f.questIcon:Hide()

    if addon.db.profile.nameplates.shadowEnabled then
        addon.Utils.apply_font_shadow(f.name)
    end

    f.guild = overlay:CreateFontString(nil, "OVERLAY")
    f.guild:SetFont(nameplates.currentGuildFont())
    f.guild:SetWidth(nameplates.BAR_W * 2)
    f.guild:SetWordWrap(true)
    f.guild:SetMaxLines(2)
    f.guild:SetPoint("TOP", f.name, "BOTTOM", 0, -1)
    f.guild:SetJustifyH("CENTER")
    f.guild:Hide()
    if addon.db.profile.nameplates.shadowEnabled then
        addon.Utils.apply_font_shadow(f.guild)
    end

    f.musicIcon = overlay:CreateTexture(nil, "OVERLAY")
    f.musicIcon:SetSize(fontSize + 2, fontSize + 2)
    f.musicIcon:SetTexture("Interface/AddOns/Musician/ui/textures/unmuted.blp")
    f.musicIcon:SetPoint("BOTTOM", f.name, "TOP", 0, 4)
    f.musicIcon:Hide()
end

function nameplates.applyName(f, unit, plateType)
    local PlateType = nameplates.PlateType
    local nameStr = UnitName(unit) or ""

    local classification = UnitClassification(unit)
    local isRare = classification == "rare" or classification == "rareelite"

    if plateType == PlateType.Full then
        if nameplates.isSelected(unit) then
            f.name:SetVertexColor(0.5, 0.8, 1.0)
        elseif isRare then
            f.name:SetVertexColor(1, 0.82, 0)
        else
            f.name:SetVertexColor(1, 1, 1)
        end
        f.name:SetText(nameStr)
        return
    end

    -- NameOnly: class/faction colors with PvP title support
    local text
    if UnitIsPlayer(unit) then
        local rpFullName = addon.TRPUtils.getRPFullName(unit)
        if rpFullName and rpFullName ~= "" and rpFullName ~= nameStr then
            local nc = nameColor(unit)
            local rpTitle = addon.TRPUtils.getRPTitle(unit)
            if rpTitle then
                text = titleColor() .. rpTitle .. " " .. COLOR_END .. nc .. rpFullName .. COLOR_END
            else
                text = nc .. rpFullName .. COLOR_END
            end
        else
            local preTitle, characterName, postTitle = addon.Utils.GetPlayerNameParts(unit)
            local nc = nameColor(unit)
            text = titleColor() .. preTitle .. COLOR_END
                .. nc .. characterName .. COLOR_END
                .. titleColor() .. postTitle .. COLOR_END
        end
    else
        local nc = isRare and COLOR_RARE or nameColor(unit)
        text = nc .. nameStr .. COLOR_END
    end

    f.name:SetVertexColor(1, 1, 1)
    f.name:SetText(text)
end

local function getSubtitle(unitToken)
    if nameplates.isInInstance() then return nil, false end
    if UnitIsPlayer(unitToken) then
        return GetGuildInfo(unitToken), true
    end

    local guid = UnitGUID(unitToken)
    if guid and subtitleCache[guid] then
        local data = subtitleCache[guid]
        return data.text, data.isGuild
    end

    local subtitle, isGuild
    local tooltipData = C_TooltipInfo.GetUnit(unitToken) -- Expensive call
    if tooltipData and tooltipData.lines and tooltipData.lines[2] then
        local text = tooltipData.lines[2].leftText
        if text and text ~= "" and not text:match("^Level %d") then
            subtitle = text
            isGuild = false
        end
    end

    if guid then
        if subtitleCacheCount >= SUBTITLE_CACHE_MAX then
            wipe(subtitleCache)
            subtitleCacheCount = 0
        end
        subtitleCache[guid] = { text = subtitle, isGuild = isGuild }
        subtitleCacheCount = subtitleCacheCount + 1
    end
    return subtitle, isGuild
end

function nameplates.applyMusicIcon(f, unit)
    f.musicIcon:SetShown(addon.TRPUtils.isPlayingMusic(unit))
end

function nameplates.applyGuild(f, unitToken)
    local showName = nameplates.shouldShowName(unitToken)
    if not showName then
        f.guild:Hide()
        return
    end

    local subtitle
    if UnitIsPlayer(unitToken) then
        subtitle = addon.TRPUtils.getRPFullTitle(unitToken) or getSubtitle(unitToken)
    else
        subtitle = getSubtitle(unitToken)
    end

    if subtitle then
        local gc = ChatTypeInfo["GUILD"]
        f.guild:SetVertexColor(gc.r, gc.g, gc.b)
        f.guild:SetText(subtitle)
        f.guild:Show()
    else
        f.guild:Hide()
    end
end

--#endregion

--#region ── Layout ───────────────────────────────────────────────────────────

local LAYOUT_TRANSITION = 0.2

function nameplates.applyLayout(f, plateType)
    local PlateType = nameplates.PlateType
    f.name:ClearAllPoints()
    f.bar:ClearAllPoints()

    local font, fontSize, fontFlag = nameplates.currentFont()
    local fromSize = select(2, f.name:GetFont()) or fontSize

    f.mark:ClearAllPoints()
    f.elite:ClearAllPoints()
    if plateType == PlateType.Full then
        f.bar:SetPoint("CENTER", f, "CENTER")
        f.name:SetPoint("BOTTOMLEFT", f.bar, "TOPLEFT", 2, -6)
        f.name:SetJustifyH("LEFT")
        f.name:SetWidth(nameplates.BAR_W - 10)
        f.questIcon:SetPoint("RIGHT", f.name, "LEFT", 4, -6)
        f.elite:SetPoint("LEFT", f.name, "RIGHT", -4, -6)
        f.mark:SetPoint("BOTTOM", f.bar, "TOP", 0, -6)
        f.guild:Hide()
    else -- PlateType.NameOnly
        f.bar:SetPoint("TOP", f.guild, "BOTTOM", 0, -2)
        f.name:SetPoint("BOTTOM", f, "TOP")
        f.name:SetJustifyH("CENTER")
        f.name:SetWidth(0)
        f.questIcon:SetPoint("RIGHT", f.name, "LEFT", -4, 1)
        f.elite:SetPoint("RIGHT", f.name, "LEFT", -4, 1)
        f.mark:SetPoint("BOTTOM", f.name, "TOP", 0, 2)
    end

    local toSize = (plateType == PlateType.Full) and (fontSize - 6) or fontSize
    if fromSize == toSize then
        f.name:SetFont(font, toSize, fontFlag)
        f:SetScript("OnUpdate", nil)
        return
    end

    f.layoutTrans = { elapsed = 0, fromSize = fromSize, toSize = toSize, font = font, flag = fontFlag }
    f:SetScript("OnUpdate", function(self, dt)
        local t = self.layoutTrans
        t.elapsed = t.elapsed + dt
        local pct = math.min(t.elapsed / LAYOUT_TRANSITION, 1)
        pct = pct * pct * (3 - 2 * pct) -- smoothstep
        self.name:SetFont(t.font, t.fromSize + (t.toSize - t.fromSize) * pct, t.flag)
        if pct >= 1 then
            self:SetScript("OnUpdate", nil)
            self.layoutTrans = nil
        end
    end)
end

--#endregion
