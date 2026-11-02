# Skeleton animation packs

The Footsoldier and Acolyte use authored idle, walk and attack clips in all eight directions. Each pack contains 24 clips and 224 lossless RGBA PNGs. Original rotation art, catalog mappings, display height, feet anchors, collision, monster stats, drops and spell projectile behavior are preserved.

Idle plays eight frames at 4 FPS, walking eight at 9 FPS, and attacks twelve at 10 FPS once per trigger. Frame canvases add symmetric transparent padding without increasing the original body scale. Exact source PNG hashes, provider job IDs, original references and any whole-frame selections are recorded in `art_sources/skeleton-*-animations/manifest.json` and the runtime pack provenance. Sources are unchanged; sequence curation removes documented generated slash-effect frames and may hold a clean pose.

## Artwork decisions and status

- Acolyte: the complete eight-direction set, staff-led casting and dark purple fiery mana were explicitly approved on 2026-11-01. The original staff grip in each view remains continuous; the originals use the right hand in NE/SW and the left in other views.
- Footsoldier: the complete eight-direction idle/walk/overhead-cut set and original-palette edge smoothing were explicitly approved on 2026-11-01.
- Knight and Captain: original rotations remain in use. Their animation candidates are still under review and are not installed as finished packs. Boneshard and Sniper do not have mapped source artwork in this pass.
- Face redraw candidates were rejected. They are not installed. The four existing skeleton skins use only the approved neighboring-color edge smoothing, retaining original faces and palettes. Player and goblins retain their existing rendering.

`CharacterSpriteLibrary` overlays the two fixed animation packs without rewriting the original catalog. `ActorSprite` shares the skeleton-only material in `shaders/skeleton_edge_refinement.tres`. Its shader applies Scale2x corner rules by choosing existing neighboring texture colors; it does not blur, interpolate a palette or rescale the actor. The material is cleared when an actor changes to another skin.

The Acolyte's mana is a separate PixelLab VFX sheet with crisp sampling and no mipmaps. `skeleton_staff_mana.gd` synchronizes its atlas frame and authored staff-tip anchor to the current cast pose. It disappears outside the cast, on interruption, death and completion; changing skin removes it. No combat or projectile logic is owned by this decorative visual. Its exact recipe, source export, palette, atlas offset and source-attack hashes are in `art_sources/skeleton-acolyte-staff-mana/manifest.json` and `data/skeleton_acolyte_staff_mana.json`.

## Validation

Run with Godot 4.5.1, using isolated user data for testing:

```text
--headless --path godot_client --script res://scripts/dev_tools/skeleton_animation_smoke.gd -- --skin=skeleton_footsoldier --skin=skeleton_acolyte
--headless --path godot_client --script res://scripts/dev_tools/skeleton_edge_style_smoke.gd
--headless --path godot_client --script res://scripts/dev_tools/skeleton_staff_mana_smoke.gd
```

The skeleton smoke checks original source rotations, base-catalog preservation, native texture pixels/imports, actual natural animation cycles and one-shot completion/cancel/restart, plus existing EastOutskirts public spawn/motion/combat and the separate Acolyte projectile. Its default intentionally requires all four planned skeleton packs; select installed skins as above while Knight/Captain remain pending.

For visual review, omit `--headless`, use `--max-fps 60` and add `--capture-dir=<absolute-directory>` after `--`. It records normal and actual 4x Godot renders with the player, two natural idle/walk cycles and each facing's full attack. Rendering checks, source review, installation and user approval are separate statuses. Generated evidence and machine-specific logs stay outside Git.
