#!/usr/bin/env python3
"""Build flavor-specific portrait tables from reproducible, merged source snapshots."""

import argparse
import csv
import hashlib
import io
import json
import re
import tempfile
from pathlib import Path
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
EXPORTS = {
    "retail": ("Creature.12.1.5.csv", "CreatureDataRetail.lua"),
    "forever": ("Creature.1.60.1.csv", "CreatureDataForever.lua"),
}
LUA_STRING = r'"(?:\\.|[^"\\])*"'

TRUESHOT_NOTICE = """MIT License

Copyright (c) 2026 chazlander

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE."""

TRUESHOT_URL = ("https://raw.githubusercontent.com/chazlander/TrueshotLodge/"
                "034da7802f6c880562411c14e8e159d04049e7fd/data/")
DEFAULT_SOURCES = {
    "forever": [
        {"name": "TrueshotLodge-034da780", "flavor": "forever", "locale": "enUS",
         "format": "trueshot", "snapshot": "trueshot-forever.json", "notice": TRUESHOT_NOTICE,
         "inputs": {"npcs": TRUESHOT_URL + "NPCs.lua", "looks": TRUESHOT_URL + "Looks.lua"}},
        {"name": "Wago-1.60.1.70888", "flavor": "forever", "locale": "enUS",
         "format": "csv", "snapshot": "wago-forever.json",
         "inputs": {"records": "https://wago.tools/db2/Creature/csv?build=1.60.1.70888"}},
    ],
}


def lua_string(value):
    # Lua 5.1 uses decimal escapes for control characters, not JSON's Unicode escapes.
    return '"' + ''.join(
        '\\' + char if char in '\\"' else
        f'\\{ord(char):03d}' if ord(char) < 32 or ord(char) == 127 else char
        for char in value
    ) + '"'


def positive_int(value):
    if isinstance(value, bool):
        raise ValueError("booleans are not creature/display IDs")
    result = int(str(value))
    if result <= 0:
        raise ValueError(f"expected a positive ID, got {value!r}")
    return result


def record(npc_id, name, displays):
    if not isinstance(name, str) or not name.strip():
        raise ValueError(f"missing name for NPC {npc_id}")
    return {"id": positive_int(npc_id), "name": name,
            "displayIds": list(dict.fromkeys(positive_int(value) for value in displays))}


def parse_csv(text):
    reader = csv.DictReader(io.StringIO(text.lstrip('\ufeff')))
    columns = set(reader.fieldnames or ())
    wago = {"ID", "Name_lang", "DisplayID_0"} <= columns
    if not wago and not {"id", "name", "displayId"} <= columns:
        raise ValueError("CSV requires ID/Name_lang/DisplayID_0 or id/name/displayId")
    rows = []
    for row in reader:
        name = row["Name_lang" if wago else "name"]
        if not name:
            continue
        displays = [row.get(f"DisplayID_{i}") for i in range(4)] if wago else [row["displayId"]]
        rows.append(record(row["ID" if wago else "id"], name,
                           [value for value in displays if value and value != "0"]))
    return rows


def parse_json(text):
    rows = json.loads(text)
    if not isinstance(rows, list):
        raise ValueError("record JSON must be an array")
    return [record(row["id"], row["name"], row.get("displayIds",
                   [row["displayId"]] if row.get("displayId") else [])) for row in rows]


def parse_trueshot(npcs, looks):
    # Read only the published table fields; never execute downloaded Lua.
    names = {int(npc): json.loads(name) for npc, name in re.findall(
        rf'^\s*\[(\d+)\]\s*=\s*\{{\s*name\s*=\s*({LUA_STRING})', npcs, re.M)}
    if len(names) != len(re.findall(r'^\s*\[\d+\]\s*=\s*\{', npcs, re.M)):
        raise ValueError("some TrueshotLodge NPC rows were not recognized")
    displays = {}
    mappings = re.findall(r'\{\s*display\s*=\s*(\d+),[^{}]*npcs\s*=\s*\{([\d,\s]+)\}', looks)
    if len(mappings) != len(re.findall(r'\bdisplay\s*=', looks)):
        raise ValueError("some TrueshotLodge display mappings were not recognized")
    for display, ids in mappings:
        for npc in re.findall(r'\d+', ids):
            displays.setdefault(int(npc), []).append(display)
    if not names or not displays:
        raise ValueError("TrueshotLodge tables not recognized; upstream format may have changed")
    return [record(npc, name, displays.get(npc, [])) for npc, name in names.items()]


def read_input(location, root):
    if location.startswith("https://"):
        request = Request(location, headers={"User-Agent": "CouchMode-creature-parser/1"})
        with urlopen(request, timeout=30) as response:
            data = response.read()
    elif "://" in location:
        raise ValueError("remote sources must use HTTPS")
    else:
        data = (root / location).read_bytes()
    return data.decode("utf-8-sig"), hashlib.sha256(data).hexdigest()


def refresh_source(source, flavor, root):
    inputs, hashes = {}, {}
    for key, location in source["inputs"].items():
        inputs[key], hashes[key] = read_input(location, root)
    kind = source["format"]
    if kind == "trueshot":
        rows = parse_trueshot(inputs["npcs"], inputs["looks"])
    elif kind in ("csv", "json"):
        rows = (parse_csv if kind == "csv" else parse_json)(inputs["records"])
    else:
        raise ValueError(f"unknown source format: {kind}")
    if not rows:
        raise ValueError(f"{source['name']} produced no records")
    return {"flavor": flavor, "locale": source["locale"], "source": source["name"], "inputs": source["inputs"],
            "sha256": hashes, "records": rows}


