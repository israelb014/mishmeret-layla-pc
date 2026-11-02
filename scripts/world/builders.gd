class_name Builders
extends RefCounted
## Set-piece builders (1:1 port of the browser edition's builders.js) in zone-local space.

const FACADES := ["limestone", "limestone_warm", "plaster_white", "plaster_cream", "limestone", "plaster_peach", "plaster_blue", "concrete"]
const BLD := {"bld_small": Vector2(12.46, 14.54), "bld_medium": Vector2(15.06, 13.06), "bld_large": Vector2(20.64, 16.64)}
const BLD_H := {"bld_small": 17.0, "bld_medium": 25.0, "bld_large": 28.0}
const CURBS := {"redwhite": [Color("#d32f2f"), Color("#f4f4f4")], "bluewhite": [Color("#1e5fbf"), Color("#f4f4f4")], "plain": [Color("#bdbab2"), Color("#cfccc4")]}
const SHOP_NAMES := [["פלאפל הרצל", "#e8a317", "#3a1d00"], ["מכולת השכונה", "#1f7a3d", "#ffffff"], ["פיצה בכיכר", "#c62828", "#ffffff"],
	["בית קפה", "#5d4037", "#ffe0a8"], ["שווארמה", "#ffcf33", "#5a1a00"], ["ירקות ופירות", "#2e7d32", "#ffffff"],
	["מספרה", "#1a237e", "#ffffff"], ["תכשיטים", "#212121", "#f5d36b"], ["סלולר", "#00838f", "#ffffff"], ["מאפייה", "#ef6c00", "#ffffff"],
	["חומרי בניין", "#37474f", "#ffd54f"], ["בגדים", "#ad1457", "#ffffff"], ["פיצוחים", "#6d4c41", "#ffe082"], ["מרכז הבריאות", "#0d47a1", "#ffffff"],
	["קיוסק", "#f9a825", "#212121"], ["נעליים", "#4e342e", "#ffffff"], ["הלבשה", "#6a1b9a", "#ffffff"], ["חשמל", "#0277bd", "#ffffff"]]
const GRAFFITI := ["שלום", "אהבה", "חופש", "ים", "יאללה", "קדימה", "לילה"]
const CAR_TINTS := ["#c62828", "#1565c0", "#f2f2f2", "#2e7d32", "#f9a825", "#6a1b9a", "#37474f", "#ef6c00", "#00838f"]
const CAR_TYPES := ["car_sedan", "car_hatch", "car_sport", "car_suv", "car_taxi", "car_sport2"]
const CONT_COLORS := ["#d84315", "#1565c0", "#2e7d32", "#f9a825", "#6a1b9a", "#00838f", "#c62828", "#8d6e63", "#eceff1"]

## a data flag is "on" unless it is explicitly false
static func on(d: Dictionary, k: String) -> bool:
	return not (d.get(k) is bool and d.get(k) == false)

static func run_set(z: Zone, s: Dictionary) -> void:
	match String(s["kind"]):
		"street": set_street(z, s)
		"crossStreet": set_crossStreet(z, s)
		"market": set_market(z, s)
		"intersection": set_intersection(z, s)
		"plaza": set_plaza(z, s)
		"portGround": set_portGround(z, s)
		"containers": set_containers(z, s)
		"warehouse": set_warehouse(z, s)
		"water": set_water(z, s)
		"gantry": set_gantry(z, s)
		"shipDeck": set_shipDeck(z, s)
		"bridgeTower": set_bridgeTower(z, s)
		"deckSlab": set_deckSlab(z, s)
		"platform": set_platform(z, s)
		"tracks": set_tracks(z, s)
		"hall": set_hall(z, s)
		"tunnel": set_tunnel(z, s)
		_: push_warning("unknown set %s" % s["kind"])

static func f(d: Dictionary, k: String, dv: float) -> float:
	return float(d[k]) if d.has(k) and d[k] != null else dv

static func _in(z: Zone, parent: Node3D, nm: String, x: float, zz: float, rot: float, o: Dictionary = {}) -> Node3D:
	var obj := z.place(nm, x, zz, rot, o)
	if parent != null:
		obj.reparent(parent, false)
	return obj

# ------------------------------------------------------------------ street pieces
static func _curb(z: Zone, x: float, z0: float, z1: float, colors: Array, along_x := false) -> void:
	var length := absf(z1 - z0)
	var n := maxi(1, roundi(length / 1.2))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(length / n if along_x else 0.32, 0.2, 0.32 if along_x else length / n)
	var mat: ORMMaterial3D = z.mats.get_mat("concrete", Color.WHITE, 1.5, 0.0, "curb").duplicate()
	mat.vertex_color_use_as_albedo = true
	var xf := []; var cols := []
	for i in n:
		var t := minf(z0, z1) + (i + 0.5) * length / n
		xf.append(Transform3D(Basis(), Vector3(t if along_x else x, 0.08, x if along_x else t)))
		cols.append(colors[i % 2])
	z.multimesh(mesh, mat, xf, cols)

