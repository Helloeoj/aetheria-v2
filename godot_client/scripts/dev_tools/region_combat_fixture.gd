extends RefCounted
## Explicit test encounters. Production region startup must never add these.
static func add_monsters(region: RefCounted) -> void:
	var templates := GameData.get_active_monster_templates()
	if templates.is_empty():
		return
	for index in range(3):
		var template: Dictionary = templates[mini(index, templates.size() - 1)]
		if int(template.get("tier", 1)) > 2:
			template = templates[0]
		var point: Vector2 = region._safe_position(Vector2(15 + index * 4, 15))
		if not point.is_finite():
			continue
		var monster := MonsterState.new(template, point.x, point.y)
		monster.entity_id = "fixture-mob:" + str(index)
		var stats := monster.get_combat_stats()
		var data := stats.duplicate(true)
		data.merge({"entity_id": monster.entity_id, "name": monster.name, "x": point.x, "y": point.y,
			"hp": monster.current_hp, "max_hp": monster.max_hp, "is_monster": true,
			"attack_style": stats.style, "monster_attack_type": monster.damage_type}, true)
		region.world.register_monster_actor(monster, CombatActor.new().configure(data))
		region._add_body(monster.entity_id)
