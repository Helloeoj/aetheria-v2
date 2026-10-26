extends RefCounted
## Resolves future configured anchors through existing authored interaction APIs.
## There are deliberately no production anchors or guessed coordinates here.
const Approach := preload("res://scripts/interaction_approach.gd")

static func resolve(game: Node, config: Dictionary, region_id: String, anchor_id: String) -> Dictionary:
	if game == null or not is_instance_valid(game) or not game is Node2D or game.get_parent() == null:
		return {}
	var anchor: Dictionary = config.get("anchors",{}).get(anchor_id,{})
	if anchor.is_empty() or anchor.get("region_id") != region_id:
		return {}
	var target := game.get_parent().get_node_or_null(NodePath(String(anchor.get("node_path","")))) as Node2D
	if target == null:
		return {}
	return Approach.describe(game,target,String(anchor.get("interaction_kind","")))

static func context(game: Node, config: Dictionary, region_id: String, anchor_id: String, player: PlayerState, world: WorldState) -> Dictionary:
	var approach := resolve(game,config,region_id,anchor_id)
	var nearby := not approach.is_empty() and Approach.in_range(world,player,approach)
	if nearby:
		nearby = world.has_line_of_sight(player.get_position(),approach.point)
	return {"region_id":region_id,"anchor_id":anchor_id,"in_range":nearby}

static func nearest(game: Node, config: Dictionary, region_id: String, player: PlayerState, world: WorldState) -> String:
	var selected := ""
	var best := INF
	for id: String in config.get("anchors",{}):
		var approach := resolve(game,config,region_id,id)
		if approach.is_empty() or not context(game,config,region_id,id,player,world).in_range:
			continue
		var distance := player.get_position().distance_to(approach.point)
		if distance < best:
			selected = id
			best = distance
	return selected
