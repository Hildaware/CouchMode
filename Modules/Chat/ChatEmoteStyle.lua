-- Inline identity colors for player emotes. Preserve the localized sentence
-- and raw message; the event provides no separate emote target identity.
local addonName, addon = ...
local chat = addon.Chat
local isSecret = addon.Utils.IsSecretValue

local function safeString(value)
    return not isSecret(value) and type(value) == 'string' and value ~= ''
end

local function colorCode(classFile)
    local color = not isSecret(classFile) and classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        or HIGHLIGHT_FONT_COLOR
    if not color then return '|cffffffff' end
    return string.format('|cff%02x%02x%02x',
        math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
end

-- Treat UTF-8 bytes as name characters too, so a name is never matched inside
-- a longer name. Apostrophes remain boundaries to allow possessive suffixes.
local function nameByte(byte)
    return byte and (byte >= 128 or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57)
        or byte == 45 or byte == 95)
end

local function highlightPlain(text, names)
    local out, cursor = {}, 1
    while cursor <= #text do
        local first, last, color
        for _, entry in ipairs(names) do
            local start = cursor
            while start <= #text do
                local a, b = text:find(entry.name, start, true)
                if not a then break end
                if not nameByte(text:byte(a - 1)) and not nameByte(text:byte(b + 1)) then
                    if not first or a < first or (a == first and b > last) then
                        first, last, color = a, b, entry.color
                    end
                    break
                end
                start = b + 1
            end
        end
        if not first then
            out[#out + 1] = text:sub(cursor)
            break
        end
        out[#out + 1] = text:sub(cursor, first - 1)
        out[#out + 1] = color .. text:sub(first, last) .. '|r'
        cursor = last + 1
    end
    return table.concat(out)
end

-- Keep links, textures, atlases and existing color spans intact. Never match
-- names in hyperlink destinations or nest our colors inside existing colors.
local function highlightText(text, names)
    local out, cursor = {}, 1
    while cursor <= #text do
        local pipe = text:find('|', cursor, true)
        if not pipe then
            out[#out + 1] = highlightPlain(text:sub(cursor), names)
            break
        end
        out[#out + 1] = highlightPlain(text:sub(cursor, pipe - 1), names)
        local token = text:sub(pipe + 1, pipe + 1)
        local finish
        if token == 'H' then
            local label = text:find('|h', pipe + 2, true)
            finish = label and text:find('|h', label + 2, true)
        elseif token == 'c' or token == 'C' then
            finish = text:find('|r', pipe + 2, true)
        elseif token == 'T' then
            finish = text:find('|t', pipe + 2, true)
        elseif token == 'A' then
            finish = text:find('|a', pipe + 2, true)
        elseif token == '|' then
            finish = pipe
        end
        -- Unknown or incomplete markup is left untouched through the end.
        if not finish then
            out[#out + 1] = text:sub(pipe)
            break
        end
        out[#out + 1] = text:sub(pipe, finish + 1)
        cursor = finish + 2
    end
    return table.concat(out)
end

function chat:FormatEmoteText(msg)
    if not safeString(msg.text) then return nil end
    local colors = {}
    local function add(name, realm, classFile)
        if not safeString(name) then return end
        local knownClass = not isSecret(classFile) and classFile
        local color = knownClass and colorCode(knownClass) or colors[name] or colorCode(nil)
        colors[name] = color
        if safeString(realm) then colors[name .. '-' .. realm] = color end
    end

    -- Previously resolved senders cover players without a current unit token.
    for _, identity in pairs(self.identByGuid) do
        add(identity.name, identity.realm, identity.classFile)
    end
    local function addUnit(unit)
        if not safeString(unit) then return end
        local name, realm = UnitName(unit)
        if not safeString(name) then return end
        local _, classFile
        local isPlayer = UnitIsPlayer(unit)
        if not isSecret(isPlayer) and isPlayer then _, classFile = UnitClass(unit) end
        add(name, realm, classFile)
    end
    for _, unit in ipairs({ 'player', 'target', 'mouseover', 'focus' }) do addUnit(unit) end
    if msg.unitToken then
        addUnit(msg.unitToken)
        addUnit(msg.unitToken .. 'target')
    end
    local raid = IsInRaid and IsInRaid()
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, count do addUnit((raid and 'raid' or 'party') .. i) end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do addUnit(plate.namePlateUnitToken) end
    end

    -- The speaker is authoritative if a nearby NPC happens to share a name.
    local identity = msg.guid and self.identByGuid[msg.guid]
    local classFile = msg.classFile or (identity and identity.classFile)
    if isSecret(classFile) then classFile = nil end
    if not classFile and msg.direction == 'out' then
        local _, playerClass = UnitClass('player')
        classFile = playerClass
    end
    add(msg.sender, nil, classFile)
    if safeString(msg.sender) then add(msg.sender:match('^[^-]+'), nil, classFile) end
    local _, playerClass = UnitClass('player')
    if safeString(YOU) then
        add(YOU, nil, playerClass)
        add(YOU:lower(), nil, playerClass)
    end

    local names = {}
    for name, color in pairs(colors) do names[#names + 1] = { name = name, color = color } end
    return highlightText(msg.text, names)
end
