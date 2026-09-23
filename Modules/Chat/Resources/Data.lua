local _, addon = ...

addon.BanterData = addon.BanterData or {}

---@param name string
---@return number? npcId, number? displayId
function addon.BanterData.GetByName(name)
    if issecretvalue and issecretvalue(name) then return end

    local data = addon.BanterData.CreatureByName
    local entry = data and data[name]
    if entry then return entry.id, entry.displayId end
end
