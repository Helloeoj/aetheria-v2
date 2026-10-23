extends RefCounted
## Shared display/authority motion only. Never resolves outcomes or touches a player.
static func prepare(fish: Dictionary, rng: RandomNumberGenerator) -> Array:
	var plan: Array = []
	var until := 0.0
	while until < 60.0:
		# Keep original magnitude, sign, duration distributions and RNG draw order.
		var pull := rng.randf_range(0.6, 1.0) * float(fish.get("fish_strength", 0.65)) * (-1.0 if rng.randf() < 0.5 else 1.0)
		var duration := rng.randf_range(float(fish.get("fish_dart_min", 1.0)), float(fish.get("fish_dart_max", 1.8)))
		until += maxf(1.0 / 60.0, ceilf(duration * 60.0) / 60.0)
		plan.append([minf(until, 60.0), pull])
	return plan

static func step(body: RefCounted, delta: float, steering: float, rules: Dictionary) -> void:
	body.fight_time += delta
	if not body.fight_plan.is_empty():
		while body.plan_index < body.fight_plan.size() - 1 and body.fight_time > float(body.fight_plan[body.plan_index][0]) + 0.000001:
			body.plan_index += 1
		body.fish_pull = float(body.fight_plan[body.plan_index][1])
		body.dart_after = maxf(0.0, float(body.fight_plan[body.plan_index][0]) - body.fight_time)
	var target: float = body.fish_pull / float(rules.tolerance) + clampf(steering, -1.0, 1.0) * float(rules.control)
	body.velocity = move_toward(body.velocity, target, delta * 2.8)
	var limit := float(rules.limit)
	body.lateral = clampf(body.lateral + body.velocity * delta, -limit, limit)
	if absf(body.lateral) >= limit and body.lateral * body.velocity > 0.0:
		body.velocity = 0.0
	if absf(body.lateral) > float(rules.boundary):
		body.strain = minf(1.0, body.strain + delta * 0.8)
	else:
		body.strain = maxf(0.0, body.strain - delta * 0.55)
		body.remaining = maxf(0.0, body.remaining - delta * float(rules.reel))
