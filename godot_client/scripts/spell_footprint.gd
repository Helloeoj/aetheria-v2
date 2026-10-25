class_name SpellFootprint
extends RefCounted
## Shared by combat and the development preview. Area sizes are provisional.
## Existing area spells ignore walls; do not substitute movement walkability here.

static func grid_for(world: Variant) -> HiddenGrid:
	if world is WorldState:
		return world.cell_grid
	var fallback := HiddenGrid.new()
	fallback.configure(Vector2.ZERO, Vector2(-1000000,-1000000), Vector2(1000000,1000000))
	return fallback

static func cells(grid: HiddenGrid, anchor: Vector2i, spell: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var shape := String(spell.get("area_shape", "circle"))
	if shape == "offsets":
		var offsets: Variant = spell.get("area_offsets", [])
		if not offsets is Array or offsets.size() > 4096:
			return result
		for offset: Variant in offsets:
			if not offset is Array or offset.size() != 2:
				return []
			for value: Variant in offset:
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)) or absf(float(value)) > 64:
					return []
			var cell := anchor + Vector2i(int(offset[0]), int(offset[1]))
			if grid.contains(grid.center(cell)) and not result.has(cell):
				result.append(cell)
	elif shape == "circle":
		var radius := float(spell.get("area_radius", 0.0))
		if not is_finite(radius) or radius < 0.0 or radius > 64.0:
			return result
		var extent := int(floor(radius))
		for y in range(-extent, extent + 1):
			for x in range(-extent, extent + 1):
				var cell := anchor + Vector2i(x,y)
				if x*x + y*y <= radius*radius + 0.00000001 and grid.contains(grid.center(cell)):
					result.append(cell)
	result.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result

static func encode(cells_value: Array[Vector2i]) -> Array:
	var result: Array = []
	for cell: Vector2i in cells_value:
		result.append([cell.x,cell.y])
	return result
