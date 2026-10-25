extends RefCounted
## Timestamped interpolation holds on packet loss and resets on teleports.
var _samples: Array[Dictionary] = []

func push(time: float, position: Vector2, travel: Dictionary = {}) -> void:
	if not is_finite(time) or not position.is_finite():
		return
	var points := PackedVector2Array()
	if not _samples.is_empty():
		if time <= float(_samples.back().time):
			return
		var previous: Dictionary = _samples.back()
		var history: Array = travel.get("trail", [])
		var first_serial := int(previous.get("arrival", 0))
		var last_serial := int(travel.get("arrival", 0))
		var complete := not travel.is_empty() and (last_serial == first_serial or (not history.is_empty() and int(history[0].serial) <= first_serial + 1))
		if int(travel.get("epoch", 0)) != int(previous.get("epoch", 0)) or (not complete and position.distance_to(previous.position) > 2.0):
			_samples.clear()
		else:
			points.append(previous.position)
			if not travel.is_empty() and not complete:
				# Missing turns must never become a diagonal shortcut through a wall.
				points.clear()
			else:
				for entry: Dictionary in history:
					if int(entry.serial) > first_serial and int(entry.serial) <= last_serial:
						points.append(Vector2(float(entry.point[0]), float(entry.point[1])))
				points.append(position)
	_samples.append({"time": time, "position": position, "path": points,
		"epoch": int(travel.get("epoch", 0)), "arrival": int(travel.get("arrival", 0))})
	if _samples.size() > 32:
		_samples.pop_front()

func sample(time: float) -> Vector2:
	if _samples.is_empty():
		return Vector2.ZERO
	while _samples.size() > 2 and float(_samples[1].time) <= time:
		_samples.pop_front()
	var first: Dictionary = _samples[0]
	if time <= float(first.time) or _samples.size() == 1:
		return first.position
	var second: Dictionary = _samples[1]
	var weight := clampf((time - float(first.time)) / (float(second.time) - float(first.time)), 0.0, 1.0)
	var path: PackedVector2Array = second.path
	if path.is_empty():
		return second.position if weight >= 1.0 else first.position
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	var remaining := weight * length
	for index in range(1, path.size()):
		var distance := path[index - 1].distance_to(path[index])
		if remaining <= distance:
			return path[index - 1].move_toward(path[index], remaining)
		remaining -= distance
	return second.position
