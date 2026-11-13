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

-- Names match the frame labels supplied by each module at registration.
local moduleByLabel = {
    ['CouchMode Map'] = 'Minimap', ['CouchMode Tips'] = 'Tips',
    ['CouchMode Party'] = 'Party', ['CouchMode Toasts'] = 'Toasts',
    ['CouchMode Chat'] = 'Chat', ['CouchMode Cast Ring'] = 'CastRing',
    ['CouchMode Quick Thanks'] = 'QualityOfLife',
    ['CouchMode Cast Bar'] = 'PlayerCastBar', ['CouchMode Health'] = 'PlayerHealthBar',
    ['CouchMode Power'] = 'PlayerPowerBar', ['CouchMode Mana'] = 'PlayerManaBar',
}
editMode.registrations = {}
local moduleByFrame = {}

---Register a frame with the active Edit Mode backend.
function editMode:RegisterFrame(frame, callback, default, name)
    backend:AddFrame(frame, function(registeredFrame, layoutName, ...)
        if layoutName then
            callback(registeredFrame, layoutName, ...)
        end
    end, default, name)
    local moduleName = moduleByLabel[name]
    if moduleName then
        moduleByFrame[frame] = moduleName
        self.registrations[moduleName] = { frame = frame }
        backend:AddFrameSettingsButtons(frame, {
            {
                text = 'More Settings', name = 'More Settings',
                desc = 'Open this component in CouchMode settings.',
                click = function() addon:GetModule('Options'):OpenModule(moduleName) end,
            },
        })
    end
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

    backend:AddFrameSettings(frame, backendSettings)
    local moduleName = moduleByFrame[frame]
    if moduleName then
        self.registrations[moduleName].settings = settings
        self:RefreshLayoutOptions(moduleName)
    end
end

function editMode:RefreshFrameSettings(frame)
    backend:RefreshFrameSettings(frame)
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
