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
detection and the mock fixtures.

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

For current Blizzard UI implementation details, consult the extracted client
source described in `AGENTS.md`.
