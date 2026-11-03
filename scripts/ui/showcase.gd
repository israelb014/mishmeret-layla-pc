class_name Showcase
extends Control
## Live background of the loading screens, the main menu and the results screen.
## Real zones of the game are built into their own worlds (one per stage, with that stage's
## sky, sun and fog) and rendered live; the camera cross-fades every 4 seconds between preset
## viewpoints. Stage 1's viewpoints come first; stages 2-3 join when they finish streaming.
## Each viewpoint is saved once as a JPEG in user://loading/, so on later launches those images
## show from the very first frame until the live scene is ready. Before anything exists (first
## seconds of the very first launch) only the dark background is shown.

const HOLD := 4.0
const FADE := 1.2
const DRIFT := 0.35 # m/s slow dolly toward the view target
const VIEWS := [
	{"key": "street", "stage": 0, "zone": "1-1"},
	{"key": "market", "stage": 0, "zone": "1-4א"},
	{"key": "alley", "stage": 0, "zone": "1-5א"},
	{"key": "boss1", "stage": 0, "zone": "1-8"},
	{"key": "port", "stage": 1, "zone": "2-1"},
	{"key": "station", "stage": 2, "zone": "3-1"},
]

var game: Node
var active := false
var worlds := {} # stage index -> holder SubViewport (own World3D, never rendered itself)
var live: Array = [] # ready live viewpoints
var cached: Array = [] # images saved by earlier launches
var saved := {} # viewpoint key -> JPEG exists (or is being written)
var tasks: Array = [] # WorkerThreadPool tasks writing JPEGs
var layers: Array = [] # two display layers: {rect, vp, cam, slide, age}
var front := 0
var printed := false
var rot := 0
var base := ColorRect.new()
var shade := TextureRect.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	base.color = Color(0.03, 0.035, 0.05)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	for i in 2:
		var vp := SubViewport.new()
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.size = Vector2i(1280, 720)
		var cam := Camera3D.new()
		cam.fov = 62.0
		cam.near = 0.2
		cam.far = 300.0
		vp.add_child(cam)
		add_child(vp)
		var r := TextureRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.modulate.a = 0.0
		add_child(r)
		layers.append({"rect": r, "vp": vp, "cam": cam, "slide": null, "age": 0.0})
	# darker top and bottom so the title, the tip and the menu always read
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.75)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	gt.width = 4; gt.height = 256
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

## Images saved by earlier launches: shown instantly until the live views are ready.
func load_cache() -> void:
	for v in VIEWS:
		var path := "user://loading/%s.jpg" % v["key"]
		if not FileAccess.file_exists(path): continue
		var img := Image.load_from_file(path)
		if img == null or img.is_empty(): continue
		cached.append({"kind": "img", "key": v["key"], "tex": ImageTexture.create_from_image(img)})
		saved[v["key"]] = true