static func _dashes(z: Zone, x: float, z0: float, z1: float, o: Dictionary = {}) -> void:
	var w := f(o, "w", 0.15); var length := f(o, "len", 3.0); var gap := f(o, "gap", 4.0)
	var along_x: bool = o.get("alongX", false)
	var total := absf(z1 - z0)
	var n := int(total / (length + gap))
	if n < 1: return
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(length if along_x else w, w if along_x else length)
	var y := f(o, "y", 0.012)
	var xf := []
	for i in n:
		var t := minf(z0, z1) + i * (length + gap) + length / 2.0
		xf.append(Transform3D(Basis(), Vector3(t if along_x else x, y, x if along_x else t)))
	z.multimesh(mesh, z.mats.paint(U.col(o.get("color", 0xf2f2f2)), 0.55), xf)

static func _crosswalk(z: Zone, x: float, zz: float, width: float, along_x := false) -> void:
	var n := int(width / 1.0)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(3.0 if along_x else 0.5, 0.5 if along_x else 3.0)
	var xf := []
	for i in n:
		var o := -width / 2.0 + (i + 0.5) * width / n
		xf.append(Transform3D(Basis(), Vector3(x if along_x else x + o, 0.013, zz + o if along_x else zz)))
	z.multimesh(mesh, z.mats.paint(Color("#f5f5f5"), 0.5), xf)

# ------------------------------------------------------------------ buildings
static func building(z: Zone, type: String, x: float, zz: float, rot_deg: float, o: Dictionary = {}) -> Node3D:
	var r := z.rand
	var b := z.prefabs.make(type)
	var facade := z.mats.facade(String(o.get("facade")) if o.get("facade") != null else String(r.pick(FACADES)))
	var trim := U.col(o.get("trim")) if o.get("trim") != null else Color(String(r.pick(["#f1ead8", "#e9dcc0", "#ffffff", "#d8cfbd"])))
	var accent := U.col(o.get("accent")) if o.get("accent") != null else Color(String(r.pick(["#2f6e4f", "#3c5a8a", "#8a4b2f", "#5b6b73", "#6d6d6d"])))
	_reskin(z, b, facade, trim, accent)
	b.position = Vector3(x, 0, zz)
	b.rotation_degrees.y = rot_deg
	z.add_static(b)
	if on(o, "details"):
		_decorate(z, b, BLD[type], BLD_H[type], o)
	return b

static func _reskin(z: Zone, n: Node, facade: Material, trim: Color, accent: Color) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m == null: continue
				var nm := m.resource_name
				if nm.contains("RedBrick") or nm.ends_with("Concrete"):
					mi.set_surface_override_material(i, facade)
				elif nm == "MI_Trim" or nm.contains("Trim_Green") or nm.contains("Trim_Dark"):
					var key := "%s|%s" % [m.get_instance_id(), (trim if nm == "MI_Trim" else accent).to_html()]
					var tm: BaseMaterial3D = z.mats.cache.get(key)
					if tm == null:
						tm = m.duplicate()
						tm.albedo_color = trim if nm == "MI_Trim" else accent
						z.mats.cache[key] = tm
					mi.set_surface_override_material(i, tm)
		_reskin(z, c, facade, trim, accent)

