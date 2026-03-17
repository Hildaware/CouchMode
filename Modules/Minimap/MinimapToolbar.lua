local addon_name = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MinimapModule: AceModule
local minimod = addon:GetModule('Minimap')

local _G = _G
local AnchorUtil = _G.AnchorUtil
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent

--#region ── D-pad focus state ────────────────────────────────────────────────

local focused_btn = nil

local function get_toolbar_buttons()
    local btns = {}
    if minimod.worldMapOpen then
        for _, def in ipairs(minimod.WM_BUTTON_DEFS) do
            local b = minimod[def.btn]
            if b and b:IsShown() then btns[#btns + 1] = b end
        end
    else
        if minimod.trackingBtn and minimod.trackingBtn:IsShown() then
            btns[#btns + 1] = minimod.trackingBtn
        end
    end
    if minimod.settings_btn and minimod.settings_btn:IsShown() then
        btns[#btns + 1] = minimod.settings_btn
    end
    return btns
end

local function set_focus(btn)
    if focused_btn and focused_btn ~= btn then
        focused_btn:UnlockHighlight()
    end
    focused_btn = btn
    minimod.focused_btn = btn
    if focused_btn then focused_btn:LockHighlight() end
end

-- TODO: Not working
function minimod.navigate(delta)
    local btns = get_toolbar_buttons()
    if #btns == 0 then return end
    local idx = 1
    for i, b in ipairs(btns) do
        if b == focused_btn then
            idx = i; break
        end
    end
    idx = ((idx - 1 + delta) % #btns) + 1
    set_focus(btns[idx])
end

--#endregion

--#region ── Toolbar creation ─────────────────────────────────────────────────

function minimod.createToolbar(blizz_tracking_btn)
    local db = addon.db.profile.minimap

    minimod.toolbar = CreateFrame("Frame", nil, UIParent)
    minimod.toolbar:SetHeight(24)
    minimod.toolbar:SetPoint("BOTTOMLEFT", minimod.wrapper, "TOPLEFT", 0, 0)
    minimod.toolbar:SetPoint("BOTTOMRIGHT", minimod.wrapper, "TOPRIGHT", 0, 0)
    minimod.toolbar:SetFrameStrata("DIALOG")
    minimod.toolbar:SetFrameLevel(minimod.wrapper:GetFrameLevel() + 50)
    minimod.toolbar:Hide()

    local toolbar_bg = minimod.toolbar:CreateTexture(nil, "BACKGROUND")
    toolbar_bg:SetAllPoints(minimod.toolbar)
    toolbar_bg:SetColorTexture(0, 0, 0, 0.6)

    minimod.toolbarBorders = minimod.MapUtils.create_border_textures(minimod.toolbar, minimod.toolbar)

    -- Settings button
    local settings_btn = minimod.MapUtils.create_toolbar_button(minimod.toolbar, "echoes-icon", function()
        LibStub("AceConfigDialog-3.0"):Open(addon_name)
    end, "Settings")
    settings_btn:SetPoint("RIGHT", minimod.toolbar, "RIGHT", -2, 0)
    minimod.settings_btn = settings_btn

    -- Tracking button: open native DropdownButton menu anchored to our button
    local tracking_btn = minimod.MapUtils.create_toolbar_button(minimod.toolbar, "UI-HUD-Minimap-Tracking-Up",
        function() end, "Tracking")
    tracking_btn:SetPoint("RIGHT", settings_btn, "LEFT", -10, 0)
    minimod.trackingBtn = tracking_btn
    if blizz_tracking_btn then
        blizz_tracking_btn:SetParent(tracking_btn)
        blizz_tracking_btn:ClearAllPoints()
        blizz_tracking_btn:SetPoint("CENTER", tracking_btn, "CENTER")
        blizz_tracking_btn:SetAlpha(0)
        blizz_tracking_btn.Button:SetMenuAnchor(AnchorUtil.CreateAnchor("BOTTOMLEFT", tracking_btn, "TOPLEFT", 0, 2)) ---@diagnostic disable-line: undefined-global
        tracking_btn:SetScript("OnClick", function()
            blizz_tracking_btn:OpenMenu()
        end)
    end

    -- World Map filter toggle buttons (hidden until world map is open)
    local wm_toggles = {
        { btn = "wmBtnWQ",       atlas = "worldquest-tracker-questmarker", tooltip = "World Quests",   dps = { "wmDpWorldQuests" },                          db = "worldMapShowWorldQuests" },
        { btn = "wmBtnAQ",       atlas = "QuestNormal",                    tooltip = "Active Quests",  dps = { "wmDpActiveQuests" },                         db = "worldMapShowActiveQuests" },
        { btn = "wmBtnLS",       atlas = "questlog-storylineicon",         tooltip = "Local Stories",  dps = { "wmDpLocalStories" },                         db = "worldMapShowLocalStories" },
        { btn = "wmBtnDungeons", atlas = "questlog-questtypeicon-heroic",  tooltip = "Dungeons/Raids", dps = { "wmDpDungeons" },                             db = "worldMapShowDungeons" },
        { btn = "wmBtnDelves",   atlas = "questlog-questtypeicon-Delves",  tooltip = "Delves",         dps = { "wmDpDelves" },                               db = "worldMapShowDelves" },
        { btn = "wmBtnEvents",   atlas = "questlog-questtypeicon-story",   tooltip = "Events",         dps = { "wmDpEvents" },                               db = "worldMapShowEvents" },
        { btn = "wmBtnTravel",   atlas = "MagePortalAlliance",             tooltip = "Travel",         dps = { "wmDpTravel", "wmDpPortals", "wmDpAreaPOI" }, db = "worldMapShowTravel" },
    }

    local prev_btn = settings_btn
    for i, config in ipairs(wm_toggles) do
        local btn = minimod.MapUtils.create_toolbar_button(minimod.toolbar, config.atlas, function()
            if not minimod.worldMap then return end
            db[config.db] = not db[config.db]
            for _, dpField in ipairs(config.dps) do
                local dp = minimod[dpField] ---@type any
                if dp then
                    if db[config.db] then dp:RefreshAllData() else dp:RemoveAllData() end
                end
            end
            minimod[config.btn]:SetAlpha(db[config.db] and 1 or 0.4)
        end, config.tooltip)

        btn:Hide()
        btn:SetPoint("RIGHT", prev_btn, "LEFT", i == 1 and -10 or -2, 0)
        minimod[config.btn] = btn
        prev_btn = btn
    end
end

--#endregion
