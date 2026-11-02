class_name Prefabs
extends RefCounted
## Prefab catalogue (ported from the browser edition) + Poly Haven CC0 model upgrades.
## Each prefab is normalised once to real-world size with its origin at bottom-centre,
## then instances are cheap duplicates sharing meshes and materials.

const NON_BLOCKING := ["balcony", "awning", "overhang", "cables", "scaffold", "parasol", "rail_guard", "catwalk", "street_light", "lamp",
	"traffic_light", "palm", "tree", "bush", "sign_", "elec_pole", "solar_panel", "water_tank", "ac_unit", "fence", "struct_", "crane",
	"potted", "plant", "bench", "bollard", "cone", "display", "pillar", "stairs", "escalator", "hydrant", "camera", "chair"]

## Higher-detail Poly Haven replacements (CC0). name -> [gltf path, size]
const UPGRADES := {
	"barrel": ["res://assets/phm/barrel_03/barrel_03.gltf", {"h": 1.0}],
	"crate": ["res://assets/phm/wooden_crate_01/wooden_crate_01.gltf", {"h": 1.1}],
	"pickup_crate": ["res://assets/phm/wooden_military_crate/wooden_military_crate.gltf", {"l": 1.1}],
	"trashcan": ["res://assets/phm/metal_trash_can/metal_trash_can.gltf", {"h": 1.0}],
	"bench": ["res://assets/phm/painted_wooden_bench/painted_wooden_bench.gltf", {"l": 1.9}],
	"potted_plant": ["res://assets/phm/potted_plant_01/potted_plant_01.gltf", {"h": 1.3}],
	"planter": ["res://assets/phm/planter_box_01/planter_box_01.gltf", {"l": 1.6}],
	"manhole": ["res://assets/phm/water_manhole_cover/water_manhole_cover.gltf", {"l": 0.9}],
	"trash_bags": ["res://assets/phm/trashbag/trashbag.gltf", {"h": 0.7}],
	"box": ["res://assets/phm/cardboard_box_01/cardboard_box_01.gltf", {"h": 0.6}],
	"hydrant": ["res://assets/phm/fire_hydrant/fire_hydrant.gltf", {"h": 0.8}],
	"utility_box": ["res://assets/phm/utility_box_01/utility_box_01.gltf", {"h": 1.4}],
	"monobloc": ["res://assets/phm/plastic_monobloc_chair_01/plastic_monobloc_chair_01.gltf", {"h": 0.85}],
	"picnic_table": ["res://assets/phm/wooden_picnic_table/wooden_picnic_table.gltf", {"l": 1.9}],
	"shutter_door": ["res://assets/phm/rollershutter_door/rollershutter_door.gltf", {"l": 3.2}],
	"camera_cctv": ["res://assets/phm/security_camera_01/security_camera_01.gltf", {"l": 0.45}],
	"propane": ["res://assets/phm/propane_tank/propane_tank.gltf", {"h": 1.2}],
	"plastic_crate": ["res://assets/phm/plastic_crate_01/plastic_crate_01.gltf", {"l": 0.6}],
	"jerrycan": ["res://assets/phm/metal_jerrycan/metal_jerrycan.gltf", {"h": 0.45}],
	"wine_barrel": ["res://assets/phm/wine_barrel_01/wine_barrel_01.gltf", {"h": 0.95}],
	"street_lamp_ph": ["res://assets/phm/street_lamp_01/street_lamp_01.gltf", {"h": 4.2}],
}
## Colour fixes for library materials whose authored colours read wrong.
const MATERIAL_FIX := {"leafsGreen": Color("#3f8f34"), "woodBark": Color("#7a5434"), "grass": Color("#4f9a2c"), "plant": Color("#3d8a33"), "wood": Color("#9c6b3e"), "woodDark": Color("#6e4a2b")}

var defs := {}
var templates := {}  # name -> Node3D (normalised, not in tree)
var sizes := {}  # name -> Vector3

func _init() -> void:
	var f := FileAccess.open("res://data/prefabs.json", FileAccess.READ)
	defs = JSON.parse_string(f.get_as_text())

func path_of(name: String) -> String:
	if UPGRADES.has(name):
		return UPGRADES[name][0]
	return "res://assets/props/%s.glb" % name

