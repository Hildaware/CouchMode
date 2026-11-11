-- /cm and Edit Mode use the same geometry descriptors and setters.
local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local editMode = addon.EditMode
local layoutOptions = {}
local geometryKeys = { Width = 'width', Height = 'height', Size = 'size', Scale = 'scale', Shape = 'shape' }

local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function available(moduleName)
    local module = addon:GetModule(moduleName, true)
    return module and module:IsEnabled() and editMode.registrations[moduleName]
end

function editMode:EditLayout(moduleName)
    if inCombat() then return end
    local manager = EditModeManagerFrame
    if not manager or not available(moduleName) then return end
    if not manager:IsShown() and not manager:CanEnterEditMode() then return end
    LibStub('AceConfigDialog-3.0'):Close(addonName)
    if not manager:IsShown() then ShowUIPanel(manager) end
    -- Selection stays with LibEditMode's own click handlers, including gamepad input.
end

function editMode:GetLayoutOptions(moduleName)
    if layoutOptions[moduleName] then return layoutOptions[moduleName] end
    local args = {
        description = {
            name = 'Move this component in Edit Mode. Position follows the active Edit Mode layout; '
                .. 'size and appearance are shared across layouts in this CouchMode profile. '
                .. 'Enable this component to adjust its layout.',
            type = 'description', order = 0,
        },
        editLayout = {
            name = 'Edit Layout', type = 'execute', order = 1,
            desc = 'Open Edit Mode, then select this component to move or resize it.',
            disabled = function()
                return inCombat() or not available(moduleName) or not EditModeManagerFrame
                    or (not EditModeManagerFrame:IsShown() and not EditModeManagerFrame:CanEnterEditMode())
            end,
            func = function() editMode:EditLayout(moduleName) end,
        },
    }
    layoutOptions[moduleName] = args
    self:RefreshLayoutOptions(moduleName)
    return args
end

-- Registration happens after options are assembled. Populate the same args table
-- when a component creates its frame, including components enabled later.
function editMode:RefreshLayoutOptions(moduleName)
    local args, registration = layoutOptions[moduleName], self.registrations[moduleName]
    if not args or not registration then return end
    for index, descriptor in ipairs(registration.settings or {}) do
        local setting = descriptor
        local key = geometryKeys[setting.name]
        if key then
            local option = {
                name = setting.name, desc = setting.desc, order = index + 1,
                disabled = function()
                    if inCombat() or not available(moduleName) then return true end
                    if type(setting.disabled) == 'function' then
                        return setting.disabled(editMode:GetActiveLayoutName())
                    end
                    return setting.disabled == true
                end,
                get = function() return setting.get(editMode:GetActiveLayoutName()) end,
                set = function(_, value)
                    if inCombat() or not available(moduleName) then return end
                    setting.set(editMode:GetActiveLayoutName(), value, false)
                    editMode:RefreshFrameSettings(registration.frame)
                end,
            }
            if setting.kind == self.SettingType.Slider then
                option.type = 'range'
                option.min, option.max, option.step = setting.minValue, setting.maxValue, setting.valueStep
            elseif setting.kind == self.SettingType.Dropdown then
                option.type = 'select'
                option.values = function()
                    local values = {}
                    local entries = type(setting.values) == 'function' and setting.values() or setting.values
                    for _, entry in ipairs(entries or {}) do values[entry.value] = entry.text end
                    return values
                end
            end
            args[key] = option
        end
    end
    LibStub('AceConfigRegistry-3.0'):NotifyChange(addonName)
end
