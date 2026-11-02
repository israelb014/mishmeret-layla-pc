class_name U
extends RefCounted
## Small helpers shared by all systems.

## Colour from JSON data: 0xRRGGBB number, "#rrggbb" string, or Color.
static func col(v) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color(v)
	var i := int(v)
	return Color8((i >> 16) & 255, (i >> 8) & 255, i & 255)

static func v3(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

## tint data from JSON ({pattern: 0xRRGGBB} or a number) -> Godot form
static func tint(t):
	if t == null:
		return null
	if t is Dictionary:
		var d := {}
		for k in t.keys():
			if t[k] != null:
				d[k] = col(t[k])
		return d
	return col(t)

static func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

static func smoother(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

static func load_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

## xorshift RNG with a deterministic seed (same layouts as the browser edition)
class Rng:
	var s: int
	func _init(seed: int) -> void:
		s = seed & 0xffffffff
		if s == 0: s = 1
	func next() -> float:
		s ^= (s << 13) & 0xffffffff
		s ^= (s >> 17)
		s ^= (s << 5) & 0xffffffff
		s &= 0xffffffff
		return float(s % 100000) / 100000.0
	func pick(arr: Array):
		return arr[int(next() * arr.size()) % arr.size()]