func all_names() -> Array:
	var a := defs.keys()
	for k in UPGRADES.keys():
		if not a.has(k):
			a.append(k)
	return a

func prepare(name: String) -> Node3D:
	if templates.has(name):
		return templates[name]
	var def: Dictionary = defs.get(name, {})
	var size: Dictionary = def.get("size", {"s": 1})
	if UPGRADES.has(name):
		size = UPGRADES[name][1]
		def = {}
	var ps: PackedScene = load(path_of(name))
	var inner: Node3D = ps.instantiate()
	var root := Node3D.new()
	root.name = name
	root.add_child(inner)
	if def.has("rotY"):
		inner.rotation.y = float(def["rotY"])
	var box := _aabb(root)
	var s := 1.0
	if size.has("s"): s = float(size["s"])
	elif size.has("h"): s = float(size["h"]) / maxf(0.001, box.size.y)
	elif size.has("l"): s = float(size["l"]) / maxf(0.001, maxf(box.size.x, box.size.z))
	inner.scale *= s
	if def.has("scale3"):
		var s3: Array = def["scale3"]
		inner.scale *= Vector3(s3[0], s3[1], s3[2])
	box = _aabb(root)
	var c := box.get_center()
	inner.position -= Vector3(c.x, box.position.y, c.z)
	box = _aabb(root)
	_fix_materials(root, def.get("noShadow", false))
	root.set_meta("size", box.size)
	root.set_meta("aabb", box)
	templates[name] = root
	sizes[name] = box.size
	return root

func _fix_materials(n: Node, no_shadow: bool) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if no_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m is BaseMaterial3D:
					var bm := m as BaseMaterial3D
					if MATERIAL_FIX.has(bm.resource_name):
						bm.albedo_color = MATERIAL_FIX[bm.resource_name]
						bm.roughness = 0.85
					if bm.resource_name.to_lower().contains("glass") or bm.resource_name.to_lower().contains("window"):
						bm.roughness = minf(bm.roughness, 0.12)
						bm.metallic = 0.35
					bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_fix_materials(c, no_shadow)

static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while stack.size() > 0:
		var cur = stack.pop_back()
		if cur is MeshInstance3D and cur.mesh != null:
			var xf: Transform3D = _rel_xf(n, cur)
			var b: AABB = xf * cur.mesh.get_aabb()
			if first: out = b; first = false
			else: out = out.merge(b)
		for c in cur.get_children():
			stack.append(c)
	return out

static func _rel_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

func make(name: String, tint = null) -> Node3D:
	var t := prepare(name)
	var o: Node3D = t.duplicate()
	o.set_meta("prefab", name)
	o.set_meta("size", t.get_meta("size"))
	o.set_meta("aabb", t.get_meta("aabb"))
	if tint != null:
		tint_object(o, tint)
	return o

func size_of(name: String) -> Vector3:
	return prepare(name).get_meta("size")

static func blocks(name: String) -> bool:
	for p in NON_BLOCKING:
		if name.begins_with(p):
			return false
	return true

## Recolour materials by name pattern. tint: Dictionary {regex: Color} or a Color for all.
static var _tint_cache := {}
static func tint_object(n: Node, tint) -> void:
	var map: Dictionary = tint if tint is Dictionary else {".*": tint}
	var regs := {}
	for k in map.keys():
		var r := RegEx.new()
		r.compile("(?i)" + String(k))
		regs[k] = r
	_tint_rec(n, map, regs)

static func _tint_rec(n: Node, map: Dictionary, regs: Dictionary) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i)
				if not (m is BaseMaterial3D):
					continue
				for k in map.keys():
					if (regs[k] as RegEx).search(m.resource_name) != null:
						var col: Color = U.col(map[k])
						var key := "%s|%s|%s" % [m.get_instance_id(), col.to_html(), k]
						var nm: BaseMaterial3D = _tint_cache.get(key)
						if nm == null:
							nm = m.duplicate()
							nm.albedo_color = col
							if k != ".*":
								nm.albedo_texture = null
							_tint_cache[key] = nm
						mi.set_surface_override_material(i, nm)
						break
		_tint_rec(c, map, regs)
