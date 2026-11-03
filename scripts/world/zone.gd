class_name Zone
extends Node3D
## One zone of a stage: built from data in local space (camera looks -Z), placed at its anchor.
## Holds colliders (StaticBody3D, layer 1), destructibles (layer 3), lights, a reflection probe and decals.

const L_WORLD := 1
const L_HIT := 2
const L_DESTRUCT := 4
const L_PICKUP := 8

var def: Dictionary
var index: int
var stage: Dictionary
var game: Node
var probe: ReflectionProbe
var prefabs: Prefabs
var mats: Materials
var rand: U.Rng
var night := false
var static_root := Node3D.new()
var dynamic_root := Node3D.new()
var rig := Node3D.new()
var destructibles: Array = []
var cars: Array = []
var lamp_budget := 6
var anchor_pos := Vector3.ZERO
var anchor_yaw := 0.0
var bounds := AABB()

func setup(g: Node, d: Dictionary, i: int, st: Dictionary, apos: Vector3, ayaw: float) -> void:
	game = g; def = d; index = i; stage = st
	prefabs = g.prefabs; mats = g.mats
	night = bool(st.get("night", false))
	rand = U.Rng.new(int(d.get("seed", 1)) * 7919 + i * 31)
	name = "zone_%s" % d.get("id", str(i))
	position = apos; rotation.y = ayaw
	anchor_pos = apos; anchor_yaw = ayaw
	static_root.name = "static"; dynamic_root.name = "dynamic"; rig.name = "rig"
	add_child(static_root); add_child(dynamic_root); add_child(rig)
	lamp_budget = 8 if Settings.preset_value("lamp_shadows") else 4

func build() -> void:
	for s in def.get("set", []):
		Builders.run_set(self, s)
	for p in def.get("props", []):
		var o: Dictionary = p[4] if p.size() > 4 and p[4] is Dictionary else {}
		var nm := String(p[0])
		var x := float(p[1]); var zz := float(p[2]); var rot := float(p[3]) if p.size() > 3 else 0.0
		match nm:
			"car": Builders.car(self, x, zz, rot, String(o.get("type", "random")), o)
			"building": Builders.building(self, String(o.get("type", "bld_small")), x, zz, rot, o)
			"neon": Builders.neon(self, String(o["text"]), x, float(o.get("y", 4)), zz, rot, float(o.get("w", 6)), float(o.get("h", 1.2)), String(o.get("color", "#ff3fb4")))
			"escalator": Builders.escalator(self, x, zz, rot, float(o.get("y", 0)))
			"sign":
				if o.get("swing", false): swing_sign(Vector3(x, float(o.get("y", 3.5)), zz), deg_to_rad(rot), String(o["text"]), o.get("style", {}))
			"glass": glass_pane(Vector3(x, float(o.get("y", 1.5)), zz), deg_to_rad(rot), float(o.get("w", 2)), float(o.get("h", 2.2)))
			"bottle": bottle(Vector3(x, float(o.get("y", 1)), zz))
			_: place(nm, x, zz, rot, o)
	_add_probe_and_decals()

# ------------------------------------------------------------------ building helpers
## Anti-z-fighting: every slab, wall and prop gets its own tiny offset (0.8 mm steps, < 1 cm),
## so no two of their faces ever share a plane (flat model bases on floors, slab ends meeting,
## props standing in the same spot). Invisible to the eye, resolvable by the depth buffer.
var geo_seq := 0
func _geo_eps() -> float:
	geo_seq += 1
	return 0.001 + 0.0006 * float(geo_seq % 8)

