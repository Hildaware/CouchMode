local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips = addon:GetModule('Tips')

tips.MAX_QUEST_LINES = 6
tips.MAX_OBJECTIVES = 4

--#region ── Section build ────────────────────────────────────────────────────

function tips.buildQuestInfo()
    ---@type QuestSection
    local container = addon.Layout:VStack(UIParent, { spacing = tips.LINE_GAP })

    local fontPath, baseSize, fontFlag = tips.currentFont()
    local guildSize = math.max(10, math.floor(baseSize * 0.60))
    local guildFont = function() return fontPath, guildSize, fontFlag end

    -- Divider
    local dividerRow = addon.Layout:Container(container)
    dividerRow:SetHeight(8)
    container.questDivider = dividerRow:AddBackground("Adventure-MissionEnd-Line")
    container:AddChild(dividerRow)

    -- Quest lines stack
    local questStack = addon.Layout:VStack(container, { spacing = tips.LINE_GAP })

    container.questLines = {}
    container.questIcons = {}
    container.questObjectives = {}
    container.questRows = {}

    local lineW = tips.TIP_W - tips.PADDING * 2 - tips.QUEST_ICON_SIZE - tips.QUEST_ICON_GAP

    for i = 1, tips.MAX_QUEST_LINES do
        -- Quest title row: icon + label side by side
        local questRow = addon.Layout:HStack(questStack, { spacing = tips.QUEST_ICON_GAP })
        container.questRows[i] = questRow

        local icon = questRow:Texture("OVERLAY", { atlas = "QuestNormal", size = tips.QUEST_ICON_SIZE })
        container.questIcons[i] = icon
        questRow:AddChild(icon, { valign = "TOP" })

        local ql = questRow:FontString({ font = guildFont, color = { 1, 0.82, 0 }, justifyH = "LEFT" })
        container.questLines[i] = ql
        questRow:AddChild(ql, { valign = "TOP" })

        questStack:AddChild(questRow)

        -- Objectives
        container.questObjectives[i] = {}
        for j = 1, tips.MAX_OBJECTIVES do
            local obj = questStack:FontString({ font = guildFont, color = { 0.6, 0.6, 0.6 }, justifyH = "LEFT" })
            container.questObjectives[i][j] = obj
            questStack:AddChild(obj, {
                xOffset = tips.PADDING + 10,
                fillWidth = true,
                widthOffset = -(tips.PADDING + 10)
            })
        end
    end

    container:AddChild(questStack)

    container.hasData = false

    --#region internal helper

    local function applyQuestData(self, questData)
        if questData and #questData > 0 then
            for i = 1, tips.MAX_QUEST_LINES do
                local quest = questData[i]
                local hasTitle = quest and quest.title ~= nil
                self.questLines[i]:SetText(quest and quest.title or "")
                self.questLines[i]:SetShown(hasTitle)
                self.questIcons[i]:SetShown(hasTitle)
                for j = 1, tips.MAX_OBJECTIVES do
                    local obj = quest and quest.objectives[j]
                    local objLabel = self.questObjectives[i][j]
                    if obj then
                        if obj.finished then
                            objLabel:SetText(CreateAtlasMarkup("VAS-icon-checkmark", 12, 12) .. " " .. obj.text)
                            objLabel:SetVertexColor(0.45, 0.45, 0.45)
                        else
                            objLabel:SetText(obj.text)
                            objLabel:SetVertexColor(1, 1, 1)
                        end
                        objLabel:Show()
                    else
                        objLabel:SetText("")
                        objLabel:Hide()
                    end
                end
            end
            self.hasData = true
        else
            for i = 1, tips.MAX_QUEST_LINES do
                self.questLines[i]:SetText("")
                self.questLines[i]:Hide()
                self.questIcons[i]:Hide()
                for j = 1, tips.MAX_OBJECTIVES do
                    self.questObjectives[i][j]:SetText("")
                    self.questObjectives[i][j]:Hide()
                end
            end
            self.hasData = false
        end
    end

    --#endregion

    --#region populate

    function container:populate(unit)
        local questData = not UnitIsPlayer(unit) and addon.QuestUtils.getQuestData(unit)
        applyQuestData(self, questData)
    end

    function container:populateFromData(questData)
        applyQuestData(self, questData)
    end

    --#endregion

    --#region draw

    function container:draw()
        if not self.hasData then
            self:SetHeight(0)
            return
        end

        dividerRow:SetWidth(tips.TIP_W)
        questStack:SetWidth(tips.TIP_W - tips.PADDING)
        questStack:ClearChildren()

        for i = 1, tips.MAX_QUEST_LINES do
            local ql = self.questLines[i]
            if not ql:IsShown() then break end

            ql:SetWidth(lineW)
            local rowH = math.max(ql:GetStringHeight(), tips.QUEST_ICON_SIZE)
            ql:SetHeight(rowH)
            self.questRows[i]:SetHeight(rowH)
            self.questRows[i]:Layout()
            questStack:AddChild(self.questRows[i])

            for j = 1, tips.MAX_OBJECTIVES do
                local obj = self.questObjectives[i][j]
                if not obj:IsShown() then break end
                obj:SetHeight(math.max(obj:GetStringHeight(), 1))
                questStack:AddChild(obj, {
                    xOffset = tips.PADDING + 10,
                    fillWidth = true,
                    widthOffset = -(tips.PADDING + 10)
                })
            end
        end

        questStack:Layout(tips.PADDING)
        self:Layout()
        self:SetWidth(tips.TIP_W)
    end

    --#endregion

    --#region reset

    function container:reset()
        self.hasData = false
        for i = 1, tips.MAX_QUEST_LINES do
            self.questLines[i]:SetText("")
            self.questLines[i]:Hide()
            self.questIcons[i]:Hide()
            for j = 1, tips.MAX_OBJECTIVES do
                self.questObjectives[i][j]:SetText("")
                self.questObjectives[i][j]:Hide()
            end
        end
        self:SetHeight(0)
    end

    --#endregion

    return container
end

--#endregion
