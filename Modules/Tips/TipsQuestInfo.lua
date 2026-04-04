local addon_name     = ...

---@class CouchMode: AceAddon
local addon          = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips           = addon:GetModule('Tips')

tips.MAX_QUEST_LINES = 6
tips.MAX_OBJECTIVES  = 4

function tips.populateQuestSection(f, questData)
    if questData then
        f.questDivider:Show()
        for i, quest in ipairs(questData) do
            if i > tips.MAX_QUEST_LINES then break end
            local hasTitle = quest.title ~= nil
            f.questLines[i]:SetText(quest.title or "")
            f.questLines[i]:SetShown(hasTitle)
            f.questIcons[i]:SetShown(hasTitle)
            local objList = f.questObjectives[i]
            for j = 1, tips.MAX_OBJECTIVES do
                local obj = quest.objectives[j]
                if obj then
                    if obj.finished then
                        objList[j]:SetText(CreateAtlasMarkup("VAS-icon-checkmark", 12, 12) .. " " .. obj.text)
                        objList[j]:SetVertexColor(0.45, 0.45, 0.45)
                    else
                        objList[j]:SetText(obj.text)
                        objList[j]:SetVertexColor(1, 1, 1)
                    end
                    objList[j]:Show()
                else
                    objList[j]:SetText("")
                    objList[j]:Hide()
                end
            end
        end
        for i = #questData + 1, tips.MAX_QUEST_LINES do
            f.questLines[i]:SetText("")
            f.questLines[i]:Hide()
            f.questIcons[i]:Hide()
            for j = 1, tips.MAX_OBJECTIVES do
                f.questObjectives[i][j]:SetText("")
                f.questObjectives[i][j]:Hide()
            end
        end
    else
        f.questDivider:Hide()
        for i, ql in ipairs(f.questLines) do
            ql:SetText("")
            ql:Hide()
            f.questIcons[i]:Hide()
            for j = 1, tips.MAX_OBJECTIVES do
                f.questObjectives[i][j]:SetText("")
                f.questObjectives[i][j]:Hide()
            end
        end
    end
end

function tips.populateQuestInfo(f, unit)
    local isPlayer = UnitIsPlayer(unit)
    local questData = not isPlayer and addon.QuestUtils.getQuestData(unit)
    tips.populateQuestSection(f, questData)
end

function tips.buildQuestInfo(f, overlay, subfont)
    -- Quest section
    f.questDivider = overlay:CreateTexture(nil, "OVERLAY")
    f.questDivider:SetAtlas("Adventure-MissionEnd-Line")
    f.questDivider:SetHeight(8)
    f.questDivider:Hide()

    f.questLines = {}
    f.questIcons = {}
    f.questObjectives = {}
    for i = 1, tips.MAX_QUEST_LINES do
        local icon = overlay:CreateTexture(nil, "OVERLAY")
        icon:SetAtlas("QuestNormal")
        icon:SetSize(14, 14)
        icon:Hide()
        f.questIcons[i] = icon

        local ql = tips.makeFontString(overlay, subfont, { 1, 0.82, 0 })
        ql:Hide()
        f.questLines[i] = ql
        f.questObjectives[i] = {}
        for j = 1, tips.MAX_OBJECTIVES do
            local obj = tips.makeFontString(overlay, subfont, { 0.6, 0.6, 0.6 })
            obj:Hide()
            f.questObjectives[i][j] = obj
        end
    end
end

function tips.layoutQuestInfo(f, y, height, fonts)
    if f.questDivider:IsShown() then
        y = y - 8

        f.questDivider:ClearAllPoints()
        f.questDivider:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
        f.questDivider:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
        local divH            = f.questDivider:GetHeight()
        y                     = y - divH - tips.LINE_GAP
        height                = height + divH + tips.LINE_GAP

        local QUEST_ICON_SIZE = 14
        local QUEST_ICON_GAP  = 4
        for i, ql in ipairs(f.questLines) do
            if ql:IsShown() then
                f.questIcons[i]:ClearAllPoints()
                f.questIcons[i]:SetPoint("TOPLEFT", f, "TOPLEFT", tips.PADDING, y - 1)
                ql:ClearAllPoints()
                ql:SetWidth(tips.TIP_W - tips.PADDING * 2 - QUEST_ICON_SIZE - QUEST_ICON_GAP)
                ql:SetFont(fonts.path, fonts.guildSize, fonts.flag)
                ql:SetPoint("TOPLEFT", f, "TOPLEFT", tips.PADDING + QUEST_ICON_SIZE + QUEST_ICON_GAP, y)
                local lineH = math.max(ql:GetStringHeight(), QUEST_ICON_SIZE)
                y           = y - lineH - tips.LINE_GAP
                height      = height + lineH + tips.LINE_GAP

                for _, obj in ipairs(f.questObjectives[i]) do
                    if obj:IsShown() then
                        obj:ClearAllPoints()
                        obj:SetWidth(tips.TIP_W - tips.PADDING * 2 - 10)
                        obj:SetFont(fonts.path, fonts.guildSize, fonts.flag)
                        obj:SetPoint("TOPLEFT", f, "TOPLEFT", tips.PADDING + 10, y)
                        local objH = math.max(obj:GetStringHeight(), 1)
                        y          = y - objH - tips.LINE_GAP
                        height     = height + objH + tips.LINE_GAP
                    end
                end
            end
        end
    end
    return y, height
end