## Slabs and walls: the smallest inset (from 0.6 mm up) whose six faces are all > 0.5 mm away
## from the same-facing faces of every slab/wall already built that it touches.
var boxes: Array = [] # zone-space AABBs of built slabs/walls
func _box_eps(parent: Node3D, center: Vector3, size: Vector3, shrink: Vector3, lower: float) -> float:
	var xf := Prefabs._rel_xf(self, parent) if parent != null and parent != self else Transform3D.IDENTITY
	for k in range(1, 40):
		var e := 0.0006 * k
		var sz := size - shrink * 2.0 * e
		var c := center - Vector3(0, lower * e, 0)
		var box: AABB = xf * AABB(c - sz / 2.0, sz)
		var ok := true
		for old in boxes:
			var ob: AABB = old
			if not ob.grow(0.01).intersects(box): continue
			for ax in 3:
				if absf(ob.position[ax] - box.position[ax]) < 0.0005 or absf(ob.end[ax] - box.end[ax]) < 0.0005:
					ok = false
					break
			if not ok: break
		if ok:
			boxes.append(box)
			return e
	return 0.0006 * 40

var placed := {} # identical placements (same prefab, spot and angle) are made only once

func place(nm: String, x: float, zz: float, rot_deg: float, o: Dictionary = {}) -> Node3D:
	var key := "%s|%d|%d|%d|%d" % [nm, roundi(x * 100.0), roundi(zz * 100.0), roundi(float(o.get("y", 0.0)) * 100.0), roundi(rot_deg)]
	var grouped := bool(o.get("_grouped", false))
	if not grouped and placed.has(key) and is_instance_valid(placed[key]):
		return placed[key]
	var obj := prefabs.make(nm, U.tint(o.get("tint")))
	if not grouped: placed[key] = obj
	obj.position = Vector3(x, float(o.get("y", 0.0)) + 0.002 + _geo_eps(), zz)
	# a flat base must never land on the top face of a slab/wall below it (prefabs sit on y = 0)
	if not grouped:
		var foot := AABB(Vector3(x - 0.3, obj.position.y - 0.01, zz - 0.3), Vector3(0.6, 0.02, 0.6))
		for b in boxes:
			if (b as AABB).intersects(foot) and absf((b as AABB).end.y - obj.position.y) < 0.002:
				obj.position.y += 0.003
				break
	obj.rotation_degrees = Vector3(float(o.get("rx", 0.0)), rot_deg, float(o.get("rz", 0.0)))
	if o.has("scale"):
		obj.scale = Vector3.ONE * float(o["scale"])
	if o.get("noShadow", false):
		_set_shadow(obj, false)
	if o.get("destructible", null) != null:
		dynamic_root.add_child(obj)
		add_destructible(String(o["destructible"]), obj, o)
	elif o.get("dynamic", false):
		dynamic_root.add_child(obj)
	else:
		add_static(obj, o)
	return obj

func add_static(n: Node3D, o: Dictionary = {}) -> void:
	static_root.add_child(n)
	var pf := String(n.get_meta("prefab", ""))
	if not Settings.preset_value("lamp_shadows") and n.has_meta("size"):
		var s: Vector3 = n.get_meta("size")
		if maxf(s.x, maxf(s.y, s.z)) < 1.6:
			_set_shadow(n, false)
	if o.get("collide", true) and (pf == "" or Prefabs.blocks(pf)) and n.has_meta("aabb"):
		var box: AABB = n.get_meta("aabb")
		if pf.begins_with("bld_"):
			box = AABB(box.position + Vector3(1.2, 0, 2.2), box.size - Vector3(2.4, 0, 4.4))
		add_box_collider(n, box, _surface_of(pf))

func add_box_collider(n: Node3D, box: AABB, surface := "stone", layer := L_WORLD) -> StaticBody3D:
	if box.size.x < 0.05 or box.size.y < 0.05 or box.size.z < 0.05:
		if maxf(box.size.x, maxf(box.size.y, box.size.z)) < 0.35:
			return null
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size.max(Vector3(0.05, 0.05, 0.05))
	cs.shape = shape
	cs.position = box.get_center()
	body.add_child(cs)
	n.add_child(body)
	return body

func _surface_of(pf: String) -> String:
	for k in ["car", "bus", "van", "truck", "cont", "lamp", "light", "traffic", "rail", "deck", "pillar", "struct", "crane", "dumpster", "vending", "ticket", "barrel", "propane"]:
		if pf.contains(k): return "metal"
	for k in ["crate", "box", "pallet", "planks", "bench", "stand"]:
		if pf.contains(k): return "wood"
	return "stone"

