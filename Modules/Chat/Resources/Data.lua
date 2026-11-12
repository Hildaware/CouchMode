local _, addon = ...

addon.BanterData = addon.BanterData or {}

---@param name string
---@return number? npcId, number? displayId
function addon.BanterData.GetByName(name)
    if addon.Utils.IsSecretValue(name) then return end

    local data = addon.BanterData.CreatureByName
    local entry = data and data[name]
    if entry then return entry.id, entry.displayId end
end

--- Prefer the speaker's exact creature ID over potentially duplicated names.
---@param guid string?
---@return number? npcId, number? displayId
function addon.BanterData.GetByGUID(guid)
    if addon.Utils.IsSecretValue(guid) or type(guid) ~= 'string' then return end
    local kind, id = guid:match('^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-')
    if kind ~= 'Creature' and kind ~= 'Vehicle' then return end
    id = tonumber(id)
    local data = addon.BanterData.CreatureByID
    local entry = data and data[id]
    return id, entry and entry.displayId
end
