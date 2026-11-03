extends Node
const Recovery = preload("res://scripts/player_recovery.gd")
var game: Node
var panel: PanelContainer
var label: Label
var _leaving := false

func configure(owner_game: Node) -> void:
 game = owner_game
 process_physics_priority = 100
 panel = PanelContainer.new()
 panel.name = "DownedCountdown"
 panel.position = Vector2(370,110)
 panel.custom_minimum_size = Vector2(540,92)
 panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
 game.ui_root.add_child(panel)
 label = Label.new()
 label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 label.add_theme_font_size_override("font_size",22)
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 panel.add_child(label)
 panel.hide()

func _process(_delta: float) -> void:
 if game == null:
  return
 var downed: bool = game.player.current_hp <= 0
 panel.visible = downed
 if downed:
  label.text = "DOWNED - awaiting revival\nRespawn at Valtheris outskirts in %ds" % ceili(maxf(0.0,Recovery.WINDOW-game.player.downed_elapsed))

func _physics_process(delta: float) -> void:
 if game == null or Network.online() or _leaving:
  return
 if game.grid_adapter != null and not game.grid_adapter.completed:
  return
 var expired: bool = Recovery.advance(game.world,game.player,delta)
 if game.player.current_hp <= 0:
  game._reset_held_movement()
  game.interactions.cancel_walk()
  game.auto_chase_target = false
  game.spell_cast_requested = false
  if game.fishing_panel.visible:
   game.fishing_panel.close()
  if game.cooking_controller != null and game.cooking_controller.panel.visible:
   game.cooking_controller.panel.close()
  if game.crafting_panel != null and game.crafting_panel.visible:
   game.crafting_panel.close()
  if game.offline_mining != null:
   game.offline_mining.stop("death")
 if expired:
  respawn()

func revive(health: int) -> bool:
 if Network.online() or _leaving:
  return false
 return Recovery.revive(game.world,game.player,health)

func respawn() -> void:
 var travel := get_node_or_null("/root/SceneTravel")
 if travel == null or travel.is_transitioning():
  return
 _leaving = true
 Recovery.restore(game.player)
 game._refresh_player_actor_from_player()
 if not travel.request_travel(game,Recovery.SCENE,"",true):
  _respawn_failed("")
  return
 travel.transition_failed.connect(_respawn_failed,CONNECT_ONE_SHOT)

func _respawn_failed(_message: String) -> void:
 game.player.remove_meta("recovery_arrival")
 game.player.current_hp = 0
 game.player.downed_elapsed = Recovery.WINDOW
 game._refresh_player_actor_from_player()
 _leaving = false
