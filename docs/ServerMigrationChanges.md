# Audit of the server migration

This audits the changes introduced by `38ec1f8` and `3d1c781` relative to
`06fb469`, not unrelated map, chat-name or Sentinel work in the shared checkout.
The user requested server authority, login and persistent character progression;
that did not authorize redesigning existing gameplay or interfaces.

| Area | What changed | Current status |
| --- | --- | --- |
| Fishing | Online play bypassed the original lake-art minigame for a simplified panel | Original `ui_fishing.gd` is reconnected online; its artwork, drawing, rod, bobber, meter, controls and pale menus are reused. Cast/release/hook actions go to the server; prepared varied fights and frame-level local prediction keep controls responsive. |
| Cooking | Online play bypassed the existing pan/flip interface for the same simplified panel | Original `ui_cooking.gd` and `ui_cooking_pan.gd` are reconnected online. Raw-food consumption, flips, burns and rewards remain on the server. Bounded frame-level timers and neutral pending feedback avoid stale timer resets. |
| Login/startup | Changed normal startup from East Outskirts to account Login | Retained at the user's explicit request. |
| Character storage | Added PostgreSQL accounts, password hashes, tickets, leases, revisioned saves and reconnect restoration | Retained at the user's explicit request. Private runtime/database data remains outside Git. |
| Monsters | Added three automatic server-created goblins per region | The active game keeps these encounters only in explicit regression fixtures. |
| Developer tools | Hid/blocked F5/F6/F7, K and P while online; later added a separate sandbox entry | This was a change to the testing workflow. The sandbox remains available, but it is not a replacement for restoring minigames online. Trusted server-side developer permissions have not been implemented. |
| Inventory/crafting/food | Changed equip, unequip, food, crafting, purchase, pickup and drop actions to server requests | Existing journal/crafting interfaces remain; authoritative results come from the server. |
| Orb empowerment | Blocked the journal's direct online empowerment action with an enchanting-station message | Still a parity gap: direct empowerment was not wired to a server command. |
| Movement | Replaced client simulation with server movement and collision; snapshots update the displayed position | Keyboard input predicts locally and remote actors interpolate. Online click-walking still requires a clear direct path, unlike the existing offline interaction path routing around obstacles. |
| Combat | Added per-character server combat/XP ownership and replicated actor state | Complete original projectile/cast-effect presentation is not replicated yet. This is a parity gap, not a completed visual migration. |
| Travel | Replaced local online scene changes with approved server portal intents | Server validates portal/range and saves destination region/position. |
| Logout/disconnect | Added combat logout restriction, a 30-second disconnect grace, five-second transient checkpoints and frozen recovery on save failures | These were additional online lifecycle behaviors. They are documented here rather than presented as unchanged original behavior. |
| Online HUD | Added connection status and save/logout controls | Hidden while the original minigame modal is open so they do not obscure its existing layout. |
| Artwork and original rule files | Original fishing/cooking art, `fishing_session.gd`, `cooking_session.gd` and pan drawing were not deleted or replaced | Reused. The original interfaces were bypassed by online routing; that routing is now repaired. |

The minigame repair does not claim the remaining parity gaps above are resolved.
No additional redesign is authorized. `AGENTS.md` now records that explicitly.