## Israeli details: shop sign, awning, glass fronts or roller shutters, closed-in balconies, AC units,
## solar water heaters, graffiti.
static func _decorate(z: Zone, b: Node3D, dims: Vector2, height: float, o: Dictionary) -> void:
	var r := z.rand
	var w := dims.x; var d := dims.y
	var front := d / 2.0 + 0.05
	var rot := b.rotation_degrees.y
	var local := func(lx: float, ly: float, lz: float) -> Vector3: return b.position + Vector3(lx, ly, lz).rotated(Vector3.UP, b.rotation.y)
	if on(o, "shop"):
		var shop: Array = [o["shopName"], o.get("shopBg", "#1d4fa3"), o.get("shopFg", "#ffffff")] if o.has("shopName") else r.pick(SHOP_NAMES)
		var s := z.sign_board(String(shop[0]), w * 0.62, 0.95, {"bg": shop[1], "fg": shop[2], "emissive": 1.6 if z.night else 0.0})
		s.position = local.call(0, 4.35, front + 0.32)
		s.rotation.y = b.rotation.y
		z.static_root.add_child(s)
		if r.next() < 0.75:
			var a := z.place("awning_wide", 0, 0, rot, {"tint": {"colormap": r.pick([0xd84a3a, 0x2f8f5b, 0x2a6fc0, 0xe0a420])}})
			a.position = local.call(0, 3.05, front + 0.05)
		if on(o, "glass"):
			for gx in [-w * 0.3, w * 0.3]:
				var k := r.next()
				if k < 0.25: continue
				if k < 0.45:
					# closed shop: roller shutter (Poly Haven model)
					var sh := z.place("shutter_door", 0, 0, rot, {})
					sh.position = local.call(gx, 0.0, front + 0.12)
				else:
					z.glass_pane(local.call(gx, 1.55, front + 0.14), b.rotation.y, w * 0.24, 2.3)
	var floors := int((height - 6.0) / 3.2)
	for fl in floors:
		var y := 6.2 + fl * 3.2
		for bx in [-w * 0.3, 0.0, w * 0.3]:
			var k := r.next()
			if k < 0.28 and y < height - 3.0:
				var bal := z.place("balcony", 0, 0, rot, {})
				bal.position = local.call(bx, y - 1.0, front + 0.5)
				bal.scale = Vector3.ONE * 0.9
				if r.next() < 0.6:
					var mi := MeshInstance3D.new()
					var qm := QuadMesh.new(); qm.size = Vector2(2.5, 1.3)
					mi.mesh = qm
					mi.material_override = z.mats.get_mat("shutter", Color(String(r.pick(["#e8e2d0", "#d6e4ea", "#f2e2c0"]))), 1.3)
					mi.position = local.call(bx, y + 0.3, front + 0.9)
					mi.rotation.y = b.rotation.y
					z.static_root.add_child(mi)
			elif k < 0.5:
				var ac := z.place("ac_unit", 0, 0, rot, {})
				ac.position = local.call(bx + 1.0, y - 0.9, front + 0.02)
	var roof_y := height - 0.02
	var nh := 1 + int(r.next() * 3)
	for i in nh:
		var hx := -w * 0.3 + i * 2.6
		var hz := -d * 0.1
		var panel := z.place("solar_panel", 0, 0, rot + 180, {"rx": -28})
		panel.position = local.call(hx, roof_y + 0.5, hz + 1.0)
		var tank := z.place("water_tank", 0, 0, rot + 90, {})
		tank.position = local.call(hx, roof_y + 1.1, hz - 0.3)
	if o.get("graffiti", false) or r.next() < 0.2:
		var word := String(r.pick(GRAFFITI))
		var col := Color(String(r.pick(["#ff3fb4", "#2ee6ff", "#ffd400", "#8cff3a"])))
		var gx := w * 0.42 * (-1.0 if r.next() < 0.5 else 1.0)
		if z.game.graffiti_tex.has(word):
			# spray tag projected onto the facade (Decal: follows the wall's relief and lighting)
			var dec := Decal.new()
			dec.texture_albedo = z.game.graffiti_tex[word]
			dec.modulate = col
			dec.albedo_mix = 0.92
			dec.size = Vector3(2.4, 0.5, 0.9)
			dec.cull_mask = 1
			dec.position = local.call(gx, 1.25, front - 0.05)
			dec.rotation = Vector3(PI / 2.0, b.rotation.y, 0.0)
			z.static_root.add_child(dec)
		else:
			var tag := z.sign_board(word, 2.2, 0.8, {"bg": "transparent", "fg": "#" + col.to_html(false)})
			tag.position = local.call(gx, 1.2, front + 0.03)
			tag.rotation.y = b.rotation.y
			z.static_root.add_child(tag)

static func building_row(z: Zone, side: int, x_edge: float, z0: float, z1: float, o: Dictionary = {}) -> void:
	var r := z.rand
	var zz := maxf(z0, z1)
	var z_end := minf(z0, z1)
	while zz > z_end:
		var type: String = r.pick(o["types"]) if o.has("types") else ("bld_small" if r.next() < 0.55 else "bld_medium")
		var dm: Vector2 = BLD[type]
		building(z, type, x_edge + side * (dm.y / 2.0), zz - dm.x / 2.0, 90.0 if side < 0 else -90.0, o)
		zz -= dm.x + f(o, "gap", 0.0)

