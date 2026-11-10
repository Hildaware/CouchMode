# Focused gesture icons

Created with the built-in imagegen tool by refining a simple generic-character
concept. Exploratory variants were discarded after the focused set was approved.
Each icon now emphasizes the relevant face, hand, head, or leg gesture instead
of always showing the whole body. Palette, outline style, and 4×4 cell ordering
remain consistent with the earlier atlas.

- Source: [emote-icons-focused-source.png](emote-icons-focused-source.png)
- Active game texture: [emote-icons-focused.tga](../../../Resources/Media/Emotes/emote-icons-focused.tga),
  1024×1024 uncompressed 32-bit BGRA with straight alpha.

## Export

```sh
swift scripts/export-emote-atlas.swift scripts/assets/emotes/emote-icons-focused-source.png Resources/Media/Emotes/emote-icons-focused.tga
```

## Reframing prompt

Use case: precise-object-edit.
Edit target: the supplied 4x4 fantasy emote icon atlas.
Keep its simple original icon language: the SAME generic round-headed ivory adventurer, thick dark-brown outlines, very restrained muted gold accents, broad flat shapes, at most one simple shadow. Preserve the exact 4x4 cell arrangement and ordering, transparency, and the last two empty cells.
Change the framing of EACH icon to emphasize ONLY THE PART OF THE BODY PERFORMING THE EMOTE. Do not make all icons full-body mannequins. Each relevant body part should fill its cell generously so it reads at 36-40 pixels. Add minimal face marks wherever facial expression IS the emote: two simple eye curves and a clear mouth shape. Still no hair, beard, race features, ears, nose detail, armor, costume texture, complex anatomy or realistic shading. Facial marks must be bold and extremely simple, not detailed portraits.
Framing and content, left-to-right then top-to-bottom:
Row 1:
1 WAVE: close-up of a single upright open hand and wrist, palm facing viewer, three or four broad rounded finger shapes, one gold waving motion curve. No head or body.
2 THANKS: close-up of two simple hands pressed together in gratitude, only wrists and hands. No face, no torso.
3 CHEER: shoulders, generic head, and BOTH arms raised in a V; crop below upper chest. No waist or legs.
4 LAUGH: a LARGE laughing face only, generic ivory round head tilted back slightly, eyes as two joyful closed curves, broad clearly open laughing mouth. No torso, arms or legs.
Row 2:
5 NOD: close-up of generic head and tiny neck, head tilted down in side-three-quarter view, one short muted-gold downward motion arrow. No body.
6 NO: close-up of the same generic head with a short gold horizontal side-to-side motion arrow. Minimal neutral face marks allowed. No body.
7 APOLOGIZE: close-up of deeply bowed head and shoulders with contrite posture, tiny closed-eye marks, crop at chest, no legs.
8 GOODBYE: close-up of waving hand seen from the back, wrist turned sideways and two gold outward waving strokes; distinct viewpoint from WAVE. No head or body.
Row 3:
9 SALUTE: close-up of head with one simple hand at brow; crop at shoulders. No waist or legs.
10 FLIRT: close-up of face blowing a kiss with one hand near mouth and one small muted-gold heart leaving the hand. No torso.
11 DANCE: focus on a pair of legs and simple feet stepping/dancing, one foot lifted and crossed, one short gold motion stroke. Crop above knees, no torso or head.
12 SILLY: close-up of a goofy generic face, one simple winking eye, the other a tiny dot, tongue sticking out from a simple crooked mouth. No hands or body.
Row 4:
13 JOKE: close-up of generic grinning face and one small EMPTY gold speech bubble, eyebrows slightly raised, not a full-body storyteller. No torso.
14 FACEPALM: close-up of head covered by one hand, head slightly lowered, no torso.
15 and 16 remain completely transparent and empty.
All artwork must be centered within its own equal-size cell, with at least 12% transparent margins on each side. No frames, tile backgrounds, labels, letters, grid lines, or extra icons. Keep the set quiet and cohesive. Use body parts and clear expressions, not detail, to communicate meaning. Preserve genuine transparent alpha.

## Edge cleanup prompt

Use case: background-extraction / precise-object-edit. Clean this existing 4x4 emote icon atlas without redesigning it. Preserve all fourteen icon drawings, cell positions, sizes, expressions, simple dark brown outlines, ivory-and-gold palette and transparent background. Remove ALL stray red, yellow and white speckles, detached pixel debris and smears in the transparent margins around the icons, especially underneath the salute at row 3 column 1 and between that salute and the joke face below it, and underneath the cropped heads and shoulders. Only the clean intended icon silhouettes, gold motion arrows, heart and speech bubble may have visible pixels; everything else must have zero alpha. No added frames, text, shadows, outlines or backgrounds. Do not add details. Keep last two cells empty. Export clean genuinely transparent alpha with crisp antialiased edges.
