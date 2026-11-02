extends Node
## Entry point: loading, warm-up, menu, run lifecycle, perf monitor, benchmark and autotest.

var ui: UI
var game: Game
var loaded := {}
var mode := "boot"
var aiming := false
var bot_aim := Vector2(-1, -1)
var autoplay: Autoplay
var bench: Dictionary = {} # benchmark / autotest state
var frame_times := PackedFloat32Array()
var ft_i := 0
var perf_visible := false
var final_rank := "B"
var prebuilt := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.physics_ticks_per_second = 120
	frame_times.resize(1200)
	Settings.apply_display()
	ui = UI.new()
	ui.setup(self)
	add_child(ui)
	game = Game.new()
	add_child(game)
	game.setup(self)
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if args.has("--windowed"):
		Settings.data["display"] = "window"
		Settings.data["resolution"] = "1280x720"
		Settings.apply_display()
	if args.has("--benchmark"):
		bench = {"kind": "benchmark", "results": []}
		Settings.apply_preset("high")
		Settings.apply_display()
	elif args.has("--autotest"):
		bench = {"kind": "autotest", "results": [], "errors": 0}
	elif args.has("--shots"):
		bench = {"kind": "shots", "results": []}
	await _boot()

func _boot() -> void:
	var ring := ui.loading()
	await load_everything(func(p): ring.set_value(p); ring.label = "%d%%" % int(p * 100); ring.queue_redraw())
	if not bench.is_empty():
		await _run_bench()
		return
	await show_menu()

## Threaded loading of every asset with real progress.
func load_everything(progress: Callable) -> void:
	var paths: Array = []
	for n in game.prefabs.all_names(): paths.append(game.prefabs.path_of(n))
	for m in Character.OUTFIT_MATS.keys(): paths.append("res://assets/chars/%s.glb" % m)
	paths.append("res://assets/anims/anims.glb")
	for s in Materials.SETS:
		for p in game.mats.textures_of(s): paths.append(p)
	for h in ["afternoon", "sunset", "night"]: paths.append("res://assets/hdr/%s.hdr" % h)
	for p in paths:
		ResourceLoader.load_threaded_request(p, "", true)
	var done := 0
	while done < paths.size():
		done = 0
		var frac := 0.0
		for p in paths:
			var prog := []
			var st := ResourceLoader.load_threaded_get_status(p, prog)
			if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED:
				done += 1; frac += 1.0
			else:
				frac += float(prog[0]) if prog.size() > 0 else 0.0
		progress.call(0.85 * frac / paths.size())
		await get_tree().process_frame
	for p in paths:
		loaded[p] = ResourceLoader.load_threaded_get(p)
	Character.init_library()
	await game.make_graffiti_textures()
	# normalise every prefab once
	var names: Array = game.prefabs.all_names()
	for i in names.size():
		game.prefabs.prepare(names[i])
		if i % 12 == 0:
			progress.call(0.85 + 0.15 * float(i) / names.size())
			await get_tree().process_frame
	progress.call(1.0)
	print("[load] assets ready ", paths.size())

## Stage loading screen: build every zone (both branches), pool characters, warm shaders.
func prepare_stage(index: int) -> void:
	print("[load] stage ", index)
	var ring := ui.loading()
	ring.label = "0%"
	var st: Dictionary = game.stages[index]
	var defs: Array = []
	for z in st["zones"]:
		defs.append(z)
		if z.has("branch"):
			for side in ["left", "right"]: defs.append_array(z["branch"][side]["zones"])
	# character pool sized from the stage data
	var counts := {}
	_count_models(st, counts)
	var models := counts.keys()
	for mi in models.size():
		game.pools.warm(models[mi], mini(8, int(counts[models[mi]]) + 2))
		ring.set_value(0.3 * float(mi + 1) / models.size()); ring.label = "%d%%" % int(ring.value * 100)
		await get_tree().process_frame
	for old in game.prebuilt.values():
		if is_instance_valid(old) and not old.is_inside_tree(): old.free()
	game.prebuilt.clear()
	game.stage = st
	game.stage_index = index
	for i in defs.size():
		var z := Zone.new()
		z.setup(game, defs[i], i, st, Vector3(0, 0, -100000), 0.0)
		z.build()
		game.setup_rig(z)
		game.prebuilt[String(defs[i]["id"])] = z
		ring.set_value(0.3 + 0.5 * float(i + 1) / defs.size()); ring.label = "%d%%" % int(ring.value * 100)
		await get_tree().process_frame
	print("[load] zones built ", defs.size())
	await warm_up(st, ring)
	print("[load] warm-up done")

