extends Node
const Population = preload("res://scripts/valtherian_population.gd")
const RATES := {"Bronze":15.0,"Iron":12.0,"Steel":12.0,"Blacksteel":8.0,"Mithril":10.0,"Adamantite":7.0}
var failures: Array[String] = []
func _ready() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("[Dungeon loot FAIL] " + label)
func _run() -> void:
	var table: Dictionary = GameData.loot_data.get("dungeons", {}).get("valtherian_mines", {})
	check(not table.is_empty(), "dungeon runtime table exists")
	if table.is_empty():
		get_tree().quit(1)
		return
	var loot := LootSystem.new()
	loot.random.seed = 20261104
	var weights: Dictionary = {}
	var declared: Dictionary = {}
	var total := 0.0
	for entry: Dictionary in table.common.outcomes:
		total += float(entry.chance)
		if entry.item == null: continue
		var item := GameData.get_item_by_name(String(entry.item))
		check(not item.is_empty(), "catalog item exists: " + String(entry.item))
		declared[String(item.name)] = String(entry.armor_tier)
		weights[entry.armor_tier] = float(weights.get(entry.armor_tier, 0.0)) + float(entry.chance)
	check(is_equal_approx(total,100.0), "weights total 100")
	for material: String in RATES:
		check(is_equal_approx(float(weights.get(material,0)),RATES[material]), "exact rate: " + material)
	var seen_templates: Dictionary = {}
	for encounter: Array in Population.ENCOUNTERS:
		var id := int(encounter[0])
		if seen_templates.has(id): continue
		seen_templates[id] = true
		var monster := MonsterState.new(GameData.monsters_by_id[id],0,0)
		monster.set_meta("dungeon_loot_table","valtherian_mines")
		var capped := loot._get_monster_loot_table(monster)
		var maximum := int(table.max_tier_by_monster[monster.name])
		check(not capped.is_empty(), "all dungeon templates have a runtime table")
		var seen_items: Dictionary = {}
		var seen: Dictionary = {}
		var counts: Dictionary = {}
		for attempt in 5000:
			var result := loot.roll_monster_loot(monster)
			check(int(result.gold)>0 and result.items.size()<=1,"tier gold and at most one armor drop")
			for drop: Dictionary in result.items:
				var name := String(drop.item.name)
				check(declared.has(name) and int(drop.quantity)==1,"only declared single armor pieces")
				check(loot.Acquisition.can_drop(drop.item,monster),"real acquisition rules allow armor")
				seen_items[name] = true
				seen[String(drop.item.slot)] = true
				check(int(drop.item.tier)<=maximum,"difficulty limits armor tiers")
				var material: String = declared[name]
				counts[material] = int(counts.get(material,0))+1
		for material: String in RATES:
			var tier := RATES.keys().find(material)+1
			var expected := float(RATES[material]) if tier<=maximum else 0.0
			check(absf(float(counts.get(material,0))/50.0-expected)<2.0,"seeded difficulty rate: " + material)
		for item_name: String in declared:
			var item := GameData.get_item_by_name(item_name)
			check(seen_items.has(item_name) == (int(item.tier)<=maximum),"all and only eligible pieces actually drop: " + item_name)
		for slot: String in ["head","chest","legs","shield","cape"]:
			check(seen.has(slot),"complete usable armor slots")
		monster.set_meta("suppress_loot",true)
		check(loot.roll_monster_loot(monster)=={"gold":0,"items":[]},"explicit suppression still honored")
	check(loot._get_monster_loot_table(GameData.get_monster_by_name("Goblin Scout")) != table,"outside dungeon loot unchanged")
	print("[Dungeon loot] %d templates; %d failures" % [seen_templates.size(),failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
