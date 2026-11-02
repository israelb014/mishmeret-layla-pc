class_name Civilian
extends RefCounted
## Civilians: walk, freeze, run in panic, cross the line of fire, or be held hostage.

const CIV_OUTFITS := [{"0": 0x4fc3f7, "1": 0xfafafa}, {"0": 0xffb74d, "1": 0x795548}, {"0": 0xe57373, "1": 0x37474f}, {"0": 0x81c784, "1": 0x5d4037},
	{"0": 0xba68c8, "1": 0x263238}, {"0": 0xfff176, "1": 0x1565c0}]

var game: Node
var spec: Dictionary
var zone: Zone
var kind: String
var c: Character
var parent: Node3D
var is_enemy := false
var is_boss := false
var is_civilian := true
var alive := true
var down := false
var removed := false
var rescued := false
var state := "wait"
var t := 0.0
var speed := 1.45
var pos := Vector3.ZERO
var from := Vector3.ZERO
var to := Vector3.ZERO
var threat = null

func _init(g: Node, s: Dictionary, z: Zone, p: Node3D = null) -> void:
	game = g; spec = s; zone = z
	kind = String(s.get("kind", "walk"))
	var model := String(s.get("model", ["beach", "woman", "farmer", "casual"][randi() % 4]))
	var outfit = s.get("outfit", CIV_OUTFITS[randi() % CIV_OUTFITS.size()])
	c = game.pools.take_character(model, {"outfit": outfit, "rim": true, "rim_color": Color("#bfe6ff"), "rim_strength": 0.25})
	parent = p if p != null else (z.rig if s.get("rig", false) else z.dynamic_root)
	pos = U.v3(s.get("pos", s.get("to", [0, 0, -10])))
	from = U.v3(s.get("from", s.get("pos", [0, 0, -10])))
	to = U.v3(s.get("to", s.get("pos", [0, 0, -10])))

func cam_local() -> Vector3:
	return parent.to_local(game.camera.global_position)

func begin() -> void:
	parent.add_child(c)
	if kind == "hostage":
		c.play("Idle_Neutral"); c.set_surrender(0.65); state = "held"; return
	c.position = from
	if kind == "freeze":
		c.position = pos; c.play("crouch"); state = "freeze"; c.face_towards(parent.to_global(cam_local()))
	else:
		var run := kind == "panic" or kind == "cross"
		c.play("sprint" if run else ("walk_formal" if spec.get("formal", false) else "Walk"))
		speed = float(spec.get("speed", 5.2 if run else 1.45))
		state = "move"
		c.face_towards(parent.to_global(to))
		if run and randf() < 0.7:
			Sfx.play("scream" if randf() < 0.5 else "scream2", 0.55)

func panic() -> void:
	if not alive or state != "move" or kind != "walk": return
	kind = "panic"; speed = 5.0; c.play("sprint")

func release() -> void:
	if not alive: return
	c.set_surrender(0.0)
	kind = "panic"
	from = c.position
	var away := c.position - cam_local(); away.y = 0; away = away.normalized()
	var side := Vector3(away.z, 0, -away.x) * (6.0 if randf() < 0.5 else -6.0)
	to = c.position + side + away * 4.0
	c.play("sprint"); speed = 5.2; state = "move"; t = 0.0
	c.face_towards(parent.to_global(to))
	rescued = true

func update(dt: float) -> void:
	if removed: return
	t += dt
	match state:
		"move":
			var dir := to - c.position; dir.y = 0
			var d := dir.length()
			if d < 0.2:
				state = "leaving"; t = 0.0
			else:
				c.position += dir.normalized() * minf(d, speed * dt)
				c.face_towards(parent.to_global(to), 0.2)
		"freeze":
			c.face_towards(parent.to_global(cam_local()), 0.05)
			if t > float(spec.get("hold", 3.5)):
				kind = "panic"; from = c.position
				to = U.v3(spec["to"]) if spec.has("to") else Vector3(pos.x + 8, 0, pos.z - 4)
				c.play("sprint"); speed = 5.0; state = "move"
		"leaving", "hurt":
			var fade_start := 1.6 if state == "hurt" else 0.0
			if t > fade_start: c.set_opacity(maxf(0.0, 1.0 - (t - fade_start) / 0.5))
			if t > fade_start + 0.55: remove()
	if removed: return
	if state == "hurt" and t > 0.35 and c.current != "crouch":
		c.play("crouch", true, 0.3)
	c.step(dt)
	if alive: c.update_hit_shapes()
	else: c.hit_shapes.clear()

func hit(_part: String, point: Vector3) -> bool:
	if not alive: return false
	alive = false
	game.fx.fabric(point, Color("#dfe8ee"))
	c.set_surrender(0.0)
	c.play("HitRecieve_2", false, 0.05)
	state = "hurt"; t = 0.0
	game.on_civilian_hit(self, point)
	return true

func remove() -> void:
	if removed: return
	removed = true; alive = false
	game.pools.give_character(c)

func ring_anchor() -> Vector3:
	return c.bone_pos("Chest")

func root_global() -> Vector3:
	return c.global_position
