local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class NameplatesModule: AceModule
local nameplates = addon:GetModule('Nameplates')

--#region ── Name colors ──────────────────────────────────────────────────────

local COLOR_END  = "|r"
local titleColorCache

local function hexColor(r, g, b)
    return string.format("|cFF%02X%02X%02X", r * 255, g * 255, b * 255)
end

local function titleColor()
    if not titleColorCache then
        local c = FACTION_BAR_COLORS[4]
        titleColorCache = c and hexColor(c.r, c.g, c.b) or "|cFFFFD200"
    end
    return titleColorCache
end

local function nameColor(unit)
    if UnitIsPlayer(unit) then
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
local questGUIDs    = {}
local subtitleCache = {}

function nameplates.isQuestUnit(unit)
    -- This function is expensive due to tooltip scanning. It should be called
    -- sparingly, ideally only when a unit appears or when the quest log changes.
    -- It is cached per GUID.
    if nameplates.isInInstance() then return false end
    local guid = UnitGUID(unit)
    if not guid then return false end

    if questGUIDs[guid] == false then return false end

    local tooltipData = C_TooltipInfo.GetHyperlink("unit:" .. guid)
    if not tooltipData then
        questGUIDs[guid] = false
        return false
    end

    for _, line in ipairs(tooltipData.lines or {}) do
        if line.type == Enum.TooltipDataLineType.QuestObjective then
            local text = line.leftText or ""
            local p1, p2 = text:match("(%d+)/(%d+)")
            if p1 and p2 then
                if tonumber(p1) < tonumber(p2) then return true end
            else
                local pct = text:match("(%d+)%%")
                if pct then
                    if tonumber(pct) < 100 then return true end
                else
                    return true
                end
            end
        end
    end

    questGUIDs[guid] = false
    return false
end

function nameplates.wipeQuestCache()
    wipe(questGUIDs)
    wipe(subtitleCache)
end

function nameplates.shouldShowName(unit)
    if nameplates.isInInstance() then return true end
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

function nameplates.isInInstance()
    local inInstance, instanceType = IsInInstance()
    if instanceType == "scenario" then return true end
    return inInstance
        and instanceType ~= "none"
        and instanceType ~= "neighborhood"
        and instanceType ~= "interior"
end

function nameplates.buildNameFrame(f, overlay)
    local currentFont, fontSize, fontFlag = nameplates.currentFont()
    f.name = overlay:CreateFontString(nil, "OVERLAY")
    f.name:SetFont(currentFont, fontSize, fontFlag)
    f.name:SetPoint("BOTTOM", f, "TOP", 0, 0)

    f.questIcon = overlay:CreateTexture(nil, "OVERLAY")
    f.questIcon:SetSize(fontSize + 4, fontSize + 4)
    f.questIcon:SetAtlas("QuestNormal")
    f.questIcon:SetPoint("RIGHT", f.name, "LEFT", -4, 1)
    f.questIcon:Hide()

    f.guild = overlay:CreateFontString(nil, "OVERLAY")
    f.guild:SetFont(nameplates.currentGuildFont())
    f.guild:SetPoint("TOP", f.name, "BOTTOM", 0, -1)
    f.guild:Hide()
end

function nameplates.applyName(f, unit, plateType)
    local PlateType = nameplates.PlateType
    local nameStr = UnitName(unit) or ""

    if plateType == PlateType.Full then
        if nameplates.isSelected(unit) then
            f.name:SetVertexColor(0.5, 0.8, 1.0)
        else
            f.name:SetVertexColor(1, 1, 1)
        end
        f.name:SetText(nameStr)
        return
    end

    -- NameOnly: class/faction colors with PvP title support
    local text
    if UnitIsPlayer(unit) then
        local fullStr = UnitPVPName(unit) or nameStr
        local s, e    = fullStr:find(nameStr, 1, true)
        local nc      = nameColor(unit)

        if s and s > 1 then
            local prefix = fullStr:sub(1, s - 1)
            text = titleColor() .. prefix .. COLOR_END .. nc .. nameStr .. COLOR_END
        elseif e and e < #fullStr then
            local suffix = fullStr:sub(e + 1)
            text = nc .. nameStr .. COLOR_END .. titleColor() .. suffix .. COLOR_END
        else
            text = nc .. nameStr .. COLOR_END
        end
    else
        text = nameColor(unit) .. nameStr .. COLOR_END
    end

    f.name:SetVertexColor(1, 1, 1)
    f.name:SetText(text)
end

local function getSubtitle(unitToken)
    -- This function can be expensive due to tooltip scanning. It is cached per GUID.
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
            isGuild  = false
        end
    end

    if guid then
        subtitleCache[guid] = { text = subtitle, isGuild = isGuild }
    end
    return subtitle, isGuild
end

function nameplates.applyGuild(f, unitToken)
    local showName = nameplates.shouldShowName(unitToken)
    local subtitle = getSubtitle(unitToken)
    if showName and subtitle then
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
        f.elite:SetPoint("RIGHT", f.name, "LEFT", 4, -6)
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