func _set_shadow(n: Node, on: bool) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_shadow(c, on)

## Box surface with top at y (architecture: road, sidewalks, floors), world-triplanar PBR
func slab(mat: Material, w: float, d: float, x: float, y: float, zz: float, h := 0.02, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var e := _box_eps(parent if parent else static_root, Vector3(x, y - h / 2.0, zz), Vector3(w, h, d), Vector3(1, 0, 1), 1.0)
	bm.size = Vector3(maxf(0.01, w - 2.0 * e), h, maxf(0.01, d - 2.0 * e))
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(x, y - h / 2.0 - e, zz)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if h > 0.3 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else static_root).add_child(mi)
	add_box_collider(mi, AABB(-bm.size / 2.0, bm.size), "stone")
	return mi

func wall(mat: Material, w: float, h: float, x: float, y: float, zz: float, rot := 0.0, thick := 0.3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# axis-aligned walls (0/90/180/270 degrees) get a guaranteed inset; others the generic one
	var q := rot / (PI / 2.0)
	var aligned := absf(q - roundf(q)) < 0.001
	var swap := aligned and posmod(roundi(q), 2) == 1
	var wsize := Vector3(thick, h, w) if swap else Vector3(w, h, thick)
	# inset on every side, bottom included (walls meeting at corners/pillars share their floor plane)
	var e := _box_eps(parent if parent else static_root, Vector3(x, y + h / 2.0, zz), wsize, Vector3(1, 1, 1), 0.0) if aligned else _geo_eps()
	bm.size = Vector3(maxf(0.01, w - 2.0 * e), maxf(0.01, h - 2.0 * e), maxf(0.01, thick - 2.0 * e))
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(x, y + h / 2.0, zz)
	mi.rotation.y = rot
	(parent if parent else static_root).add_child(mi)
	add_box_collider(mi, AABB(-bm.size / 2.0, bm.size), "stone")
	return mi

## Continuous curb along local Z (or X): one mesh, UV u runs along the length so a striped
## texture repeats every `period` metres. Only the visible faces are built (road face, top,
## sidewalk-side lip, end caps); none of them lies in the plane of the road or the sidewalk.
func curb_mesh(length: float, width: float, bottom: float, top: float, period: float) -> ArrayMesh:
	var v := []; var n := []; var uv := [] # Arrays (references): the lambda below appends to them
	var L := length; var u1 := L / period
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nn: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2):
		for q in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
			v.append(q[0]); n.append(nn); uv.append(q[1])
	# local frame: x across (0 = road face, width = sidewalk side), y up, z along (0..L)
	quad.call(Vector3(0, bottom, 0), Vector3(0, top, 0), Vector3(0, top, L), Vector3(0, bottom, L), Vector3(-1, 0, 0), Vector2(0, 1), Vector2(0, 0), Vector2(u1, 0), Vector2(u1, 1))
	quad.call(Vector3(0, top, 0), Vector3(width, top, 0), Vector3(width, top, L), Vector3(0, top, L), Vector3(0, 1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(u1, 1), Vector2(u1, 0))
	quad.call(Vector3(width, top, 0), Vector3(width, bottom, 0), Vector3(width, bottom, L), Vector3(width, top, L), Vector3(1, 0, 0), Vector2(0, 0), Vector2(0, 1), Vector2(u1, 1), Vector2(u1, 0))
	quad.call(Vector3(0, bottom, 0), Vector3(width, bottom, 0), Vector3(width, top, 0), Vector3(0, top, 0), Vector3(0, 0, -1), Vector2(0, 1), Vector2(0.2, 1), Vector2(0.2, 0), Vector2(0, 0))
	quad.call(Vector3(0, top, L), Vector3(width, top, L), Vector3(width, bottom, L), Vector3(0, bottom, L), Vector3(0, 0, 1), Vector2(0, 0), Vector2(0.2, 0), Vector2(0.2, 1), Vector2(0, 1))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(v); arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(n); arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uv)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Instanced repeated geometry (curbs, lane dashes, sleepers)
