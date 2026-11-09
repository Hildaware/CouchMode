---
name: ui-best-practices
description: GUI creation best practices for LUA
disable-model-invocation: false
---

---
name: wow-ui-lua
description: Implement or review World of Warcraft UI code in Blizzard's FrameXML and AddOns tree, especially Lua frames, mixins, events, game APIs, and secure UI behavior.
metadata:
  short-description: WoW UI Lua conventions
---

# WoW UI Lua

Use this skill when changing Lua in this checkout or code that follows its Blizzard UI conventions. Treat this source tree as the primary reference: conventions and available APIs vary by game flavor and client version. Prefer a nearby, current implementation with the same responsibility over generic addon examples.

## Find the right local pattern

- Check the addon's `.toc` first. It declares load order, dependencies, load-on-demand behavior, and flavor-specific files using tokens such as `[Game]`, `[Family]`, and `[AllowLoadGameType]`. A symbol used by a file must be loaded earlier or come from a declared dependency.
- Follow the local split among `Shared`, `Mainline`, `Classic`, `Camelot`, and other flavor directories. Do not copy a Mainline-only API into shared code without checking its availability in each target flavor. Keep a shared implementation shared only when behavior and APIs really match.
- Search `Blizzard_APIDocumentationGenerated/*Documentation.lua` for the current function, event, enum, and structure contract. Search actual call sites for usage and timing. Older call patterns elsewhere may be deprecated; look for transition guides under `Blizzard_Deprecated` when an API family has recently changed.
- Prefer `C_*` namespaces and structured return values where the current API exposes them. Many older global functions remain in use, so follow the API that exists for the target flavor rather than mechanically renaming calls. Check return values and optional data before indexing or displaying them.

## Lua organization and objects

- Keep file-only helpers and constants `local`. Use named mixin tables for behavior shared by XML templates or multiple frame instances; use `CreateFromMixins` when composing existing behaviors. Frame methods normally use `function SomeMixin:Method(...)` and access the frame as `self`.
- Put initialization in `OnLoad` or the established template initializer, and split state updates into named methods such as `Refresh`, `Update`, or `Set...`. Reuse base mixin methods explicitly when extending a mixin; inspect whether the inherited lifecycle method needs to run first.
- Prefer data-driven tables and small helpers for repeated UI choices. Keep persistent SavedVariables separate from live frame state, initialize missing or malformed saved data to safe defaults, and save only values that should survive reloads.
- Match the surrounding file's conventions. This tree commonly uses tabs, semicolons, uppercase constants, and local helper functions, but older modules vary.

## Build UI with existing frame infrastructure

- Reuse existing frame templates, mixins, layout helpers, texture atlases, and widgets before creating new controls. Most substantial UI is declared in XML templates and driven by Lua mixins; Lua should own behavior and changing state, while XML owns stable hierarchy, named child references, anchors, layers, and scripts when that matches the surrounding addon.
- When adding a template, give it a clear reusable name and attach its mixin and lifecycle scripts consistently. Use `parentKey` for child references where practical. Keep anchoring relative to frames and layout containers instead of hard-coded screen coordinates; account for scale, resizing, and the UI's other input modes.
- In Lua, create frames with `CreateFrame` only when runtime creation is needed. Supply an existing template when available. For repeated or transient controls, use `CreateFramePool`/`CreateFramePoolCollection`, acquire and release frames, and reset all instance-specific state before reuse.
- Use `ScrollBox` views and `ScrollUtil` helpers for large or recycled lists. Element initializers must fully set each row's visible state, because pooled rows are reused. For non-list visual collections, follow the owning subsystem's layout/pool conventions.
- Use `SetShown` for state-driven visibility; update textures, text, checked/enabled state, highlights, and anchors as a coherent refresh so stale pooled or previously displayed state does not leak through. Prefer atlases and shared color/util helpers when the UI already uses them.
- Prefer anchors to express relationships between controls. Anchor to the owning frame or a meaningful sibling, with offsets for small visual insets; avoid screen-coordinate placement when the element should move with its parent. For a fixed-size control, combine an anchor with `SetSize`/`SetWidth`/`SetHeight`; use opposing anchors to stretch a region across the space between them, or `SetAllPoints` when it should exactly cover another region.
- `SetPoint` adds an anchor constraint. When changing an existing layout, call `ClearAllPoints()` first, then install the complete new set of points; do not clear between points that jointly define a stretched rectangle. For conditional layouts, clear and rebuild every branch so old constraints cannot remain. Keep one obvious owner for dynamic anchoring, and mark XML anchors as script-managed when Lua takes over, as in `Blizzard_DamageMeter/DamageMeterEntry.xml` and its style setup.
- Use the frame's own point and the relative frame's point deliberately (`TOPLEFT` to `BOTTOMLEFT`, for example), then apply only the needed offsets. Positive X moves right and positive Y moves up in frame coordinates. Anchor to named child regions through `parentKey`/`relativeKey` where possible rather than repeating global frame names.
- Localize visible strings with the established global string constants and format helpers. Do not hard-code player-facing English text when a localization token exists.
- Register only the scripts/events the object needs. Prefer named mixin methods or `GenerateClosure` for callbacks that need instance context; clear temporary `OnUpdate` scripts when their work ends. Use a timer or event for infrequent work instead of polling every frame.

## Render order: draw layers, strata, and frame levels

