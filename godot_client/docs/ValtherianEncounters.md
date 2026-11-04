# Valtherian Mines combat progression

Existing native character sprites and foot anchors are reused unchanged. No terrain, ores, props, interfaces, character progression or loot balance is changed.

The shared `valtherian_population.gd` controller runs offline and in the authoritative `valtherian_mines` region after the player grid completes its physics audit. Authored world pixel anchors are checked against the same full-body floor and wall queries used for player movement. Spawn points never relocate automatically. Occupied anchors wait until clear.

The entrance/eastern rooms start with level 5 scouts and level 12 workers/footsoldiers. Interior rooms contain level 18 knights, level 25 warriors and level 30 acolytes. Western/deep chambers contain level 36 captains, level 45 shamans and level 50 chieftains. Levels and drops retain existing catalog definitions. Goblins use their explicit tables. At the user's explicit request, skeletons are included with both item and gold drops disabled pending a separate loot design prompt. This per-population flag does not change dev-spawned skeleton loot. The level 36+ group acquires living players within ten tiles of both the monster and its home, with terrain line of sight required.

Roaming and combat travel use the player shared grid, full-body sweeps and diagonal corner protection. Every roaming target and route stays within ten tiles of its spawn. Mine targets beyond ten tiles of home are forgotten. The shared monster travel leash is reduced from twenty to ten tiles. Each defeated population member gets a fresh identity and full health after fifteen seconds, waiting if its home is occupied. Loot continues through the existing offline/server death handlers, once per death.

Validation: `valtherian_population_smoke.gd` exercises the actual playable scene, placement, drops, timed respawn, roaming, collision, sight aggression and target loss. Runtime 4x evidence is stored outside Git. Animated actors are covered by this runtime check; the passive-prop worldbuilding validator does not support animated characters. No passive content or collision is edited.