func set_active(on: bool) -> void:
	active = on
	if not on:
		for l in layers:
			(l["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED

func has_live() -> bool:
	return not live.is_empty()

func has_stage(index: int) -> bool:
	return worlds.has(index)

static func _zone_def(stage: Dictionary, id: String):
	for z in stage["zones"]:
		if String(z["id"]) == id: return z
		if z.has("branch"):
			for side in ["left", "right"]:
				for bz in z["branch"][side]["zones"]:
					if String(bz["id"]) == id: return bz
	return null

## Builds a stage's viewpoint zones into a world of their own (one zone per frame).
## The stage's prefabs must already be loaded and prepared.
func add_stage(index: int) -> void:
	if worlds.has(index): return
	var holder := SubViewport.new()
	holder.world_3d = World3D.new() # shared with the display viewports below
	holder.render_target_update_mode = SubViewport.UPDATE_DISABLED
	holder.size = Vector2i(2, 2)
	add_child(holder)
	worlds[index] = holder
	var stage: Dictionary = game.stages[index]
	var wenv := WorldEnvironment.new()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 1.2
	sun.light_angular_distance = 0.6
	var attr := CameraAttributesPractical.new()
	holder.add_child(wenv)
	holder.add_child(sun)
	game.apply_environment_to(stage, wenv, sun, attr)
	attr.auto_exposure_enabled = false # every cut starts at the right brightness
	attr.dof_blur_far_enabled = false
	var k := 0
	for v in VIEWS:
		if int(v["stage"]) != index: continue
		var def = _zone_def(stage, String(v["zone"]))
		if def == null: continue
		var off := Vector3(800.0 * k, 0, 0)
		var z := Zone.new()
		z.setup(game, def, 0, stage, off, 0.0)
		z.build()
		holder.add_child(z)
		var path: Array = def.get("path", [[0, 1.7, 0]])
		var p: Vector3 = off + U.v3(path[0])
		var t: Vector3 = off + U.v3(def.get("look", [0, 1.5, -20]))
		live.append({"kind": "live", "key": v["key"], "world": holder.world_3d, "pos": p, "target": t, "attr": attr, "far": Game.far_for(stage)})
		k += 1
		await get_tree().process_frame
	if k > 0 and not printed:
		printed = true
		print("LIVE_BACKGROUND_MS=%d" % Time.get_ticks_msec())

func _next_slide(after):
	var list: Array = live if not live.is_empty() else cached
	if list.is_empty(): return null
	rot += 1
	var s = list[rot % list.size()]
	if s == after and list.size() > 1:
		rot += 1
		s = list[rot % list.size()]
	return s

func _show(l: Dictionary, s: Dictionary) -> void:
	l["slide"] = s
	l["age"] = 0.0
	var r: TextureRect = l["rect"]
	var vp: SubViewport = l["vp"]
	if s["kind"] == "img":
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		r.texture = s["tex"]
	else:
		vp.world_3d = s["world"]
		var main_vp := get_viewport()
		vp.msaa_3d = main_vp.msaa_3d
		vp.screen_space_aa = main_vp.screen_space_aa
		(l["cam"] as Camera3D).attributes = s["attr"]
		(l["cam"] as Camera3D).far = float(s["far"])
		(l["cam"] as Camera3D).current = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		r.texture = vp.get_texture()
		_update_cam(l)

func _update_cam(l: Dictionary) -> void:
	var s = l["slide"]
	if s == null or s["kind"] != "live": return
	var p: Vector3 = s["pos"]
	var t: Vector3 = s["target"]
	var dir := t - p
	dir.y = 0.0
	if dir.length_squared() < 0.01: dir = Vector3(0, 0, -1)
	dir = dir.normalized()
	var pos := p + dir * DRIFT * float(l["age"])
	(l["cam"] as Camera3D).look_at_from_position(pos, t + dir * DRIFT * float(l["age"]), Vector3.UP)

func _process(dt: float) -> void:
	if not active or not is_visible_in_tree(): return
	var px := Vector2i(maxi(640, int(size.x)), maxi(360, int(size.y)))
	for l in layers:
		if (l["vp"] as SubViewport).size != px: (l["vp"] as SubViewport).size = px
	var f: Dictionary = layers[front]
	var b: Dictionary = layers[1 - front]
	if f["slide"] == null:
		var s = _next_slide(null)
		if s == null: return # nothing yet: dark background only
		_show(f, s)
		f["age"] = FADE
		(f["rect"] as TextureRect).modulate.a = 1.0
		_order(f)
	f["age"] = float(f["age"]) + dt
	_update_cam(f)
	_maybe_save(f)
	# move on when the hold is over, or as soon as the live scene replaces the saved images
	var switch_now: bool = float(f["age"]) >= FADE + HOLD or (f["slide"]["kind"] == "img" and not live.is_empty())
	if not switch_now and b["slide"] == null: return
	if b["slide"] == null:
		var n = _next_slide(f["slide"])
		if n == null or n == f["slide"]:
			f["age"] = FADE
			return
		_show(b, n)
		_order(b)
	b["age"] = float(b["age"]) + dt
	_update_cam(b)
	(b["rect"] as TextureRect).modulate.a = clampf(float(b["age"]) / FADE, 0.0, 1.0)
	if float(b["age"]) >= FADE:
		(f["rect"] as TextureRect).modulate.a = 0.0
		(f["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		f["slide"] = null
		front = 1 - front

## The incoming layer is drawn on top (just under the shade).
func _order(l: Dictionary) -> void:
	move_child(l["rect"], shade.get_index() - 1 if shade.get_index() > 0 else 0)

## Saves a live viewpoint as JPEG once it has been fully visible for a moment.
func _maybe_save(l: Dictionary) -> void:
	var s = l["slide"]
	if s == null or s["kind"] != "live" or saved.has(s["key"]) or float(l["age"]) < FADE + 0.6: return
	saved[s["key"]] = true
	if DisplayServer.get_name() == "headless": return
	var img := (l["vp"] as SubViewport).get_texture().get_image()
	if img == null or img.is_empty(): return
	if img.get_width() > 1600:
		img.resize(1600, int(1600.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://loading"))
	var path := ProjectSettings.globalize_path("user://loading/%s.jpg" % s["key"])
	tasks.append(WorkerThreadPool.add_task(func(): img.save_jpg(path, 0.88)))

## Joins the JPEG writers (called before quitting).
func wait_tasks() -> void:
	for id in tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	tasks.clear()

func poll_tasks() -> void:
	var i := tasks.size() - 1
	while i >= 0:
		if WorkerThreadPool.is_task_completed(tasks[i]):
			WorkerThreadPool.wait_for_task_completion(tasks[i])
			tasks.remove_at(i)
		i -= 1
