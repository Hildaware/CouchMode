import csv
import os

# Resolve absolute paths relative to this script's location
script_dir = os.path.dirname(os.path.abspath(__file__))
csv_path = os.path.join(script_dir, 'Creature.12.0.5.csv')
lua_path = os.path.join(script_dir, 'Data.lua')

lua_output = "-- This file is auto-generated. Do not edit directly.\n"
lua_output += "local addonName, addon = ...\n\n"
lua_output += "local CREATURE_DISPLAY_DATA = {\n"

with open(csv_path, 'r', encoding='utf-8') as csvfile:
    # csv.DictReader automatically handles commas inside quoted names
    reader = csv.DictReader(csvfile)
    for row in reader:
        npc_id = row['ID']
        display_id = row['DisplayID_0']
        name = row['Name_lang']
        
        # Filter out invalid display IDs
        if display_id and display_id != '0':
            lua_output += f"    [{npc_id}] = {display_id}, -- {name}\n"

lua_output += "}\n\n"
lua_output += "addon.BanterData = addon.BanterData or {}\n\n"
lua_output += "---@param npcId number\n"
lua_output += "---@return number? displayId\n"
lua_output += "function addon.BanterData.GetDisplayId(npcId)\n"
lua_output += "    return CREATURE_DISPLAY_DATA[npcId]\n"
lua_output += "end\n"

with open(lua_path, 'w', encoding='utf-8') as luafile:
    luafile.write(lua_output)

print("Successfully generated Data.lua with optimized flat mappings!")
