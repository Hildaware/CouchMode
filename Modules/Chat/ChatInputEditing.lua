-- Native edit-box adapters used only by the chat composer.
local _, addon = ...
local Input = addon.ChatInput

local function get(frame, method, attribute)
    if frame[method] then return frame[method](frame) end
    return frame:GetAttribute(attribute)
end

local function set(frame, method, attribute, value)
    if frame[method] then frame[method](frame, value)
    else frame:SetAttribute(attribute, value) end
end

local function changedByController(frame, character)
    -- Insert/SetText are programmatic edits. Drive the same autocomplete hooks
    -- as physical typing, without replacing Blizzard's parser or suggestion UI.
    local changed = frame:GetScript('OnTextChanged')
    if changed then changed(frame, true) end
    local onChar = character and frame:GetScript('OnChar')
    if onChar then onChar(frame, character) end
end

function Input:CaptureDraft()
    local frame = self:GetEditBox()
    if not frame then return nil end
    return {
        text = frame:GetText(), cursor = frame:GetCursorPosition(),
        chatType = get(frame, 'GetChatType', 'chatType') or 'SAY',
        target = get(frame, 'GetTellTarget', 'tellTarget'),
        channel = get(frame, 'GetChannelTarget', 'channelTarget'),
        language = frame.languageID,
    }
end

