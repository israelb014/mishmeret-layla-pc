class_name Enemy
extends RefCounted
## Enemy AI — one class, behaviour chosen by spawn "kind" (port of the browser edition).

const OUTFITS := {
	"yellow": {"0": 0xffd21f, "1": 0xffd21f, "2": 0x3b3b3b, "Suit": 0xffd21f, "Black": 0x2b2b2b},
	"purple": {"0": 0x7b2fd0, "1": 0x7b2fd0, "2": 0x2a2a2a, "Suit": 0x7b2fd0},
	"red": {"0": 0xd62828, "1": 0xd62828, "2": 0x222222, "Suit": 0xd62828},
	"teal": {"0": 0x14b8a6, "1": 0x14b8a6, "2": 0x1f2937, "Suit": 0x14b8a6},
	"white": {"0": 0xf5f5f5, "1": 0xf5f5f5, "2": 0x1f1f1f, "Suit": 0xf5f5f5, "Tie": 0xd62828},
	"leather": {"0": 0x3a2418, "1": 0x2e5aa8, "2": 0xf0f0f0},
	"orange": {"0": 0xff7a1a, "1": 0xff7a1a, "2": 0x2b2b2b, "Suit": 0xff7a1a},
	"armor": {"0": 0x3d4a2f, "1": 0x7a1f1f},
	"boss1": {"Suit": 0xf3efe2, "Black": 0x5a1010, "Tie": 0xd4af37},
	"boss2": {"0": 0x2b3a55, "1": 0xd1501a, "2": 0x2b2b2b, "3": 0x3a2a1a},
	"boss3": {"0": 0x111111, "1": 0xe11d74, "2": 0x111111},
}
const DEATHS := ["death_back", "death_fwd", "Death", "spin"]

var game: Node
var spec: Dictionary
var zone: Zone
var kind: String
var c: Character
var parent: Node3D
var is_enemy := true
var is_boss := false
var is_civilian := false
var hp := 1
var state := "wait"
var t := 0.0
var shots_fired := 0
var threat = null # {remaining, duration}
var alive := true
var down := false
var removed := false
var escaped := false
var pos := Vector3.ZERO
var from := Vector3.ZERO
var enter_dur := 1.0
var hide_time := 0.5
var jump_dur := 0.75
var knife_start := 1.0
var stabbed := false
var thrown := false
var spinning := false
var car: Node3D
var hostage = null
var window_start := Vector3.ZERO

func _init(g: Node, s: Dictionary, z: Zone) -> void:
	game = g; spec = s; zone = z
	kind = String(s.get("kind", "popup"))
	var weapon = s.get("weapon")
	if weapon == null:
		weapon = "knife" if kind == "knife" else (null if kind == "grenade" else ("smg" if kind == "heavy" else "pistol"))
	var model := String(s.get("model", "swat" if kind == "heavy" else "punk"))
	var outfit: Dictionary = OUTFITS.get(String(s.get("outfit", "armor" if kind == "heavy" else "yellow")), OUTFITS["yellow"])
	c = game.pools.take_character(model, {"outfit": outfit, "weapon": weapon, "rim": true, "rim_color": U.col(game.stage.get("rim", 0xfff2d6)), "rim_strength": float(game.stage.get("rimStrength", 0.5)), "saturate": true})
	hp = int(s.get("hp", 3 if kind == "heavy" else 1))
	parent = z.rig if s.get("rig", false) else z.dynamic_root
	pos = U.v3(s.get("pos", [0, 0, -10]))
	from = U.v3(s["from"]) if s.has("from") else pos
	c.visible = false

func cam_local() -> Vector3:
	return parent.to_local(game.camera.global_position)

