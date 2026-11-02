class_name FX
extends Node3D
## Pooled GPU particle effects, flash lights and decals. Everything is created once at load
## time and re-triggered during play (no allocations, no resource loads mid-game).

var pools := {}   # type -> Array[GPUParticles3D]
var idx := {}
var lights: Array[OmniLight3D] = []
var light_t: PackedFloat32Array = PackedFloat32Array()
var light_dur: PackedFloat32Array = PackedFloat32Array()
var light_peak: PackedFloat32Array = PackedFloat32Array()
var holes: Array[Decal] = []
var hole_i := 0
var scorches: Array[Decal] = []
var scorch_i := 0
var ambient: GPUParticles3D
var quality := 1.0

func _ready() -> void:
	name = "FX"
	quality = float(Settings.preset_value("particles"))
	var soft := _radial(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	var spark_tex := _radial(Color(1, 0.95, 0.8, 1), Color(1, 0.55, 0.1, 0))
	_make("spark", 10, 12, spark_tex, true, Color(1.0, 0.82, 0.48), 0.32, 0.09, 6.0, -12.0, 40.0)
	_make("flash", 6, 1, soft, true, Color(1.0, 0.89, 0.62) * 2.0, 0.07, 0.7, 0.0, 0.0, 180.0)
	_make("dust", 10, 6, soft, false, Color(0.85, 0.78, 0.66, 0.7), 0.9, 0.45, 1.4, 0.4, 70.0)
	_make("fabric", 10, 5, soft, false, Color(0.92, 0.9, 0.85, 0.85), 0.55, 0.3, 1.2, 0.2, 80.0)
	_make("smoke", 6, 12, soft, false, Color(0.3, 0.28, 0.27, 0.8), 2.2, 1.6, 2.4, 1.2, 90.0)
	_make("fire", 6, 8, soft, true, Color(1.0, 0.62, 0.22) * 2.5, 0.5, 1.8, 4.0, 1.0, 90.0)
	_make("glass", 6, 26, null, false, Color(0.8, 0.92, 0.96, 0.8), 1.6, 0.12, 3.0, -12.0, 70.0, _shard_mesh())
	_make("chunk", 6, 10, null, false, Color(0.55, 0.42, 0.3), 1.4, 0.14, 6.0, -11.0, 60.0, _chunk_mesh())
	_make("casing", 8, 1, null, false, Color(0.85, 0.66, 0.25), 1.2, 0.04, 3.0, -11.0, 30.0, _casing_mesh())
	var shadows := bool(Settings.preset_value("lamp_shadows"))
	for i in 4:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 12.0
		l.shadow_enabled = shadows
		l.light_volumetric_fog_energy = 2.0
		add_child(l)
		lights.append(l)
		light_t.append(0.0); light_dur.append(0.1); light_peak.append(0.0)
	var hole_tex := _radial(Color(0.07, 0.06, 0.05, 1), Color(0.07, 0.06, 0.05, 0), 64, 0.25)
	for i in 80:
		var d := Decal.new()
		d.texture_albedo = hole_tex
		d.size = Vector3(0.16, 0.2, 0.16)
		d.visible = false
		d.cull_mask = 1
		add_child(d)
		holes.append(d)
	var scorch_tex := _radial(Color(0.05, 0.04, 0.03, 0.9), Color(0.05, 0.04, 0.03, 0), 128, 0.1)
	for i in 8:
		var d := Decal.new()
		d.texture_albedo = scorch_tex
		d.size = Vector3(4.0, 2.0, 4.0)
		d.visible = false
		d.cull_mask = 1
		add_child(d)
		scorches.append(d)

func _radial(c0: Color, c1: Color, size := 64, mid := 0.4) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	g.add_point(mid, c0.lerp(c1, 0.4))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size; t.height = size
	return t

func _shard_mesh() -> Mesh:
	var m := PrismMesh.new()
	m.size = Vector3(0.12, 0.14, 0.01)
	return m

func _chunk_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.22, 0.05, 0.08)
	return m

func _casing_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.006; m.bottom_radius = 0.006; m.height = 0.025; m.radial_segments = 6; m.rings = 1
	return m

func _make(type: String, count: int, amount: int, tex: Texture2D, additive: bool, color: Color, life: float, size: float,
		speed: float, gravity: float, spread: float, mesh: Mesh = null) -> void:
	var arr: Array[GPUParticles3D] = []
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed * 1.2
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = 1.0; pm.damping_max = 2.0
	pm.scale_min = 0.7; pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1)); ramp.set_color(1, Color(1, 1, 1, 0))
	var rt := GradientTexture1D.new(); rt.gradient = ramp
	pm.color_ramp = rt
	if mesh == null:
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.6)); grow.add_point(Vector2(1, 1.0 + (2.0 if type in ["dust", "smoke", "fabric"] else 0.0)))
		var ct := CurveTexture.new(); ct.curve = grow
		pm.scale_curve = ct
	else:
		pm.angular_velocity_min = -400; pm.angular_velocity_max = 400
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	if mesh == null:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if additive:
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.disable_receive_shadows = true
		var q := QuadMesh.new(); q.size = Vector2(size, size); q.material = mat
		mesh = q
	else:
		mat.roughness = 0.2 if type == "glass" else 0.8
		mat.metallic = 0.5 if type in ["glass", "casing"] else 0.0
		if type == "glass":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh = mesh.duplicate()
		(mesh as PrimitiveMesh).material = mat
	for i in count:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = maxi(1, int(amount * (quality if type in ["dust", "smoke", "glass", "chunk", "spark"] else 1.0)))
		p.lifetime = life
		p.explosiveness = 0.95
		p.randomness = 0.3
		p.local_coords = false
		p.fixed_fps = 60
		p.interpolate = true
		p.process_material = pm
		p.draw_pass_1 = mesh
		p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mesh is QuadMesh else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(p)
		arr.append(p)
	pools[type] = arr
	idx[type] = 0

