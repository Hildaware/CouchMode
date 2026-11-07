local addon_name     = ...

---@class CouchMode: AceAddon
local addon          = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MapModule: AceModule
local map            = addon:GetModule('Minimap')

local _G             = _G
local AnchorUtil     = _G.AnchorUtil
local CreateFrame    = _G.CreateFrame
local UIParent       = _G.UIParent

TOOLBAR_BUTTON_TYPE  = {
    MINIMAP   = 1,
    WORLD_MAP = 2,
}

--#region ── Button definitions ───────────────────────────────────────────────

local poi_defs       = {
    { btn = "poiBtnQuests",    atlas = "QuestNormal",             tooltip = "Quest Labels",     db = "poiLabelsShowQuests" },
    { btn = "poiBtnRares",     atlas = "VignetteKill",            tooltip = "Rare Labels",      db = "poiLabelsShowRares" },
    { btn = "poiBtnTreasures", atlas = "VignetteTreasure",        tooltip = "Treasure Labels",  db = "poiLabelsShowTreasures" },
    { btn = "poiBtnPetTamers", atlas = "WildBattlePetCapturable", tooltip = "Pet Tamer Labels", db = "poiLabelsShowPetTamers" },
}

local world_map_defs = {
    { btn = "wmBtnWQ",       atlas = "worldquest-tracker-questmarker", tooltip = "World Quests",   dps = { "wmDpWorldQuests" },                          db = "worldMapShowWorldQuests" },
    { btn = "wmBtnAQ",       atlas = "QuestNormal",                    tooltip = "Active Quests",  dps = { "wmDpActiveQuests" },                         db = "worldMapShowActiveQuests" },
    { btn = "wmBtnLS",       atlas = "questlog-storylineicon",         tooltip = "Local Stories",  dps = { "wmDpLocalStories" },                         db = "worldMapShowLocalStories" },
    { btn = "wmBtnDungeons", atlas = "questlog-questtypeicon-heroic",  tooltip = "Dungeons/Raids", dps = { "wmDpDungeons", "wmDpBosses" },               db = "worldMapShowDungeons" },
    { btn = "wmBtnDelves",   atlas = "questlog-questtypeicon-Delves",  tooltip = "Delves",         dps = { "wmDpDelves" },                               db = "worldMapShowDelves" },
    { btn = "wmBtnEvents",   atlas = "questlog-questtypeicon-story",   tooltip = "Events",         dps = { "wmDpEvents" },                               db = "worldMapShowEvents" },
    { btn = "wmBtnTravel",   atlas = "MagePortalAlliance",             tooltip = "Travel",         dps = { "wmDpTravel", "wmDpPortals", "wmDpAreaPOI" }, db = "worldMapShowTravel" },
}

local function wrap_blizz_btn(btn, blizz, on_click)
    blizz:SetParent(btn)
    blizz:ClearAllPoints()
    blizz:SetPoint("CENTER", btn, "CENTER")
    blizz:SetAlpha(0)
    blizz:EnableMouse(false)
    btn:SetScript("OnClick", on_click)
end

local function useNativeToolbarButton(btn, blizz, clickTarget)
    -- Keep Blizzard's mouse handlers and menu anchors on Forever. Forwarding a
    -- click through addon code taints menu state read by gamepad focus cleanup.
    -- Tracking's DropdownButton is a child of its decorative container.
    clickTarget = clickTarget or blizz
    blizz:ClearAllPoints()
    blizz:SetSize(btn:GetSize())
    blizz:SetPoint("CENTER", btn, "CENTER")
    blizz:SetFrameStrata(btn:GetFrameStrata())
    blizz:SetFrameLevel(btn:GetFrameLevel() + 1)
    blizz:SetAlpha(0)
    blizz:EnableMouse(clickTarget == blizz)
    clickTarget:SetSize(btn:GetSize())
    clickTarget:EnableMouse(true)
    blizz:SetShown(btn:IsVisible())

    btn:SetScript("OnClick", nil)
    btn:EnableMouse(false)
    btn:HookScript("OnShow", function() blizz:Show() end)
    btn:HookScript("OnHide", function() blizz:Hide() end)
