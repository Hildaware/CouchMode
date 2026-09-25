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
- **Toasts** — a standalone, session-scoped feed. It shows item
  acquisitions (icon, name and carried count, tinted by rarity), money gains,
  currency gains, reputation increases and system messages as bottom-anchored, auto-fading rows
  with mouse-wheel scrolling, history browsing and a return-to-bottom button.
  System messages use a distinct color and wrap across multiple lines. Recognized
  lines are removed from Blizzard chat while the matching category is enabled;
  group loot, losses and unsupported-client reward lines stay in native chat.
  Placed and scaled independently through Edit Mode.
- **Bags**, **CastBar**, **Nameplates**, **Map**, **Tips**, **Player Bars** — see
  the in-game options under *Options → AddOns → Couch Mode*.

Chat and Chat Bubbles share a single message router (`Modules/Chat/Router.lua`)
so WoW chat events are normalized and dispatched once, deduplicated by line ID.

## Development

Syntax-check every Lua file:

```sh
rg --files -g '*.lua' | xargs luac -p
```

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

`Modules/Toasts/Mock.lua` fires representative rewards and system messages:

```
/cm toasts items             -- a few item rewards
/cm toasts mock              -- every category
/cm toasts mock system       -- system messages
/cm toasts sets              -- list the available sets
/cm toasts clear             -- wipe the current login's history
```

Sets: `item`, `money`, `currency`, `reputation`, `system`, plus `all`. There is
also a **Test Rewards** button under *Options → AddOns → Couch Mode → Toasts*.

Chat currently keeps its own System category. Its removal from the Chat feed is
reserved for the separate Chat module change.

For current Blizzard UI implementation details, consult the extracted client
source described in `AGENTS.md`.
