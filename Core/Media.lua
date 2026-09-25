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

-- Bundled font used when a configured face is not registered with LibSharedMedia.
local FALLBACK_FONT = 'Interface/AddOns/CouchMode/Resources/Fonts/BebasNeue-Regular.ttf'

--- Resolves a configured font face to a usable font path, falling back to the
--- bundled default when LibSharedMedia does not know the face.
---@param face string?
---@return string
function addon.Media.ResolveFont(face)
    return LSM:Fetch(LSM.MediaType.FONT, face) or FALLBACK_FONT
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