func _count_models(v, counts: Dictionary) -> void:
	if v is Dictionary:
		if v.has("enemy") and v["enemy"] is Dictionary:
			var e: Dictionary = v["enemy"]
			var m := String(e.get("model", "swat" if e.get("kind") == "heavy" else "punk"))
			counts[m] = int(counts.get(m, 0)) + 1
			if e.get("kind") == "hostage": counts[String(e.get("hostage", "woman"))] = int(counts.get(String(e.get("hostage", "woman")), 0)) + 1
		if v.has("civ") and v["civ"] is Dictionary:
			var cm := String(v["civ"].get("model", "casual"))
			counts[cm] = int(counts.get(cm, 0)) + 1
		if v.has("boss") and v["boss"] is Dictionary:
			counts[String(v["boss"]["model"])] = int(counts.get(String(v["boss"]["model"]), 0)) + 2
			for s in v["boss"].get("summon", []):
				var sm := String(s.get("model", "punk"))
				counts[sm] = int(counts.get(sm, 0)) + 2
		for k in v.keys(): _count_models(v[k], counts)
	elif v is Array:
		for x in v: _count_models(x, counts)
	for m in ["beach", "woman", "farmer", "casual"]:
		counts[m] = maxi(int(counts.get(m, 0)), 2)

## Render everything once off-screen (behind the loading screen) so all shader pipelines
## and particle materials are compiled before gameplay starts.
func warm_up(st: Dictionary, ring: Ring) -> void:
	game.setup_stage(game.stage_index)
	var cam := game.camera
	cam.global_position = Vector3(0, 1.7, 8)
	cam.look_at(Vector3(0, 1.5, 0))
	var temp := []
	for z in game.prebuilt.values():
		z.position = Vector3(0, 0, 0)
		# probe updates take several frames; never queue one for a zone that is detached right after
		if z.probe: z.probe.visible = false
		game.stage_root.add_child(z)
		temp.append(z)
	var chars := game.pools.all_characters()
	for i in chars.size():
		var c: Character = chars[i]
		c.visible = true
		c.position = Vector3((i % 8) - 4.0, 0, -2.0 - int(i / 8))
		c.configure(game, {"rim": true, "rim_strength": 0.5, "weapon": "pistol"})
	game.pools.visible = true
	game.fx.warm_up(Vector3(0, 1.5, 0))
	for f in 6:
		cam.rotate_y(TAU / 6.0)
		ring.set_value(0.8 + 0.2 * (f + 1) / 6.0); ring.label = "%d%%" % int(ring.value * 100)
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	for z in temp:
		game.stage_root.remove_child(z)
		z.position = Vector3(0, 0, -100000)
		if z.probe: z.probe.visible = true
	for c in chars:
		c.visible = false
		c.detach_weapon()
	game.pools.visible = false
	game.fx.clear()

# ------------------------------------------------------------------ menu / runs
func show_menu() -> void:
	mode = "menu"
	set_aiming(false)
	ui.hud_show(false)
	await prepare_stage(0)
	game.setup_stage(0, true)
	for i in 3: game.ensure_zone(i)
	var z0: Zone = game.zones[0]
	var path := []
	for p in game.stage["menuPath"]: path.append(game.to_world(z0, p))
	var look := game.to_world(z0, game.stage["intro"]["look"])
	game.state = "menu"
	_fly_menu(path, look)
	ui.menu()
	Sfx.play_music("menu")

func _fly_menu(path: Array, look: Vector3) -> void:
	if mode != "menu": return
	game.rail.jump(path[0], look)
	game.rail.move_along(path.slice(1), {"duration": 34.0, "linear": true, "travel": true, "look_ahead": 0.05, "on_done": _fly_menu.bind(path, look)})