# ------------------------------------------------------------------ STAGE 1
static func set_street(z: Zone, p: Dictionary) -> void:
	var x := f(p, "x", 0); var W := f(p, "width", 9); var sw := f(p, "sidewalk", 4.5); var z0 := f(p, "z0", 20); var z1 := f(p, "z1", -60)
	var length := absf(z0 - z1); var zc := (z0 + z1) / 2.0
	var asphalt := z.mats.get_mat("asphalt", Color("#c4c4c4"), 4.0)
	var pavers := z.mats.get_mat("pavers", Color("#e6ded0"), 3.0)
	z.slab(asphalt, W, length, x, 0, zc, 0.2)
	if sw > 0:
		z.slab(pavers, sw, length, x - W / 2.0 - sw / 2.0, 0.16, zc, 0.36)
		z.slab(pavers, sw, length, x + W / 2.0 + sw / 2.0, 0.16, zc, 0.36)
		var curbs: Array = CURBS[String(p.get("curbs", "redwhite"))]
		_curb(z, x - W / 2.0 - 0.16, z0, z1, CURBS[p["curbsL"]] if p.has("curbsL") else curbs)
		_curb(z, x + W / 2.0 + 0.16, z0, z1, CURBS[p["curbsR"]] if p.has("curbsR") else curbs)
	if on(p, "center"):
		_dashes(z, x, z0, z1)
	if on(p, "buildings"):
		var bz0 := f(p, "bldZ0", z0); var bz1 := f(p, "bldZ1", z1)
		var bld: Dictionary = p.get("bld", {}) if p.get("bld") != null else {}
		if on(p, "left"): building_row(z, -1, x - W / 2.0 - sw, bz0, bz1, bld)
		if on(p, "right"): building_row(z, 1, x + W / 2.0 + sw, bz0, bz1, bld)
	var r := z.rand
	var zz := z0 - 6.0
	while zz > z1 + 4.0:
		for s in [-1, 1]:
			var sx: float = x + s * (W / 2.0 + 0.7)
			z.place("street_light", sx, zz, 90.0 if s < 0 else -90.0)
			if z.night: z.lamp(Vector3(sx + s * -1.8, 6.2, zz), Color("#ffd59a"))
			var k := r.next()
			var fx: float = x + s * (W / 2.0 + 1.6)
			if on(p, "trees") and k < 0.45:
				z.place("tree_round" if p.get("trees") == "round" else ("palm" if r.next() < 0.7 else "palm_short"), fx, zz - 5, r.next() * 360.0)
			elif k < 0.65: z.place("bench", x + s * (W / 2.0 + sw - 0.9), zz - 6, 90.0 if s < 0 else -90.0, {"y": 0.16})
			elif k < 0.8: z.place("trashcan", fx, zz - 4, r.next() * 360.0, {"y": 0.16})
			else: z.place("potted_plant", x + s * (W / 2.0 + sw - 0.7), zz - 3, 0, {"y": 0.16})
			if r.next() < 0.5: z.place("bollard", x + s * (W / 2.0 + 0.5), zz - 8, 0, {"y": 0.16})
			if r.next() < 0.18: z.place("hydrant", x + s * (W / 2.0 + 1.0), zz - 10, 0, {"y": 0.16})
			if r.next() < 0.12 and sw > 2.0: z.place("utility_box", x + s * (W / 2.0 + sw - 0.5), zz - 12, 90.0 if s < 0 else -90.0, {"y": 0.16})
		zz -= f(p, "lampEvery", 16)
	for c in p.get("parked", []):
		car(z, float(c[0]), float(c[1]), float(c[2]) if c.size() > 2 else 0.0, String(c[3]) if c.size() > 3 else "random", {})

static func car(z: Zone, x: float, zz: float, rot_deg: float, type := "random", o: Dictionary = {}) -> Node3D:
	var r := z.rand
	var t: String = r.pick(CAR_TYPES) if type == "random" or type == "" else type
	var tint = null
	if o.get("tint") != null:
		tint = {"^(Blue|Red|Green|Yellow|White|Orange|Grey)$": U.col(o["tint"])}
	elif t != "car_taxi" and t != "car_cop":
		tint = {"^(Blue|Red|Green|Yellow|White|Orange|Grey)$": Color(String(r.pick(CAR_TINTS)))}
	var obj := z.prefabs.make(t, tint)
	obj.position = Vector3(x, 0, zz)
	obj.rotation_degrees.y = rot_deg
	z.car_obj(obj, o)
	return obj

static func police_car(prefabs: Prefabs) -> Node3D:
	# Israeli-style police car: white body, blue stripe, red/blue light bar
	return prefabs.make("car_cop", {"^Black$": Color("#f4f4f4"), "^White$": Color("#f7f7f7"), "^Grey$": Color("#1d4fd8"), "WhiteLights": Color("#ff2020")})

static func set_market(z: Zone, p: Dictionary) -> void:
	var r := z.rand
	var x := f(p, "x", 0); var zc := f(p, "z", -15); var w := f(p, "w", 24); var d := f(p, "d", 30)
	z.slab(z.mats.get_mat("pavers", Color("#e9e0cf"), 3.0), w, d, x, 0.02, zc, 0.24)
	for row in p.get("rows", [[-5, 1], [5, -1]]):
		var rx := float(row[0]); var side := float(row[1])
		var zz := zc + d / 2.0 - 4.0
		while zz > zc - d / 2.0 + 3.0:
			z.place("fruit_stand" if r.next() < 0.5 else "bread_stand", rx, zz, 90.0 if side > 0 else -90.0)
			z.place("parasol_a" if r.next() < 0.5 else "parasol_b", rx + side * 0.3, zz, 90.0 if side > 0 else -90.0, {"tint": {"colormap": r.pick([0xe53935, 0xfdd835, 0x1e88e5, 0x43a047, 0xfb8c00])}})
			if r.next() < 0.7:
				for i in 3:
					z.bottle(Vector3(rx + side * 0.2 + (r.next() - 0.5) * 0.5, 1.24, zz + (i - 1) * 0.35))
			if r.next() < 0.4: z.place("box", rx - side * 1.0, zz + 1, r.next() * 40.0)
			if r.next() < 0.35: z.place("plastic_crate", rx - side * 1.2, zz - 1.0, r.next() * 60.0)
			if r.next() < 0.25: z.place("monobloc", rx - side * 1.6, zz + 0.4, r.next() * 360.0)
			zz -= 3.6
	if p.has("sign"):
		z.swing_sign(Vector3(x, 4.3, zc + d / 2.0 - 2.0), 0, String(p["sign"]), {"bg": "#e8a317", "fg": "#2b1300"})