def merge(sources):
    by_id, conflicts = {}, []
    for source, snapshot in sources:
        for item in snapshot["records"]:
            row = record(item["id"], item["name"], item["displayIds"])
            previous = by_id.get(row["id"])
            # Incomplete discoveries cannot erase a usable portrait. Never join
            # different creatures' display IDs using a shared name.
            if previous and previous["displayIds"] and not row["displayIds"]:
                continue
            if previous and (previous["name"], previous["displayIds"]) != (row["name"], row["displayIds"]):
                conflicts.append({"id": row["id"], "previous": previous, "selected": source["name"]})
            # Move overrides to the end so name priority also follows source order.
            by_id.pop(row["id"], None)
            by_id[row["id"]] = dict(row, source=source["name"])
    by_name, collisions = {}, []
    for row in by_id.values():
        if not row["displayIds"]:
            continue
        old = by_name.get(row["name"])
        if old and old["id"] != row["id"]:
            collisions.append({"name": row["name"], "ids": [old["id"], row["id"]]})
        by_name[row["name"]] = row
    return by_id, by_name, conflicts, collisions


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding="utf-8")


def generate(flavor, args, manifest):
    definitions = manifest.get(flavor)
    root = args.manifest.parent if args.manifest else HERE
    sources, pending = [], []
    if definitions is None:
        csv_name, _ = EXPORTS[flavor]
        text, digest = read_input(str(HERE / csv_name), HERE)
        sources.append(({"name": csv_name}, {"records": parse_csv(text), "sha256": {"records": digest}}))
    else:
        names = set()
        for source in definitions:
            if source["name"] in names:
                raise ValueError(f"duplicate source name: {source['name']}")
            names.add(source["name"])
            if source["flavor"] != flavor or source["locale"] != "enUS":
                raise ValueError(f"{source['name']}: expected {flavor}/enUS source")
            path = args.cache_dir / source["snapshot"]
            if args.refresh or not path.exists():
                snapshot = refresh_source(source, flavor, root)
                pending.append((path, snapshot))
            else:
                snapshot = json.loads(path.read_text(encoding="utf-8"))
            if (snapshot["flavor"] != flavor or snapshot["locale"] != source["locale"]
                    or snapshot["source"] != source["name"]
                    or snapshot["inputs"] != source["inputs"]):
                raise ValueError(f"{source['name']}: snapshot differs from manifest; use --refresh")
            sources.append((source, snapshot))
    by_id, by_name, conflicts, collisions = merge(sources)
    if not by_name:
        raise ValueError(f"refusing to generate an empty {flavor} portrait table")
    lines = ["-- This file is auto-generated by creature_parser.py. Do not edit directly."]
    for source, _ in sources:
        lines.append(f"-- Source: {source['name']}")
        if source.get("notice"):
            lines.extend('-- ' + line if line else '--' for line in source["notice"].splitlines())
    lines.extend(["local _, addon = ...", "addon.BanterData.CreatureByName = {"])
    for name, row in sorted(by_name.items()):
        lines.append(f"    [{lua_string(name)}] = {{ id = {row['id']}, displayId = {row['displayIds'][0]} }},")
    lines.extend(["}", "addon.BanterData.CreatureByID = {"])
    for npc, row in sorted(by_id.items()):
        if row["displayIds"]:
            lines.append(f"    [{npc}] = {{ displayId = {row['displayIds'][0]} }},")
    lines.extend(["}", ""])
    output = args.output_dir / EXPORTS[flavor][1]
    report = {"flavor": flavor, "names": len(by_name), "creatures": len(by_id),
              "portraits": sum(bool(row["displayIds"]) for row in by_id.values()),
              "sources": [{"name": source["name"], "records": len(snapshot["records"]),
                           "sha256": snapshot["sha256"]} for source, snapshot in sources],
              "conflicts": conflicts, "nameCollisions": collisions,
              "records": sorted(by_id.values(), key=lambda row: row["id"])}
    # Fetch and validate every source before writing any snapshots or output.
    for path, snapshot in pending:
        write_json(path, snapshot)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text('\n'.join(lines), encoding="utf-8")
    if args.report_dir:
        write_json(args.report_dir / output.with_suffix('.sources.json').name, report)
    print(f"Generated {output.name}: {len(by_name)} names, {report['portraits']} NPC portraits; "
          f"{len(conflicts)} ID conflicts, {len(collisions)} name collisions")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("flavor", choices=(*EXPORTS, "all"), nargs="?", default="all")
    parser.add_argument("--manifest", type=Path, help="optional external source configuration")
    parser.add_argument("--cache-dir", type=Path, default=Path(tempfile.gettempdir()) / "couchmode-creatures")
    parser.add_argument("--report-dir", type=Path, help="optional directory for provenance reports")
    parser.add_argument("--refresh", action="store_true", help="refresh snapshots from configured inputs")
    parser.add_argument("--output-dir", type=Path, default=HERE)
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8")) if args.manifest else DEFAULT_SOURCES
        for flavor in EXPORTS if args.flavor == "all" else (args.flavor,):
            generate(flavor, args, manifest)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"creature_parser: {error}\n")


if __name__ == "__main__":
    main()
