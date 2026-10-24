# Mining discovery

Focused reconnaissance only; no Mining behavior or catalog entries were added.

## Current catalog

- `godot_client/data/items.json` is authoritative. `godot_client/scripts/game_data.gd` loads it and exposes `get_item()`, `get_item_by_name()`, `canonical_item_name()`, and `list_items()`.
- Existing ore IDs are **235 Bronze Ore**, **239 Iron Ore**, **242 Steel Ore**, **246 Blacksteel Ore**, **249 Mithril Ore**, **252 Adamantite Ore**, and **256 Starforged Ore**. They are stackable `Crafting` items with tiers 1–7.
- Existing ingot IDs are 236 Bronze, 40 Iron, 243 Steel, 70 Blacksteel, 90 Mithril, 253 Adamantite, and 257 Starforged. `godot_client/data/recipes.json` consumes the ores through furnace recipes.
- There are **no pickaxe items** and no items typed/named as minerals. Do not allocate IDs during Mining implementation without a separate catalog decision.
- Steel Ore (242) is retained only for saved-inventory compatibility and excluded from generic loot; Steel uses Iron Ore + Coal (329). See `godot_client/scripts/smithing_catalog.gd` and `godot_client/docs/Crafting.md`.
- Starforged Ore has an approved Golem Titan-only acquisition policy in `godot_client/data/acquisition.json`; `godot_client/scripts/acquisition_rules.gd` and `godot_client/tests/catalog_acquisition_smoke.gd` enforce it. Mining must not create a bypass.

## Dependency map

| Concern | Existing interface / reusable implementation | Mining gap |
| --- | --- | --- |
| Skill registry and curve | `godot_client/scripts/skill_progression.gd`: `SKILL_IDS`, `SKILL_NAMES`, level 1–100 shared curve, `experience_for_level()`, `level_for_experience()`, `experience_source_text()`. | `mining` is absent from the eight-skill registry and source text. |
| Player progression | `godot_client/scripts/player_state.gd`: `levels`, `skill_experience`, `get_skill_progress()`, `set_skill_level()`, `add_skill_experience()`. Registry entries are initialized automatically. | Add Mining defaults/registry integration; define rewards and unlock semantics. |
| Skill UI/session rates | `godot_client/scripts/ui_skill_debug_panel.gd` and the character journal in `godot_client/scripts/ui_inventory_menu.gd` consume `SKILL_IDS`; `godot_client/scripts/skill_training_session.gd` records generic `skill_experience_gained` events. | Mining will appear automatically once registered, but its earned-XP path must emit/record the standard event where relevant. |
| Inventory | `godot_client/scripts/inventory_system.gd`: canonical name-based stacks, `add_to_backpack()`, `remove_from_backpack()`, `inventory_slots()`. `PlayerState.add_item()` rejects unknown catalog items. `godot_client/scripts/ground_item_drop.gd` handles collectible world stacks. | Decide whether mined ore credits directly or becomes a ground drop; no capacity limit currently exists for stackable ores. |
| Equipment | `InventorySystem.equip_item()` and `unequip_slot()` use catalog `slot`; `PlayerState.equipment` has weapon plus armor slots. `godot_client/scripts/equipment_progression.gd` applies combat requirements. | No tool slot/tool requirement and no pickaxe catalog entries. Reusing `weapon` would affect combat/equipment visuals and needs an explicit design decision. |
| World interaction | `godot_client/scripts/world_interaction.gd` hit-tests groups/types, builds left/right-click actions, routes around collision, and holds pending interactions until in range. `FishingSpot` (`godot_client/scripts/fishing_spot.gd`) supplies `contains_global_point()`, an approach point, and interaction radius. | No mining-deposit node/group, hit test, context action, pending route, range check, depletion, or respawn state. |
| Gathering rules | `godot_client/scripts/fishing_session.gd` is a self-contained authoritative-compatible state machine: validates owned/unlocked inputs, reserves/consumes resources, resolves one reward, and awards XP once. Cooking uses the same session pattern. | No generic gathering abstraction exists. Mining needs its own rule/session object; reuse the session contract rather than altering Fishing. |
| Client interface | `godot_client/scripts/main.gd` owns `request_fishing()`/nearby interaction; `godot_client/scripts/ui_fishing.gd` preserves the original Fishing UI. `godot_client/network/remote_minigame_sessions.gd` mirrors server Fishing/Cooking state into the original panels without client rewards. | No Mining input/UI/presentation contract. Do not substitute or modify the Fishing interface. |
| Character animation | `godot_client/scripts/actor_sprite.gd` supports directional `idle`, `walk`, and `attack`; `play_attack()` has an authored animation or lunge fallback. `godot_client/scripts/character_sprite_library.gd` builds only those three actions. Equipment follows sockets via `character_attachment_rig.gd`. | No gather/mine action, timing marker, or pickaxe attachment art. A goblin prompt mentions a pickaxe in `data/character_sprites.json`, but it is not a player tool or reusable mining animation. |
| Server authority | `godot_client/network/authoritative_region.gd` validates a command allowlist, owns movement/range/inventory mutation, discovers approved station nodes, routes activity commands, marks saves dirty, and publishes actors/drops/stations. `godot_client/network/region_activities.gd` owns per-character Fishing/Cooking sessions and authoritative rewards. | Add validated Mining commands/activity state and server-side deposit lookup/range/tool/skill/reward checks. Client-side reward rolls would violate the current model. |
| Replication/world state | `godot_client/network/world_host.gd` serializes commands, advances regions, sends 10 Hz snapshots, and persists dirty character state. `godot_client/network/online_world_view.gd` applies actors/drops/stations; `network_manager.gd` sends actions and applies snapshots. | Deposit identity, availability/depletion and respawn must be represented in authoritative region snapshots (or equivalent replicated state); none exists now. |
| Durable saves | `godot_client/network/character_codec.gd` stores inventory by numeric item ID, equipment by ID, and `skill_experience`; levels are derived on decode. | Important migration: decode currently requires every `SKILL_IDS` key. Adding Mining without a version/default migration will reject existing saves as `save_skills`. Deposit state is not persisted anywhere. |

## Recommended reuse boundary

Keep item lookup, XP curve, player inventory, interaction routing, activity ownership, snapshots, and save scheduling. Model Mining beside Fishing/Cooking as a server-owned activity with a dedicated deposit node and rules/session class. Avoid a premature generic gathering refactor: Fishing is specialized, and no shared gather base currently exists.

## Functionality still requiring decisions

- Which existing ores are mineable, their levels/XP/yields, and whether Starforged remains boss-only (current policy says it must).
- Pickaxe catalog/IDs, acquisition, equip/tool-slot behavior, and visuals; none are defined.
- Mining interaction cadence/minigame, interruption rules, inventory-full behavior (if any), deposit sharing, depletion, respawn, and persistence across server restarts.
- Mining animation/action frames and attachment sockets.
- Save-schema migration for pre-Mining characters and tests covering offline parity, authority, concurrency, reconnects, and duplication prevention.