func multimesh(mesh: Mesh, mat: Material, xforms: Array, colors: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.set_meta("xforms", xforms) # headless servers do not keep instance transforms (geometry CI check)
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	static_root.add_child(mmi)
	return mmi

## Hebrew sign board: coloured board + Label3D (advanced text server = correct RTL shaping)
func sign_board(text: String, w: float, h: float, style: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	var bg := String(style.get("bg", "#1d4fa3"))
	if bg != "transparent":
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w, h)
		q.mesh = qm
		var em := float(style.get("emissive", 0.0))
		q.material_override = mats.emissive(Color(bg), em * 0.25) if em > 0.0 else mats.paint(Color(bg), 0.55)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(q)
	var lb := Label3D.new()
	lb.text = text
	lb.font = game.font_title
	lb.font_size = 160
	lb.outline_size = 0
	lb.pixel_size = h * 0.55 / 160.0
	var fg := Color(String(style.get("fg", "#ffffff")))
	var emissive := float(style.get("emissive", 0.0))
	if emissive > 0.0:
		lb.shaded = false
		lb.modulate = Color(fg.r * (1.0 + emissive), fg.g * (1.0 + emissive), fg.b * (1.0 + emissive))
	else:
		lb.shaded = true
		lb.modulate = fg
	lb.position.z = 0.01
	lb.width = w / lb.pixel_size * 0.92
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	# shrink long names to fit the board
	var est := text.length() * 0.62 * h * 0.55
	if est > w * 0.9:
		lb.pixel_size *= (w * 0.9) / est
	lb.double_sided = false
	lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	root.add_child(lb)
	return root

func lamp(pos: Vector3, color: Color, intensity := 1.0) -> void:
	if lamp_budget <= 0:
		return
	lamp_budget -= 1
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.2 * intensity
	l.omni_range = 16.0
	l.omni_attenuation = 1.4
	l.shadow_enabled = bool(Settings.preset_value("lamp_shadows"))
	l.light_volumetric_fog_energy = 1.5
	l.position = pos
	static_root.add_child(l)

# ------------------------------------------------------------------ destructibles
func glass_pane(pos: Vector3, rot_y: float, w: float, h: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, 0.03)
	mi.mesh = bm
	mi.material_override = mats.glass()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation.y = rot_y
	dynamic_root.add_child(mi)
	add_destructible("glass", mi, {"w": w, "h": h})
	return mi

func bottle(pos: Vector3) -> Node3D:
	var o := prefabs.make("bottle" if rand.next() < 0.5 else "water_bottle")
	o.position = pos
	_set_shadow(o, false)
	dynamic_root.add_child(o)
	add_destructible("bottle", o, {})
	return o

func swing_sign(pos: Vector3, rot_y: float, text: String, style: Dictionary) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation.y = rot_y
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 0.75, 0.06)
	board.mesh = bm
	board.material_override = mats.paint(Color("#5d4037"), 0.7)
	board.position.y = -0.75
	var face := sign_board(text, 2.1, 0.68, style)
	face.position = Vector3(0, -0.75, 0.035)
	var back := sign_board(text, 2.1, 0.68, style)
	back.position = Vector3(0, -0.75, -0.035)
	back.rotation.y = PI
	var chain := MeshInstance3D.new()
	var cm := BoxMesh.new(); cm.size = Vector3(0.03, 0.4, 0.03)
	chain.mesh = cm
	chain.material_override = mats.paint(Color("#333333"), 0.4, 0.8)
	chain.position.y = -0.2
	pivot.add_child(board); pivot.add_child(face); pivot.add_child(back); pivot.add_child(chain)
	dynamic_root.add_child(pivot)
	add_destructible("sign", pivot, {"board": board})
	return pivot

