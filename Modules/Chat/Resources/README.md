# Creature portrait data

Build the Forever portrait tables:

```sh
python3 Modules/Chat/Resources/creature_parser.py forever
```

The parser downloads missing inputs into the system temporary directory under
`couchmode-creatures`, outside the addon checkout. Subsequent builds reuse those
snapshots without network access. `--refresh` downloads them again; `--cache-dir`
selects another local build-cache directory. Source snapshots and provenance
reports are not shipped or committed. Only the generated Lua tables are needed
at runtime.

The default sources are configured in `creature_parser.py`: Wago's `Creature`
table for Forever build 1.60.1.70888 and TrueshotLodge at commit
`034da7802f6c880562411c14e8e159d04049e7fd`. Update the pinned versions deliberately
when adopting newer data. TrueshotLodge's required MIT notice is embedded in the
generated Lua, so no separate source/license directory is needed.

## Additional sources

Use `--manifest /path/outside/the/addon/sources.json` to supply a custom source
configuration. Its top-level keys are flavors (`forever` or `retail`), each
containing an array of sources in increasing priority. Each source needs a unique
`name`, matching `flavor`, `locale: "enUS"`, `snapshot` filename (relative to the
cache directory), `format`, and `inputs`. Local input paths are relative to the
manifest; HTTPS URLs also work. Include required attribution in a `notice` string,
which will be embedded in the generated Lua.

Supported formats:

- `csv`: `inputs: {"records": "path-or-url"}`. Accepts Wago columns (`ID`,
  `Name_lang`, `DisplayID_0` through `DisplayID_3`) or simple columns (`id`,
  `name`, `displayId`).
- `json`: the same input shape, with an array of records such as
  `[{"id": 113, "name": "Stonetusk Boar", "displayIds": [193]}]`.
  A single `displayId` field is also accepted.
- `trueshot`: `inputs` contains `npcs` and `looks` Lua files in the upstream
  format. These are parsed without executing downloaded Lua.

After changing configuration, use `--refresh`. Python's standard library is
sufficient. Retail retains the previous external `Creature.12.1.5.csv` input
unless a custom manifest configures retail sources. The `all` command requires
that retail input too. Data from different client flavors is never mixed.

## Merge policy and review

Records merge by NPC ID. Later usable records win; an incomplete record cannot
erase an existing portrait. Different creatures are never joined by matching
their names. The Lua tables expose both `CreatureByName` and `CreatureByID`;
chat prefers the GUID's NPC ID to avoid duplicate-name mismatches. Name-only
lookups use the last usable record. The first display ID is the representative
model; live-unit portraits remain preferable for creatures with multiple looks.

For an optional provenance report, use `--report-dir /tmp/creature-reports`.
This records input hashes, selected sources, conflicts, name collisions, and
records without portraits. `--output-dir /tmp/creature-preview` generates Lua
elsewhere for review. Reports are not written by default. Do not edit generated
Lua or snapshots manually.

The current sources expand companions and hunter beasts, but do not provide
complete coverage of quest givers, guards, vendors, or every talking NPC.