static func set_crossStreet(z: Zone, p: Dictionary) -> void:
	var zz := f(p, "z", -40); var W := f(p, "width", 10); var sw := f(p, "sidewalk", 4); var x0 := f(p, "x0", -30); var x1 := f(p, "x1", 30)
	var length := x1 - x0; var xc := (x0 + x1) / 2.0
	z.slab(z.mats.get_mat("asphalt", Color("#c4c4c4"), 4.0), length, W, xc, 0, zz, 0.2)
	z.slab(z.mats.get_mat("pavers", Color("#e6ded0"), 3.0), length, sw, xc, 0.16, zz - W / 2.0 - sw / 2.0, 0.36)
	_curb(z, zz - W / 2.0 - 0.16, x0, x1, CURBS[String(p.get("curbs", "redwhite"))], true)
	_dashes(z, zz, x0, x1, {"alongX": true})
	if on(p, "crosswalk"):
		_crosswalk(z, 0, zz + W / 2.0 + 1.6, f(p, "cwWidth", 8))
	var r := z.rand
	var x := x0
	while x < x1:
		var type := "bld_small" if r.next() < 0.5 else "bld_medium"
		var dm: Vector2 = BLD[type]
		building(z, type, x + dm.x / 2.0, zz - W / 2.0 - sw - dm.y / 2.0, 0, p.get("bld", {}) if p.get("bld") != null else {})
		x += dm.x
	var lx := x0 + 6.0
	while lx < x1:
		z.place("street_light", lx, zz - W / 2.0 - 0.7, 0)
		lx += 16.0

static func set_intersection(z: Zone, p: Dictionary) -> void:
	var x := f(p, "x", 0); var zz := f(p, "z", 0); var W := f(p, "width", 9); var size := W + 9.0
	z.slab(z.mats.get_mat("asphalt", Color("#c4c4c4"), 4.0), size + 30.0, W, x, -0.005, zz, 0.2)
	_crosswalk(z, x, zz + W / 2.0 + 1.8, W)
	_crosswalk(z, x, zz - W / 2.0 - 1.8, W)
	z.place("traffic_light", x - (W / 2.0 + 0.8), zz + (W / 2.0 + 0.8), 0)
	z.place("traffic_light", x + (W / 2.0 + 0.8), zz - (W / 2.0 + 0.8), 180)

static func set_plaza(z: Zone, p: Dictionary) -> void:
	z.slab(z.mats.get_mat("pavers", U.col(p.get("color", 0xeee4d2)), 3.0), f(p, "w", 30), f(p, "d", 30), f(p, "x", 0), 0.02, f(p, "z", -15), 0.24)

# ------------------------------------------------------------------ STAGE 2: port
static func set_portGround(z: Zone, p: Dictionary) -> void:
	var x := f(p, "x", 0); var zz := f(p, "z", -30); var w := f(p, "w", 60); var d := f(p, "d", 80)
	z.slab(z.mats.get_mat("concrete", Color("#d9d2c4"), 4.0), w, d, x, 0, zz, 0.3)
	if on(p, "lines"):
		_dashes(z, x - 4.5, zz + d / 2.0, zz - d / 2.0, {"color": 0xffc400, "len": 6, "gap": 2, "w": 0.2})
		_dashes(z, x + 4.5, zz + d / 2.0, zz - d / 2.0, {"color": 0xffc400, "len": 6, "gap": 2, "w": 0.2})
	var r := z.rand
	for i in 3:
		if r.next() < 0.6: z.place(r.pick(["propane", "jerrycan", "wine_barrel"]), x + (r.next() - 0.5) * w * 0.8, zz + (r.next() - 0.5) * d * 0.8, r.next() * 360.0)

static func set_containers(z: Zone, p: Dictionary) -> void:
	var r := z.rand
	var n := int(f(p, "n", 4)); var rot := f(p, "rot", 90)
	var dx := f(p, "dx", 0.0 if rot == 90.0 else 2.6); var dz := f(p, "dz", -2.6 if rot == 90.0 else 0.0)
	for i in n:
		var h: int = int(p["heights"][i % p["heights"].size()]) if p.has("heights") else 1 + int(r.next() * f(p, "stack", 2))
		for k in h:
			z.place(r.pick(["cont_a", "cont_b", "cont_c"]), f(p, "x", 0) + i * dx, f(p, "z", 0) + i * dz, rot + (0.0 if r.next() < 0.5 else 180.0),
				{"y": f(p, "y", 0) + k * 2.6, "tint": {"colormap": r.pick(CONT_COLORS)}})

