class_name LegacyCombatTickSystem
extends RefCounted

var game: Variant
var current_tick := 0
var player_next_attack_tick := 0
var monster_next_attack: Dictionary = {}
var combat := CombatEngine.new()

func _init(game_ref: Variant) -> void:
	game = game_ref

## Legacy Arcade adapter. Its caller must invoke this from the shared game tick.
func tick() -> void:
	_update_projectiles()
	_update_player_combat()
	_update_monster_combat()
	current_tick += 1

func _update_projectiles() -> void:
	var to_remove: Array = []
	for projectile: Variant in game.projectile_sprites:
		projectile.update(game.active_monsters)
		if bool(projectile.marked_for_removal):
			to_remove.append(projectile)
	for projectile: Variant in to_remove:
		game.projectile_sprites.erase(projectile)

func _update_player_combat() -> void:
	var player: Variant = game.player
	var target: Variant = game.targeted_monster
	if target == null:
		return
	if int(target.current_hp) <= 0:
		target.in_combat = false
		player.in_combat = false
		game.targeted_monster = null
		return
	if current_tick < player_next_attack_tick:
		return
	var stats := _prepare_combat_stats(player)
	if float(stats.get("projectile_speed", 0.0)) > 0.0:
		var projectile := _create_projectile(player, target, stats)
		game.projectile_sprites.append(_projectile_factory(projectile))
	else:
		var damage := _fight_turn(player, target, stats)
		target.current_hp -= damage
	player.in_combat = true
	target.in_combat = true
	player_next_attack_tick = current_tick + maxi(1, int(stats.get("attack_speed", 4)))

func _update_monster_combat() -> void:
	for monster_sprite: Variant in game.active_monsters:
		var monster: Variant = monster_sprite.monster
		if not bool(monster.in_combat):
			continue
		if int(monster.current_hp) <= 0:
			monster.in_combat = false
			continue
		if monster.target == null:
			monster.in_combat = false
			continue
		var next_attack := int(monster_next_attack.get(monster, 0))
		if current_tick < next_attack:
			continue
		var stats := _prepare_combat_stats(monster)
		if float(stats.get("projectile_speed", 0.0)) > 0.0:
			var projectile := _create_projectile(monster, monster.target, stats)
			game.projectile_sprites.append(_projectile_factory(projectile))
		else:
			var damage := _fight_turn(monster, monster.target, stats)
			monster.target.current_hp -= damage
		monster_next_attack[monster] = current_tick + maxi(1, int(stats.get("attack_speed", 5)))

func _prepare_combat_stats(actor: Variant) -> Dictionary:
	var stats: Dictionary = actor.get_combat_stats()
	stats["projectile_speed"] = float(actor.get_projectile_speed()) if actor.has_method("get_projectile_speed") else float(stats.get("projectile_speed", 0.0))
	return stats

func _fight_turn(attacker: Variant, defender: Variant, stats: Dictionary) -> int:
	var source := stats.duplicate(true)
	source["attack_style"] = String(source.get("style", source.get("damage_type", "slash")))
	var target_stats: Dictionary = defender.get_combat_stats()
	var result := combat.calculate_hit_outcome(source, target_stats)
	return result.damage

func _create_projectile(attacker: Variant, target: Variant, stats: Dictionary) -> LegacyProjectile:
	return LegacyProjectile.new(attacker, target, stats, combat)

func _projectile_factory(projectile: LegacyProjectile) -> Variant:
	if game is Object and game.has_method("projectile_factory"):
		return game.call("projectile_factory", projectile)
	return LegacyProjectileSprite.new(projectile)
