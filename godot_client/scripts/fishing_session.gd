class_name FishingSession
extends RefCounted
## Simulation owns bait consumption and rewards. UI only supplies steering/actions.
enum State { READY, POWER, CASTING, WAITING, BITE, FIGHT, CAUGHT, LOST, CLOSED }
const RODS := ["Beginner Rod", "Apprentice Rod", "Pro Rod", "Master Rod", "Demon Rod"]
const BAITS := ["Low Grade Fish Food", "Medium Grade Fish Food", "High Grade Fish Food"]
const FISH := ["Reedkip", "Marlo", "Bracken", "Kessa", "Veilfin", "Lumara", "Vesper", "Moonfin", "Velora", "Sunfish"]
const EATING_COOLDOWN_SECONDS := 1.8
const CAST_POWER_CYCLE_SECONDS := 1.8
const MIN_CAST_DISTANCE := 10.0
const DISTANCE_RARITY_SCALE := 200.0
const DISTANCE_RARITY_BONUS := 0.35
const FISH_PULL_TOLERANCE_PER_LEVEL := 0.0025
const PERFECT_CAST_POWER := 0.95
const FIGHT_BOUNDARY_SCALE := 0.6
# Extra travel beyond each red bar, matching the user's red-to-green guide gap.
# The outer stops follow rod- and skill-dependent safe-zone width.
const OUTSIDE_BOUNDARY_MARGIN := 0.24
const REEL_REFERENCE_DISTANCE := 200.0
const SHORT_CAST_REEL_PADDING := 50.0
var state := State.READY
var player: PlayerState
var rng := RandomNumberGenerator.new()
var rod := ""
var bait := ""
var fish: Dictionary = {}
var message := "Choose a pole and bait, then cast."
var elapsed := 0.0
var power := 0.0
var cast_power := 0.0
var distance := 0.0
var remaining := 0.0
var lateral := 0.0
var velocity := 0.0
var strain := 0.0
var fight_time := 0.0
var bite_after := 0.0
var dart_after := 0.0
var fish_pull := 0.0
var start_position := Vector2.ZERO
var start_hp := 0
var reward_xp := 0

static func raw_fish_names() -> Array[String]:
	var names: Array[String] = []
	for species: String in FISH:
		names.append("Raw " + species)
	return names

func _init(owner_player: PlayerState = null) -> void:
	player = owner_player
	rng.randomize()
	if player != null:
		start_position = player.get_position()
		start_hp = player.current_hp
		for name: String in RODS:
			if available(name):
				rod = name
				break
		for name: String in BAITS:
			if available(name):
				bait = name
				break

func available(item_name: String) -> bool:
	if player == null or int(player.backpack.get(item_name, 0)) <= 0:
		return false
	return player.get_skill_level("fishing") >= int(GameData.get_item_by_name(item_name).get("fishing_level", 1))

func active_cast() -> bool:
	return state in [State.POWER, State.CASTING, State.WAITING, State.BITE, State.FIGHT]

func act() -> void:
	match state:
		State.READY, State.CAUGHT, State.LOST:
			if player.fishing_pale_count() >= PlayerState.FISHING_PALE_SIZE:
				message = "Your Fishing Pale is full. Move or drop a fish before casting."
				return
			if not available(rod) or not available(bait):
				message = "You need an unlocked fishing pole and bait in your backpack."
				return
			power = 0.0
			elapsed = 0.0
			state = State.POWER
			message = "Click or Space again to set cast power."
		State.POWER:
			# Revalidate at commit time; no bait is spent for merely charging a cast.
			if player.fishing_pale_count() >= PlayerState.FISHING_PALE_SIZE:
				state = State.READY
				message = "Your Fishing Pale is full. Move or drop a fish before casting."
				return
			if not available(rod) or not available(bait):
				state = State.READY
				message = "Your pole or bait is no longer available."
				return
			# Evaluate the distance that will actually be committed, not the last cast.
			distance = projected_cast_distance()
			if catch_pool().is_empty():
				state = State.READY
				message = "No fish match your level, food grade and cast distance."
				return
			if not player.remove_item(bait):
				state = State.READY
				return
			cast_power = power
			distance = projected_cast_distance()
			remaining = distance
			lateral = 0.0
			velocity = 0.0
			strain = 0.0
			fight_time = 0.0
			reward_xp = 0
			fish = _roll_fish()
			bite_after = rng.randf_range(2.5, 6.0)
			state = State.CASTING
			elapsed = 0.0
			message = "Casting..."
		State.BITE:
			state = State.FIGHT
			elapsed = 0.0
			dart_after = 0.0
			message = "Pull against the fish. Keep the bobber between the red lines!"

func advance(delta: float, steering: float = 0.0) -> void:
	if delta <= 0.0 or state == State.CLOSED:
		return
	# Small deterministic steps keep physics and escape timing stable at low FPS.
	var left := minf(delta, 2.0)
	while left > 0.00001:
		var step := minf(left, 1.0 / 60.0)
		_step(step, clampf(steering, -1.0, 1.0))
		left -= step

