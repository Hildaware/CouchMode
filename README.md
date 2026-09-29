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
- **Toasts** — a standalone live feed. It shows item
  acquisitions (icon, name and carried count, tinted by rarity), money gains,
  currency gains, reputation increases and system messages as bottom-anchored,
  auto-fading rows with a weighted countdown. The active-row limit defaults to
  15; additional rewards wait in order until a slot opens.
  System messages use a distinct color and wrap across multiple lines. Recognized
  lines are removed from Blizzard chat while the matching category is enabled;
  group loot, losses and unsupported-client reward lines stay in native chat.
  Placed independently through Edit Mode.
- **Bags**, **CastBar**, **Nameplates**, **Map**, **Tips**, **Player Bars** — see
  the in-game options under *Options → AddOns → Couch Mode*.

Chat and Chat Bubbles share a single message router (`Modules/Chat/Router.lua`)
so WoW chat events are normalized and dispatched once, deduplicated by line ID.

## TODO

### Chat

### Map
- There's a new gamepad map scroll thing added to Forever. Once it's out of alpha we should adopt it for the gamepad map scroll.
