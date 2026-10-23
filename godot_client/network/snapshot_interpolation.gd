extends RefCounted
## Timestamped interpolation holds on packet loss and resets on teleports.
var _samples: Array[Dictionary] = []

func push(time: float, position: Vector2) -> void:
	if not _samples.is_empty():
		if time <= float(_samples.back().time):
			return
		if position.distance_to(_samples.back().position) > 2.0:
			_samples.clear()
	_samples.append({"time": time, "position": position})
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
	return first.position.lerp(second.position, weight)