function Input:RestoreDraft(draft)
    local frame = self:GetEditBox()
    if not frame or not draft then return end
    set(frame, 'SetChatType', 'chatType', draft.chatType)
    set(frame, 'SetTellTarget', 'tellTarget', draft.target)
    set(frame, 'SetChannelTarget', 'channelTarget', draft.channel)
    frame.languageID = draft.language
    frame:SetText(draft.text or '')
    frame:SetCursorPosition(math.min(draft.cursor or 0, #(draft.text or '')))
    self:UpdateDestinationHeader()
end

function Input:UpdateDestinationHeader()
    local frame = self:GetEditBox()
    if not frame then return end
    if frame.UpdateHeader then frame:UpdateHeader()
    elseif ChatEdit_UpdateHeader then ChatEdit_UpdateHeader(frame) end
end

function Input:InsertText(text)
    local frame = self:GetEditBox()
    if not frame or not text then return end
    -- Blizzard's text-changed handler parses channel commands after Insert.
    text = text:gsub('|', '||')
    frame:Insert(text)
    changedByController(frame, text)
end

function Input:InsertSpace()
    local frame = self:GetEditBox()
    if not frame then return end
    local handler = frame:GetScript('OnSpacePressed')
    if handler then handler(frame) end
    frame:Insert(' ')
    changedByController(frame)
end

-- Byte spans match EditBox cursor/highlight offsets. Keep hyperlinks, textures,
-- atlas escapes and raid markers intact while traversing UTF-8 characters.
local function spans(text)
    local result, pos = {}, 1
    while pos <= #text do
        local tail = text:sub(pos)
        local token = tail:match('^|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r')
            or tail:match('^|H.-|h.-|h') or tail:match('^|T.-|t')
            or tail:match('^|A.-|a') or tail:match('^{rt%d}') or tail:match('^||')
        local length = token and #token or 1
        if not token then
            local byte = text:byte(pos)
            if byte >= 240 then length = 4
            elseif byte >= 224 then length = 3
            elseif byte >= 192 then length = 2 end
        end
        result[#result + 1] = { pos - 1, math.min(#text, pos + length - 1) }
        pos = pos + length
    end
    return result
end

function Input:MoveCaret(direction)
    local frame = self:GetEditBox()
    if not frame then return end
    local text, cursor = frame:GetText(), frame:GetCursorPosition()
    local atoms = spans(text)
    if direction < 0 then
        for i = #atoms, 1, -1 do
            if atoms[i][1] < cursor then frame:SetCursorPosition(atoms[i][1]); return end
        end
    else
        for _, atom in ipairs(atoms) do
            if atom[2] > cursor then frame:SetCursorPosition(atom[2]); return end
        end
    end
end

function Input:Backspace()
    local frame = self:GetEditBox()
    if not frame then return end
    local text, cursor = frame:GetText(), frame:GetCursorPosition()
    -- Inserting an empty string deletes a native selection first. This preserves
    -- Blizzard's selection behavior for mouse and physical-keyboard users.
    frame:Insert('')
    if frame:GetText() ~= text then changedByController(frame); return end
    local atoms = spans(text)
    for i = #atoms, 1, -1 do
        local atom = atoms[i]
        if atom[1] < cursor then
            frame:HighlightText(atom[1], atom[2])
            frame:Insert('')
            frame:SetCursorPosition(atom[1])
            changedByController(frame)
            return
        end
    end
end

function Input:InsertPhrase(phrase)
    if type(phrase) ~= 'string' or phrase:match('^%s*/') then return end
    local frame = self:GetEditBox()
    if not frame then return end
    local text, cursor = frame:GetText(), frame:GetCursorPosition()
    phrase = phrase:gsub('[\r\n]', ' '):gsub('|', '||')
    local before, after = text:sub(cursor, cursor), text:sub(cursor + 1, cursor + 1)
    if cursor > 0 and not before:match('%s') then phrase = ' ' .. phrase end
    if after ~= '' and not after:match('%s') then phrase = phrase .. ' ' end
    frame:Insert(phrase)
    changedByController(frame)
end

local channelLabels = {
    SAY = SAY_MESSAGE or 'Say', YELL = YELL_MESSAGE or 'Yell',
    PARTY = PARTY_MESSAGE or 'Party', RAID = RAID_MESSAGE or 'Raid',
    INSTANCE_CHAT = INSTANCE_CHAT_MESSAGE or 'Instance', GUILD = GUILD_MESSAGE or 'Guild',
    WHISPER = WHISPER_MESSAGE or 'Whisper', BN_WHISPER = WHISPER_MESSAGE or 'Whisper',
}

function Input:GetDestinationLabel(compact)
    local draft = self:CaptureDraft()
    if not draft then return '' end
    local label = channelLabels[draft.chatType] or draft.chatType
    if draft.chatType == 'WHISPER' or draft.chatType == 'BN_WHISPER' then
        if compact then return label end
        return label .. ': ' .. tostring(draft.target or '?')
    elseif draft.chatType == 'CHANNEL' then
        local id, name = GetChannelName(draft.channel or 0)
        if compact then return id and id > 0 and (tostring(id) .. '.') or 'Channel' end
        return name and name ~= '' and (tostring(id) .. '. ' .. name) or 'Channel unavailable'
    end
    return label
end

function Input:GetDestinationColor()
    local frame = self:GetEditBox()
    local kind = frame and get(frame, 'GetChatType', 'chatType') or 'SAY'
    local info = ChatTypeInfo and ChatTypeInfo[kind]
    if kind == 'CHANNEL' and ChatTypeInfo then
        -- Match Blizzard's edit-box header, including customized numbered-channel colors.
        local id = GetChannelName(get(frame, 'GetChannelTarget', 'channelTarget') or 0)
        if id and id > 0 then info = ChatTypeInfo['CHANNEL' .. id] or info end
    end
    if info and info.r and info.g and info.b then return info.r, info.g, info.b end
    return 0.87, 0.84, 0.76
end

function Input:GetDestinations()
    local result = {}
    local function add(chatType, available, target, channel, label)
        if available then
            result[#result + 1] = { chatType = chatType, target = target, channel = channel,
                label = label or channelLabels[chatType] or chatType }
        end
    end
    add('SAY', true)
    add('YELL', true)
    add('PARTY', IsInGroup())
    add('RAID', IsInRaid())
    add('INSTANCE_CHAT', LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE))
    add('GUILD', IsInGuild())
    if GetChannelList then
        local channels = { GetChannelList() }
        for i = 1, #channels, 3 do
            local id, name, disabled = channels[i], channels[i + 1], channels[i + 2]
            add('CHANNEL', not disabled, nil, id, tostring(id) .. '. ' .. tostring(name))
        end
    end
    local last, lastType
    if ChatFrameUtil and ChatFrameUtil.GetLastTellTarget then
        last, lastType = ChatFrameUtil.GetLastTellTarget()
    elseif ChatEdit_GetLastTellTarget then last, lastType = ChatEdit_GetLastTellTarget() end
    add(lastType or 'WHISPER', last and last ~= '', last, nil, 'Reply: ' .. tostring(last or ''))
    if UnitIsPlayer('target') and UnitIsFriend('player', 'target') then
        local name = GetUnitName('target', true)
        add('WHISPER', name ~= nil, name, nil, 'Whisper: ' .. tostring(name))
    end
    return result
end

function Input:DestinationAvailable()
    local draft = self:CaptureDraft()
    if not draft then return false end
    local kind = draft.chatType
    if kind == 'PARTY' then return IsInGroup()
    elseif kind == 'RAID' then return IsInRaid()
    elseif kind == 'GUILD' then return IsInGuild()
    elseif kind == 'INSTANCE_CHAT' then
        return LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    elseif kind == 'WHISPER' or kind == 'BN_WHISPER' then
        return draft.target ~= nil and draft.target ~= ''
    elseif kind == 'CHANNEL' then
        local id = GetChannelName(draft.channel or 0)
        return id and id > 0
    end
    return true
end

function Input:SelectDestination(destination)
    local frame = self:GetEditBox()
    if not frame then return end
    set(frame, 'SetChatType', 'chatType', destination.chatType)
    set(frame, 'SetTellTarget', 'tellTarget', destination.target)
    set(frame, 'SetChannelTarget', 'channelTarget', destination.channel)
    self:UpdateDestinationHeader()
end