static func set_warehouse(z: Zone, p: Dictionary) -> void:
	var corr := z.mats.get_mat("corrugated", U.col(p.get("color", 0xb0bec5)), 3.0, 0.4)
	var w := f(p, "w", 30); var h := f(p, "h", 11); var d := f(p, "d", 20)
	var g := Node3D.new()
	g.position = Vector3(f(p, "x", 0), 0, f(p, "z", -30))
	g.rotation_degrees.y = f(p, "rot", 0)
	z.static_root.add_child(g)
	if on(p, "front"): z.wall(corr, w, h, 0, 0, d / 2.0, 0, 0.3, g)
	else:
		z.wall(corr, w * 0.3, h, -w * 0.35, 0, d / 2.0, 0, 0.3, g); z.wall(corr, w * 0.3, h, w * 0.35, 0, d / 2.0, 0, 0.3, g)
		z.wall(corr, w * 0.4, h * 0.35, 0, h * 0.65, d / 2.0, 0, 0.3, g)
	if on(p, "back"): z.wall(corr, w, h, 0, 0, -d / 2.0, 0, 0.3, g)
	elif p.get("backOpening", false):
		z.wall(corr, w * 0.3, h, -w * 0.35, 0, -d / 2.0, 0, 0.3, g); z.wall(corr, w * 0.3, h, w * 0.35, 0, -d / 2.0, 0, 0.3, g)
		z.wall(corr, w * 0.4, h * 0.45, 0, h * 0.55, -d / 2.0, 0, 0.3, g)
	z.wall(corr, d, h, -w / 2.0, 0, 0, PI / 2.0, 0.3, g)
	z.wall(corr, d, h, w / 2.0, 0, 0, PI / 2.0, 0.3, g)
	z.slab(z.mats.get_mat("corrugated", Color("#8a9aa3"), 3.0, 0.4), w + 1, d + 1, 0, h + 0.15, 0, 0.3, g)
	if p.get("inside", false):
		z.slab(z.mats.get_mat("concrete", Color("#c9c4b8"), 4.0), w - 0.4, d - 0.4, 0, 0.03, 0, 0.1, g)
		var zz := d / 2.0 - 6.0
		while zz > -d / 2.0:
			var strip := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = Vector3(w * 0.6, 0.08, 0.5)
			strip.mesh = bm
			strip.material_override = z.mats.emissive(Color("#fff4dd"), 3.0)
			strip.position = Vector3(0, h - 0.3, zz)
			g.add_child(strip)
			var l := OmniLight3D.new(); l.light_energy = 1.6; l.omni_range = 14; l.position = Vector3(0, h - 1.2, zz)
			l.shadow_enabled = bool(Settings.preset_value("lamp_shadows")) and zz > 0
			g.add_child(l)
			zz -= 10.0
	for dx in p.get("doors", [-8, 0, 8]):
		var door := MeshInstance3D.new()
		var qm := QuadMesh.new(); qm.size = Vector2(6, 6.5)
		door.mesh = qm
		door.material_override = z.mats.get_mat("shutter", Color("#d0d6d9"), 2.0)
		door.position = Vector3(float(dx), 3.25, d / 2.0 + 0.17)
		g.add_child(door)
	if p.has("sign"):
		var s := z.sign_board(String(p["sign"]), 10, 1.6, {"bg": "#0d3b66", "fg": "#ffffff", "emissive": 1.4 if z.night else 0.0})
		s.position = Vector3(0, h - 1.4, d / 2.0 + 0.18)
		g.add_child(s)

