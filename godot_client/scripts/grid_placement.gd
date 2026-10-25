class_name GridPlacement
extends RefCounted
## No blind rounding, clamping through walls, or guessing a different floor.
## A failed migration leaves durable data untouched for recovery by the owner.
static func resolve(grid: HiddenGrid, point: Vector2) -> Vector2:
	if not point.is_finite():
		return Vector2(INF,INF)
	var recovered: Variant = grid.recovery_cell(point)
	return grid.center(recovered) if recovered != null else Vector2(INF,INF)
