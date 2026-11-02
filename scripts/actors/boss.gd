class_name Boss
extends RefCounted
## Boss: health bar, moves between covers, two+ attack patterns, optional second phase.

var game: Node
var spec: Dictionary
var zone: Zone
var c: Character
var parent: Node3D
var is_enemy := true
var is_boss := true
var is_civilian := false
var kind := "boss"
var max_hp := 30
var hp := 30
var alive := true
var down := false
var removed := false
var phase := 0
var covers: Array = []
var cover_idx := 0
var pattern_idx := 0
var state := "wait"
var t := 0.0
var threat = null
var move_from := Vector3.ZERO
var move_to := Vector3.ZERO
var move_dur := 1.0
var rolling := false
var burst_n := 0
var burst_count := 3
var burst_gap := 0.14
var thrown := false
var extra_throw := false
var jump_from := Vector3.ZERO
var jump_to := Vector3.ZERO

func _init(g: Node, s: Dictionary, z: Zone) -> void:
	game = g; spec = s; zone = z
	c = game.pools.take_character(String(s.get("model", "suit")), {"outfit": Enemy.OUTFITS.get(String(s.get("outfit", "boss1")), Enemy.OUTFITS["boss1"]),
		"weapon": s.get("weapon", "smg"), "rim": true, "rim_color": Color("#ffe3a0"), "rim_strength": 0.7, "saturate": true})
	c.scale = Vector3.ONE * 1.08
	max_hp = int(s.get("hp", 30)); hp = max_hp
	for cv in s["covers"]: covers.append(U.v3(cv))
	parent = z.rig if s.get("rig", false) else z.dynamic_root

func cam_w() -> Vector3:
	return game.camera.global_position

func _set_state(s: String) -> void:
	state = s; t = 0.0

func begin() -> void:
	parent.add_child(c)
	c.scale = Vector3.ONE * 1.08
	c.position = U.v3(spec.get("start", spec["covers"][0]))
	c.face_towards(cam_w())
	c.play(String(spec.get("introAnim", "fold_arms")))
	_set_state("intro")
	game.ui.boss_bar(String(spec["name"]), 1.0)

func patterns() -> Array:
	if phase == 1 and spec.has("phase2") and spec["phase2"].has("patterns"):
		return spec["phase2"]["patterns"]
	return spec.get("patterns", ["burst", "grenade"])

func next_cover() -> Vector3:
	cover_idx = (cover_idx + 1 + randi() % maxi(1, covers.size() - 1)) % covers.size()
	return covers[cover_idx]

func update(dt: float) -> void:
	if removed: return
	t += dt
	match state:
		"intro":
			c.face_towards(cam_w(), 0.1)
			if t > float(spec.get("introTime", 2.2)): go_to_cover()
		"move":
			var u := minf(1.0, t / move_dur)
			c.position = move_from.lerp(move_to, (1.0 - (1.0 - u) * (1.0 - u)) if rolling else u)
			if not rolling: c.face_towards(parent.to_global(move_to), 0.25)
			if u >= 1.0: c.pose("crouch", 0.3); _set_state("duck")
		"duck":
			c.face_towards(cam_w(), 0.2)
			if t > (0.55 if phase else 0.85): attack()
		"aim":
			c.face_towards(cam_w(), 0.2)
			if threat != null and not game.paused:
				threat["remaining"] -= dt
				if threat["remaining"] <= 0.0: fire_burst()
		"burst":
			if t > burst_gap * burst_n and burst_n < burst_count:
				burst_n += 1
				var m := c.muzzle()
				game.fx.muzzle(m, 1.4)
				Sfx.play("boss_mg", 0.8)
			if burst_n >= burst_count and t > burst_gap * burst_count + 0.25: go_to_cover()
		"throw":
			if t > 0.55 and not thrown:
				thrown = true; game.spawn_grenade(c.bone_pos("WristR"), 1.6 if phase else 1.9)
			if t > 0.95 and extra_throw:
				extra_throw = false; game.spawn_grenade(c.bone_pos("WristR"), 2.1, 1.5)
			if t > 1.5: go_to_cover()
		"stagger":
			if t > 0.5: go_to_cover()
		"phase":
			var u := minf(1.0, t / 1.0)
			c.position = jump_from.lerp(jump_to, u)
			c.position.y = lerpf(jump_from.y, jump_to.y, u) + sin(u * PI) * 1.4
			c.face_towards(cam_w(), 0.2)
			if u >= 1.0:
				c.play("land", false, 0.1, 1.0, 0.25); Sfx.play("thud"); _set_state("stagger"); t = -0.2
		"dying":
			if t > 3.2: c.set_opacity(maxf(0.0, 1.0 - (t - 3.2) / 0.6))
			if t > 3.85: remove()
	if removed: return
	c.step(dt)
	if alive: c.update_hit_shapes()
	else: c.hit_shapes.clear()

