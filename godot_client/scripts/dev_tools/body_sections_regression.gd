extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures < 12:printerr(label)
func run() -> void:
	await process_frame
	var actor := ActorSprite.new().configure(Vector2(32,32),Color.BLUE,"sections")
	root.add_child(actor)
	actor.set_process(false)
	actor.set_skin("peasant")
	actor.set_equipment({"chest":{"name":"Iron Platebody"},"legs":{"name":"Iron Platelegs"}})
	actor.animated_sprite.play("walk_south")
	actor.animated_sprite.pause()
	actor.animated_sprite.frame = 1
	actor.attachment_rig.sync_pose()
	var head := actor.animated_sprite.get_node("ArmorHeadForeground") as Sprite2D
	var original := FittedEquipmentLibrary.texture("original/south/2.png").get_image()
	check(head.texture.get_image().get_pixel(40,38) == original.get_pixel(40,38),"Walking chin pixel was cut out of the original head")
	check(actor.animated_sprite.has_node("BodyChestArms") and actor.animated_sprite.has_node("BodyLegsFeet"),"Bare body is not split into three independent sections")
	if not actor.animated_sprite.has_node("BodyChestArms"):
		actor.free()
		quit(1)
		return
	actor.animated_sprite.play("idle_south")
	actor.animated_sprite.pause()
	actor.attachment_rig.sync_pose()
	var upper_hand := actor.animated_sprite.get_node("BodyChestArms") as Sprite2D
	var lower_hand := actor.animated_sprite.get_node("BodyLegsFeet") as Sprite2D
	check(upper_hand.texture.get_image().get_pixel(23,53).a>0 and lower_hand.texture.get_image().get_pixel(23,53).a==0,"Dark outline of low hand belongs to chest/arms, not legs")
	for direction: String in CharacterSpriteLibrary.DIRECTIONS:
		for n in range(9):
			actor.animated_sprite.play(CharacterSpriteLibrary.animation_name("idle" if n==0 else "walk",direction))
			actor.animated_sprite.pause()
			actor.animated_sprite.frame = maxi(0,n-1)
			actor.attachment_rig.sync_pose()
			var ctx := actor.attachment_rig._fitted_context()
			var pose := FittedEquipmentLibrary.frame(ctx)
			var source := FittedEquipmentLibrary.texture(pose.original).get_image()
			var images := [head.texture.get_image(),actor.animated_sprite.get_node("BodyChestArms").texture.get_image(),actor.animated_sprite.get_node("BodyLegsFeet").texture.get_image()]
			var chest := actor.attachment_rig.get_equipped_visual("chest") as FittedEquipmentVisual
			var armor := chest.part_sprites[0].texture.get_image()
			for y in range(80):
				for x in range(80):
					var color := source.get_pixel(x,y)
					var face_center := FittedEquipmentLibrary.point(pose.joints.head)
					var neck := FittedEquipmentLibrary.point(pose.joints.neck)
					# Independent anatomical/color oracle, not the exported mask:
					# original face skin around eyes/nose/chin must belong to head.
					if color.a>0 and absf(x-face_center.x)<=12 and y>=face_center.y-4 and y<=neck.y+1 and color.r>0.42 and color.r>color.g*1.2 and color.g>color.b*1.05:
						check(images[0].get_pixel(x,y)==color,"Original face skin was assigned outside head: "+direction+"/"+str(n)+" at "+str(Vector2i(x,y)))
					var owners := 0
					for im: Image in images:
						if im.get_pixel(x,y).a>0:
							owners += 1
							check(im.get_pixel(x,y)==source.get_pixel(x,y),"Body section changed original RGBA pixels")
					check(owners==(1 if source.get_pixel(x,y).a>0 else 0),"Body section overlap or missing source pixel")
					if images[0].get_pixel(x,y).a>0:check(armor.get_pixel(x,y).a==0,"Armor occupies original head silhouette")
	actor.free()
	print("[Body sections] checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
