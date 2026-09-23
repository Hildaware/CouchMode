# CouchMode

Utilities that make World of Warcraft feel more like a console experience.

## Modules

- **Chat** — a full chat replacement built for controllers and couches:
  scrollback, grouped speaker headers, identity icons (portrait/race/class plus a
  specialization badge), fixed filters (All / NPC / Whispers / Group / Guild /
  Public / System), local player & guild blocking, cosmetic channel aliases and
  auto-fade. The channel, name and message fields each have their own font and
  size, message text reveals character-by-character while the channel and name
  labels fade in (the same effect as Chat Bubbles), an ornamental divider can be
  drawn between messages, and the whole panel can be
  tuned to taste. It
  reuses Blizzard's own chat edit box, so slash commands, sticky
  channels, whispers, autocomplete, history, item links, tooltips and player
  menus behave exactly as before. Disabling Chat restores Blizzard chat exactly.
- **Chat Bubbles** — reskins NPC overhead speech bubbles with portraits and a
  reveal animation. NPC lines that cannot be replaced overhead are routed into
  Chat. Chat and Chat Bubbles can be enabled independently.
- **Loot** — a standalone, session-scoped reward feed. It shows item
  acquisitions (icon, name and carried count, tinted by rarity), money gains,
  currency gains and reputation increases as bottom-anchored, auto-fading rows
  with mouse-wheel scrolling, history browsing and a return-to-bottom button.
  Recognized reward lines are removed from Blizzard chat only while the matching
  reward category is enabled; group loot, losses and unsupported-client lines
  stay in native chat. Placed and scaled independently through Edit Mode.
- **Bags**, **CastBar**, **Nameplates**, **Map**, **Tips**, **Player Bars** — see
  the in-game options under *Options → AddOns → Couch Mode*.

Chat and Chat Bubbles share a single message router (`Modules/Chat/Router.lua`)
so WoW chat events are normalized and dispatched once, deduplicated by line ID.

## Development

Syntax-check every Lua file and run the pure test suite:

```sh
scripts/run-tests.sh
```

The tests cover source normalization, category mapping, grouping, local
moderation rules, router dedup/routing, the profile migration, client-flavor
detection, loot recognition/normalization/enrichment and the mock fixtures.

### In-game mock messages

`Modules/Chat/Mock.lua` fires representative chat events through the real router
so normalization, grouping, filters and identity all behave as in live chat:

```
/cm chat mock          -- every source set
/cm chat mock npc      -- a single set
/cm chat sets          -- list the available sets
/cm chat clear         -- wipe the current login's history
```

Sets: `npc`, `whisper`, `group`, `guild`, `public`, `system`, `rich` (links,
emotes and long wrapping text), plus `all`. There is also a **Test Messages**
button under *Options → AddOns → Couch Mode → Chat*.

`Modules/Loot/Mock.lua` fires representative rewards for every Loot category:

```
/cm loot items             -- a few item rewards
/cm loot mock              -- every reward category
/cm loot mock item         -- a single set
/cm loot sets              -- list the available sets
/cm loot clear             -- wipe the current login's history
```

Sets: `item`, `money`, `currency`, `reputation`, plus `all`. There is also a
**Test Rewards** button under *Options → AddOns → Couch Mode → Loot*.

For current Blizzard UI implementation details, consult the extracted client
source described in `AGENTS.md`.