func start_run(diff: String, stage_i := 0, zone := 0, skip_intro := false) -> void:
	mode = "game"
	ui.clear_screen()
	await prepare_stage(stage_i)
	ui.clear_screen()
	game.new_run(diff, stage_i, zone, skip_intro)
	set_aiming(true)

func set_aiming(v: bool) -> void:
	aiming = v
	ui.crosshair.visible = v
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if v else Input.MOUSE_MODE_VISIBLE

func aim_position() -> Vector2:
	if bot_aim.x >= 0.0: return bot_aim
	return get_viewport().get_mouse_position()

func toggle_pause() -> void:
	if mode != "game": return
	if game.state != "playing" and game.state != "intro": return
	if game.paused:
		resume(); return
	game.set_paused(true)
	get_tree().paused = true
	ui.pause()

func resume() -> void:
	ui.clear_screen()
	get_tree().paused = false
	game.set_paused(false)

func restart_stage() -> void:
	ui.clear_screen()
	get_tree().paused = false
	game.set_paused(false)
	game.scoring.total -= int(game.scoring.stage["score"])
	await prepare_stage(game.stage_index)
	ui.clear_screen()
	game.start_stage(game.stage_index)
	set_aiming(true)

func quit_to_menu() -> void:
	ui.clear_screen()
	get_tree().paused = false
	game.set_paused(false)
	game.clear_stage()
	await show_menu()

func continue_run() -> void:
	ui.clear_screen()
	game.continue_game()

func end_run() -> void:
	var total := game.scoring.total
	var rank := String(game.scoring.rank(int(game.stage.get("target", 30000)), game.continues_used_stage)["letter"])
	ui.clear_screen()
	if Settings.qualifies(total):
		ui.name_entry(total, game.stage_index + 1, rank, func(idx): ui.highscores(idx, quit_to_menu))
	else:
		quit_to_menu()

func after_results() -> void:
	if game.stage_index >= 2:
		var avg := 0.0
		for r in game.run_ranks: avg += float(r)
		avg /= maxf(1.0, game.run_ranks.size())
		final_rank = "S" if avg >= 85 else ("A" if avg >= 70 else ("B" if avg >= 55 else ("C" if avg >= 38 else "D")))
		ui.ending(game.scoring.total, final_rank)
		return
	ui.clear_screen()
	await prepare_stage(game.stage_index + 1)
	ui.clear_screen()
	game.next_stage()
	set_aiming(true)

func finish_run() -> void:
	var total := game.scoring.total
	if Settings.qualifies(total):
		ui.name_entry(total, 3, final_rank, func(idx): ui.highscores(idx, quit_to_menu))
	else:
		ui.highscores(-1, quit_to_menu)

# ------------------------------------------------------------------ input & loop
func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("perf"):
		perf_visible = not perf_visible
		ui.perf_label.visible = perf_visible
	if e.is_action_pressed("pause"):
		toggle_pause()
		return
	if not aiming or game.paused: return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			game.mouse_down = mb.pressed
			if mb.pressed: game.on_shoot()
	if e.is_action_pressed("reload"):
		game.reload()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == "game" and not game.paused and bench.is_empty():
		toggle_pause()

func _physics_process(dt: float) -> void:
	if get_tree().paused: return
	game.step(dt)
	if not bench.is_empty(): _bench_tick()