- Keep the three ordering systems distinct. A frame's strata places it among broad screen layers; frame level orders frames within a strata; a texture or font string's draw layer and sublevel order regions within their frame. Fix the ordering system that owns the overlap instead of raising all three.
- For regions in one frame, use the established draw layers (`BACKGROUND`, `BORDER`, `ARTWORK`, `OVERLAY`, `HIGHLIGHT`) to describe semantic roles. Use texture sublevels to order regions within a layer; keep them close to zero and assign explicit sublevels only when same-layer overlap needs control. XML expresses these with `<Layer level="..." textureSubLevel="...">`; Lua can use `SetDrawLayer(layer, sublevel)`. See `Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml` for an icon/background/art/overlay stack.
- A child frame normally draws above its parent, while parent regions can still layer around child frames according to the UI render rules. If a texture is hidden behind a child frame, changing its draw layer may not solve it; place it in the appropriate frame or adjust the child frame's level. Use `useParentLevel` when an overlay such as a cooldown should share its parent's frame level and not cover sibling frames just because it is a child.
- Keep frames on their inherited/default strata unless they must cross another UI window's layer. Set a higher strata only for a clear interaction reason such as a dialog or tooltip. Raising strata can make a frame cover unrelated UI and can affect input, so do not use it as a cosmetic fix.
- Avoid arbitrary large frame levels. Prefer template structure and natural parent/child ordering; when siblings need a deliberate order, use a small, documented relative offset from the relevant frame (for example, `parent:GetFrameLevel() + 1`). Keep level assignments consistent with `fixedFrameLevel`/`useParentLevel` conventions already on the template. A level change can alter the ordering of every child and may be protected in current clients, so make it during safe initialization and check secure/combat restrictions.
- Check mouse interaction as well as appearance. A visually transparent overlay frame with mouse enabled can intercept clicks; disable mouse on decorative frames and textures unless they need input. After changing order, verify tooltips, dropdowns, popups, highlights, and click targets, not only the static screenshot.

## Events and game API calls

- Treat game state as event-driven. Register the narrow event set needed by the frame, handle it in `OnEvent` or an `EventRegistry` callback, and unregister one-shot or visibility-scoped events when finished. Use `RegisterUnitEvent` when only one unit token matters. Gate expensive refreshes to the events that invalidate their data.
- Do not assume event payloads or API data are ready at frame creation. Use the correct lifecycle event (`ADDON_LOADED`, `VARIABLES_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, or a feature-specific update event) for the state in question. Unregister bootstrap events after initialization when appropriate.
- Read signatures and restrictions in generated API documentation before calling an unfamiliar API. Check whether an operation is protected, combat-restricted, asynchronous, or gated by player state; do not infer safety from a call site's UI context.
- Handle unavailable or delayed item/spell/collection data deliberately. Use continuable objects such as `Item:CreateFromItemID(...):ContinueOnItemLoad(...)` when the API documents async loading, and refresh the relevant widget after completion. Show an intentional placeholder when data is still missing.
- Cache API results only when repeated calls or server-mirror timing make it necessary. Give caches a clear invalidation source or expiry and avoid letting stale cached state overwrite newer game state.
- Prefer typed enums/constants over unexplained numeric literals, and preserve documented return ordering when APIs still return tuples. Use named info tables when provided.

## Secure frames and combat

- Identify secure/protected templates and restricted operations before modifying action buttons, unit frames, or other combat-sensitive UI. Secure attributes and protected frame structure often must be configured out of combat; changing them during combat can fail or taint the UI.
- For a restricted update, either arrange the configuration before combat or record the pending desired state and apply it on `PLAYER_REGEN_ENABLED`. Keep protected mutations out of generic refresh methods that may run during combat.
- Use secure templates and handlers for actions that need secure execution. Do not replace secure behavior with insecure click scripts, hook protected functions to alter their behavior, or assume `hooksecurefunc` grants permission to mutate the hooked operation. Follow existing secure utility/handler patterns.
- Preserve existing action button attributes, click registration, parent state, and secure snippets when extending these systems. Verify all combat entry and exit paths and the behavior when a requested update arrives during combat.

## Review and validation

- Trace the full path from template or frame creation through event registration, API data acquisition, refresh, hide/reuse, and teardown. Check for duplicate registrations, stale pooled state, missing nil handling, and callbacks firing after the frame is no longer relevant.
- For flavor-sensitive edits, inspect each affected flavor's `.toc` and matching source implementation. For API-sensitive edits, compare the generated documentation with a current call site.
- Run the repository's available lint/build/check commands when the checkout provides them. When the full game client is required to validate protected behavior or rendering, state that limitation and give the in-client scenario that should be exercised.

Useful reference files in this checkout include `Blizzard_MapCanvas/Blizzard_MapCanvas.lua` for mixins, events, and data providers; `Blizzard_Collections/Mainline/Blizzard_MountCollection.lua` for pooled ScrollBox rows and async item data; `Blizzard_ActionBar/Shared/ActionButton.lua` and `Blizzard_ActionBar/Shared/ActionBar.lua` for secure attributes and combat-aware behavior; `Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml` for region draw layers; `Blizzard_DamageMeter/DamageMeterEntry.xml` and `Blizzard_DamageMeter/DamageMeterEntry.lua` for layout-owned dynamic anchors; `Blizzard_SettingsDefinitions_Frame/ActionBars.lua` for settings registration; and `Blizzard_Collections/Blizzard_Collections.toc` for flavor-aware loading.