end

local function minimap_defs()
    local day = _G.C_DateAndTime and _G.C_DateAndTime.GetCurrentCalendarTime().monthDay or 1
    return {
        {
            btn = "trackingBtn",
            atlas = "UI-HUD-Minimap-Tracking-Up",
            tooltip = "Tracking",
            blizz = map.blizzTracking,
            setup = function(btn, blizz)
                if addon.Utils.IsFlavor('forever') then
                    useNativeToolbarButton(btn, blizz, blizz.Button)
                    return
                end
                blizz.Button:SetMenuAnchor(AnchorUtil.CreateAnchor("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)) ---@diagnostic disable-line: undefined-global
                blizz.Button:EnableMouse(false)
                local is_open = false
                hooksecurefunc(blizz.Button, "CloseMenu", function() is_open = false end)
                wrap_blizz_btn(btn, blizz, function()
                    if is_open then blizz.Button:CloseMenu() else
                        is_open = true; blizz.Button:OpenMenu()
                    end
                end)
            end
        },
        {
            btn = "compartmentBtn",
            atlas = "PetJournal-FavoritesIcon",
            tooltip = "Addons",
            blizz = map.blizzCompartment,
            setup = function(btn, blizz)
                if addon.Utils.IsFlavor('forever') then
                    useNativeToolbarButton(btn, blizz)
                else
                    blizz:SetMenuAnchor(AnchorUtil.CreateAnchor("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)) ---@diagnostic disable-line: undefined-global
                    local is_open = false
                    hooksecurefunc(blizz, "CloseMenu", function() is_open = false end)
                    wrap_blizz_btn(btn, blizz, function()
                        if is_open then blizz:CloseMenu() else
                            is_open = true; blizz:OpenMenu()
                        end
                    end)
                end
            end
        },
        {
            btn = "calendarBtn",
            atlas = ("ui-hud-calendar-%d-up"):format(day),
            tooltip = "Calendar",
            blizz = map.blizzCalendar,
            setup = function(btn, blizz)
                if addon.Utils.IsFlavor('forever') then
                    useNativeToolbarButton(btn, blizz)
                else
                    wrap_blizz_btn(btn, blizz, function() _G.GameTimeFrame_OnClick(blizz) end) ---@diagnostic disable-line: undefined-global
                end
            end
        },
    }
end

--#endregion

--#region ── Button visibility ────────────────────────────────────────────────

local function toggle_minimap_buttons(visible)
    local db = addon.db.profile.minimap ---@type MinimapDB
    for _, entry in ipairs(map.toolbar.buttons[TOOLBAR_BUTTON_TYPE.MINIMAP]) do
        local alpha = visible and (entry.db and (db[entry.db] and 1 or 0.4) or 1) or 0
        entry.frame:SetAlpha(alpha)
        entry.frame:SetShown(visible)
    end
end

local function toggle_world_map_buttons(visible)
    local db = addon.db.profile.minimap ---@type MinimapDB
    for _, entry in ipairs(map.toolbar.buttons[TOOLBAR_BUTTON_TYPE.WORLD_MAP]) do
        entry.frame:SetAlpha(visible and (db[entry.db] and 1 or 0.4) or 0)
        entry.frame:SetShown(visible)
    end
end

--#endregion

--#region ── Toolbar creation ─────────────────────────────────────────────────

function map.applyToolbarPosition()
    if not map.toolbar then return end
    local db = addon.db.profile.minimap ---@type MinimapDB
    map.toolbar:ClearAllPoints()
    if db.toolbarDock == "bottom" then
        map.toolbar:SetPoint("TOPLEFT", map.container, "BOTTOMLEFT", 0, 8)
        map.toolbar:SetPoint("TOPRIGHT", map.container, "BOTTOMRIGHT", 0, 8)
    else
        map.toolbar:SetPoint("BOTTOMLEFT", map.container, "TOPLEFT", 0, -14)
        map.toolbar:SetPoint("BOTTOMRIGHT", map.container, "TOPRIGHT", 0, -14)
    end
    map.applyBorder()
end

function map.createToolbar()
    local db = addon.db.profile.minimap ---@type MinimapDB

    map.toolbar = CreateFrame("Frame", "CTMinimapToolbar", UIParent)
    map.toolbar:SetHeight(50)
    map.applyToolbarPosition()
    map.toolbar:SetFrameStrata("DIALOG")
    map.toolbar:SetFrameLevel(map.container:GetFrameLevel() + 50)
    map.toolbar:Hide()

    addon.Components.Metal.CreateHeader(map.toolbar)

    -- Settings button
    local settings_btn = map.MapUtils.create_toolbar_button(map.toolbar, "echoes-icon", function()
        LibStub("AceConfigDialog-3.0"):Open(addon_name)
    end, "Settings")
    settings_btn:SetPoint("RIGHT", map.toolbar, "RIGHT", -2, 0)
    map.settings_btn = settings_btn

    map.toolbar.buttons = {
        [TOOLBAR_BUTTON_TYPE.MINIMAP]   = {},
        [TOOLBAR_BUTTON_TYPE.WORLD_MAP] = {},
    }

    -- Minimap-specific toolbar buttons
    local prev_btn = settings_btn
    for i, config in ipairs(minimap_defs()) do
        local btn = map.MapUtils.create_toolbar_button(map.toolbar, config.atlas, function() end, config.tooltip)
        btn:SetPoint("RIGHT", prev_btn, "LEFT", i == 1 and -10 or -2, 0)
        map[config.btn] = btn
        map.toolbar.buttons[TOOLBAR_BUTTON_TYPE.MINIMAP][i] = { frame = btn }
        if config.blizz then config.setup(btn, config.blizz) end
        prev_btn = btn
    end

    -- POI label filter toggle buttons
    local n = #map.toolbar.buttons[TOOLBAR_BUTTON_TYPE.MINIMAP]
    for i, config in ipairs(poi_defs) do
        local btn
        btn = map.MapUtils.create_toolbar_button(map.toolbar, config.atlas, function()
            db[config.db] = not db[config.db]
            btn.selected_bg:SetShown(db[config.db])
            btn:SetAlpha(db[config.db] and 1 or 0.4)
            map.updatePOILabels()
        end, config.tooltip)

        btn:SetPoint("RIGHT", prev_btn, "LEFT", i == 1 and -4 or -2, 0)
        btn.selected_bg:SetShown(db[config.db])
        map[config.btn] = btn
        map.toolbar.buttons[TOOLBAR_BUTTON_TYPE.MINIMAP][n + i] = { frame = btn, db = config.db }
        prev_btn = btn
    end

    -- World Map filter toggle buttons (hidden until world map is open)
    prev_btn = settings_btn
    for i, config in ipairs(world_map_defs) do
        local btn
        btn = map.MapUtils.create_toolbar_button(map.toolbar, config.atlas, function()
            if not map.worldMap then return end
            db[config.db] = not db[config.db]
            for _, dpField in ipairs(config.dps) do
                local dp = map[dpField] ---@type any
                if dp then
                    if db[config.db] then dp:RefreshAllData() else dp:RemoveAllData() end
                end
            end
            btn.selected_bg:SetShown(db[config.db])
            btn:SetAlpha(db[config.db] and 1 or 0.4)
        end, config.tooltip)

        btn:Hide()
        btn:SetPoint("RIGHT", prev_btn, "LEFT", i == 1 and -10 or -2, 0)
        btn.selected_bg:SetShown(db[config.db])
        map[config.btn] = btn
        map.toolbar.buttons[TOOLBAR_BUTTON_TYPE.WORLD_MAP][i] = { frame = btn, db = config.db }
        prev_btn = btn
    end
end

function map.setToolbarType(type)
    if type == TOOLBAR_BUTTON_TYPE.MINIMAP then
        toggle_minimap_buttons(true)
        toggle_world_map_buttons(false)
    elseif type == TOOLBAR_BUTTON_TYPE.WORLD_MAP then
        toggle_minimap_buttons(false)
        toggle_world_map_buttons(true)
    end
end

--#endregion
