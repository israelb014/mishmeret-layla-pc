class_name Game
extends Node
## Game session: stage flow, zones, encounters, shooting, damage and scoring
## (port of the browser edition's game.js) + native rendering setup per stage.

const DIFF := {"easy": 3.2, "normal": 2.6, "hard": 2.0}

var main: Node
var ui: Node
var world := Node3D.new()
var stage_root := Node3D.new()
var camera := Camera3D.new()
var env := WorldEnvironment.new()
var sun := DirectionalLight3D.new()
var cam_attr := CameraAttributesPractical.new()
var prefabs: Prefabs
var mats: Materials
var fx: FX
var pools: Pools
var rail: Rail
var font_title: Font
var water_material: ShaderMaterial
var decal_tex := {}
var warming := false # Main is rendering a stage off-screen (shader warm-up): rail/simulation idle
var graffiti_tex := {} # word -> ImageTexture (spray tag rendered with Secular One during loading)
var stages: Array = []
var prebuilt := {}

var stage: Dictionary = {}
var stage_index := 0
var route: Array = []
var anchors: Array = []
var zones: Array = []
var zone_idx := 0
var current_zone: Zone
var actors: Array = []
var objects: Array = []
var encounter = null
var wave_idle := false
var branch_signs = null
var branch_timer := 0.0
var forced_branch := ""
var boss = null
var state := "idle"
var paused := false
var slowmo := 0.0
var time_scale := 1.0
var stage_time := 0.0
var zone_start := 0.0
var invuln := 0.0
var shields := 5
var continues_used := 0
var continues_used_stage := 0
var difficulty := "normal"
var scoring := Scoring.new()
var weapon := PlayerWeapon.new()
var run_ranks: Array = []
var travel_done := false
var pending_advance := false
var dev_god := false
var autoplay = null
var shake := 0.0
var _turn_check := 0.0
var siren_lights: Array = []
var mouse_down := false
var timers: Array = [] # [time_left, Callable]

func setup(m: Node) -> void:
	main = m
	ui = m.ui
	name = "Game"
	add_child(world)
	world.name = "World"
	world.add_child(env)
	world.add_child(sun)
	world.add_child(camera)
	world.add_child(stage_root)
	stage_root.name = "Stage"
	camera.current = true
	camera.fov = 62.0
	camera.near = 0.08
	camera.far = 400.0
	camera.attributes = cam_attr
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.6
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.03
	sun.light_volumetric_fog_energy = 1.2
	prefabs = Prefabs.new()
	mats = Materials.new()
	font_title = load("res://assets/fonts/SecularOne-Regular.ttf")
	fx = FX.new(); world.add_child(fx)
	pools = Pools.new(); pools.setup(self); world.add_child(pools)
	rail = Rail.new(camera)
	for i in 3:
		stages.append(U.load_json("res://data/stage%d.json" % (i + 1)))
	_make_water()
	_make_decal_textures()

