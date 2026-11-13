-- Presentation of player speech in a language other than the normal chat
-- language. IDs describe the spoken language, independently of the speaker.
local _, addon = ...
local chat = addon.Chat
local Sources = addon.ChatSources
local function db() return addon.db.profile.chat end
local races = {
    [1] = 'orc',       -- Orcish
    [2] = 'nightelf',  -- Darnassian
    [3] = 'tauren',    -- Taurahe
    [6] = 'dwarf',     -- Dwarven
    [7] = 'human',     -- Common
    [10] = 'bloodelf', -- Thalassian
    [13] = 'gnome',    -- Gnomish
    [14] = 'troll',    -- Troll
    [33] = 'undead',   -- Gutterspeak
    [35] = 'draenei',  -- Draenei
    [36] = 'undead',   -- Zombie
    [37] = 'gnome',    -- Gnomish Binary
    [38] = 'goblin',   -- Goblin Binary
}
local iconCache = {}

function chat:NonDefaultLanguage(msg)
    if msg.category == 'NPC' or msg.category == 'SYSTEM' or msg.isBN
        or Sources.IsEmote(msg.event) then return end
    local name, id = msg.language, msg.languageID
    if not name or id == 0 or (id and (id < 0 or id == 0xFFFFFFFF)) then return end
    if not GetDefaultLanguage then return end
    local defaultName, defaultID = GetDefaultLanguage()
    if (msg.event == 'CHAT_MSG_SAY' or msg.event == 'CHAT_MSG_YELL') and GetAlternativeDefaultLanguage then
        local alternative, alternativeID = GetAlternativeDefaultLanguage()
        if not Sources.isSecret(alternative) and type(alternative) == 'string' and alternative ~= '' then
            defaultName, defaultID = alternative, alternativeID
        end
    end
    if id and not Sources.isSecret(defaultID) and type(defaultID) == 'number' then
        if id ~= defaultID then return name end
    elseif not Sources.isSecret(defaultName) and type(defaultName) == 'string'
        and defaultName ~= '' and name ~= defaultName then
        return name
    end
end

function chat:LanguageIcon(id, size)
    local atlas = id and iconCache[id]
    if atlas == nil then
        atlas = false
        local race = races[id]
        if race and GetRaceAtlas and C_Texture and C_Texture.GetAtlasInfo then
            for _, hires in ipairs({ true, false }) do
                local candidate = GetRaceAtlas(race, 'male', hires)
                if candidate and C_Texture.GetAtlasInfo(candidate) then atlas = candidate; break end
            end
        end
        if id then iconCache[id] = atlas end
    end
    if atlas then return ('|A:%s:%d:%d|a'):format(atlas, size, size) end
    return ('|TInterface\\Icons\\INV_Misc_Book_09:%d:%d|t'):format(size, size)
end

-- A custom hyperlink makes just the icon hoverable; it is atomic during reveal.
-- Raw message text remains untouched for copying, grouping and moderation.
function chat:LanguagePresentation(msg, index, normalFace, fontSize)
    local text = msg.emoteText or msg.text
    if not self:NonDefaultLanguage(msg) or Sources.isSecret(text) then return text, normalFace end
    local size = math.max(14, math.min(16, math.floor(fontSize)))
    local icon = self:LanguageIcon(msg.languageID, size)
    return ('|Hcouchmodelanguage:%d|h%s|h '):format(index, icon) .. (text or ''),
        addon.Media.ResolveItalicFont(db().msgFontFace)
end