static func set_water(z: Zone, p: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(f(p, "w", 400), f(p, "d", 300))
	mi.mesh = pm
	mi.material_override = z.game.water_material
	mi.position = Vector3(f(p, "x", 0), f(p, "y", -1.2), f(p, "z", -100))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	z.static_root.add_child(mi)

static func set_gantry(z: Zone, p: Dictionary) -> void:
	var g := Node3D.new()
	g.position = Vector3(f(p, "x", 0), 0, f(p, "z", -30)); g.rotation_degrees.y = f(p, "rot", 0)
	z.static_root.add_child(g)
	var span := f(p, "span", 22)
	for sx in [-span / 2.0, span / 2.0]:
		for sz in [-4.0, 4.0]:
			_in(z, g, "struct_tall", sx, sz, 0)
	for sz in [-4.0, 4.0]:
		var beam := _in(z, g, "struct_high", 0, sz, 90, {"rz": 90})
		beam.position.y = 30
		beam.scale = Vector3(1, (span + 2.0) / 22.0, 1)
	_in(z, g, "crane_k", 0, 0, 0, {"y": 18})

static func set_shipDeck(z: Zone, p: Dictionary) -> void:
	var x := f(p, "x", 0); var zz := f(p, "z", -30); var w := f(p, "w", 26); var d := f(p, "d", 70); var y := f(p, "y", 0)
	z.slab(z.mats.get_mat("deck", Color("#9aa4a8"), 3.0, 0.6), w, d, x, y, zz, 0.4)
	var hull := z.mats.get_mat("deck", Color("#7a1f1f"), 3.0, 0.5, "hull")
	z.wall(hull, d, 9, x - w / 2.0, y - 9.2, zz, PI / 2.0, 0.5)
	z.wall(hull, d, 9, x + w / 2.0, y - 9.2, zz, PI / 2.0, 0.5)
	for s in [-1, 1]:
		var rz := zz + d / 2.0 - 2.0
		while rz > zz - d / 2.0:
			z.place("rail_guard", x + s * (w / 2.0 - 0.3), rz, 90, {"y": y})
			rz -= 3.0

static func set_bridgeTower(z: Zone, p: Dictionary) -> void:
	var white := z.mats.get_mat("plaster", Color("#f4f4f0"), 3.0, 0.0, "bridgew")
	var w := f(p, "w", 18); var d := f(p, "d", 10); var h := f(p, "h", 14)
	var g := Node3D.new(); g.position = Vector3(f(p, "x", 0), f(p, "y", 0), f(p, "z", -60))
	z.static_root.add_child(g)
	z.wall(white, w, h, 0, 0, d / 2.0, 0, 0.3, g); z.wall(white, w, h, 0, 0, -d / 2.0, 0, 0.3, g)
	z.wall(white, d, h, -w / 2.0, 0, 0, PI / 2.0, 0.3, g); z.wall(white, d, h, w / 2.0, 0, 0, PI / 2.0, 0.3, g)
	z.slab(white, w + 2, d + 2, 0, h + 0.2, 0, 0.4, g)
	var band := MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(w - 1, 2.2)
	band.mesh = qm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color("#223344"); gm.roughness = 0.04; gm.metallic = 0.8
	band.material_override = gm
	band.position = Vector3(0, h - 2.6, d / 2.0 + 0.17)
	g.add_child(band)

static func set_deckSlab(z: Zone, p: Dictionary) -> void:
	var mat := String(p.get("mat", "deck"))
	z.slab(z.mats.get_mat(mat, U.col(p.get("color", 0x9aa4a8)), 3.0, 0.5 if mat == "deck" else 0.0), f(p, "w", 10), f(p, "d", 3), f(p, "x", 0), f(p, "y", 0), f(p, "z", 0), f(p, "h", 0.3))

# ------------------------------------------------------------------ STAGE 3: station
static func set_platform(z: Zone, p: Dictionary) -> void:
	var x := f(p, "x", 0); var zz := f(p, "z", -30); var w := f(p, "w", 8); var d := f(p, "d", 80); var h := 1.1
	z.slab(z.mats.get_mat("tiles", Color("#e9e9e4"), 2.0), w, d, x, h, zz, h)
	for s in p.get("edges", [1]):
		_dashes(z, x + float(s) * (w / 2.0 - 0.5), zz + d / 2.0, zz - d / 2.0, {"len": 2, "gap": 0.01, "w": 0.3, "color": 0xffd200, "y": h + 0.012})
	var pz := zz + d / 2.0 - 6.0
	while pz > zz - d / 2.0 + 4.0:
		z.place("pillar", x, pz, 0, {"y": h})
		if z.night: z.lamp(Vector3(x, h + 4.6, pz - 6), Color("#dff4ff"), 0.9)
		z.place("bench_metal", x - 1.6, pz - 4, 90, {"y": h})
		if z.rand.next() < 0.3: z.place("camera_cctv", x, pz, 180, {"y": h + 4.2})
		pz -= 12.0
	if on(p, "roof"):
		z.slab(z.mats.get_mat("corrugated", Color("#9fb1bb"), 3.0, 0.5, "stroof"), w + 4, d, x, h + 5.8, zz, 0.25)

static func set_tracks(z: Zone, p: Dictionary) -> void:
	var x := f(p, "x", 0); var z0 := f(p, "z0", 20); var z1 := f(p, "z1", -120)
	var length := absf(z1 - z0)
	z.slab(z.mats.get_mat("concrete", Color("#8b8378"), 2.0, 0.0, "ballast"), 4.2, length, x, 0, (z0 + z1) / 2.0, 0.15)
	var steel := z.mats.paint(Color("#6f6f6f"), 0.35, 0.9)
	for s in [-0.72, 0.72]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.12, 0.16, length)
		mi.mesh = bm; mi.material_override = steel
		mi.position = Vector3(x + s, 0.08, (z0 + z1) / 2.0)
		z.static_root.add_child(mi)
	var n := int(length / 0.9)
	var sm := BoxMesh.new(); sm.size = Vector3(2.4, 0.1, 0.25)
	var xf := []
	for i in n:
		xf.append(Transform3D(Basis(), Vector3(x, 0.02, z0 - i * 0.9)))
	z.multimesh(sm, z.mats.get_mat("planks", Color("#6d5a48"), 1.0, 0.0, "sleeper"), xf)