func emit(type: String, pos: Vector3, normal := Vector3.UP, scale := 1.0) -> void:
	var arr: Array = pools[type]
	var i: int = idx[type]
	idx[type] = (i + 1) % arr.size()
	var p: GPUParticles3D = arr[i]
	p.global_position = pos
	if normal.length_squared() > 0.01:
		p.global_basis = _basis_up(normal.normalized())
	p.scale = Vector3.ONE * scale
	p.restart()
	p.emitting = true

static func _basis_up(up: Vector3) -> Basis:
	var x := up.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001: x = up.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)

# ------------------------------------------------------------------ effect recipes
func sparks(pos: Vector3, normal: Vector3, _n := 10) -> void:
	emit("spark", pos, normal)
	emit("flash", pos, normal, 0.4)

func dust(pos: Vector3, normal: Vector3, _col := Color.WHITE, _n := 5) -> void:
	emit("dust", pos, normal)

func fabric(pos: Vector3, _col := Color.WHITE) -> void:
	emit("fabric", pos, Vector3.UP)
	emit("spark", pos, Vector3.UP, 0.5)

func muzzle(pos: Vector3, big := 1.0) -> void:
	emit("flash", pos, Vector3.UP, big)
	emit("casing", pos, Vector3.RIGHT)
	flash_light(pos, Color(1.0, 0.73, 0.4), 6.0 * big, 0.07)

func flash_light(pos: Vector3, color: Color, energy: float, dur: float) -> void:
	var best := 0
	for i in lights.size():
		if light_t[i] < light_t[best]: best = i
	var l := lights[best]
	l.global_position = pos
	l.light_color = color
	light_t[best] = dur; light_dur[best] = dur; light_peak[best] = energy

func explosion(pos: Vector3, scale := 1.0) -> void:
	emit("fire", pos, Vector3.UP, scale)
	emit("smoke", pos + Vector3(0, 0.5, 0), Vector3.UP, scale)
	emit("spark", pos, Vector3.UP, 1.5 * scale)
	emit("chunk", pos, Vector3.UP, scale)
	flash_light(pos + Vector3(0, 1, 0), Color(1.0, 0.6, 0.25), 30.0 * scale, 0.5)
	var d := scorches[scorch_i]; scorch_i = (scorch_i + 1) % scorches.size()
	d.global_position = Vector3(pos.x, pos.y, pos.z)
	d.size = Vector3(4.0, 2.0, 4.0) * scale
	d.visible = true

func glass(pos: Vector3, normal: Vector3, _w := 1.5, _h := 2.0) -> void:
	emit("glass", pos, normal)

func chunks(pos: Vector3, _col := Color.WHITE, _n := 8) -> void:
	emit("chunk", pos, Vector3.UP)

func hole(pos: Vector3, normal: Vector3) -> void:
	var d := holes[hole_i]
	hole_i = (hole_i + 1) % holes.size()
	d.global_position = pos
	d.global_basis = _basis_up(normal)
	d.visible = true

func clear() -> void:
	for d in holes: d.visible = false
	for d in scorches: d.visible = false
	for arr in pools.values():
		for p in arr: (p as GPUParticles3D).emitting = false

## Ambient particles in the air (dust motes) that follow the camera.
func set_ambient(camera: Camera3D, color: Color, amount: int) -> void:
	if ambient:
		ambient.queue_free()
	ambient = GPUParticles3D.new()
	ambient.amount = int(amount * quality)
	ambient.lifetime = 8.0
	ambient.preprocess = 8.0
	ambient.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 6, 14)
	pm.gravity = Vector3(0, -0.05, 0)
	pm.initial_velocity_min = 0.05; pm.initial_velocity_max = 0.3
	pm.spread = 180
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	ambient.process_material = pm
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _radial(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 32)
	mat.albedo_color = color
	var q := QuadMesh.new(); q.size = Vector2(0.04, 0.04); q.material = mat
	ambient.draw_pass_1 = q
	ambient.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 20, 40))
	ambient.position = Vector3(0, 0, -8)
	camera.add_child(ambient)

func update(dt: float) -> void:
	for i in lights.size():
		if light_t[i] > 0.0:
			light_t[i] -= dt
			lights[i].light_energy = maxf(0.0, light_peak[i] * light_t[i] / light_dur[i])
		else:
			lights[i].light_energy = 0.0

## Emit every effect once (off-screen) so all particle shaders compile during loading.
func warm_up(at: Vector3) -> void:
	for type in pools.keys():
		emit(type, at, Vector3.UP)
	flash_light(at, Color.WHITE, 1.0, 0.05)
	explosion(at, 0.5)
	hole(at, Vector3.UP)
