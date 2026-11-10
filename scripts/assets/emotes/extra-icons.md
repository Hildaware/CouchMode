# Additional emote icons

Sixteen original companion icons generated with the built-in imagegen tool,
matching the approved focused-gesture atlas. Together the two sheets provide
all 30 slots in a three-row, ten-column Emotes panel.

- [Source PNG](emote-icons-extra-source.png)
- [Game texture](../../../Resources/Media/Emotes/emote-icons-extra.tga): 1024×1024 uncompressed 32-bit BGRA TGA.
- The original 14 icons remain in [emote-icons-focused.tga](../../../Resources/Media/Emotes/emote-icons-focused.tga).

## Cell order

The companion sheet uses four columns and four rows:

1. Bow, Clap, Hug, Kiss
2. Shrug, Cry, ROFL, Point
3. Flex, Chicken, Sleep, Sit
4. Kneel, Shy, Congratulations, Train

Commands were checked against Blizzard's extracted `ChatEmoteConstants.lua`.
This is a curated set of familiar social gestures, not a measured popularity
ranking. The [community favorites discussion](https://us.forums.blizzard.com/en/wow/t/favemost-used-emote/685455)
provided examples of commonly used social emotes.

## Export

```sh
swift scripts/export-emote-atlas.swift scripts/assets/emotes/emote-icons-extra-source.png Resources/Media/Emotes/emote-icons-extra.tga
```

## Generation prompt

Use case: stylized-concept.
Asset type: one companion 4x4 emote icon atlas. Use the supplied reference ONLY to match its existing simple ivory-and-gold generic-character icon family; do not repeat any of its gestures. Generate 16 NEW emote icons in an EXACT evenly spaced 4-column, 4-row square sheet. All sixteen cells occupied. Transparent background, no frames, text, labels, tile backplates or grid.
Style invariants: original generic round ivory head, dark brown bold outline, warm ivory broad flat shapes, sparse muted gold accents, no hair, beard, gender, race features, armor, fabric detail, or realistic shading. Tiny simple eyes and mouth when expressions are meaningful. Hands are rounded simplified mitten forms; fingers only if essential. At most one broad shadow plane. Each cell shows ONLY the body part carrying the emote, not always a whole character. Same line weight and same optical scale as the reference. Every icon must be extremely readable at 32-36 pixels.
Every icon stays in the central 74% of its own equal-size cell, with generous clean transparent gutters. No red/yellow/white stray pixels, decorative flecks, speckles or debris outside the actual icon silhouette and its intentional small gold motion cue.
Exact order left to right, top to bottom:
ROW 1:
1 BOW: generic head and shoulders bowing deeply, three-quarter side view, hands together below head, crop at chest. Readable respectful bow.
2 CLAP: close-up of TWO rounded hands clapping palm-to-palm at an angle, tiny gold impact marks, no head or body.
3 HUG: close-up of TWO generic round heads side by side with simple arms embracing around both shoulders, no legs. Clearly two people hugging.
4 KISS: close-up of generic face puckering lips and blowing ONE tiny gold heart, simple expression, no hands or body.
ROW 2:
5 SHRUG: close-up of generic face and shoulders, both hands turned palms-up beside head, eyebrows raised, no legs.
6 CRY: close-up of sad generic face, closed downward eyes and two big tear shapes, clear downturned mouth. Restrained ivory/dark brown/gold palette.
7 ROFL: generic head tipped sideways with laughing closed eyes and wide open mouth, ONE small gold circular rolling motion arrow around side of head, no full body.
8 POINT: close-up of a simple hand pointing to the right, ONE clearly extended index finger, no head or body.
ROW 3:
9 FLEX: close-up of a single bent arm with rounded flexed bicep and mitten fist, no face or body.
10 CHICKEN: generic head with both arms bent like flapping chicken wings at shoulders; tiny gold flapping marks, no costume, no bird head, no legs.
11 SLEEP: generic face resting sideways on one mitten hand, eyes peacefully closed, NO letters or Z symbols, no full body.
12 SIT: simple lower torso, hips and bent legs resting in a seated position, crop above waist. No head, no chair prop.
ROW 4:
13 KNEEL: simple lower torso and legs with ONE knee on ground and other knee bent upright, side profile, crop above waist, no head.
14 SHY: close-up of a generic head tilted down and sideways, simple downcast eyes, one mitten hand near cheek, small muted-gold cheek marks.
15 CONGRATULATIONS: close-up of two simple hands clasped in a congratulatory handshake, tiny gold sparkle, no heads or bodies.
16 TRAIN: generic upper body with mitten fist raised pulling an imaginary train whistle cord; a small simple gold steam puff beside the fist, no literal train, no detailed costume or background.
Prioritize the gesture and expressive body part. All sixteen original icon designs must look like members of the reference family. Clean genuine transparency, consistent uniform 4x4 cells, sparse silhouette design.

## Transparency cleanup prompt

Use case: background-extraction. Edit the supplied emote sprite sheet. Keep ALL SIXTEEN ICON DRAWINGS, exact cell ordering, 4x4 grid positions, sizes, ivory fill, dark brown outlines and gold gesture marks unchanged. Remove the entire cloudy gray/beige background and every drop shadow and glow. Everything between the icons and outside their crisp intended silhouettes must be FULLY TRANSPARENT with alpha exactly zero, including every outer edge and corner and every gap. Retain full opacity inside the ivory figures. Only thin antialiasing on actual icon edges may be partially transparent. No semi-transparent wash, no checkerboard image, no opaque canvas, no shadow haze. Do not redraw, reinterpret or move the icons. Deliver the isolated existing sixteen pictograms as a clean true-alpha sprite sheet.