static func set_hall(z: Zone, p: Dictionary) -> void:
	var x := f(p, "x", 0); var zz := f(p, "z", -20); var w := f(p, "w", 30); var d := f(p, "d", 40); var h := f(p, "h", 8); var y := f(p, "y", 0)
	z.slab(z.mats.get_mat("tiles", U.col(p.get("floor", 0xf0eee8)), 2.0), w, d, x, y, zz, 0.3)
	var wall_m := z.mats.get_mat("facade_tiles", U.col(p.get("wall", 0xe0e6ea)), 3.0)
	if on(p, "back"): z.wall(wall_m, w, h, x, y, zz - d / 2.0)
	if on(p, "left"): z.wall(wall_m, d, h, x - w / 2.0, y, zz, PI / 2.0)
	if on(p, "right"): z.wall(wall_m, d, h, x + w / 2.0, y, zz, PI / 2.0)
	if on(p, "ceiling"):
		z.slab(z.mats.get_mat("concrete", Color("#9aa0a6"), 3.0, 0.0, "ceil"), w, d, x, y + h + 0.3, zz, 0.3)
	var lz := zz + d / 2.0 - 3.0
	while lz > zz - d / 2.0:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(w * 0.7, 0.06, 0.4)
		s.mesh = bm
		s.material_override = z.mats.emissive(Color("#f4fbff"), 2.5 if z.night else 1.6)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = Vector3(x, y + h - 0.05, lz)
		z.static_root.add_child(s)
		lz -= 6.0
	var pz := zz + d / 2.0 - 6.0
	while pz > zz - d / 2.0:
		z.lamp(Vector3(x, y + h - 1.0, pz), Color("#eaf6ff"), 1.0)
		pz -= 14.0

static func set_tunnel(z: Zone, p: Dictionary) -> void:
	var x := f(p, "x", 0); var z0 := f(p, "z0", 10); var z1 := f(p, "z1", -150); var w := f(p, "w", 12); var h := f(p, "h", 7)
	var con := z.mats.get_mat("concrete", Color("#8f949a"), 3.0, 0.0, "tunnel")
	var length := absf(z1 - z0); var zc := (z0 + z1) / 2.0
	z.wall(con, length, h, x - w / 2.0, 0, zc, PI / 2.0, 0.6)
	z.wall(con, length, h, x + w / 2.0, 0, zc, PI / 2.0, 0.6)
	z.slab(con, w + 1, length, x, h + 0.3, zc, 0.3)
	z.slab(con, w, length, x, 0, zc, 0.2)
	var lamp_m := z.mats.emissive(Color("#ffc070"), 4.0)
	var lz := z0 - 4.0
	while lz > z1:
		for s in [-1, 1]:
			var l := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = Vector3(0.15, 0.25, 1.4)
			l.mesh = bm; l.material_override = lamp_m
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			l.position = Vector3(x + s * (w / 2.0 - 0.35), h - 1.5, lz)
			z.static_root.add_child(l)
		lz -= 10.0
	var pz := z0 - 8.0
	while pz > z1:
		z.lamp(Vector3(x, h - 1.2, pz), Color("#ffc070"), 1.0)
		pz -= 26.0

static func neon(z: Zone, text: String, x: float, y: float, zz: float, rot_deg: float, w := 6.0, h := 1.2, color := "#ff3fb4") -> Node3D:
	var s := z.sign_board(text, w, h, {"bg": "#0a0a14", "fg": color, "emissive": 2.4})
	s.position = Vector3(x, y, zz)
	s.rotation_degrees.y = rot_deg
	z.static_root.add_child(s)
	# a coloured light so the neon actually lights its surroundings
	var l := OmniLight3D.new()
	l.light_color = Color(color); l.light_energy = 1.4; l.omni_range = 7.0
	l.position = Vector3(0, 0, 0.8)
	s.add_child(l)
	return s

static func escalator(z: Zone, x: float, zz: float, rot_deg: float, y := 0.0) -> void:
	var g := Node3D.new()
	g.position = Vector3(x, y, zz); g.rotation_degrees.y = rot_deg
	z.static_root.add_child(g)
	_in(z, g, "stairs", 0, 0, 0)
	_in(z, g, "stairs_rail", -0.8, 0, 0, {"scale": 1.6})
	_in(z, g, "stairs_rail", 0.8, 0, 0, {"scale": 1.6})