func _step(delta: float, steering: float) -> void:
	elapsed += delta
	match state:
		State.POWER:
			power = power_at_time(elapsed)
		State.CASTING:
			if elapsed >= 0.65:
				state = State.WAITING
				elapsed = 0.0
				message = "Watch the bobber..."
		State.WAITING:
			if elapsed >= bite_after:
				state = State.BITE
				elapsed = 0.0
				message = "BITE! Click or Space to hook!"
		State.BITE:
			if elapsed >= 2.0:
				lose("Too slow! The fish took the bait.")
		State.FIGHT:
			if remaining <= 0.0:
				_land()
				return
			fight_time += delta
			dart_after -= delta
			var strength := float(fish.get("fish_strength", 0.65))
			if dart_after <= 0.0:
				fish_pull = rng.randf_range(0.6, 1.0) * strength * (-1.0 if rng.randf() < 0.5 else 1.0)
				dart_after = rng.randf_range(float(fish.get("fish_dart_min", 1.0)), float(fish.get("fish_dart_max", 1.8)))
			velocity = move_toward(velocity, fight_velocity_target(steering), delta * 2.8)
			var limit := lateral_limit()
			lateral = clampf(lateral + velocity * delta, -limit, limit)
			# Do not accumulate outward momentum against the stop: a player can
			# steer back immediately rather than fight an invisible velocity debt.
			if absf(lateral) >= limit and lateral * velocity > 0.0:
				velocity = 0.0
			if absf(lateral) > boundary():
				strain = minf(1.0, strain + delta * 0.8)
			else:
				strain = maxf(0.0, strain - delta * 0.55)
				remaining = maxf(0.0, remaining - delta * reel_speed())
			if strain >= 1.0:
				lose("The fish escaped beyond the red lines.")
			elif remaining <= 0.0:
				_land()
			elif fight_time >= 60.0:
				lose("The fish slipped free after a long fight.")

func boundary() -> float:
	var base := float(GameData.get_item_by_name(rod).get("fishing_width", 0.40))
	return minf(0.78, base + float(player.get_skill_level("fishing") - 1) * 0.0015) * FIGHT_BOUNDARY_SCALE

func lateral_limit() -> float:
	return boundary() + OUTSIDE_BOUNDARY_MARGIN

func reel_travel_distance() -> float:
	if distance <= 0.0:
		return 0.0
	# Give close casts room for a fight, fading the extra travel out at 200 ft.
	# Actual cast feet still own species eligibility, rarity and the distance UI.
	var short_cast := clampf((REEL_REFERENCE_DISTANCE - distance) / (REEL_REFERENCE_DISTANCE - MIN_CAST_DISTANCE), 0.0, 1.0)
	return distance + SHORT_CAST_REEL_PADDING * short_cast

func reel_speed() -> float:
	var base := float(GameData.get_item_by_name(rod).get("reel_speed", 9.0))
	if distance <= 0.0:
		return base
	return base * distance / maxf(distance, reel_travel_distance())

func bobber_water_depth() -> float:
	# Match the extra visual travel to the fight duration, reaching shore smoothly.
	# Every point of a 200-ft cast keeps its original screen position.
	var progress := clampf(remaining / maxf(1.0, distance), 0.0, 1.0)
	return progress * clampf(reel_travel_distance() / REEL_REFERENCE_DISTANCE, 0.0, 1.0)

static func power_at_time(seconds: float) -> float:
	# Fixed tempo: 0.9 seconds up, 0.9 seconds down, repeating without a pause.
	var phase := fposmod(maxf(0.0, seconds), CAST_POWER_CYCLE_SECONDS) / CAST_POWER_CYCLE_SECONDS
	return 1.0 - absf(phase * 2.0 - 1.0)

func projected_cast_distance() -> float:
	# A short perfect-cast band makes cap-distance fish reachable by a human,
	# rather than demanding the exact single instant at the triangle's peak.
	return lerpf(MIN_CAST_DISTANCE, effective_max_cast_distance(), clampf(power / PERFECT_CAST_POWER, 0.0, 1.0))

func cast_mastery_level() -> int:
	var item := GameData.get_item_by_name(rod)
	return int(item.get("cast_mastery_level", int(item.get("fishing_level", 1)) + 10))

func effective_max_cast_distance() -> float:
	var item := GameData.get_item_by_name(rod)
	var unlock_level := int(item.get("fishing_level", 1))
	var mastery_level := cast_mastery_level()
	var progress := clampf(float(player.get_skill_level("fishing") - unlock_level) / float(maxi(1, mastery_level - unlock_level)), 0.0, 1.0)
	var cap := float(item.get("cast_distance", 60))
	var starting_distance := clampf(float(item.get("cast_distance_at_unlock", MIN_CAST_DISTANCE)), MIN_CAST_DISTANCE, cap)
	return lerpf(starting_distance, cap, progress)

func skill_pull_tolerance() -> float:
	return 1.0 + float(clampi(player.get_skill_level("fishing"), 1, 100) - 1) * FISH_PULL_TOLERANCE_PER_LEVEL

func effective_fish_pull() -> float:
	return fish_pull / skill_pull_tolerance()

func input_strength() -> float:
	return float(GameData.get_item_by_name(rod).get("fishing_control", 1.2))

