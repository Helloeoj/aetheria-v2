extends Node
## Exercises real journal controls; --live also captures the actual world scene.
class Fixture extends Node:
	var player := PlayerState.new("Summoning menu test")
	var spell_cast_requested := false

var checks := 0
var failures := 0
var output := ""
var live := false

@onready var root: Window = get_tree().root

func _ready() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("[Summoning menu FAIL] " + label)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--live": live = true
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	get_tree().create_timer(60).timeout.connect(func() -> void: get_tree().quit(1))
	root.size = Vector2i(1280, 720)
	root.position = Vector2i(-10000, -10000)
	var game: Node
	var menu: InventoryMenu
	if live:
		root.get_node("SceneTravel").set("_player", null)
		var world: Node = load("res://scenes/EastOutskirtsLayered.tscn").instantiate()
		root.add_child(world)
		get_tree().current_scene = world
		game = world.get_node("Combat")
		game.set_physics_process(false)
		menu = game.inventory_menu
		world.get_node("MapCamera").zoom = Vector2(4, 4)
	else:
		game = Fixture.new()
		root.add_child(game)
		menu = InventoryMenu.new()
		game.add_child(menu)
		menu.configure(game)
	menu.visible = true
	check(menu.has_method("select_summon"), "Journal exposes summon selection")
	check(menu.tabs.get_tab_count() == 7, "All six existing pages plus Summoning")
	if failures > 0:
		get_tree().quit(1)
		return
	check(menu.get_parent() is CanvasLayer and menu.get_parent().layer > 80, "Journal stays above chat and food HUD")
	var player: PlayerState = game.player
	var mana := player.current_mana
	var spell := player.selected_spell_id
	menu.select_page(6)
	await get_tree().process_frame
	await get_tree().process_frame
	check(menu.tabs.get_tab_title(menu.tabs.current_tab) == "Summoning", "Summoning routes to the new page")
	check(menu.tabs.get_tab_title(2) == "Spells" and menu.tabs.get_tab_title(3) == "Summoning", "Summoning appears beside Spells")
	menu.tabs.current_tab = 0
	menu.tabs.current_tab = 3
	check(menu.selected_page == 6, "Native tab clicks route to the preserved page IDs")
	var roster: Array = menu.get("summon_catalog")
	check(roster.size() == 7, "Seven summon concepts")
	for entry: Dictionary in roster:
		menu.call("select_summon", String(entry.id))
		await get_tree().process_frame
		var title := menu.find_child("SummonName", true, false) as Label
		check(title != null and title.text == String(entry.name), "Selection updates " + String(entry.name))
		var portrait: Control = menu.find_child("SummonPortrait", true, false)
		check(portrait != null and portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Crisp portrait " + String(entry.id))
		if portrait != null:
			var frames: Array = portrait.get("frames")
			check(frames.size() > 1, "Animated idle " + String(entry.id))
			portrait.call("_process", 0.2)
			check(int(portrait.get("frame_index")) > 0, "Idle playback advances " + String(entry.id))
			for frame: Dictionary in frames:
				check(ResourceLoader.exists(String(frame.src)), "Portrait source exists")
	var summon := menu.find_child("SummonAction", true, false) as Button
	check(summon != null and summon.disabled, "Unavailable gameplay cannot spend mana or spawn actors")
	menu.call("select_summon", "invalid")
	check(menu.get("selected_summon_id") == "abyssal_fiend", "Invalid selection retains current summon")
	menu.select_page(2)
	check(menu.tabs.get_tab_title(menu.tabs.current_tab) == "Spells", "Original spellbook still accessible")
	menu.select_page(5)
	check(menu.tabs.get_tab_title(menu.tabs.current_tab) == "Captain's Ledger", "Existing page IDs preserved")
	menu.select_page(6)
	check(menu.get("selected_summon_id") == "abyssal_fiend", "Selection survives changing tabs")
	check(player.current_mana == mana and player.selected_spell_id == spell, "Browsing leaves mana and readied spell unchanged")
	await get_tree().process_frame
	await get_tree().process_frame
	if live and not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("summoning-menu-world.png"))
	root.size = Vector2i(1024, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	check(menu.panel.get_global_rect().end.x <= root.size.x, "Journal fits smaller window")
	check(menu.tabs.get_global_rect().end.x <= menu.panel.get_global_rect().end.x, "Tabs stay inside panel")
	if live and not output.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("summoning-menu-1024.png"))
	print("[Summoning menu] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
