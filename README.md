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

## Configuration

Open `/cm` for module settings. General contains enable and behavior controls;
Layout contains dimensions, scale, and anchoring; Appearance contains fonts,
colors, and opacity. Modules with sample displays have a Preview section.
Source filters, moderation, and other module-specific controls keep their own groups.

Use **Edit Layout** to open Edit Mode, then select the component to move or resize
it. Geometry controls in `/cm` and Edit Mode share the same values and ranges;
enable a component before adjusting its geometry. **More Settings** on its Edit
Mode panel opens the corresponding `/cm` page. This leaves Edit Mode open so
unsaved Blizzard layout changes are preserved.

Positions follow the active Edit Mode layout. Dimensions and appearance are
shared across layouts within the current CouchMode profile. Chat Bubbles follow
NPCs, so their offsets and scale live in `/cm` alongside **Preview NPC Bubble**.

## Chat composer

Assign **CouchMode → Chat Composer** in Key Bindings, or open it from
**Chat → Quick Replies** in CouchMode settings. **Chat History** remains a
separate binding. The composer offers QWERTY typing, editable quick replies,
an emote wheel, and a channel/whisper picker. ConsolePort is optional.

| Controller input | Action |
|---|---|
| Left stick / D-pad | Select keys or phrases; choose emotes |
| A / Cross | Type or confirm; perform selected emote |
| B / Circle | Back / close and keep draft |
| X / Square | Backspace (hold to repeat) |
| Y / Triangle | Space |
| LB / RB | Switch tabs |
| Left trigger | Hold Shift |
| Right trigger | Send from Keyboard or Quick Replies |
| Right stick left/right | Move caret |
| Left-stick click | Choose channel / whisper destination |

Quick replies insert text for review before sending. Edit and reorder phrases
in Chat settings. Emotes perform once and close the composer; unfinished drafts
are kept for the current session. Physical typing and clickable keys also work.
Closing returns controller input after held buttons and sticks are released.

The input frames are configured outside combat and reused during combat. After
logging in or reloading during combat, initial setup waits for combat to end.
Combat behavior and native Gamepad UI taint still require validation in WoW.

### In-client verification

- Check Retail with ConsolePort and Forever with native Gamepad UI, both with
  and without ConsolePort. Confirm only one virtual keyboard appears, and that
  ConsolePort still handles unrelated text fields.
- Type, edit, send, cancel, and reopen drafts. Check physical typing, UTF-8 text,
  item links, autocomplete, slash commands, group channels, and whispers.
- Add, edit, reorder, and delete replies; verify an empty list stays empty after
  reload and that profile changes close the composer and discard its old draft.
- Perform each emote with and without a target. Check D-pad and stick selection,
  one action per press, and preservation of an unfinished message.
- Open, type, send, and close during combat; enter and leave combat while open.
  Hold controls across dismissal, move focus elsewhere, and disconnect the
  controller. Check for input leaks, stuck controls, and protected-action errors.
- After closing, exercise native menus, bags, minimap/world-map toolbars, and
  outside-click dismissal. Check composer fit and readability at 720p/1080p and
  different UI scales; time short messages to tune navigation comfort.

## TODO

### Chat Bubbles
- Sizing

### Map
- There's a new gamepad map scroll thing added to Forever. Once it's out of alpha we should adopt it for the gamepad map scroll.

### Frames (Party)
- The blizzard castbar has dope 'fill' and spark. We should replicate it.