func go_to_cover() -> void:
	threat = null
	move_from = c.position
	move_to = next_cover()
	var d := move_from.distance_to(move_to)
	rolling = patterns().has("roll") and randf() < 0.5 and d < 7.0
	move_dur = 0.9 if rolling else maxf(0.5, d / 4.8)
	c.play("Roll" if rolling else "Run", true, 0.2, 1.1 if rolling else 1.0)
	if rolling: c.rotation.y = atan2(move_to.x - move_from.x, move_to.z - move_from.z)
	_set_state("move")

func attack() -> void:
	var pats := patterns()
	var p := String(pats[pattern_idx % pats.size()])
	pattern_idx += 1
	if p == "grenade":
		c.play("throw", false, 0.1); thrown = false; extra_throw = phase == 1; _set_state("throw")
	elif p == "summon":
		for s in spec.get("summon", []): game.spawn_enemy(s.duplicate(true), zone)
		c.play("call", false); _set_state("stagger"); t = -1.0
	else:
		c.play("Idle_Gun_Pointing", true, 0.15)
		var d: float = game.threat_duration(0) * (0.95 if p == "mg" else 0.75) * (0.85 if phase else 1.0)
		threat = {"remaining": d, "duration": d}
		burst_count = 6 if p == "mg" else 3
		burst_gap = 0.09 if p == "mg" else 0.14
		_set_state("aim")

func fire_burst() -> void:
	threat = null
	burst_n = 0
	c.play("Idle_Gun_Shoot", true, 0.1, 1.6)
	_set_state("burst")
	game.enemy_attack(self, "shot")

func hit(part: String, point: Vector3) -> bool:
	if not alive or state == "phase" or (state == "intro" and t < 0.5): return false
	var dmg: int = {"head": 3, "torso": 2, "legs": 1, "weapon": 2}.get(part, 1)
	hp = maxi(0, hp - dmg)
	game.fx.fabric(point, Color("#f0e6d0"))
	Sfx.play("ricochet" if part == "weapon" else "hit_body", 0.8)
	game.ui.boss_bar(String(spec["name"]), float(hp) / max_hp)
	game.on_boss_hurt(self, part, point)
	if hp <= 0:
		defeat(); return true
	if spec.has("phase2") and phase == 0 and hp <= max_hp * 0.5:
		start_phase2(); return true
	if state == "aim" or state == "duck" or state == "intro":
		threat = null
		c.hit_react()
		_set_state("stagger")
	return true

func start_phase2() -> void:
	phase = 1; threat = null
	var p2: Dictionary = spec["phase2"]
	var new_parent: Node3D = zone.rig if p2.get("rig", false) else zone.dynamic_root
	c.reparent(new_parent, true)
	parent = new_parent
	covers.clear()
	for cv in p2["covers"]: covers.append(U.v3(cv))
	jump_from = c.position
	jump_to = covers[0]
	c.play("Run", true, 0.2, 0.7)
	_set_state("phase")
	game.ui.callout(String(p2.get("callout", "שלב שני!")), "warn")

func defeat() -> void:
	alive = false; down = true; threat = null
	c.play("death_back", false, 0.1)
	_set_state("dying")
	game.on_boss_defeated(self)

func remove() -> void:
	if removed: return
	removed = true
	game.pools.give_character(c)

func ring_anchor() -> Vector3:
	return c.bone_pos("Chest")

func root_global() -> Vector3:
	return c.global_position