func begin() -> void:
	parent.add_child(c)
	c.visible = true
	match kind:
		"popup", "grenade":
			_start_hidden()
		"heavy" when spec.get("cover", false):
			_start_hidden()
		"window":
			if from == pos:
				var cl := cam_local()
				var yaw := atan2(cl.x - pos.x, cl.z - pos.z)
				c.position = pos + Vector3(0, 0, -0.9).rotated(Vector3.UP, yaw)
			else:
				c.position = from
			window_start = c.position
			c.play("Idle_Gun_Pointing")
			_set_state("enter"); enter_dur = 0.5
		"jumpdown":
			c.position = from
			c.play("Idle_Gun")
			_set_state("prejump")
		"driveby":
			_setup_driveby()
		"hostage":
			_setup_hostage()
		_:
			c.position = from
			var anim := {"roll": "Roll", "knife": "sprint", "runacross": "Run_Shoot", "heavy": "Walk"}.get(kind, "Run")
			c.play(anim, true, 0.2, 1.15 if kind == "roll" else 1.0)
			if kind == "knife": c.face_towards(parent.to_global(cam_local()))
			else: c.face_towards(parent.to_global(pos))
			if kind == "roll": c.rotation.y = atan2(pos.x - from.x, pos.z - from.z)
			_set_state("enter")
			var spd: float = {"runout": 5.2, "roll": 4.2, "runacross": 4.6, "knife": 5.6, "heavy": 2.2}.get(kind, 5.0)
			enter_dur = maxf(0.4, from.distance_to(pos) / spd)
			if kind == "roll": enter_dur = minf(enter_dur, 1.0)
			if kind == "runacross": start_threat(game.threat_duration(0) * 0.9)
			if kind == "knife":
				knife_start = from.distance_to(cam_local())
				Sfx.play("knife", 0.5)

func _start_hidden() -> void:
	c.position = pos
	c.face_towards(parent.to_global(cam_local()))
	c.pose("crouch", 0.3)
	_set_state("hidden")
	hide_time = float(spec.get("delay", 0.5))

func _setup_driveby() -> void:
	car = game.prefabs.make(String(spec.get("car", "car_sedan")), {"^(Blue|Red|Green|Yellow|White|Orange|Grey)$": U.col(spec.get("carColor", 0x111111))})
	parent.add_child(car)
	car.position = from
	car.rotation.y = atan2(pos.x - from.x, pos.z - from.z)
	var side := float(spec.get("side", 1))
	c.reparent(car, false)
	c.position = Vector3(side * 0.55, -0.45, -0.3)
	c.rotation.y = side * PI / 2.0
	c.play("Idle_Gun_Pointing")
	_set_state("drive")
	enter_dur = from.distance_to(pos) / float(spec.get("speed", 9))
	start_threat(game.threat_duration(0) * 0.85)
	Sfx.play("screech", 0.45)

func _setup_hostage() -> void:
	c.position = pos
	c.face_towards(parent.to_global(cam_local()))
	hostage = game.spawn_civilian({"kind": "hostage", "model": spec.get("hostage", "woman"), "pos": [0, 0, 0]}, zone, parent)
	var fwd := Vector3(sin(c.rotation.y), 0, cos(c.rotation.y))
	var right := Vector3(fwd.z, 0, -fwd.x)
	hostage.c.position = pos + fwd * 0.42 - right * 0.1
	hostage.c.rotation.y = c.rotation.y
	c.position += right * 0.22
	c.play("Idle_Gun_Pointing")
	_set_state("aim")
	start_threat(game.threat_duration(0) * 1.15)

func _set_state(s: String) -> void:
	state = s; t = 0.0

func start_threat(d: float) -> void:
	threat = {"remaining": d, "duration": d}

