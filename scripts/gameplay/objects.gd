class_name Objects
extends RefCounted
## Dynamic gameplay objects: grenades, pickups, branch signs and tumbling debris.

static var icon_cache := {}
static func icon(name: String) -> Texture2D:
	if not icon_cache.has(name):
		icon_cache[name] = load("res://assets/icons/%s.svg" % name)
	return icon_cache[name]

class Grenade:
	extends RefCounted
	var game: Node
	var node: Node3D
	var marker: Sprite3D
	var from: Vector3
	var to: Vector3
	var flight := 1.9
	var t := 0.0
	var alive := true
	var pos := Vector3.ZERO
	var is_grenade := true
	var threat = null
	func _init(g: Node, f: Vector3, dest: Vector3, fl: float) -> void:
		game = g; from = f; to = dest; flight = fl; pos = f
		node = game.prefabs.make("grenade")
		node.scale = Vector3.ONE * 1.6
		marker = Sprite3D.new()
		marker.texture = Objects.icon("grenadeMarker")
		marker.pixel_size = 0.55 / 64.0
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.render_priority = 10
		marker.shaded = false
		node.add_child(marker)
		game.world.add_child(node)
		node.global_position = f
		Sfx.play("grenade_bounce", 0.4)
	func update(dt: float) -> void:
		if not alive: return
		t += dt
		var u := minf(1.0, t / flight)
		pos = from.lerp(to, u)
		pos.y += sin(u * PI) * (2.2 + from.distance_to(to) * 0.08)
		node.global_position = pos
		node.rotation.x += dt * 9.0; node.rotation.z += dt * 5.0
		marker.modulate.a = 0.6 + 0.4 * sin(t * 18.0)
		threat = {"remaining": flight - t, "duration": flight}
		if u >= 1.0:
			alive = false
			game.grenade_landed(self)
			dispose()
	func hit_test(o: Vector3, d: Vector3) -> Dictionary:
		var t2 := Character.ray_capsule(o, d, pos, pos, 0.5)
		return {"t": t2, "point": o + d * t2} if t2 > 0.0 else {}
	func shot() -> void:
		alive = false
		game.fx.explosion(pos, 0.6)
		Sfx.play("explosion2", 0.8)
		dispose()
	func dispose() -> void:
		if is_instance_valid(node): node.queue_free()
	func ring_anchor() -> Vector3:
		return pos

class Pickup:
	extends RefCounted
	var game: Node
	var type: String
	var node := Node3D.new()
	var halo: Sprite3D
	var model: Node3D
	var base: Vector3
	var t := 0.0
	var life := 9.0
	var alive := true
	var is_pickup := true
	func _init(g: Node, ty: String, p: Vector3) -> void:
		game = g; type = ty; base = p
		halo = Sprite3D.new()
		halo.texture = Objects.icon("shieldPickup" if ty == "shield" else "weaponHalo")
		halo.pixel_size = (1.1 if ty == "shield" else 1.3) / 128.0
		halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		halo.shaded = false
		node.add_child(halo)
		if ty != "shield":
			var mname: String = {"mpistol": "smg", "shotgun": "shotgun", "magnum": "revolver"}[ty]
			model = game.prefabs.make(mname)
			model.scale = Vector3.ONE * (1.1 if ty == "shotgun" else 2.2)
			model.position.y = -0.1
			node.add_child(model)
		var l := OmniLight3D.new()
		l.light_color = Color("#ffcf3a") if ty != "shield" else Color("#2ee6ff")
		l.light_energy = 1.2; l.omni_range = 3.0
		node.add_child(l)
		game.world.add_child(node)
		node.global_position = p
	func update(dt: float) -> void:
		if not alive: return
		t += dt
		node.global_position = base + Vector3(0, sin(t * 3.0) * 0.12, 0)
		if model: model.rotation.y += dt * 2.4
		halo.rotation.z += dt * 0.8
		if t > life - 2.0: node.visible = int(t * 8.0) % 2 == 0
		if t > life:
			alive = false; dispose()
	func hit_test(o: Vector3, d: Vector3) -> Dictionary:
		var p := node.global_position
		var t2 := Character.ray_capsule(o, d, p, p, 0.6)
		return {"t": t2, "point": o + d * t2} if t2 > 0.0 else {}
	func dispose() -> void:
		if is_instance_valid(node): node.queue_free()

