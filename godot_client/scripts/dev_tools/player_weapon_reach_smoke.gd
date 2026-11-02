extends SceneTree
## Geometric regression against the actual extracted source limb lengths.
## Visible/nonempty limbs and exact weapon grips alone cannot prove arm reach.
const FAMILIES := ["dagger", "shortsword", "longsword", "mace", "warmaul", "bow", "crossbow", "magic-staff", "magic-wand", "pickaxe"]
const TOLERANCE := 1.5
var checks := 0
var samples := 0
var failures: Array[String] = []
var worst_gap := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(CharacterWeaponMotion.enabled(), "run with --player-motion-candidate while candidate gate exists")
	if not CharacterWeaponMotion.enabled():
		_finish()
		return
	var actor := ActorSprite.new().configure(Vector2(32, 32), Color.BLUE, "weapon_reach_regression")
	root.add_child(actor)
	actor.set_skin("peasant")
	actor.set_process(false)
	var body_script: Script = load("res://scripts/player_articulated_body.gd")
	for armored: bool in [true, false]:
		for family: String in FAMILIES:
			var loadout := {"weapon": {"name": "Bronze " + family.replace("-", " ").capitalize()}}
			if armored:
				loadout.chest = {"name": "Bronze Platebody"}
				loadout.legs = {"name": "Bronze Platelegs"}
			actor.set_equipment(loadout)
			for direction: String in CharacterSpriteLibrary.DIRECTIONS:
				actor.animated_sprite.play(CharacterSpriteLibrary.animation_name("attack", direction))
				actor.animated_sprite.pause()
				for frame in range(8):
					actor.animated_sprite.frame = frame
					actor.attachment_rig.sync_pose()
					var context := actor.attachment_rig._fitted_context()
					var motion: Dictionary = context.weapon_motion
					var label := ("armor" if armored else "bare") + "/" + family + "/" + direction + "/" + str(frame)
					_check(bool(motion.get("active", false)), label + " has resolved attack motion")
					if not bool(motion.get("active", false)):
						continue
					var parts: Dictionary = body_script.call("source_parts", context)
					var body: PlayerArticulatedBody = actor.attachment_rig._fitted_body.motion_body
					for side: String in ["left", "right"]:
						var arm: Dictionary = parts.arms[side]
						var shoulder := FittedEquipmentLibrary.point(motion.joints["shoulder_" + side])
						var wrist: Vector2 = motion[side + "_hand"]
						# These are the actual source pivots, including a borrowed
						# far-side donor. Approximate actor joints are insufficient.
						var upper: float = arm.shoulder.distance_to(arm.elbow)
						var lower: float = arm.elbow.distance_to(arm.wrist)
						var distance := shoulder.distance_to(wrist)
						var elbow := body.solve_elbow(shoulder, wrist, upper, lower, side, direction)
						var proximal_gap := absf(shoulder.distance_to(elbow) - upper)
						var distal_gap := absf(wrist.distance_to(elbow) - lower)
						worst_gap = maxf(worst_gap, maxf(proximal_gap, distal_gap))
						samples += 1
						_check(distance <= upper + lower + TOLERANCE, label + "/" + side + " exceeds full arm reach: " + str(distance) + " > " + str(upper + lower))
						_check(distance + TOLERANCE >= absf(upper - lower), label + "/" + side + " folds inside minimum arm reach")
						_check(proximal_gap <= TOLERANCE, label + "/" + side + " shoulder hinge gap " + str(proximal_gap))
						_check(distal_gap <= TOLERANCE, label + "/" + side + " wrist/forearm gap " + str(distal_gap))
	actor.free()
	_finish()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		if failures.size() <= 15:
			printerr("[Weapon reach] ", label)


func _finish() -> void:
	print(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "arm_samples": samples, "worst_joint_gap": worst_gap, "failures": failures, "artwork_approval": false}))
	quit(0 if failures.is_empty() else 1)
