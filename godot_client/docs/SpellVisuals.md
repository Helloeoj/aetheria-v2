# Installed spell visuals

The November 2, 2026 integration installs the 27 reviewed spell designs in the active game. Crashing Tide is displayed as **Ice Spear** and Falling Monolith as **Upheaval**; their stable IDs and every other gameplay field are unchanged.

`Assets/Effects/Spells/manifest.json` describes native lossless cast, projectile and impact clips. The compact object sprites have eight directional views; Mending Light retains the reference size. Projectile size is already baked into the PNGs: runtime draws at native scale 1. Original cast and impact PNGs retain their bytes and dimensions. Nearest texture filtering and lossless, non-mipmapped imports preserve crisp pixels at 4×.

`spell_visuals.gd` attaches art to the existing `CombatProjectile` position and facing. It never moves an object, changes a collider, selects a victim, modifies damage or decides a hit. Removal follows the actual projectile dictionary. Collision events create a separate one-shot effect at the actual collision point. Range expiry does not invent a hit. Existing non-projectile heal, area, wall and knockback events retain their original gameplay timing and receive the corresponding visuals; they are not converted into new physical spells.

Casting uses the existing cast duration and stops on completion or failure. A wall animation spans the existing wall lifetime. Area and wall artwork retains its approved world-space orientation. New visuals are transient game children with nearest filtering and participate in the existing actor/world drawing hierarchy. Leaving an area clears them. No map geometry, prop placements, world collisions, inventory, interfaces, character saves or gameplay controls were changed.

Online authority publishes live spell projectile positions and a bounded, serial-numbered cosmetic event history. The client projects those positions, removes stale projectile sprites, and deduplicates hit events. No client action or presentation event applies damage. Snapshots retain their existing transport and combat authority; the dedicated server needs this revision to publish the extra presentation fields.

Restart the source game to load the installed art. Existing spell selection and casting controls are unchanged: **Q/R** browse known spells, **E** casts at the selected target. The existing Developer Sandbox skill-testing panel (**K**) can raise Magic for trying higher tiers; normal character unlock rules remain intact.

Validation: editor import/parse, main Login startup, exact gameplay-field comparison (only two display names differ), 224 lossless/no-mipmap PNG imports, and the focused `spell_visual_integration.gd` test. The latter passed 46 checks, including real Main/CombatEngine casts and collisions on EastOutskirtsLayered, four actual Godot 4× screenshots of compact Ice Spear/Upheaval objects and independent full-size impacts, online presentation and deduplication, and scene-exit cleanup. Screenshots/logs remain in the supporting workspace, outside Git. These transient effects do not place props or change physical worldbuilding contracts.

Run the focused test with the installed Godot engine:

```powershell
& $env:GODOT --path godot_client --script res://scripts/dev_tools/spell_visual_integration.gd -- --spell-capture=C:/path/outside/repository
```

Native source provenance and the approved-master hashes are retained in `art_sources/spells/installation.json`. The approved master archive and editable review pack remain in the supporting Aetheria workspace.
