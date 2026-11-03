extends RefCounted
## Trusted simulation API. No client revive/respawn command is exposed.
const WINDOW := 30.0
const SCENE := "res://scenes/EastOutskirtsLayered.tscn"
const REGION := "outskirts"

static func advance(world: WorldState, player: PlayerState, delta: float) -> bool:
 var actor: CombatActor = world.combat.actors.get(player.entity_id)
 if actor == null:
  return false
 player.current_hp = actor.hp
 if actor.hp > 0:
  player.downed_elapsed = 0.0
  actor.remove_meta("recovery_downed")
  return false
 actor.is_alive = false
 if not actor.has_meta("recovery_downed"):
  actor.set_meta("recovery_downed",true)
  clear_combat(world,player)
 if is_finite(delta) and delta > 0.0:
  player.downed_elapsed = minf(WINDOW,player.downed_elapsed + delta)
 return player.downed_elapsed + 0.0000001 >= WINDOW

static func clear_combat(world: WorldState, player: PlayerState) -> void:
 var id := player.entity_id
 player.current_target = ""
 player.in_combat = false
 world.cancel_grid_route(id)
 world.combat.active_spell_casts.erase(id)
 world.combat.player_attack_enabled[id] = false
 var actor: CombatActor = world.combat.actors.get(id)
 if actor != null:
  actor.current_target_id = ""
  actor.active_orb_effects.clear()
 for other: CombatActor in world.combat.actors.values():
  if other.current_target_id == id:
   other.current_target_id = ""
  other.aggro_attacker_ids.erase(id)
 for key: String in world.combat.projectiles.keys():
  var shot: CombatProjectile = world.combat.projectiles[key]
  if shot.attacker_id == id or shot.target_id == id:
   world.combat.projectiles.erase(key)

static func revive(world: WorldState, player: PlayerState, health: int) -> bool:
 var actor: CombatActor = world.combat.actors.get(player.entity_id)
 if actor == null or actor.hp > 0 or health <= 0 or player.downed_elapsed + 0.0000001 >= WINDOW:
  return false
 clear_combat(world,player)
 player.current_hp = clampi(health,1,player.get_max_hp())
 player.downed_elapsed = 0.0
 actor.hp = player.current_hp
 actor.is_alive = true
 actor.death_reported = false
 actor.remove_meta("recovery_downed")
 return true

static func restore(player: PlayerState) -> void:
 player.current_hp = player.get_max_hp()
 player.downed_elapsed = 0.0
 player.current_target = ""
 player.in_combat = false

static func spawn_position(game: Node) -> Vector2:
 # Reuse the existing outskirts initial spawn, not a new map placement.
 var starter := PlayerState.new()
 return Vector2(starter.x + game._map_x_offset_tiles(),starter.y + game._map_y_offset_tiles())
