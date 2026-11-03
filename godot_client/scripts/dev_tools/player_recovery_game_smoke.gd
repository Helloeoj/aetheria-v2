extends Node
const Recovery = preload("res://scripts/player_recovery.gd")
class TestHost extends "res://network/world_host.gd":
 func _ready() -> void:
  set_physics_process(false)
 func _persist(session: Dictionary, _release: bool = false) -> bool:
  session.state = CharacterCodec.encode(session.player,session.region_id)
  return true
var failures := 0
var output := OS.get_environment("TEMP").path_join("aetheria-recovery-review")
func check(ok: bool, message: String) -> void:
 if not ok:
  failures += 1
  printerr("FAIL: ",message)
func _ready() -> void:
 run.call_deferred()
 get_tree().create_timer(90).timeout.connect(func() -> void: get_tree().quit(1))
func settle(scene: Node) -> Node:
 var game: Node = scene.get_node("Combat")
 for i in 180:
  await get_tree().physics_frame
  if game.grid_adapter != null and game.grid_adapter.completed:
   break
 await get_tree().process_frame
 return game
func capture(name_: String) -> void:
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png(output.path_join(name_+".png"))
func run() -> void:
 DirAccess.make_dir_recursive_absolute(output)
 get_tree().root.size = Vector2i(1280,720)
 var scene := (load("res://scenes/GolemKingdom.tscn") as PackedScene).instantiate()
 get_tree().root.add_child(scene)
 get_tree().current_scene = scene
 var game: Node = await settle(scene)
 var p: PlayerState=game.player
 p.gold=321
 var inventory := p.backpack.duplicate(true)
 var skills := p.skill_experience.duplicate(true)
 var actor: CombatActor=game.combat.actors[p.entity_id]
 game.fishing_panel.show()
 p.current_hp=0
 actor.hp=0
 actor.is_alive=false
 await get_tree().create_timer(0.2).timeout
 var controller: Node
 for child: Node in game.get_children():
  if child.get_script() == load("res://scripts/player_recovery_controller.gd"):
   controller=child
 check(not game.fishing_panel.visible,"death closes fishing so respawn cannot be blocked")
 check(controller != null and controller.panel.visible,"actual downed HUD is visible")
 check(controller.label.text.contains("30s"),"actual countdown begins at 30")
 check(controller.get("respawn_button") != null,"downed HUD offers immediate respawn")
 if controller.get("respawn_button") == null:
  get_tree().quit(1)
  return
 scene.get_node("MapCamera").zoom=Vector2(4,4)
 await capture("downed")
 check(controller.revive(40),"actual game can revive before deadline")
 await get_tree().physics_frame
 check(p.current_hp==40 and actor.is_alive,"actual revive makes player alive")
 p.current_hp=0
 actor.hp=0
 actor.is_alive=false
 p.downed_elapsed=0.0
 await get_tree().process_frame
 var click := InputEventMouseButton.new()
 click.button_index=MOUSE_BUTTON_LEFT
 click.position=controller.respawn_button.get_global_rect().get_center()
 click.pressed=true
 get_viewport().push_input(click)
 var release := click.duplicate() as InputEventMouseButton
 release.pressed=false
 get_viewport().push_input(release)
 var travel: Node=get_node("/root/SceneTravel")
 check(travel.is_transitioning(),"mouse click starts respawn immediately without waiting for expiry")
 await travel.transition_finished
 var outskirts := get_tree().current_scene
 game=await settle(outskirts)
 check(outskirts.scene_file_path==Recovery.SCENE,"immediate respawn button loads actual outskirts scene")
 check(game.player==p and p.gold==321 and p.backpack==inventory and p.skill_experience==skills,"respawn retains character and progression")
 check(p.get_position().distance_to(Recovery.spawn_position(game))<1.0,"respawn actor occupies outskirts spawn rather than dungeon coordinates")
 check(p.current_hp==p.get_max_hp(),"actual respawn has full health")
 check(game.combat.actors[p.entity_id].can_move(),"actual respawn restores movement")
 outskirts.get_node("MapCamera").zoom=Vector2(4,4)
 await get_tree().create_timer(0.2).timeout
 await capture("respawned")
 # Same-region timeout uses the same supported travel route.
 game.player.current_hp=0
 game.combat.actors[p.entity_id].hp=0
 game.combat.actors[p.entity_id].is_alive=false
 p.downed_elapsed=29.9
 await travel.transition_finished
 game=await settle(get_tree().current_scene)
 check(game.player==p and p.current_hp>0,"same-region death respawns successfully")
 # Real server geometry + host transfer; only account persistence is stubbed.
 var host:=TestHost.new()
 add_child(host)
 var source = await host._get_region("golem")
 var target = await host._get_region("outskirts")
 var online:=PlayerState.new("Server recovery")
 online.entity_id="recovery-server"
 online.x=source.geometry_game.player.x
 online.y=source.geometry_game.player.y
 online.current_hp=0
 online.downed_elapsed=0.2
 source.add_player(online.entity_id,online)
 check(source.players.has(online.entity_id),"server fixture admitted on real dungeon floor")
 var session: Dictionary={"peer":99,"character_id":online.entity_id,"lease_token":"test","region_id":"golem","player":online,"closing":false,"busy":false,"queue":[],"pending":{},"saving":false}
 host.sessions[99]=session
 check(source.submit(online.entity_id,{"type":"respawn"}).ok,"server accepts immediate respawn while downed")
 check(online.downed_elapsed==30.0,"request gives up remaining revival window")
 await host._respawn(session)
 check(session.region_id=="outskirts" and not source.players.has(online.entity_id) and target.players.get(online.entity_id)==online,"host transfers downed player to real outskirts")
 check(online.current_hp==online.get_max_hp() and target.world.combat.actors[online.entity_id].is_alive,"host respawn restores health and actor")
 check(session.state.region_id=="outskirts" and session.state.hp>0,"host persists respawn location and health")
 check(not target.submit(online.entity_id,{"type":"respawn"}).ok,"server rejects respawn while alive")
 print("Recovery game smoke: ",failures," failures; captures: ",output)
 get_tree().quit(0 if failures==0 else 1)
