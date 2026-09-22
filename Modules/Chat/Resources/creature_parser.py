import csv
import os

# Resolve absolute paths relative to this script's location
script_dir = os.path.dirname(os.path.abspath(__file__))
csv_path = os.path.join(script_dir, 'Creature.12.0.5.csv')
lua_path = os.path.join(script_dir, 'Data.lua')

with open(csv_path, 'r', encoding='utf-8') as csvfile:
    reader = csv.DictReader(csvfile)
    rows = list(reader)

# Read in reverse so the latest model revision wins for duplicate names.
seen_names = set()
name_rows = []  # one entry per unique name (latest wins)

for row in reversed(rows):
    npc_id = row['ID']
    display_id = row['DisplayID_0']
    name = row['Name_lang']

    if not display_id or display_id == '0' or not name:
        continue

    if name not in seen_names:
        seen_names.add(name)
        name_rows.append((name, npc_id, display_id))

lua_output = "-- This file is auto-generated. Do not edit directly.\n"
lua_output += "local addonName, addon = ...\n\n"

lua_output += "local CREATURE_DISPLAY_DATA = {\n"
for name, npc_id, display_id in name_rows:
    safe_name = name.replace("\\", "\\\\").replace('"', '\\"')
    lua_output += f'    ["{safe_name}"] = {{ id = {npc_id}, displayId = {display_id} }},\n'
lua_output += "}\n\n"

lua_output += "addon.BanterData = addon.BanterData or {}\n\n"
lua_output += "---@param name string\n"
lua_output += "---@return number? npcId, number? displayId\n"
lua_output += "function addon.BanterData.GetByName(name)\n"
lua_output += "    local entry = CREATURE_DISPLAY_DATA[name]\n"
lua_output += "    if entry then return entry.id, entry.displayId end\n"
lua_output += "end\n"

with open(lua_path, 'w', encoding='utf-8') as luafile:
    luafile.write(lua_output)

print("Successfully generated Data.lua with optimized flat mappings!")