func fight_velocity_target(steering: float) -> float:
	# Skill resists fish pull rather than amplifying binary keyboard steering,
	# which would make high-level controls twitchier and encourage overshoot.
	return effective_fish_pull() + clampf(steering, -1.0, 1.0) * input_strength()

func catch_pool(at_distance: float = -1.0) -> Array[Dictionary]:
	# Bait must match the fish's grade exactly. Distance weights that pool afterward.
	var bait_grade := int(GameData.get_item_by_name(bait).get("tier", 1))
	var feet := distance if at_distance < 0.0 else at_distance
	var pool: Array[Dictionary] = []
	for name: String in FISH:
		var entry := GameData.get_item_by_name("Raw " + name)
		if entry.is_empty() or player.get_skill_level("fishing") < int(entry.get("fishing_level", 1)):
			continue
		if int(entry.get("required_bait_grade", int(entry.get("tier", 1)))) != bait_grade:
			continue
		if feet + 0.000001 < float(entry.get("minimum_catch_distance", MIN_CAST_DISTANCE)):
			continue
		var rank := int(entry.get("tier", 1))
		var weight := float(entry.get("catch_weight", 1.0))
		# Actual feet matter, so an upgraded rod can improve the same power cast.
		weight *= 1.0 + float(rank - 1) * clampf(feet / DISTANCE_RARITY_SCALE, 0.0, 1.0) * DISTANCE_RARITY_BONUS
		pool.append({"item": entry, "weight": weight})
	return pool

func _roll_fish() -> Dictionary:
	var pool := catch_pool()
	var total := 0.0
	for entry: Dictionary in pool:
		total += float(entry.weight)
	if pool.is_empty():
		return {}
	var roll := rng.randf() * total
	for entry: Dictionary in pool:
		roll -= float(entry.weight)
		if roll <= 0.0:
			return entry.item
	return pool.back().item

func _land() -> void:
	if state != State.FIGHT:
		return
	var name := String(fish.get("name", ""))
	if not player.store_fishing_catch(name):
		# Retain the hooked fish until a slot is freed; never discard a reward.
		message = "Free a Fishing Pale slot to land this fish."
		return
	state = State.CAUGHT
	var before := player.get_skill_experience("fishing")
	var old_level := player.get_skill_level("fishing")
	player.add_skill_experience("fishing", int(fish.get("fishing_xp", 100)))
	reward_xp = player.get_skill_experience("fishing") - before
	message = "Caught %s! Added to Fishing Pale. +%d Fishing XP" % [name, reward_xp]
	if player.get_skill_level("fishing") > old_level:
		message += "  Level %d!" % player.get_skill_level("fishing")

func lose(reason: String) -> void:
	state = State.LOST
	message = reason

func close() -> void:
	state = State.CLOSED

static func eating_attack_delay_seconds(player_state: PlayerState) -> float:
	# Use current equipment, including a weapon changed since the actor refreshed.
	return PlayerStats.weapon_attack_interval_seconds(player_state.equipment.get("weapon", {}))

static func eating_error(player_state: PlayerState, name: String, engine: CombatEngine = null) -> String:
	if player_state.current_hp <= 0:
		return "You must be alive to eat."
	if player_state.food_cooldown_seconds > 0.0:
		return "Wait %.1f seconds before eating again." % player_state.food_cooldown_seconds
	if engine != null and engine.active_spell_casts.has(player_state.entity_id):
		return "Finish casting before eating."
	var item := GameData.get_item_by_name(name)
	if String(item.get("fish_state", "")) == "raw":
		return "Cook raw fish at a campfire before eating it."
	if String(item.get("fish_state", "")) == "burnt":
		return "Burnt fish cannot be eaten."
	if int(item.get("food_healing", 0)) <= 0:
		return "That item is not food."
	if int(player_state.backpack.get(name, 0)) <= 0:
		return "That fish is no longer in your backpack."
	if player_state.current_hp >= player_state.get_max_hp():
		return "You are already at full health."
	return ""

static func eat(player_state: PlayerState, name: String, engine: CombatEngine = null) -> int:
	if not eating_error(player_state, name, engine).is_empty():
		return 0
	var healing := int(GameData.get_item_by_name(name).get("food_healing", 0))
	if not player_state.remove_item(name):
		return 0
	var restored := mini(healing, player_state.get_max_hp() - player_state.current_hp)
	player_state.current_hp += restored
	player_state.food_cooldown_seconds = EATING_COOLDOWN_SECONDS
	var remaining := player_state.food_attack_cooldown_seconds
	var actor: CombatActor = engine.actors.get(player_state.entity_id) if engine != null else null
	if actor != null:
		remaining = maxf(remaining, actor.attack_cooldown_seconds)
	player_state.food_attack_interval_seconds = eating_attack_delay_seconds(player_state)
	player_state.food_attack_cooldown_seconds = maxf(0.0, remaining) + player_state.food_attack_interval_seconds
	if engine != null:
		if actor != null:
			actor.hp = player_state.current_hp
			actor.attack_cooldown_seconds = player_state.food_attack_cooldown_seconds
	return restored