func _process(dt: float) -> void:
	frame_times[ft_i] = dt
	ft_i = (ft_i + 1) % frame_times.size()
	if perf_visible and Engine.get_process_frames() % 15 == 0:
		var s := perf_stats(frame_times)
		ui.perf_label.text = "FPS %.0f   1%% low %.0f   worst %.1f ms   draws %d" % [s["avg"], s["low1"], s["worst"] * 1000.0, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	if bench.has("zone_times"): bench["zone_times"].append(dt)
	_auto_probe(dt)

## "אוטומטי": measures 5 s of the menu fly-through once and picks the preset (result is saved).
var probe_t := -1.0
var probe_frames := 0
func _auto_probe(dt: float) -> void:
	if not bench.is_empty() or Settings.g("preset") != "auto" or Settings.g("resolved") != "" or mode != "menu" or game.state != "menu":
		probe_t = -1.0
		return
	if probe_t < 0.0:
		probe_t = 0.0; probe_frames = 0
		return
	probe_t += dt; probe_frames += 1
	if probe_t < 5.0: return
	var fps := probe_frames / probe_t
	var pick := "ultra" if fps >= 110.0 else ("high" if fps >= 75.0 else ("medium" if fps >= 45.0 else "low"))
	Settings.data["resolved"] = pick
	Settings.apply_preset("auto")
	Settings.apply_display()
	game.refresh_graphics()

## free everything that is not in the scene tree before quitting (clean exit, no leaks)
func cleanup() -> void:
	game.clear_stage()
	for z in game.prebuilt.values():
		if is_instance_valid(z) and not z.is_inside_tree(): z.free()
	game.prebuilt.clear()
	for t in game.prefabs.templates.values():
		if is_instance_valid(t): t.free()
	game.prefabs.templates.clear()
	Character.scenes.clear()
	Character.library = null
	Character._tree_proto = null

func _notification_quit() -> void:
	pass

static func perf_stats(ft: PackedFloat32Array) -> Dictionary:
	var arr: Array = []
	for v in ft:
		if v > 0.0: arr.append(v)
	if arr.is_empty(): return {"avg": 0.0, "low1": 0.0, "worst": 0.0, "n": 0}
	arr.sort()
	var total := 0.0
	for v in arr: total += v
	var n1 := maxi(1, int(arr.size() * 0.01))
	var worst_sum := 0.0
	for i in n1: worst_sum += arr[arr.size() - 1 - i]
	return {"avg": arr.size() / total, "low1": n1 / worst_sum, "worst": arr[arr.size() - 1], "n": arr.size()}

# ------------------------------------------------------------------ benchmark / autotest / screenshots
func _run_bench() -> void:
	var plan := []
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stages="):
			for n in a.substr(9).split(","): only.append(int(n) - 1)
	for si in 3:
		if not only.is_empty() and not only.has(si): continue
		plan.append({"stage": si, "zone": 0, "branch": "left"})
		var bi := -1
		for i in (game.stages[si]["zones"] as Array).size():
			if game.stages[si]["zones"][i].has("branch"): bi = i
		plan.append({"stage": si, "zone": bi + 1, "branch": "right"})
	bench["plan"] = plan
	bench["step"] = -1
	await _bench_next()

func _bench_next() -> void:
	bench["step"] += 1
	if bench["step"] >= (bench["plan"] as Array).size():
		_bench_finish(); return
	var p: Dictionary = bench["plan"][bench["step"]]
	game.forced_branch = p["branch"]
	game.dev_god = true
	mode = "game"
	await prepare_stage(p["stage"])
	ui.clear_screen()
	game.new_run("normal", p["stage"], p["zone"], p["zone"] > 0)
	autoplay = Autoplay.new(); autoplay.setup(self); game.autoplay = autoplay
	game.rail.time = 0.0
	bench["zone"] = -1
	bench["zone_times"] = []
	bench["zone_t0"] = Time.get_ticks_msec()
	bench["stage_t0"] = Time.get_ticks_msec()
	bench["stage_f0"] = Engine.get_process_frames()
	bench["zone_f0"] = Engine.get_process_frames()
	bench["running"] = true
	bench["shot_zone"] = -1

func _bench_tick() -> void:
	if not bench.get("running", false): return
	var z := game.zone_idx
	if game.state == "intro":
		game.rail.time = game.rail.duration
	if z != bench["zone"] or game.state == "results":
		if bench["zone"] >= 0:
			var times: Array = bench["zone_times"]
			var ft := PackedFloat32Array(times.slice(mini(30, times.size() / 4)))
			var s := perf_stats(ft)
			var rid := String(game.route[bench["zone"]]["id"]) if bench["zone"] < game.route.size() else "?"
			var line := {"kills": game.scoring.stage["kills"], "stage": game.stage_index + 1, "zone": rid, "branch": bench["plan"][bench["step"]]["branch"], "avg": s["avg"], "low1": s["low1"], "worst_ms": s["worst"] * 1000.0, "secs": (Time.get_ticks_msec() - bench["zone_t0"]) / 1000.0}
			if not (bench["results"] as Array).any(func(r): return r["zone"] == rid and r["stage"] == line["stage"]):
				bench["results"].append(line)
				print("BENCH ", JSON.stringify(line))
		# shots/benchmark: the right-branch run ends once it rejoins zones the left run already covered
		if bench["kind"] != "autotest" and bench["plan"][bench["step"]]["branch"] == "right" and z < game.route.size() and game.state != "results":
			var nid := String(game.route[z]["id"])
			if (bench["results"] as Array).any(func(r): return r["zone"] == nid and r["stage"] == game.stage_index + 1):
				bench["running"] = false
				game.autoplay = null
				game.clear_stage()
				_bench_next.call_deferred()
				return
		bench["zone"] = z
		bench["zone_times"] = []
		bench["zone_t0"] = Time.get_ticks_msec()
		bench["zone_f0"] = Engine.get_process_frames()
	if bench["kind"] == "shots" and game.encounter != null and bench["shot_zone"] != z and game.encounter["wave_time"] > 1.0 and not game.encounter["done"] and (game.encounter["zone"] as Zone).index == z:
		bench["shot_zone"] = z
		_screenshot("stage%d_zone%02d_%s_%s" % [game.stage_index + 1, z + 1, bench["plan"][bench["step"]]["branch"], game.route[z]["id"]])
	# stuck detection in game time (frames at --fixed-fps 60), so slow software renderers do not trip it
	var frames := Engine.get_process_frames()
	var timeout: bool = frames - int(bench["stage_f0"]) > 60 * 60 * 25 and bench["kind"] != "autotest"
	if game.state == "results" or timeout or frames - int(bench["zone_f0"]) > 60 * 240:
		if game.state != "results":
			var alive := []
			for a in game.actors:
				if a.alive: alive.append("%s:%s:%s@%s" % ["boss" if a.is_boss else ("civ" if a.is_civilian else a.kind), a.state, a.get("hp"), a.root_global()])
			print("BENCH_STUCK ", game.stage_index + 1, " ", game.route[z]["id"], " wave=", game.encounter["wave"] if game.encounter else -1, " branch_signs=", game.branch_signs != null, " ", alive)
			bench["errors"] = int(bench.get("errors", 0)) + 1
		bench["running"] = false
		game.autoplay = null
		game.clear_stage()
		_bench_next.call_deferred()

func _screenshot(nm: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_environment("SHOTS_DIR")
	if dir == "": dir = OS.get_executable_path().get_base_dir()
	img.save_png("%s/%s.png" % [dir, nm])
	print("SHOT ", nm)

func _bench_finish() -> void:
	var out := "Mishmeret Layla — benchmark (%s)\n" % bench["kind"]
	out += "GPU: %s | %s | preset: %s | resolution: %s\n" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), Settings.effective_preset(), get_viewport().get_visible_rect().size]
	out += "stage\tzone\tbranch\tavg_fps\tlow1_fps\tworst_ms\n"
	var all_low := 999.0
	var all_worst := 0.0
	for r in bench["results"]:
		out += "%d\t%s\t%s\t%.1f\t%.1f\t%.2f\n" % [r["stage"], r["zone"], r["branch"], r["avg"], r["low1"], r["worst_ms"]]
		all_low = minf(all_low, r["low1"]); all_worst = maxf(all_worst, r["worst_ms"])
	out += "zones: %d | lowest 1%% low: %.1f fps | worst frame: %.2f ms | stuck: %d\n" % [(bench["results"] as Array).size(), all_low, all_worst, int(bench.get("errors", 0))]
	var path := OS.get_executable_path().get_base_dir().path_join("benchmark.txt")
	if OS.has_feature("editor") or OS.get_environment("BENCH_OUT") != "":
		path = OS.get_environment("BENCH_OUT") if OS.get_environment("BENCH_OUT") != "" else "user://benchmark.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(out); f.close()
	print(out)
	print("BENCH_DONE ", path)
	cleanup()
	get_tree().quit(0 if int(bench.get("errors", 0)) == 0 else 3)