class BranchSign:
	extends RefCounted
	var game: Node
	var side: String
	var node := Node3D.new()
	var board: Node3D
	var t := 0.0
	var alive := true
	func _init(g: Node, zone: Zone, p: Vector3, rot_y: float, label: String, s: String) -> void:
		game = g; side = s
		node.position = p; node.rotation.y = rot_y
		var post: Node3D = game.prefabs.make("sign_post")
		post.scale = Vector3.ONE * 1.15
		node.add_child(post)
		board = zone.sign_board(label, 2.6, 0.9, {"bg": "#10307a", "fg": "#ffffff", "emissive": 1.2 if zone.night else 0.3})
		board.position = Vector3(0, 2.55, 0.08)
		# arrow (SVG chevron) at the outer end of the board
		var arrow := Sprite3D.new()
		arrow.texture = Objects.icon("back")
		arrow.pixel_size = 0.6 / 64.0
		arrow.flip_h = s == "left"
		arrow.shaded = false
		arrow.position = Vector3(-1.55 if s == "left" else 1.55, 0, 0.02)
		board.add_child(arrow)
		var back := zone.sign_board(label, 2.6, 0.9, {"bg": "#10307a", "fg": "#ffffff"})
		back.position = Vector3(0, 2.55, 0.0); back.rotation.y = PI
		node.add_child(board); node.add_child(back)
		zone.add_child(node)
	func update(dt: float) -> void:
		t += dt
		board.scale = Vector3.ONE * (1.0 + sin(t * 5.0) * 0.04)
	func hit_test(o: Vector3, d: Vector3) -> Dictionary:
		var c := board.global_position
		var right := board.global_basis.x.normalized()
		var t2 := Character.ray_capsule(o, d, c - right * 1.25, c + right * 1.25, 0.5)
		return {"t": t2, "point": o + d * t2} if t2 > 0.0 else {}
	func dispose() -> void:
		if is_instance_valid(node): node.queue_free()

class Flyer:
	extends RefCounted
	var game: Node
	var node: Node3D
	var vel: Vector3
	var av: Vector3
	var life := 1.6
	var t := 0.0
	var alive := true
	func _init(g: Node, n: Node3D, p: Vector3, v: Vector3, l := 1.6) -> void:
		game = g; node = n; vel = v; life = l
		av = Vector3(randf_range(-7, 7), randf_range(-7, 7), randf_range(-7, 7))
		if node.get_parent(): node.reparent(game.world, false)
		else: game.world.add_child(node)
		node.global_position = p
	func update(dt: float) -> void:
		t += dt
		vel.y -= 11.0 * dt
		node.global_position += vel * dt
		if node.global_position.y < 0.05:
			node.global_position.y = 0.05
			vel *= 0.4; vel.y = absf(vel.y) * 0.4; av *= 0.5
		node.rotation += av * dt
		if t > life:
			alive = false
			node.queue_free()

class Traffic:
	extends RefCounted
	var node: Node3D
	var from: Vector3
	var to: Vector3
	var dur := 5.0
	var keep := false
	var t := 0.0
	var alive := true
	func update(dt: float) -> void:
		t += dt
		var u := minf(1.0, t / dur)
		node.position = from.lerp(to, u)
		if u >= 1.0:
			alive = false
			if not keep: node.queue_free()

class Swing:
	extends RefCounted
	var pivot: Node3D
	var t := 0.0
	var alive := true
	func update(dt: float) -> void:
		t += dt
		var s: float = pivot.get_meta("swing", 0.0)
		pivot.rotation.x = sin(t * 4.2) * s * 0.35
		pivot.set_meta("swing", s * maxf(0.0, 1.0 - dt * 0.8))