func update(dt: float) -> void:
	if removed: return
	t += dt
	var cam := cam_local()
	var cam_w := parent.to_global(cam)
	match state:
		"hidden":
			if t > hide_time:
				c.play("Idle_Neutral" if kind == "grenade" else "Idle_Gun_Pointing", true, 0.25)
				c.face_towards(cam_w)
				if kind == "grenade": _set_state("throw")
				else:
					_set_state("aim")
					start_threat(game.threat_duration(shots_fired))
		"prejump":
			if t > float(spec.get("delay", 0.4)):
				c.play("Run", true, 0.2, 0.6); _set_state("jump"); jump_dur = 0.75
		"jump":
			var u := minf(1.0, t / jump_dur)
			c.position = from.lerp(pos, u)
			c.position.y = lerpf(from.y, pos.y, u) + sin(u * PI) * 0.8
			c.face_towards(cam_w, 0.2)
			if u >= 1.0:
				c.play("land", false, 0.05, 1.0, 0.25); _set_state("landing"); Sfx.play("thud", 0.6)
		"landing":
			if t > 0.55:
				c.play("Idle_Gun_Pointing"); _set_state("aim"); start_threat(game.threat_duration(shots_fired))
		"enter":
			var u := minf(1.0, t / enter_dur)
			if kind == "window":
				c.position = window_start.lerp(pos, u)
				c.face_towards(cam_w, 0.3)
			elif kind == "knife":
				var target := Vector3(cam.x, 0, cam.z)
				var dir := target - c.position; dir.y = 0
				var dist := dir.length()
				c.position += dir.normalized() * minf(dist, 5.6 * dt)
				c.face_towards(cam_w, 0.3)
				threat = {"remaining": maxf(0.0, dist - 2.0) / 5.6, "duration": knife_start / 5.6, "knife": true}
				if dist < 2.2:
					c.play("slash", false, 0.08); _set_state("stab")
				_finish(dt)
				return
			else:
				c.position = from.lerp(pos, (1.0 - (1.0 - u) * (1.0 - u)) if kind == "roll" else u)
				if kind != "roll": c.face_towards(parent.to_global(pos), 0.25)
				if kind == "runacross" and threat != null: tick_threat(dt, true)
			if u >= 1.0:
				if kind == "runacross":
					escape()
				else:
					c.play("Idle_Gun_Pointing", true, 0.2); _set_state("aim")
					start_threat(game.threat_duration(shots_fired) * (0.9 if kind == "heavy" else 1.0))
		"stab":
			if t > 0.35 and not stabbed:
				stabbed = true; game.enemy_attack(self, "knife")
			if t > 1.0: escape()
		"drive":
			var u := minf(1.0, t / enter_dur)
			car.position = from.lerp(pos, u)
			if alive:
				var cl := car.to_local(game.camera.global_position)
				c.rotation.y = atan2(cl.x - c.position.x, cl.z - c.position.z)
				tick_threat(dt, true)
			if u >= 1.0:
				car.visible = false
				if alive: escape()
				else: remove()
		"throw":
			if t - dt <= 0.0: c.play("throw", false, 0.15)
			c.face_towards(cam_w, 0.2)
			if t > 0.55 and not thrown:
				thrown = true
				game.spawn_grenade(c.bone_pos("WristR"), float(spec.get("grenadeTime", 1.9)))
			if t > 1.4: c.pose("crouch", 0.3); _set_state("cover")
		"cover":
			if t > float(spec.get("rethrow", 2.4)):
				var throws := int(spec.get("throws", 2))
				if kind == "grenade" and throws > 1:
					spec["throws"] = throws - 1; thrown = false; c.play("Idle_Neutral"); _set_state("throw")
				elif kind == "grenade":
					c.attach_weapon(game, "pistol"); c.play("Idle_Gun_Pointing"); kind = "popup"; _set_state("aim"); start_threat(game.threat_duration(1))
				else:
					c.play("Idle_Gun_Pointing", true, 0.2); _set_state("aim"); start_threat(game.threat_duration(shots_fired))
		"aim":
			c.face_towards(cam_w, 0.15)
			if tick_threat(dt): fire()
		"firing":
			if t > 0.35:
				if (kind == "popup" or spec.get("duck", false)) and spec.get("duck", true) != false:
					c.pose("crouch", 0.3); _set_state("cover"); spec["rethrow"] = 0.9 + randf() * 0.8
				else:
					_set_state("aim"); start_threat(game.threat_duration(shots_fired))
		"stagger":
			if t > 0.45:
				c.play("Idle_Gun_Pointing", true, 0.2); _set_state("aim")
				if threat == null: start_threat(game.threat_duration(shots_fired))
		"dying":
			if spinning: c.rotation.y += dt * 9.0 * maxf(0.0, 1.0 - t / 0.7)
			if t > 1.6: c.set_opacity(maxf(0.0, 1.0 - (t - 1.6) / 0.6))
			if t > 2.25: remove()
		"surrender":
			c.face_towards(cam_w, 0.1)
			if t > 1.7: c.set_opacity(maxf(0.0, 1.0 - (t - 1.7) / 0.5))
			if t > 2.25: remove()
		"kneel":
			if t > 1.8: c.set_opacity(maxf(0.0, 1.0 - (t - 1.8) / 0.5))
			if t > 2.35: remove()
		"escape":
			c.set_opacity(maxf(0.0, 1.0 - t / 0.4))
			if t > 0.45: remove()
	_finish(dt)

