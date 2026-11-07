# World of Warcraft UI source

For current Blizzard UI implementation details, use the extracted client source at:

`/Users/bferrari/Documents/BlizzardInterfaceCode/Interface`

Consult it when developing or debugging CouchMode's WoW UI and gamepad integrations.

`Texture:SetDrawLayer` sublevels must be between `-8` and `7`, inclusive. Values outside this range throw an error.

# Testing

We do not write tests for this project.

# Client flavors (retail vs. WoW: Forever)

CouchMode runs on multiple clients. Detect the active one through
`addon.Utils.FLAVOR` (`'retail' | 'forever' | 'classic'`), derived from the
interface version (`12.0.5` -> 120005 retail, `16.0.1` -> 16001 WoW: Forever).

Helpers in `Core/Utils.lua`:

- `addon.Utils.IfFlavor`/`WhenFlavor`/`IsFlavor` — gate code on the client flavor.
- `addon.Utils.EventExists(event)` — whether the client knows an event
  (`C_EventUtils.IsEventValid`, falling back to a `RegisterEvent` probe).
- `addon.Utils.RegisterEventIfValid(frame, event)` — never throws on unknown events.

**Never call `RegisterEvent` with an event that may not exist on all clients** —
it throws a hard error. Events that are not universal are tagged in
`Modules/Chat/Sources.lua` (`FLAVOR_SPECIFIC`), and the chat router filters them
through `Sources.EventsForFlavor(flavor)` plus `Utils.EventExists` before
registering.

# Chat module structure

The chat subsystem lives under `Modules/Chat/`, loaded via `Chat.xml` in a fixed
order. It is **one** AceModule (`addon.Chat`) whose methods are spread across
`Chat*.lua`; the other files are pure helpers or the separate ChatBubbles module.

## Editing rules

- New behavior belongs on the shared module: in a new `Chat*.lua` file write
  `local chat = addon.Chat` then `function chat:Name(...)`. **Never create a
  second AceModule for Chat** — `ChatFeedWidgets`, `Router`, `ChatBubbles` and
  `Core/Options.lua` call `addon.Chat:<method>` directly.
- Include the new file **after** `Chat.lua` in `Chat.xml`: each split file
  captures `addon.Chat` at load time (set in `Chat.lua` when the module is
  created).
- `Chat.lua` ends with `chat:Enable()`. This is safe because AceAddon defers
  `OnEnable` until `ADDON_LOADED` (the module is still queued for
  initialization), so every method defined in later files exists when `OnEnable`
  runs. Do not reorder `Chat.lua` after the files it enables against.
- Each file defines its own file-local `db()` accessor; don't add a shared one.
- Resolve fonts with `addon.Media.ResolveFont(face)` (`Core/Media.lua`). Do not
  re-implement `fetchFont` or the Bebas Neue fallback.
- Shared panel geometry defaults live on the module: `chat.DEFAULT_WIDTH`,
  `chat.DEFAULT_HEIGHT`.
- Per-file state is initialized at file scope by the file that owns it (all
  split files load before `OnEnable`), so add new state to its owning file.

## Chat module files (methods on `addon.Chat`)

