local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

local backend = LibStub('LibEditMode')
local backendSettingTypes = backend.SettingType

---@class CouchModeEditMode
---@field SettingType table
local editMode = {
    SettingType = {
        Slider = 'slider',
        Dropdown = 'dropdown',
    },
}

---Register a frame with the active Edit Mode backend.
function editMode:RegisterFrame(frame, callback, default, name)
    backend:AddFrame(frame, function(registeredFrame, layoutName, ...)
        if layoutName then
            callback(registeredFrame, layoutName, ...)
        end
    end, default, name)
end

---Register Edit Mode controls for a frame.
function editMode:RegisterFrameSettings(frame, settings)
    local backendSettings = {}
    local kindMap = {
        [editMode.SettingType.Slider] = backendSettingTypes.Slider,
        [editMode.SettingType.Dropdown] = backendSettingTypes.Dropdown,
    }

    for index, setting in ipairs(settings) do
        local backendSetting = {}
        for key, value in pairs(setting) do
            if key == 'kind' then
                assert(kindMap[value], 'unsupported Edit Mode setting kind: ' .. tostring(value))
                backendSetting[key] = kindMap[value]
            else
                backendSetting[key] = value
            end
        end
        backendSettings[index] = backendSetting
    end

    return backend:AddFrameSettings(frame, backendSettings)
end

---Register for an Edit Mode lifecycle or layout callback.
function editMode:RegisterCallback(...)
    return backend:RegisterCallback(...)
end

---Return the active layout name, or nil until the client has loaded it.
function editMode:GetActiveLayoutName()
    return backend:GetActiveLayoutName()
end

addon.EditMode = editMode
