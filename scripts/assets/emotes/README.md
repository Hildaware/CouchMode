# Emote artwork

The Emotes panel displays 30 icons in three rows of ten. Two approved atlases
are loaded from `Resources/Media/Emotes/`; this directory holds their source
PNGs, cell maps, and built-in imagegen prompts. Discarded artwork variants are
not retained in the repository.

| Atlas | Icons | Source and prompts |
|---|---|---|
| `emote-icons-focused.tga` | Original 14 emotes; final two cells unused | [Focused gestures](focused-icons.md) |
| `emote-icons-extra.tga` | Additional 16 emotes | [Additional gestures](extra-icons.md) |

Each atlas has four columns and four rows, ordered left to right, top to bottom.
The game exports are 1024×1024 uncompressed 32-bit BGRA TGA files with straight
alpha and a top-left origin. `ChatEmotes.lua` selects the atlas and cell for each
emote. Keep that mapping synchronized with the documented cell order.

The existing release workflow and local installer exclude `scripts/`, so source
PNGs and generation notes do not ship with the addon. Both runtime atlases stay
inside `Resources/` and are included in releases.

## Export

From the repository root on macOS:

```sh
swift scripts/export-emote-atlas.swift scripts/assets/emotes/emote-icons-focused-source.png Resources/Media/Emotes/emote-icons-focused.tga
swift scripts/export-emote-atlas.swift scripts/assets/emotes/emote-icons-extra-source.png Resources/Media/Emotes/emote-icons-extra.tga
```

The exporter only resizes and converts the approved artwork. It preserves
transparency and does not redraw icons. Do not edit the runtime TGA files by hand.