| File | Responsibility |
|---|---|
| `Chat.lua` | Bootstrap: creates `Chat`, sets `addon.Chat`, shared defaults, `db()`, lifecycle (`OnInitialize`/`OnEnable`/`OnDisable`/`OnLogout`/`OnPlayerEnteringWorld`), `IsSubscriberEnabled`, `RegisterValidEvent`; ends with `chat:Enable()`. |
| `ChatSuppression.lua` | Hides/restores Blizzard chat frames (`SuppressBlizzard`/`ApplyBlizzardSuppression`/`RestoreBlizzard`/`InstallSuppressionHooks`). |
| `ChatReveal.lua` | Character-by-character `Reveal`, header `FadeInText`, and `SetTextPlain`/`CancelReveal`/`CancelTextFade`. Called by the feed widgets. |
| `ChatStyle.lua` | Feed styling callbacks: `GroupShowsIdentity`, `StyleIdentity` (name/channel/portrait/badge), `StyleLine`, `RefreshVisibleIcons`. |
| `ChatIdentity.lua` | `ResolveUnit`/`ResolveIdentity`/`BuildGuildRoster`/`ResolveGuild`, `Enrich`, and the throttled inspect pipeline (`EnqueueInspect`/`ProcessInspectQueue`/`OnInspectReady`). Owns `identByGuid`/`unitByGuid`/`guildByName`/`inspectQueue`. |
| `ChatSession.lua` | Accepted-message session and presentation queue: `ChatMessage` (router entry), `ProcessChatMessage`, `ScheduleMessageQueue` and pacing, `Recompute`, `ClearSession`, `ScrollToBottom`. Owns `session`/`groups`/`messageQueue*`. |
| `ChatPanel.lua` | Panel + filter bar + input strip construction, `ApplyLayout`, opacity, `FontMetrics`, the fade pump (`UpdateFade`), filters (`SetFilter`/`CycleFilter`) and controls (`Toggle`/`FocusInput`/`ClosePanel`/`ScrollUp`/`ScrollDown`). Owns panel geometry constants and `panel`/`feed`/`filterBtns`/fade state. |
| `ChatModeration.lua` | `BlockName`/`BlockGuild`, `ShowCopyDialog`, `ShowGroupMenu` (the feed's right-click menu). |
| `ChatOptions.lua` | `GetDefaults` and the AceConfig panel (`BuildArgs`/`GetOptions`/`RebuildOptions`, `NotifyChange`, dynamic blocked/alias lists). |
| `ChatCommands.lua` | `/cm chat …` (`HandleCommand`), the mock runner (`RunMock`), `Notify`, and the `CouchMode_Chat*` key-binding globals. |

## Support files (pure helpers / separate systems)

| File | Responsibility |
|---|---|
| `Sources.lua` | Dependency-light: `CHAT_MSG_*` → category maps, `FLAVOR_SPECIFIC`, fixed filters, `Normalize`, secret-value helpers. Loadable by a plain Lua harness. |
| `Grouping.lua` | Pure grouping policy for consecutive messages (`ShouldGroup`, `Build`). |
| `Rules.lua` | Pure moderation matching plus add/remove rules, and `ResolveAlias`. |
| `Router.lua` | The single `CHAT_MSG_*` registration point: normalizes, dedupes by `lineID`, applies `blockCheck`, dispatches to subscribers (`module:ChatMessage`) and the NPC overlay handler. |
| `Migration.lua` | Idempotent profile migrations (`ChatMigration.Run`, bumps `schemaVersion`). |
| `Mock.lua` | Representative chat scenarios fired through the real router for `/cm chat mock`. |
| `ChatInput.lua` | Embeds Blizzard's `ChatFrame1EditBox` into the panel and restores it on disable. |
| `ChatFeed.lua` | Pooled, variable-height scrolling feed engine (`ChatFeedProto.New`). |
| `ChatFeedWidgets.lua` | Anatomy of one group; calls back into `addon.Chat` for styling and reveal. |
| `ChatFeedLayout.lua` | Pure layout policy for measured groups. |
| `ChatBubbles.lua` | Separate `ChatBubbles` AceModule: overhead NPC bubble replacement; registers as the router's bubble handler. |
| `ChatBubblesContainer.lua` | Visual bubble widgets for the ChatBubbles module. |

## Cross-file interfaces (keep stable)

Methods on `addon.Chat` called from outside its source files:

- `ChatFeedWidgets`: `GroupShowsIdentity`, `StyleIdentity`, `StyleLine`,
  `CancelReveal`, `SetTextPlain`, `Reveal`, `FadeInText`, `CancelTextFade`,
  `ShowGroupMenu`.
- `Router`: `ChatMessage`, `IsSubscriberEnabled`.
- `ChatBubbles` / `Core/Options.lua`: `Toggle`, `GetDefaults`, `GetOptions`,
  `RebuildOptions`, `HandleCommand`.

# Current Issues (WoW: Forever native Gamepad UI)

Native Gamepad UI can still reach protected Blizzard functions such as
`SetPreferredGamepadInteractTarget()` from tainted menu, chat, or panel flows
after launch. The final protected call is not necessarily where taint began.
Some triggers can be avoided within CouchMode; a general client fix is not
confirmed.

On Forever, the minimap toolbar keeps Blizzard's native Tracking, Addons, and
Calendar buttons as the actual click targets. Preserve their native mouse
handlers and dropdown menu anchors rather than forwarding clicks through addon
Lua. Validate changes in the client with Gamepad UI enabled, including opening
menus, selecting entries, dismissing them by clicking outside, and switching
between minimap and world-map toolbars. Lua syntax checks cannot establish that
a protected-action error is fixed.

The native bag footer on Forever must remain display-only. A detailed taint log
showed addon-created footer binding groups writing to Blizzard's shared
`InputBindingManager.activeBindings` during opening; restoring native controls
on close then read those tainted entries. Keep A/B on SmartNavigation and X/Y
on the bag view's separate override-binding owner. Clear those overrides on
focus loss and through the secure combat state driver. Wrapping footer
activation/deactivation in `securecallfunction` does not isolate tainted binding
records stored in the shared stack.