func _make_water() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 deep : source_color = vec3(0.07, 0.25, 0.33);
uniform sampler2D n1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n2 : hint_normal, filter_linear_mipmap, repeat_enable;
void fragment() {
	vec2 uv = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 a = texture(n1, uv * 0.05 + TIME * vec2(0.012, 0.007)).rgb;
	vec3 b = texture(n2, uv * 0.09 - TIME * vec2(0.009, 0.013)).rgb;
	NORMAL_MAP = normalize(mix(a, b, 0.5));
	NORMAL_MAP_DEPTH = 0.6;
	ALBEDO = deep;
	ROUGHNESS = 0.06;
	METALLIC = 0.1;
	SPECULAR = 0.7;
}
"""
	water_material = ShaderMaterial.new()
	water_material.shader = sh
	for k in ["n1", "n2"]:
		var nt := NoiseTexture2D.new()
		nt.width = 512; nt.height = 512; nt.seamless = true; nt.as_normal_map = true; nt.bump_strength = 6.0
		var fn := FastNoiseLite.new(); fn.frequency = 0.02 if k == "n1" else 0.035
		nt.noise = fn
		water_material.set_shader_parameter(k, nt)

## Renders every graffiti word once (SubViewport + Label: correct Hebrew shaping/RTL) into a texture used by
## wall decals. Called during the loading screen; headless runs keep the Label3D fallback.
func make_graffiti_textures() -> void:
	if DisplayServer.get_name() == "headless" or not graffiti_tex.is_empty():
		return
	var vps := {}
	for word in Builders.GRAFFITI:
		var vp := SubViewport.new()
		vp.size = Vector2i(512, 192)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var l := Label.new()
		l.text = word
		l.size = Vector2(vp.size)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", font_title)
		l.add_theme_font_size_override("font_size", 132)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.07))
		l.add_theme_constant_override("outline_size", 22)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
		l.add_theme_constant_override("shadow_offset_x", 6)
		l.add_theme_constant_override("shadow_offset_y", 8)
		vp.add_child(l)
		add_child(vp)
		vps[word] = vp
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for word in vps:
		var img: Image = vps[word].get_texture().get_image()
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			graffiti_tex[word] = ImageTexture.create_from_image(img)
		vps[word].queue_free()

func _make_decal_textures() -> void:
	# procedurally generated dirt and puddle decals (no external files)
	var dirt := NoiseTexture2D.new()
	dirt.width = 256; dirt.height = 256; dirt.seamless = true
	var fn := FastNoiseLite.new(); fn.frequency = 0.015; fn.fractal_octaves = 5
	dirt.noise = fn
	var g := Gradient.new()
	g.set_color(0, Color(0.2, 0.17, 0.12, 0.0)); g.set_color(1, Color(0.22, 0.18, 0.12, 0.55))
	g.add_point(0.55, Color(0.2, 0.17, 0.12, 0.0))
	dirt.color_ramp = g
	decal_tex["dirt"] = dirt
	var puddle := NoiseTexture2D.new()
	puddle.width = 256; puddle.height = 256
	var fn2 := FastNoiseLite.new(); fn2.frequency = 0.012
	puddle.noise = fn2
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.1, 0.1, 0.12, 0.0)); g2.set_color(1, Color(0.12, 0.13, 0.15, 0.7))
	g2.add_point(0.6, Color(0.1, 0.1, 0.12, 0.0))
	puddle.color_ramp = g2
	decal_tex["puddle"] = puddle
	var pn := NoiseTexture2D.new()
	pn.width = 256; pn.height = 256; pn.as_normal_map = true; pn.bump_strength = 1.0
	var fn3 := FastNoiseLite.new(); fn3.frequency = 0.08
	pn.noise = fn3
	decal_tex["puddle_n"] = pn
	var orm := GradientTexture2D.new()
	var g3 := Gradient.new()
	g3.set_color(0, Color(1.0, 0.04, 0.0)); g3.set_color(1, Color(1.0, 0.04, 0.0)) # wet: AO 1, roughness ~0, metal 0
	orm.gradient = g3
	decal_tex["puddle_orm"] = orm

# ------------------------------------------------------------------ stage setup
func setup_stage(index: int, menu := false) -> void:
	clear_stage()
	stage = stages[index]
	stage_index = index
	_apply_environment(stage)
	route = (stage["zones"] as Array).duplicate()
	zone_idx = 0
	var st: Dictionary = stage["start"]
	anchors = [{"pos": U.v3(st["pos"]), "yaw": deg_to_rad(float(st.get("yaw", 0)))}]
	if not menu:
		fx.set_ambient(camera, Color(1, 0.95, 0.85, 0.35) if not stage.get("night", false) else Color(0.7, 0.85, 1.0, 0.3), 220)

func _apply_environment(def: Dictionary) -> void:
	apply_environment_to(def, env, sun, cam_attr)

## Sky, fog, tonemapping and sun of a stage, applied to any WorldEnvironment/sun/camera
## attributes (the game world, or the live loading/menu background in its own world).
func apply_environment_to(def: Dictionary, wenv: WorldEnvironment, dsun: DirectionalLight3D, attr: CameraAttributesPractical) -> void:
	var e := Environment.new()
	var hdr: Texture2D = main.loaded.get("res://assets/hdr/%s.hdr" % def["hdri"])
	if hdr == null: hdr = load("res://assets/hdr/%s.hdr" % def["hdri"])
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = hdr
	sky_mat.energy_multiplier = float(def.get("bgIntensity", 1.0))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.sky_rotation = Vector3(0, deg_to_rad(float(def.get("envRotation", 0))), 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# browser "hemi" fill light (sky/ground colours): Godot has no hemisphere light, so its colours are mixed
	# into the ambient term and its intensity is added to the ambient energy (lifts facades in shadow)
	var hemi: Array = def.get("hemi", [0xdfefff, 0x6b5a48, 0.35])
	e.ambient_light_color = U.col(hemi[0]).lerp(U.col(hemi[1]), 0.35)
	e.ambient_light_sky_contribution = 0.6
	e.ambient_light_energy = float(def.get("envIntensity", 1.0)) * (1.0 + float(hemi[2]) * 1.6)
	if not Settings.g("sdfgi"):
		# no (temporally noisy) GI: stable sky light carries the bounce instead, so shadowed
		# facades stay readable like the browser edition; zones add probes + fill lights
		e.ambient_light_energy *= 1.4
		e.ambient_light_sky_contribution = 0.7
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = float(def.get("exposure", 1.0)) * 1.05
	e.tonemap_white = 6.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.18 # bright, saturated arcade-remaster look
	e.adjustment_contrast = 1.06
	e.ssao_enabled = bool(Settings.g("ssao")); e.ssao_radius = 1.2; e.ssao_intensity = 1.6; e.ssao_light_affect = 0.15
	e.ssil_enabled = bool(Settings.g("ssil")); e.ssil_intensity = 0.8
	# SSR only shows on smooth surfaces (glass, puddle decals, polished station floor); rough-surface
	# SSR is disabled in project settings, full resolution, enough steps that it does not sparkle
	e.ssr_enabled = bool(Settings.g("ssr")); e.ssr_max_steps = 96; e.ssr_fade_in = 0.2; e.ssr_fade_out = 2.5; e.ssr_depth_tolerance = 0.4
	e.sdfgi_enabled = bool(Settings.g("sdfgi"))
	e.sdfgi_use_occlusion = true
	e.sdfgi_cascades = 4
	e.sdfgi_min_cell_size = 0.2
	e.sdfgi_energy = 0.9
	e.sdfgi_bounce_feedback = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.55 if not def.get("night", false) else 0.8
	e.glow_strength = 0.9
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.15 if not def.get("night", false) else 0.9
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var fogc := U.col(def["fog"][0])
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = fogc
	e.fog_depth_begin = float(def["fog"][1])
	e.fog_depth_end = float(def["fog"][2]) * 1.4
	e.fog_density = 0.6
	e.fog_aerial_perspective = 0.4
	e.fog_sky_affect = 0.15
	e.volumetric_fog_enabled = bool(Settings.g("vfog"))
	# thin fog, no temporal reprojection (it ghosts on a camera that never stops); shafts stay
	e.volumetric_fog_density = 0.006 if not def.get("night", false) else 0.01
	e.volumetric_fog_temporal_reprojection_enabled = false
	e.volumetric_fog_albedo = fogc.lerp(Color.WHITE, 0.4)
	e.volumetric_fog_anisotropy = 0.6
	e.volumetric_fog_length = 80.0
	e.volumetric_fog_sky_affect = 0.0
	e.volumetric_fog_ambient_inject = 0.15
	wenv.environment = e
	# subtle auto exposure
	attr.auto_exposure_enabled = true
	attr.auto_exposure_scale = 0.35
	attr.auto_exposure_speed = 0.6
	attr.dof_blur_far_enabled = false
	attr.dof_blur_near_enabled = false
	# sun
	var sd: Dictionary = def["sun"]
	dsun.light_color = U.col(sd["color"])
	dsun.light_energy = float(sd["intensity"]) * 0.42
	var dir := U.v3(sd["dir"]).normalized()
	if def.has("hdriSun"):
		var hs: Dictionary = def["hdriSun"]
		var a := (float(hs["u"]) - 0.5) * TAU
		var el := deg_to_rad(maxf(float(hs["elev"]), float(hs.get("minElev", 12))))
		dir = Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el)).rotated(Vector3.UP, -deg_to_rad(float(def.get("envRotation", 0)))).normalized()
	dsun.look_at_from_position(dir * 60.0, Vector3.ZERO, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	var sq: int = int(Settings.g("shadows"))
	dsun.shadow_enabled = sq > 0
	dsun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if sq >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192, 8192][sq], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([0, 2, 3, 4][sq] as RenderingServer.ShadowQuality)
	dsun.directional_shadow_max_distance = [60.0, 90.0, 110.0, 140.0][sq]
	# stable PSSM: fixed split distribution, blended splits, enough bias/blur to stop swimming
	dsun.directional_shadow_split_1 = 0.07
	dsun.directional_shadow_split_2 = 0.18
	dsun.directional_shadow_split_3 = 0.42
	dsun.directional_shadow_blend_splits = true
	dsun.directional_shadow_fade_start = 0.85
	dsun.directional_shadow_pancake_size = 30.0
	dsun.shadow_bias = 0.04
	dsun.shadow_normal_bias = 1.4
	dsun.shadow_blur = 1.6

func clear_stage() -> void:
	for a in actors: a.remove()
	actors.clear()
	for o in objects:
		if o.has_method("dispose"): o.dispose()
	objects.clear()
	for z in zones: z.queue_free()
	zones.clear()
	fx.clear()
	Sfx.stop_all_loops()
	encounter = null
	if branch_signs != null:
		for s in branch_signs: s.dispose()
	branch_signs = null
	boss = null
	timers.clear()
	ui.boss_bar("", -1.0)

func anchor_for(i: int) -> Dictionary:
	while anchors.size() <= i:
		var prev: Dictionary = anchors[anchors.size() - 1]
		var z: Dictionary = route[anchors.size() - 1]
		var nxt: Array = z.get("next", [0, 0, -40, 0])
		if z.has("branchChosen") and z["branch"][z["branchChosen"]].has("next"):
			nxt = z["branch"][z["branchChosen"]]["next"]
		var p: Vector3 = Vector3(float(nxt[0]), 0, float(nxt[2])).rotated(Vector3.UP, prev["yaw"]) + prev["pos"]
		anchors.append({"pos": p, "yaw": prev["yaw"] + deg_to_rad(float(nxt[3]) if nxt.size() > 3 else 0.0)})
	return anchors[i]

func ensure_zone(i: int) -> Zone:
	if i < 0 or i >= route.size(): return null
	for z in zones:
		if z.index == i: return z
	var a := anchor_for(i)
	var z: Zone = prebuilt.get(String(route[i]["id"]))
	if z != null and not z.is_inside_tree() and is_instance_valid(z):
		prebuilt.erase(String(route[i]["id"]))
		z.index = i
		z.def = route[i]
		z.position = a["pos"]; z.rotation.y = a["yaw"]
		z.anchor_pos = a["pos"]; z.anchor_yaw = a["yaw"]
		stage_root.add_child(z)
	else:
		# fallback (should not happen: every zone is prebuilt during loading)
		push_warning("zone built during play: %s" % route[i]["id"])
		z = Zone.new()
		z.setup(self, route[i], i, stage, a["pos"], a["yaw"])
		stage_root.add_child(z)
		z.build()
		setup_rig(z)
	zones.append(z)
	return z

func refresh_graphics() -> void:
	if not stage.is_empty(): _apply_environment(stage)

## Detaches the attached zones and returns them to the prebuilt set (menu fly-through only:
## nothing in them was changed by play).
func return_zones_to_prebuilt() -> void:
	for z in zones:
		if z.is_inside_tree(): stage_root.remove_child(z)
		z.position = Vector3(0, 0, -100000)
		prebuilt[String(z.def["id"])] = z
	zones.clear()

func dispose_zone(z: Zone) -> void:
	zones.erase(z)
	for a in actors:
		if a.zone == z and not a.removed: a.remove()
	z.queue_free()

func dispose_behind(i: int) -> void:
	for z in zones.duplicate():
		if z.index < i - 1 or z.index > i + 1: dispose_zone(z)

func to_world(z: Zone, v) -> Vector3:
	return z.to_global(U.v3(v))

func setup_rig(z: Zone) -> void:
	var d: Dictionary = z.def
	if not d.has("travel"): return
	var t: Dictionary = d["travel"]
	var veh = t.get("vehicle")
	if veh is String and veh == "police":
		var carn := Builders.police_car(prefabs)
		carn.position = Vector3(0, 0, 0.9)
		z.rig.add_child(carn)
		for mi in carn.find_children("*", "MeshInstance3D", true, false):
			for si in (mi as MeshInstance3D).mesh.get_surface_count():
				var m := (mi as MeshInstance3D).get_active_material(si)
				if m and m.resource_name.contains("Window"): (mi as MeshInstance3D).visible = false
		var red := SpotLight3D.new(); red.light_color = Color(1, 0.12, 0.12); red.spot_range = 14; red.spot_angle = 55; red.shadow_enabled = true
		var blue := SpotLight3D.new(); blue.light_color = Color(0.12, 0.3, 1); blue.spot_range = 14; blue.spot_angle = 55; blue.shadow_enabled = true
		red.position = Vector3(-0.6, 1.9, 0.6); blue.position = Vector3(0.6, 1.9, 0.6)
		red.rotation_degrees = Vector3(-20, 0, 0); blue.rotation_degrees = Vector3(-20, 0, 0)
		z.rig.add_child(red); z.rig.add_child(blue)
		z.set_meta("siren", [red, blue])
	elif veh is Dictionary:
		var v := prefabs.make(String(veh["name"]), U.tint(veh.get("tint")))
		v.position = U.v3(veh.get("pos", [0, 0, 0]))
		v.rotation.y = float(veh.get("rot", 0))
		z.rig.add_child(v)
	var anims := []
	for p in t.get("props", []):
		var o: Dictionary = p[4] if p.size() > 4 else {}
		var obj := prefabs.make(String(p[0]), U.tint(o.get("tint")))
		obj.position = Vector3(float(p[1]), float(o.get("y", 0)), float(p[2]))
		obj.rotation_degrees.y = float(p[3])
		z.rig.add_child(obj)
		if o.has("anim"): anims.append({"obj": obj, "base": obj.position.x, "sway": float(o["anim"].get("sway", 1)), "amp": float(o["anim"].get("amp", 0.6)), "t": 0.0})
	z.set_meta("rig_anims", anims)

# ------------------------------------------------------------------ flow
func start_stage(index: int, zone := 0, skip_intro := false) -> void:
	setup_stage(index)
	scoring.reset_stage()
	weapon.equip("pistol")
	stage_time = 0.0
	shields = shields if shields > 0 else 5
	ui.hud_show(true)
	ui.hud_shields(shields, false)
	ui.hud_weapon(weapon)
	ui.hud_score(scoring.total, scoring.multiplier(), scoring.combo)
	ui.hud_zones(0, count_zones(), "")
	Sfx.play_music(String(stage["music"]))
	for i in zone:
		if route[i].has("branch"):
			choose_branch(forced_branch if forced_branch != "" else "left", true)
	zone_idx = zone
	ensure_zone(zone); ensure_zone(zone + 1)
	if zone == 0 and not skip_intro:
		play_intro()
	else:
		var z := ensure_zone(zone)
		rail.jump(to_world(z, z.def["path"][0]), to_world(z, z.def["look"]))
		state = "playing"
		enter_zone(zone)

func count_zones() -> int:
	var n := 0
	for z in route:
		n += 1
		if z.has("branch") and not z.has("branchChosen"): n += (z["branch"]["left"]["zones"] as Array).size()
	return n

func play_intro() -> void:
	var z0 := ensure_zone(0)
	var pts := []
	for p in stage["intro"]["path"]: pts.append(to_world(z0, p))
	var look := to_world(z0, stage["intro"]["look"])
	rail.jump(pts[0], look)
	state = "intro"
	main.set_aiming(true)
	var dur := float(stage["intro"]["duration"])
	ui.stage_title(String(stage["title"]), String(stage["subtitle"]), dur, stage_index)
	# cinematic depth of field during the intro fly-through
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 60.0
	cam_attr.dof_blur_far_transition = 40.0
	cam_attr.dof_blur_amount = 0.08
	rail.move_along(pts.slice(1), {"duration": dur, "look_end": look, "on_done": end_intro})

func end_intro() -> void:
	if state != "intro": return
	ui.stage_title("", "", 0, 0)
	cam_attr.dof_blur_far_enabled = false
	state = "playing"
	enter_zone(0)

func enter_zone(i: int) -> void:
	zone_idx = i
	var z := ensure_zone(i)
	ensure_zone(i + 1)
	dispose_behind(i)
	current_zone = z
	var d: Dictionary = z.def
	var pts := []
	for p in d["path"]: pts.append(to_world(z, p))
	var look := to_world(z, d["look"])
	zone_start = stage_time
	ui.hud_zones(zone_idx, count_zones(), String(d.get("name", "")))
	if d.has("travel"):
		travel_done = false
		rail.move_along(pts, {"duration": float(d["travel"]["duration"]), "look_end": look, "linear": true, "travel": true, "look_ahead": 0.04, "on_done": func(): travel_done = true})
		if d["travel"].get("vehicle") is String and d["travel"]["vehicle"] == "police":
			Sfx.loop("siren", "siren", 0.25); Sfx.loop("engine", "engine", 0.35)
		if d["travel"].has("sound"):
			Sfx.loop("travel", String(d["travel"]["sound"]), 0.35, 0.8)
		start_encounter(z)
	else:
		rail.move_along(pts, {"duration": d.get("moveTime"), "look_end": look, "on_done": func(): start_encounter(z)})

func start_encounter(z: Zone) -> void:
	var d: Dictionary = z.def
	if not d.has("travel"):
		for old in zones.duplicate():
			if old.index < z.index: dispose_zone(old)
	encounter = {"zone": z, "wave": -1, "wave_time": 0.0, "pending": [], "spawned": [], "done": false, "start_time": stage_time, "gap": 0.0}
	if d.has("boss"):
		Sfx.play_music("boss")
		boss = Boss.new(self, d["boss"], z)
		boss.begin()
		actors.append(boss)
		ui.callout(String(d["boss"].get("title", "בוס!")), "boss", "")
	next_wave()

func next_wave() -> void:
	var e: Dictionary = encounter
	var waves: Array = e["zone"].def.get("waves", [])
	e["wave"] += 1
	if e["wave"] >= waves.size():
		wave_idle = true; return
	wave_idle = false
	var w: Dictionary = waves[e["wave"]]
	e["wave_time"] = 0.0
	var evs: Array = (w.get("events", []) as Array).duplicate()
	evs.sort_custom(func(a, b): return float(a.get("t", 0)) < float(b.get("t", 0)))
	e["pending"] = evs
	e["spawned"] = []
	if w.has("look"): rail.turn_to(to_world(e["zone"], w["look"]), float(w.get("turnSpeed", 4.5)))

func update_encounter(dt: float) -> void:
	if encounter == null or encounter["done"]: return
	var e: Dictionary = encounter
	e["wave_time"] += dt
	_turn_check -= dt
	if _turn_check <= 0.0 and not rail.moving:
		_turn_check = 0.4
		for a in actors:
			if not a.is_enemy or not a.alive or a.threat == null: continue
			var p: Vector3 = a.ring_anchor()
			if camera.is_position_behind(p) or not _on_screen(p, 0.92, 0.85):
				rail.turn_to(rail.look_target.lerp(p, 0.75), 5.0)
				break
	while (e["pending"] as Array).size() > 0 and float(e["pending"][0].get("t", 0)) <= e["wave_time"]:
		fire_event(e["pending"].pop_front(), e)
	var d: Dictionary = e["zone"].def
	if d.has("travel"):
		var fwd := -camera.global_basis.z
		for a in actors:
			if not a.is_enemy or a.is_boss or not a.alive or a.spec.get("rig", false): continue
			if (a.root_global() - camera.global_position).dot(fwd) < -1.0: a.escape()
	var wave_clear: bool = (e["pending"] as Array).is_empty()
	if wave_clear:
		for a in e["spawned"]:
			if not a.down: wave_clear = false; break
	if wave_clear and not wave_idle:
		e["gap"] += dt
		if e["gap"] > 0.45:
			e["gap"] = 0.0; next_wave()
	if wave_idle and wave_clear:
		var travel_ok: bool = not d.has("travel") or travel_done or d["travel"].get("endEarly", false)
		var boss_ok: bool = not d.has("boss") or (boss != null and not boss.alive)
		if travel_ok and boss_ok and not e["done"]: zone_cleared()

func _on_screen(p: Vector3, mx: float, my: float) -> bool:
	var sp := camera.unproject_position(p)
	var vs := get_viewport().get_visible_rect().size
	var nx := sp.x / vs.x * 2.0 - 1.0
	var ny := sp.y / vs.y * 2.0 - 1.0
	return absf(nx) <= mx and absf(ny) <= my

func fire_event(ev: Dictionary, e: Dictionary) -> void:
	var z: Zone = e["zone"]
	if ev.has("enemy"): e["spawned"].append(spawn_enemy((ev["enemy"] as Dictionary).duplicate(true), z))
	if ev.has("civ"): spawn_civilian(ev["civ"], z)
	if ev.has("look"): rail.turn_to(to_world(z, ev["look"]), float(ev.get("speed", 5)) if ev.get("speed") != null else 5.0)
	if ev.has("pickup"): spawn_pickup(String(ev["pickup"]["type"]), to_world(z, ev["pickup"]["pos"]))
	if ev.has("grenade"): spawn_grenade(to_world(z, ev["grenade"]["from"]), float(ev["grenade"].get("time", 2)) if ev["grenade"].get("time") != null else 2.0)
	if ev.has("sfx"): Sfx.play(String(ev["sfx"]), float(ev.get("volume", 0.7)) if ev.get("volume") != null else 0.7)
	if ev.has("callout"): ui.callout(String(ev["callout"]), String(ev.get("style", "info")) if ev.get("style") != null else "info", "")
	if ev.has("vehicle"): spawn_traffic(ev["vehicle"], z)
	if ev.has("shake"): add_shake(float(ev["shake"]))

func spawn_enemy(spec: Dictionary, z: Zone):
	var en := Enemy.new(self, spec, z)
	en.begin()
	actors.append(en)
	return en

func spawn_civilian(spec: Dictionary, z: Zone, parent: Node3D = null):
	var c := Civilian.new(self, spec, z, parent)
	c.begin()
	actors.append(c)
	return c

func spawn_traffic(v: Dictionary, z: Zone) -> void:
	var parent: Node3D = z.rig if v.get("rig", false) else z.dynamic_root
	var tint = null
	if v.get("tintMap") != null: tint = U.tint(v["tintMap"])
	elif v.get("tint") != null: tint = {"^(Blue|Red|Green|Yellow|White|Orange|Grey)$": U.col(v["tint"])}
	elif String(v.get("name", "")) == "bus": tint = {"^Bottom$": Color("#1f8f4e"), "^Top$": Color("#f4f4f4"), "^Material$": Color("#222222"), "^Windows$": Color("#26323c")}
	var obj := prefabs.make(String(v.get("name", "car_sedan")), tint)
	parent.add_child(obj)
	var tr := Objects.Traffic.new()
	tr.node = obj; tr.from = U.v3(v["from"]); tr.to = U.v3(v["to"]); tr.dur = float(v["duration"]); tr.keep = v.get("keep", false)
	obj.position = tr.from
	obj.rotation.y = atan2(tr.to.x - tr.from.x, tr.to.z - tr.from.z)
	objects.append(tr)

func spawn_grenade(from: Vector3, flight := 1.9, side := 0.0):
	var fwd := -camera.global_basis.z
	var right := fwd.cross(Vector3.UP).normalized()
	var to := camera.global_position + fwd * 1.8 + right * (side + randf_range(-0.4, 0.4))
	to.y = camera.global_position.y - 0.5
	var g := Objects.Grenade.new(self, from, to, flight)
	objects.append(g)
	return g

func spawn_pickup(type: String, pos: Vector3):
	var p := Objects.Pickup.new(self, type, pos)
	objects.append(p)
	return p

func zone_cleared() -> void:
	var e: Dictionary = encounter
	e["done"] = true
	var d: Dictionary = e["zone"].def
	Sfx.stop_loop("siren"); Sfx.stop_loop("engine"); Sfx.stop_loop("travel")
	if d.has("boss"): return
	var bonus := Scoring.zone_bonus(stage_time - e["start_time"], float(d.get("par", 18)))
	scoring.add(bonus)
	ui.callout("האזור נקי", "clear", "בונוס זמן +%s" % _n(bonus))
	Sfx.play("zone_clear", 0.8)
	ui.hud_score(scoring.total, scoring.multiplier(), scoring.combo)
	if d.has("branch"):
		later(0.9, show_branch.bind(e["zone"]))
		return
	later(1.1, advance)

func later(t: float, cb: Callable) -> void:
	timers.append([t, cb])

func advance() -> void:
	if state != "playing":
		pending_advance = true; return
	if zone_idx + 1 < route.size(): enter_zone(zone_idx + 1)

func show_branch(z: Zone) -> void:
	var b: Dictionary = z.def["branch"]
	var rots: Array = b.get("signRot", [0, 0])
	branch_signs = [
		Objects.BranchSign.new(self, z, U.v3(b["signs"][0]), deg_to_rad(float(rots[0])), String(b["left"]["label"]), "left"),
		Objects.BranchSign.new(self, z, U.v3(b["signs"][1]), deg_to_rad(float(rots[1])), String(b["right"]["label"]), "right"),
	]
	ui.callout("בחר מסלול", "info", "ירה בשלט כדי לבחור")
	branch_timer = 9.0
	if b.has("look"): rail.turn_to(to_world(z, b["look"]), 3.0)

func choose_branch(side: String, silent := false) -> void:
	var zi := -1
	for i in route.size():
		if route[i].has("branch") and not route[i].has("branchChosen") and i >= (0 if silent else zone_idx):
			zi = i; break
	if zi < 0: return
	var bz: Dictionary = (route[zi] as Dictionary).duplicate()
	var zs: Array = bz["branch"][side]["zones"]
	var nr := route.slice(0, zi + 1)
	nr.append_array(zs)
	nr.append_array(route.slice(zi + 1))
	bz["branchChosen"] = side
	nr[zi] = bz
	route = nr
	anchors.resize(mini(anchors.size(), zi + 1))
	for z in zones.duplicate():
		if z.index > zi:
			# not used yet: put it back (still prebuilt) instead of freeing it
			zones.erase(z)
			stage_root.remove_child(z)
			prebuilt[String(z.def["id"])] = z
		elif z.index == zi: z.def = bz
	if silent: return
	if branch_signs != null:
		for s in branch_signs: s.dispose()
	branch_signs = null
	Sfx.play("sign", 0.8)
	ui.callout(String(bz["branch"][side]["label"]), "info", "")
	later(0.5, advance)

# ------------------------------------------------------------------ combat
func threat_duration(n := 0) -> float:
	var base: float = DIFF[difficulty] - 0.1 * stage_index
	return maxf(0.9, base * pow(0.85, n))

func enemy_attack(enemy, type: String) -> void:
	if not enemy.alive and type != "grenade": return
	if state != "playing" or invuln > 0.0 or dev_god:
		if invuln > 0.0: ui.callout("מוגן!", "info", "")
		return
	player_hurt("נדקרת!" if type == "knife" else "")

func player_hurt(msg := "") -> void:
	shields = maxi(0, shields - 1)
	scoring.stage["damage"] += 1
	scoring.combo = 0
	invuln = 0.9
	ui.damage_flash()
	add_shake(0.85)
	Sfx.play("hurt", 0.9)
	ui.hud_shields(shields, true)
	ui.hud_score(scoring.total, scoring.multiplier(), scoring.combo)
	if msg != "": ui.callout(msg, "warn", "")
	if shields <= 0: game_over()

func add_shake(a: float) -> void:
	if Settings.g("shake"):
		shake = minf(1.2, shake + a)

func grenade_landed(_g) -> void:
	var p := camera.global_position - camera.global_basis.z * 2.2
	p.y = camera.global_position.y - 0.8
	fx.explosion(p, 0.9)
	Sfx.play("explosion", 1.0); Sfx.play("explosion2", 0.7)
	add_shake(1.1)
	if state == "playing" and invuln <= 0.0 and not dev_god: player_hurt("רימון!")

func reload() -> void:
	if state != "playing" and state != "intro": return
	if weapon.start_reload():
		Sfx.play("reload", 0.8)
		ui.hud_reloading(true)

func on_shoot() -> void:
	if paused: return
	if state == "intro":
		rail.time = rail.duration; return
	if state != "playing": return
	try_fire()

func try_fire() -> void:
	if weapon.reloading > 0.0: return
	if weapon.ammo <= 0:
		if weapon.cooldown > 0.0: return
		weapon.cooldown = 0.18
		Sfx.play("empty", 0.8)
		ui.hud_flash_ammo()
		ui.callout("טען מחדש!", "warn", "")
		return
	if not weapon.can_fire(): return
	var def: Dictionary = weapon.def
	var res := weapon.fire()
	Sfx.play(String(def["sound"]), 1.0 if int(def["pellets"]) > 1 else 0.85)
	add_shake(float(def["shake"]))
	scoring.shot()
	var mp: Vector2 = main.aim_position()
	var any_hit := false
	var any_relevant := false
	var vs := get_viewport().get_visible_rect().size
	for p in int(def["pellets"]):
		var sp := mp
		if int(def["pellets"]) > 1:
			var ang := randf() * TAU
			var r := sqrt(randf()) * float(def["spread"])
			sp += Vector2(cos(ang), sin(ang)) * r * vs.y * 0.5
		var res2 := resolve_shot(sp, bool(def["pierce"]))
		any_hit = any_hit or res2[0]
		any_relevant = any_relevant or res2[1]
	if not any_hit and not any_relevant: scoring.miss()
	if any_hit: scoring.stage["hits"] = mini(scoring.stage["hits"], scoring.stage["shots"])
	ui.hud_weapon(weapon)
	ui.hud_score(scoring.total, scoring.multiplier(), scoring.combo)
	if res == "depleted":
		later(0.25, func():
			if weapon.special() and weapon.ammo <= 0:
				weapon.equip("pistol"); ui.hud_weapon(weapon); ui.callout("חזרה לאקדח", "info", ""))
	elif weapon.ammo == 0 and not weapon.special():
		ui.callout("טען מחדש!", "warn", "")

## One bullet. Returns [hit_enemy, relevant]
func resolve_shot(screen_pos: Vector2, pierce: bool) -> Array:
	var o := camera.project_ray_origin(screen_pos)
	var d := camera.project_ray_normal(screen_pos)
	var hits := []
	for a in actors:
		if not a.alive: continue
		var h: Dictionary = a.c.hit_test(o, d)
		if not h.is_empty(): hits.append({"t": h["t"], "point": h["point"], "part": h["part"], "actor": a})
	for ob in objects:
		if not ob.alive or not ob.has_method("hit_test"): continue
		var h: Dictionary = ob.hit_test(o, d)
		if not h.is_empty(): hits.append({"t": h["t"], "point": h["point"], "object": ob})
	if branch_signs != null:
		for s in branch_signs:
			var h: Dictionary = s.hit_test(o, d)
			if not h.is_empty(): hits.append({"t": h["t"], "point": h["point"], "sign": s})
	# world + destructibles through the physics engine
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, o + d * 400.0, Zone.L_WORLD | Zone.L_DESTRUCT)
	var exclude := []
	for k in 6:
		q.exclude = exclude
		var r := space.intersect_ray(q)
		if r.is_empty(): break
		var col: Object = r["collider"]
		var dd = (col.get_meta("destructible") if col.has_meta("destructible") else null)
		if dd != null and not dd["alive"]:
			exclude.append(r["rid"]); continue
		var t := o.distance_to(r["position"])
		if dd != null: hits.append({"t": t, "point": r["position"], "normal": r["normal"], "destructible": dd})
		else: hits.append({"t": t, "point": r["position"], "normal": r["normal"], "world": (col.get_meta("surface") if col.has_meta("surface") else "stone")})
		break
	if d.y < -0.01:
		var tg := -(o.y - float(stage.get("groundY", 0))) / d.y
		if tg > 0 and tg < 400: hits.append({"t": tg, "point": o + d * tg, "normal": Vector3.UP, "world": "stone"})
	hits.sort_custom(func(a, b): return a["t"] < b["t"])
	var enemy_hit := false
	var relevant := false
	var pierced := 0
	for h in hits:
		if h.has("actor"):
			var a = h["actor"]
			if a.is_civilian:
				a.hit(h["part"], h["point"]); relevant = true; break
			if a.hit(h["part"], h["point"]):
				enemy_hit = true; relevant = true
			if pierce and pierced < 1:
				pierced += 1; continue
			break
		if h.has("object"):
			var ob = h["object"]
			relevant = true
			if ob.get("is_grenade"):
				ob.shot()
				var pts := scoring.add(int(Scoring.POINTS["grenade"]))
				ui.popup(h["point"], "+%d" % pts, "רימון", "")
			elif ob.get("is_pickup"):
				collect(ob)
			break
		if h.has("sign"):
			choose_branch(h["sign"].side); relevant = true; break
		if h.has("destructible"):
			break_destructible(h["destructible"], h); relevant = true; break
		if h.has("world"):
			world_impact(h); break
	return [enemy_hit, relevant]

func world_impact(h: Dictionary) -> void:
	var n: Vector3 = h.get("normal", Vector3.UP)
	var p: Vector3 = h["point"]
	match String(h["world"]):
		"metal":
			fx.sparks(p, n, 9); Sfx.play("ricochet", 0.35)
		"wood":
			fx.dust(p, n); Sfx.play("wood", 0.4)
		_:
			fx.dust(p, n); fx.sparks(p, n, 3)
	if p.distance_to(camera.global_position) < 60.0: fx.hole(p, n)

func break_destructible(d: Dictionary, h: Dictionary) -> void:
	var o: Node3D = d["obj"]
	var n: Vector3 = (camera.global_position - h["point"]).normalized()
	match String(d["kind"]):
		"glass":
			d["alive"] = false
			var normal := o.global_basis.z.normalized()
			if normal.dot(n) < 0: normal = -normal
			fx.glass(o.global_position, normal)
			o.visible = false
			if d.get("body"): d["body"].collision_layer = 0
			Sfx.play("glass" if randf() < 0.5 else "glass2", 0.8)
		"bottle":
			d["alive"] = false
			if d.get("body"): d["body"].collision_layer = 0
			objects.append(Objects.Flyer.new(self, o, h["point"], Vector3(randf_range(-1.5, 1.5), 4.0 + randf() * 2.0, randf_range(-1.5, 1.5)) - n * 2.0))
			fx.sparks(h["point"], n, 4)
			Sfx.play("bottle", 0.7)
		"sign":
			o.set_meta("swing", float(o.get_meta("swing", 0.0)) + 1.4)
			fx.sparks(h["point"], n, 4)
			Sfx.play("sign", 0.6)
			if not d.get("anim", false):
				d["anim"] = true
				var sw := Objects.Swing.new(); sw.pivot = o
				objects.append(sw)
		"red_barrel":
			explode_barrel(d)
		"crate":
			d["alive"] = false
			var p := o.global_position
			o.visible = false
			if d.get("body"): d["body"].collision_layer = 0
			fx.chunks(p + Vector3(0, 0.5, 0)); fx.dust(p + Vector3(0, 0.4, 0), Vector3.UP)
			Sfx.play("wood", 0.9)
			if d["opts"].get("weapon") != null:
				var pk = spawn_pickup(String(d["opts"]["weapon"]), p + Vector3(0, 1.0, 0)); pk.life = 7.0
		"car":
			var local := o.to_local(h["point"])
			var size: Vector3 = o.get_meta("size", Vector3(1.8, 1.4, 4.5))
			if local.y < 0.55 and absf(local.z) > size.z * 0.22 and d["tires"] < 4:
				d["tires"] += 1
				fx.dust(h["point"], n); Sfx.play("tire", 0.9)
				o.rotation.z += (-1.0 if local.x > 0 else 1.0) * 0.035; o.position.y -= 0.03
				ui.popup(h["point"], "", "צמיג", "")
			elif local.y > size.y * 0.55 and (d["windows"] as Array).size() > 0 and not d["cracked"]:
				d["cracked"] = true
				for wi in d["windows"]:
					var mi: MeshInstance3D = wi[0]
					var m: BaseMaterial3D = mi.get_active_material(wi[1]).duplicate()
					m.albedo_color = Color("#d8eef7"); m.roughness = 0.6; m.metallic = 0.1
					mi.set_surface_override_material(wi[1], m)
				fx.glass(h["point"], n); Sfx.play("glass", 0.6)
			else:
				fx.sparks(h["point"], n, 8); Sfx.play("metal", 0.6); fx.hole(h["point"], n)

func explode_barrel(d: Dictionary) -> void:
	d["alive"] = false
	var o: Node3D = d["obj"]
	var p := o.global_position
	o.visible = false
	if d.get("body"): d["body"].collision_layer = 0
	fx.explosion(p + Vector3(0, 0.6, 0), 1.2)
	Sfx.play("explosion", 1.0); Sfx.play("explosion2", 0.8)
	add_shake(0.8)
	var downed := 0
	for a in actors:
		if not a.alive: continue
		var ap: Vector3 = a.root_global()
		if ap.distance_to(p) < 4.5:
			if a.is_enemy and not a.is_boss:
				a.die("torso", "death_back"); downed += 1; scoring.stage["hits"] += 1
			elif a.is_boss: a.hit("torso", ap + Vector3(0, 1.2, 0))
			elif a.is_civilian: a.hit("torso", ap)
	for z in zones:
		for o2 in z.destructibles:
			if o2["alive"] and o2["kind"] == "red_barrel" and (o2["obj"] as Node3D).global_position.distance_to(p) < 3.5:
				later(0.18, func(): if o2["alive"]: explode_barrel(o2))
	if downed > 0:
		var pts := scoring.add(int(Scoring.POINTS["barrel"]) * downed)
		ui.popup(p + Vector3(0, 1.5, 0), "+%d" % pts, "פיצוץ", "")

func collect(p) -> void:
	p.alive = false; p.dispose()
	if p.type == "shield":
		shields = mini(5, shields + 1)
		ui.hud_shields(shields, false)
		Sfx.play("shield", 0.9)
		ui.callout("מגן נוסף", "good", "")
	else:
		weapon.equip(p.type)
		ui.hud_weapon(weapon)
		Sfx.play("pickup", 0.9)
		ui.callout(String(PlayerWeapon.WEAPONS[p.type]["name"]), "good", "")

func fly_away(obj: Node3D, pos: Vector3) -> void:
	var v := (pos - camera.global_position).normalized() * 1.5
	v.y = 4.5; v.x += randf_range(-1.5, 1.5)
	objects.append(Objects.Flyer.new(self, obj, pos, v, 1.4))

# ------------------------------------------------------------------ scoring callbacks
func on_enemy_neutralized(e, part: String, point: Vector3) -> void:
	var pts := scoring.hit(part)
	scoring.stage["kills"] += 1
	var label: String = {"head": "ראש", "torso": "", "legs": "רגליים", "weapon": "נטרול נקי"}[part]
	ui.popup(point, "+%s" % _n(pts), label, "gold" if part == "weapon" else ("hot" if part == "head" else ""))
	if part == "weapon": ui.callout("נטרול נקי", "good", "")
	if e.hostage != null and e.hostage.alive:
		var r := scoring.add(int(Scoring.POINTS["rescue"]))
		ui.popup(e.hostage.root_global() + Vector3(0, 2, 0), "+%d" % r, "חילוץ", "gold")
	ui.hud_score(scoring.total, scoring.multiplier(), scoring.combo)
	for a in actors:
		if a.is_civilian: a.panic()

func on_enemy_hurt(_e, point: Vector3) -> void:
	var pts := scoring.hit("torso")
	ui.popup(point, "+%d" % pts, "שריון", "")
	ui.hud_score(scoring.total, scoring.multiplier(), scoring.combo)

func on_civilian_hit(_c, point: Vector3) -> void:
	scoring.stage["civilians"] += 1
	scoring.combo = 0
	ui.callout("פגעת באזרח", "bad", "")
	ui.popup(point, "", "אזרח!", "bad")
	if state == "playing" and not dev_god: player_hurt()

func on_boss_hurt(_b, part: String, point: Vector3) -> void:
	var pts := scoring.hit("torso" if part == "weapon" else part)
	ui.popup(point, "+%d" % pts, "ראש" if part == "head" else "", "")
	ui.hud_score(scoring.total, scoring.multiplier(), scoring.combo)

func on_boss_defeated(b) -> void:
	var pts := scoring.add(int(Scoring.POINTS["boss"]))
	ui.callout("הבוס הובס!", "clear", "+%s" % _n(pts))
	ui.hud_score(scoring.total, scoring.multiplier(), scoring.combo)
	# slow motion with a push-in and depth of field on the boss
	slowmo = 1.8
	rail.fov = 45.0
	var bp: Vector3 = b.root_global() + Vector3(0, 1.2, 0)
	rail.turn_to(bp, 3.0)
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = camera.global_position.distance_to(bp) + 2.0
	cam_attr.dof_blur_far_transition = 6.0
	cam_attr.dof_blur_near_enabled = true
	cam_attr.dof_blur_near_distance = 2.0
	cam_attr.dof_blur_amount = 0.12
	Sfx.set_music_rate(0.7)
	for a in actors:
		if a.is_enemy and a != b and a.alive: a.die("torso")
	for o in objects:
		if o.get("is_grenade") and o.alive:
			o.alive = false; o.dispose()
	later(3.2, stage_clear)

func stage_clear() -> void:
	if state != "playing": return
	state = "results"
	rail.fov = 62.0
	cam_attr.dof_blur_far_enabled = false; cam_attr.dof_blur_near_enabled = false
	Sfx.set_music_rate(1.0)
	Sfx.stop_music(0.6)
	Sfx.play("stage_clear", 1.0)
	main.set_aiming(false)
	Settings.unlock_stage(stage_index + 2)
	scoring.stage["time"] = stage_time
	var rank := scoring.rank(int(stage.get("target", 30000)), continues_used_stage)
	run_ranks.append(rank["value"])
	later(1.2, func(): Sfx.play_music("results"))
	ui.show_results({"stage": stage, "stats": scoring.stage, "accuracy": scoring.accuracy(), "rank": rank, "total": scoring.total, "last": stage_index == 2})
	main.on_stage_clear()

func game_over() -> void:
	state = "gameover"
	main.set_aiming(false)
	Sfx.stop_all_loops()
	Sfx.set_music_rate(0.8)
	ui.show_game_over(3 - continues_used, scoring.total)

func continue_game() -> void:
	continues_used += 1
	continues_used_stage += 1
	scoring.reset_score()
	shields = 5
	invuln = 2.5
	Sfx.set_music_rate(1.0)
	ui.hud_shields(shields, false)
	ui.hud_score(0, 1, 0)
	state = "playing"
	main.set_aiming(true)
	for a in actors:
		if a.threat != null: a.threat["remaining"] = a.threat["duration"]
	if pending_advance:
		pending_advance = false; advance()

func new_run(diff: String, stage_i := 0, zone := 0, skip_intro := false) -> void:
	difficulty = diff
	scoring = Scoring.new()
	continues_used = 0; continues_used_stage = 0
	shields = 5
	run_ranks = []
	start_stage(stage_i, zone, skip_intro)

func next_stage(index := -1) -> void:
	continues_used_stage = 0
	shields = maxi(shields, 3)
	start_stage(index if index >= 0 else stage_index + 1)

func set_paused(p: bool) -> void:
	paused = p
	Sfx.set_paused(p)
	main.set_aiming(not p and (state == "playing" or state == "intro"))

# ------------------------------------------------------------------ frame
## Fixed-step simulation (called from _physics_process at 120 Hz).
func step(dt_real: float) -> void:
	if warming: return
	if paused:
		rail.update(0.0, true); return
	if slowmo > 0.0:
		slowmo -= dt_real; time_scale = 0.25
	else:
		time_scale = 1.0
	var dt := dt_real * time_scale
	if state == "playing" or state == "intro": stage_time += dt_real
	if invuln > 0.0: invuln -= dt_real
	for i in range(timers.size() - 1, -1, -1):
		timers[i][0] -= dt_real
		if timers[i][0] <= 0.0:
			var cb: Callable = timers[i][1]
			timers.remove_at(i)
			cb.call()
	var wr := weapon.update(dt_real)
	if wr == "reloaded":
		ui.hud_weapon(weapon); ui.hud_reloading(false)
	if state == "playing" and mouse_down and bool(weapon.def["auto"]): try_fire()
	rail.update(dt, false)
	_apply_shake(dt_real)
	_update_rigs(dt)
	if state == "playing": update_encounter(dt)
	var i := 0
	while i < actors.size():
		actors[i].update(dt)
		i += 1
	actors = actors.filter(func(a): return not a.removed)
	for o in objects:
		if o.has_method("update"): o.update(dt)
	objects = objects.filter(func(o): return o.alive)
	if branch_signs != null:
		for s in branch_signs: s.update(dt)
		if state == "playing":
			branch_timer -= dt
			if branch_timer <= 0.0: choose_branch(forced_branch if forced_branch != "" else "left")
	fx.update(dt)
	if autoplay: autoplay.tick(dt_real)

func _apply_shake(dt: float) -> void:
	if shake > 0.001:
		var a := shake * shake * 0.18
		camera.position += camera.global_basis * Vector3(randf_range(-0.5, 0.5) * a, randf_range(-0.5, 0.5) * a, 0)
		shake = maxf(0.0, shake - dt * 2.2)

func _update_rigs(dt: float) -> void:
	for z in zones:
		if not z.def.has("travel"): continue
		if z == current_zone and rail.travel and rail.curve != null:
			var p := camera.global_position
			p.y = float(z.def["travel"].get("rigY", 0))
			z.rig.position = z.to_local(p)
			z.rig.position.y = float(z.def["travel"].get("rigY", 0))
			var tan := rail.tangent_at(minf(0.999, rail.u))
			z.rig.rotation.y = atan2(-tan.x, -tan.z) - z.anchor_yaw
		if z.has_meta("siren"):
			var on := sin(stage_time * 14.0) > 0.0
			var lights: Array = z.get_meta("siren")
			lights[0].light_energy = 8.0 if on else 0.0
			lights[1].light_energy = 0.0 if on else 8.0
		for a in z.get_meta("rig_anims", []):
			a["t"] += dt
			a["obj"].position.x = a["base"] + sin(a["t"] * a["sway"]) * a["amp"]

func _n(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out