func _finish(dt: float) -> void:
	if removed: return
	c.step(dt)
	if alive: c.update_hit_shapes()
	else: c.hit_shapes.clear()

func tick_threat(dt: float, no_fire := false) -> bool:
	if threat == null or game.paused: return false
	threat["remaining"] -= dt
	if threat["remaining"] <= 0.0:
		if no_fire:
			fire(true)
			var d: float = game.threat_duration(shots_fired)
			threat = {"remaining": d, "duration": d}
			return false
		return true
	return false

func fire(keep_state := false) -> void:
	shots_fired += 1
	threat = null
	if not keep_state:
		c.play("Idle_Gun_Shoot", false, 0.05); _set_state("firing")
	var m := c.muzzle()
	game.fx.muzzle(m, 1.3 if kind == "heavy" else 1.0)
	Sfx.play("boss_mg" if kind == "heavy" else "enemy_shot", 0.75)
	game.enemy_attack(self, "shot")

## returns true if this hit consumed the bullet
func hit(part: String, point: Vector3) -> bool:
	if not alive: return false
	game.fx.fabric(point, Color("#ffd27a") if part == "weapon" else Color("#e8e0d0"))
	if part == "weapon":
		if kind == "knife" or c.weapon_name == "":
			part = "torso"
		else:
			game.fx.sparks(point, Vector3.UP, 8)
			Sfx.play("ricochet", 0.7)
			disarm()
			game.on_enemy_neutralized(self, "weapon", point)
			return true
	if kind == "heavy" and part == "torso" and hp > 1:
		hp -= 1
		game.fx.sparks(point, Vector3.BACK, 6)
		Sfx.play("metal", 0.6)
		game.on_enemy_hurt(self, point)
		c.hit_react()
		_set_state("stagger")
		return true
	Sfx.play("hit_body", 0.7)
	if part == "legs": kneel()
	else: die(part)
	game.on_enemy_neutralized(self, part, point)
	return true

func neutralize() -> void:
	alive = false; down = true; threat = null
	if hostage != null: hostage.release()

func disarm() -> void:
	neutralize()
	if c.weapon:
		var p := c.weapon.global_position
		var wn := c.weapon_name
		c.detach_weapon()
		game.fly_away(game.prefabs.make(wn), p)
	c.play("Idle_Neutral", true, 0.15)
	c.set_surrender(1.0)
	_set_state("surrender")

func kneel() -> void:
	neutralize()
	c.pose("kneel", 0.12)
	_set_state("kneel")

func die(part: String, forced := "") -> void:
	neutralize()
	var d := forced if forced != "" else ("death_back" if part == "head" else String(DEATHS[randi() % DEATHS.size()]))
	spinning = d == "spin"
	if d == "spin": d = "death_fwd"
	if car != null: d = "HitRecieve"
	c.play(d, false, 0.08)
	_set_state("dying")

func escape() -> void:
	alive = false; down = true; threat = null; escaped = true
	_set_state("escape")

func remove() -> void:
	if removed: return
	removed = true; alive = false; down = true
	game.pools.give_character(c)
	if car: car.queue_free()

func ring_anchor() -> Vector3:
	return c.bone_pos("Chest")

func root_global() -> Vector3:
	return c.global_position