func car_obj(obj: Node3D, o: Dictionary) -> void:
	dynamic_root.add_child(obj)
	add_destructible("car", obj, o)
	cars.append(obj)

## Destructibles get a collider on layer 3 that carries a reference back to the record.
func add_destructible(kind: String, obj: Node3D, o: Dictionary) -> Dictionary:
	var d := {"kind": kind, "obj": obj, "alive": true, "opts": o, "zone": self, "tires": 0, "cracked": false, "windows": []}
	var box: AABB
	if kind == "glass":
		box = AABB(Vector3(-o["w"] / 2.0, -o["h"] / 2.0, -0.08), Vector3(o["w"], o["h"], 0.16))
	elif kind == "sign":
		box = AABB(Vector3(-1.15, -1.15, -0.1), Vector3(2.3, 0.8, 0.2))
	else:
		box = obj.get_meta("aabb", AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1, 0.6)))
		if kind == "bottle": box = box.grow(0.06)
		if kind == "car": box.size.y *= 0.8 # roofs are narrower than the body
	var body := add_box_collider(obj, box, "metal" if kind == "car" else "wood", L_DESTRUCT)
	if body:
		body.set_meta("destructible", d)
	d["body"] = body
	if kind == "car":
		_find_windows(obj, d["windows"])
	destructibles.append(d)
	return d

func _find_windows(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			for i in (c as MeshInstance3D).mesh.get_surface_count():
				var m := (c as MeshInstance3D).get_active_material(i)
				if m and m.resource_name.contains("Window"):
					out.append([c, i])
		_find_windows(c, out)

# ------------------------------------------------------------------ probe, decals
## Non-shadowed fill lights beside the camera path (start and end of the zone, both sides):
## they replace the bounce light SDFGI used to add, so shadowed sides stay readable. No
## specular, so they never show up as hot spots.
func _add_fill_lights() -> void:
	var path: Array = def.get("path", [])
	if path.is_empty(): return
	var hemi: Array = stage.get("hemi", [0xdfefff, 0x6b5a48, 0.35])
	var col := U.col(hemi[0]).lerp(Color(1.0, 0.93, 0.82), 0.5)
	var energy := 0.75 if night else 0.45
	var pts := [U.v3(path[0]), U.v3(path[path.size() - 1])]
	for p in pts:
		for side in [-1.0, 1.0]:
			var l := OmniLight3D.new()
			l.position = p + Vector3(side * 6.0, 2.6, -4.0)
			l.omni_range = 18.0
			l.omni_attenuation = 0.8
			l.light_energy = energy
			l.light_color = col
			l.light_specular = 0.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 70.0
			l.distance_fade_length = 15.0
			static_root.add_child(l)

func _add_probe_and_decals() -> void:
	# reflection probe covering the zone's playable area (wet road, glass, station floor)
	probe = ReflectionProbe.new()
	probe.size = Vector3(60, 24, 70)
	probe.position = Vector3(0, 6, -24)
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.9
	probe.max_distance = 90
	probe.enable_shadows = false
	# the probe also lights its box (ambient from what it captured): local, stable bounce light
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	static_root.add_child(probe)
	_add_fill_lights()
	# dirt and puddles on the ground (city and port), scattered deterministically
	if game.decal_tex.is_empty():
		return
	var n := 7
	for i in n:
		var d := Decal.new()
		var puddle := rand.next() < 0.45 and not night or (night and rand.next() < 0.6)
		d.texture_albedo = game.decal_tex["puddle" if puddle else "dirt"]
		if puddle:
			d.texture_normal = game.decal_tex["puddle_n"]
			d.texture_orm = game.decal_tex["puddle_orm"]
		d.size = Vector3(2.5 + rand.next() * 4.0, 1.0, 2.0 + rand.next() * 3.0)
		d.position = Vector3((rand.next() - 0.5) * 9.0, 0.1, -6.0 - rand.next() * 30.0)
		d.rotation.y = rand.next() * TAU
		d.albedo_mix = 0.85
		d.cull_mask = 1
		static_root.add_child(d)
