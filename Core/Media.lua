local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local LSM = LibStub('LibSharedMedia-3.0')

addon.Media = {}

local FONTS = {
    ['Accidental Presidency'] = 'Interface\\AddOns\\CouchMode\\Resources\\Fonts\\AccidentalPresidency.ttf',
    ['Bebas Neue'] = 'Interface\\AddOns\\CouchMode\\Resources\\Fonts\\BebasNeue-Regular.ttf',
}

for name, path in pairs(FONTS) do
    if not LSM:IsValid(LSM.MediaType.FONT, name) then
        LSM:Register(LSM.MediaType.FONT, name, path)
    end
end

--- Returns AceConfig select values with human-readable names for both keys and labels.
---@return table<string, string>
function addon.Media.GetFontOptions()
    local fonts = {}
    for _, name in ipairs(LSM:List(LSM.MediaType.FONT)) do
        fonts[name] = name
    end
    return fonts
end
