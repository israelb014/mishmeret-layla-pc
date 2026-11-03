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
var stage_assets: Dictionary = {} # data/stage_assets.json: common prefabs + per-stage prefabs
var loading := false # a loading screen is up: Esc quits
var streaming: Array = [] # resource paths of stages 2-3 being loaded in the background
var stream_tick := 0
var load_time_reported := false
var prepared := -1 # stage whose zones are built + warmed and not consumed by play yet
var preparing := -1 # stage being prepared by the background job (-1: none)
var job_progress := 0.0
var job_status := ""
var common_ready := false
var inflight: Array = [] # every threaded load request not collected yet (joined before quitting)
var quitting := false
var showcase_busy := false # a stage's viewpoints are being added to the live background
var results_stage := -1
var flow := {} # --flowtest driver state
const STATUS := {"tex": "טוען טקסטורות", "char": "טוען דמויות ואנימציות", "model": "טוען מודלים", "sky": "טוען שמיים"}

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
	ui.backdrop.game = game
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if args.has("--benchmark"):
		bench = {"kind": "benchmark", "results": []}
		Settings.apply_preset("high")
		Settings.apply_display()
	elif args.has("--autotest"):
		bench = {"kind": "autotest", "results": [], "errors": 0}
	elif args.has("--shots"):
		bench = {"kind": "shots", "results": []}
	elif args.has("--flowtest"):
		bench = {"kind": "flow", "results": []}
	get_tree().set_auto_accept_quit(false)
	await _boot()

func _boot() -> void:
	# startup loads only what the menu needs (UI, fonts, the shots); stage 1 then streams and is
	# built in the background while the menu is shown
	stage_assets = U.load_json("res://data/stage_assets.json")
	if not bench.is_empty() and bench["kind"] != "flow":
		await _run_bench()
		return
	# loading screen (title + tip + thin line over the saved images, or the dark background on the
	# very first launch) until stage 1's first zones render live behind it; then the menu
	loading = true
	var line := ui.loading()
	_start_job(0)
	while not ui.backdrop.has_live() and not (prepared == 0 and preparing == -1):
		if quitting: return
		ui.set_loading(line, minf(1.0, job_progress / 0.4), job_status)
		await get_tree().process_frame
	ui.set_loading(line, 1.0)
	loading = false
	await show_menu()

func _empty_groups() -> Dictionary:
	return {"tex": [], "char": [], "model": [], "sky": []}

func _common_groups() -> Dictionary:
	var g := _empty_groups()
	for s in Materials.SETS: g["tex"].append_array(game.mats.textures_of(s))
	for m in Character.OUTFIT_MATS.keys(): g["char"].append("res://assets/chars/%s.glb" % m)
	g["char"].append("res://assets/anims/anims.glb")
	for n in stage_assets["common"]: g["model"].append(game.prefabs.path_of(n))
	return g

func _stage_groups(i: int) -> Dictionary:
	var g := _empty_groups()
	for n in stage_assets["stages"][i]: g["model"].append(game.prefabs.path_of(n))
	g["sky"].append("res://assets/hdr/%s.hdr" % game.stages[i]["hdri"])
	return g

## Loads resources on worker threads. progress(fraction, status) runs every frame with real
## per-file progress. Paths already streaming are waited for, not requested twice.
func load_groups(groups: Dictionary, progress: Callable) -> void:
	var all: Array = []
	var kinds: Array = []
	for k in ["tex", "char", "model", "sky"]:
		for p in groups[k]:
			if loaded.has(p) or all.has(p): continue
			all.append(p); kinds.append(k)
			if not streaming.has(p) and not inflight.has(p):
				ResourceLoader.load_threaded_request(p, "", true)
				inflight.append(p)
	while not all.is_empty():
		if quitting: return
		var frac := 0.0
		var left := 0
		var pending := ""
		for i in all.size():
			var prog := []
			var st := ResourceLoader.load_threaded_get_status(all[i], prog)
			if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				left += 1
				frac += float(prog[0]) if prog.size() > 0 else 0.0
				if pending == "": pending = kinds[i]
			else:
				frac += 1.0
		progress.call(frac / all.size(), STATUS.get(pending, "טוען"))
		if left == 0: break
		await get_tree().process_frame
	for p in all:
		var r = ResourceLoader.load_threaded_get(p)
		if r != null: loaded[p] = r
		else: push_error("failed to load " + p)
		streaming.erase(p)
		inflight.erase(p)
	progress.call(1.0, "")

## Normalises prefab templates, yielding a frame whenever ~6 ms were spent (UI and menu stay live).
func _prepare_prefabs(names: Array, progress: Callable) -> void:
	var t := Time.get_ticks_usec()
	for i in names.size():
		if quitting: return
		game.prefabs.prepare(names[i])
		if Time.get_ticks_usec() - t > 6000:
			progress.call(float(i + 1) / names.size())
			await get_tree().process_frame
			t = Time.get_ticks_usec()
	progress.call(1.0)

## Background streaming of a stage's files (low priority, no sub-threads) while another plays.
func _stream_stage(i: int) -> void:
	if i < 0 or i > 2: return
	var g := _stage_groups(i)
	for k in g:
		for p in g[k]:
			if loaded.has(p) or streaming.has(p) or inflight.has(p): continue
			ResourceLoader.load_threaded_request(p, "", false)
			streaming.append(p)
			inflight.append(p)

func _stream_poll() -> void:
	stream_tick += 1
	if stream_tick % 20 != 0: return
	var i := streaming.size() - 1
	while i >= 0:
		var p: String = streaming[i]
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var r = ResourceLoader.load_threaded_get(p)
			if r != null: loaded[p] = r
			streaming.remove_at(i)
			inflight.erase(p)
		i -= 1
	ui.backdrop.poll_tasks()
	# stages 2-3 join the live background once streamed, but only while it is on screen
	# (building its zones would hitch gameplay)
	if common_ready and not showcase_busy and ui.backdrop.active:
		for si in [1, 2]:
			if not ui.backdrop.has_stage(si) and _stage_files_loaded(si):
				_add_showcase(si)
				break

func _stage_files_loaded(i: int) -> bool:
	var g := _stage_groups(i)
	for k in g:
		for p in g[k]:
			if not loaded.has(p): return false
	return true

func _add_showcase(i: int) -> void:
	showcase_busy = true
	await _prepare_prefabs(stage_assets["stages"][i], func(_f): pass)
	if not quitting:
		await ui.backdrop.add_stage(i)
	showcase_busy = false

func _report_load_time() -> void:
	if load_time_reported: return
	load_time_reported = true
	print("LOAD_TIME_MS=%d" % Time.get_ticks_msec())

# ------------------------------------------------------------------ stage preparation
## Starts preparing a stage in the background (one job at a time). Runs only while the 3D view
## is hidden: behind the menu shots, the results screen or a loading screen.
func _start_job(index: int) -> void:
	if preparing != -1 or quitting: return
	preparing = index
	job_progress = 0.0
	job_status = "טוען"
	_job(index)

func _job(index: int) -> void:
	var groups := _stage_groups(index)
	if not common_ready:
		var cg := _common_groups()
		for k in cg: groups[k].append_array(cg[k])
	await load_groups(groups, func(f, s): job_progress = 0.3 * f; job_status = s)
	if quitting: return
	if not common_ready:
		await _prepare_prefabs(stage_assets["common"], func(f): job_progress = 0.3 + 0.04 * f; job_status = "מכין מודלים")
		if quitting: return
		Character.init_library()
		await game.make_graffiti_textures()
		common_ready = true
	if not ui.backdrop.has_stage(index) and not showcase_busy:
		# the loading screen / menu turns live as early as possible
		showcase_busy = true
		await _prepare_prefabs(stage_assets["stages"][index], func(f): job_progress = 0.34 + 0.04 * f; job_status = "מכין מודלים")
		if quitting: return
		await ui.backdrop.add_stage(index)
		showcase_busy = false
	if quitting: return
	await _build_stage(index)
	if quitting: return
	prepared = index
	preparing = -1
	print("[load] stage %d ready at %d ms" % [index + 1, Time.get_ticks_msec()])

## Waits until a stage is prepared, showing the live loading screen only if it is not ready yet.
## Prints STAGE_WAIT_MS whenever the player actually had to wait.
func ensure_stage(index: int) -> void:
	if prepared == index and preparing == -1: return
	var t0 := Time.get_ticks_msec()
	loading = true
	var line := ui.loading()
	while not (prepared == index and preparing == -1):
		if quitting: return
		if preparing == -1: _start_job(index)
		ui.set_loading(line, job_progress if preparing == index else 0.0, job_status if preparing == index else "מסיים טעינה קודמת")
		await get_tree().process_frame
	ui.set_loading(line, 1.0)
	loading = false
	print("STAGE_WAIT_MS=%d" % (Time.get_ticks_msec() - t0))

## The prepared zones are about to be used by play: the next start must prepare again.
## Meanwhile the following stage's files stream in the background.
func _begin_stage_play(index: int) -> void:
	prepared = -1
	ui.set_backdrop(false)
	_stream_stage(index + 1)

## Stage loading work: stage files, prefabs, character pools, every zone (both branches), warm-up.
func _build_stage(index: int) -> void:
	print("[load] stage ", index)
	var st: Dictionary = game.stages[index]
	await load_groups(_stage_groups(index), func(f, s): job_progress = 0.3 + 0.05 * f; job_status = s)
	if quitting: return
	await _prepare_prefabs(stage_assets["stages"][index], func(f): job_progress = 0.35 + 0.05 * f; job_status = "מכין מודלים")
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
		if quitting: return
		game.pools.warm(models[mi], mini(8, int(counts[models[mi]]) + 2))
		job_progress = 0.4 + 0.1 * float(mi + 1) / models.size(); job_status = "מכין דמויות"
		await get_tree().process_frame
	for old in game.prebuilt.values():
		if is_instance_valid(old) and not old.is_inside_tree(): old.free()
	game.prebuilt.clear()
	for i in defs.size():
		if quitting: return
		var z := Zone.new()
		z.setup(game, defs[i], i, st, Vector3(0, 0, -100000), 0.0)
		z.build()
		game.setup_rig(z)
		game.prebuilt[String(defs[i]["id"])] = z
		job_progress = 0.5 + 0.3 * float(i + 1) / defs.size(); job_status = "בונה את השלב"
		await get_tree().process_frame
	print("[load] zones built ", defs.size())
	await warm_up(index, func(f): job_progress = 0.8 + 0.2 * f; job_status = "מכין אפקטים")
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

## Renders the current stage's materials, characters and effects once off-screen (behind the
## shots backdrop) so their shaders and pipelines are compiled before play. One zone per step;
## compiled shaders/pipelines are kept in Godot's on-disk caches, so later launches are fast.
func warm_up(index: int, progress: Callable) -> void:
	game.warming = true
	game.setup_stage(index)
	var cam := game.camera
	var fov := cam.fov
	cam.fov = 100.0
	var zones: Array = game.prebuilt.values()
	var total := zones.size() + 2
	var views := [[Vector3(0, 3, 10), Vector3(0, 1.5, -20)], [Vector3(0, 35, 22), Vector3(0, 0, -30)], [Vector3(0, 3, -60), Vector3(0, 1.5, -20)]]
	for zi in zones.size():
		var z: Zone = zones[zi]
		z.position = Vector3.ZERO
		# probe updates take several frames; never queue one for a zone that is detached right after
		if z.probe: z.probe.visible = false
		game.stage_root.add_child(z)
		for v in views:
			cam.global_position = v[0]
			cam.look_at(v[1])
			await _draw_frame()
			if quitting: return
		game.stage_root.remove_child(z)
		z.position = Vector3(0, 0, -100000)
		if z.probe: z.probe.visible = true
		progress.call(float(zi + 1) / total)
	cam.fov = fov
	cam.global_position = Vector3(0, 1.7, 8)
	cam.look_at(Vector3(0, 1.5, 0))
	var chars := game.pools.all_characters()
	for i in chars.size():
		var c: Character = chars[i]
		c.visible = true
		c.position = Vector3((i % 8) - 4.0, 0, -2.0 - int(i / 8))
		c.configure(game, {"rim": true, "rim_strength": 0.5, "weapon": "pistol"})
	game.pools.visible = true
	await _draw_frame()
	if quitting: return
	progress.call(float(zones.size() + 1) / total)
	game.fx.warm_up(Vector3(0, 1.5, 0))
	for f in 3:
		cam.rotate_y(TAU / 3.0)
		await _draw_frame()
		if quitting: return
	for c in chars:
		c.visible = false
		c.detach_weapon()
	game.pools.visible = false
	game.fx.clear()
	game.warming = false
	progress.call(1.0)

func _draw_frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

# ------------------------------------------------------------------ menu / runs
func show_menu() -> void:
	mode = "menu"
	set_aiming(false)
	ui.hud_show(false)
	game.state = "menu"
	ui.set_backdrop(true) # live background (saved images until the live views are ready)
	ui.menu()
	Sfx.play_music("menu")
	_report_load_time()
	# stage 1 is prepared behind the menu, so starting it does not wait
	while not (prepared == 0 and preparing == -1):
		if mode != "menu" or quitting: return
		if preparing == -1: _start_job(0)
		await get_tree().process_frame
	if not flow.has("stage1_ready"):
		flow["stage1_ready"] = true
		print("STAGE1_READY_MS=%d" % Time.get_ticks_msec())
	# stages 2-3 stream in the background (and join the live background when done)
	_stream_stage(1)
	_stream_stage(2)

func start_run(diff: String, stage_i := 0, zone := 0, skip_intro := false) -> void:
	mode = "game"
	ui.clear_screen()
	await ensure_stage(stage_i)
	if quitting: return
	ui.clear_screen()
	_begin_stage_play(stage_i)
	game.new_run(diff, stage_i, zone, skip_intro)
	set_aiming(true)
	if bench.get("kind", "") == "flow": _attach_bot()

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
	var idx := game.stage_index
	await ensure_stage(idx)
	if quitting: return
	ui.clear_screen()
	_begin_stage_play(idx)
	game.start_stage(idx)
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

## Called by Game when a stage is cleared: the next stage is prepared behind the results screen.
func on_stage_clear() -> void:
	results_stage = game.stage_index
	if results_stage >= 2 or (not bench.is_empty() and bench["kind"] != "flow"): return
	var next := results_stage + 1
	get_tree().create_timer(1.5).timeout.connect(func():
		if not quitting and mode == "game" and game.state == "results" and prepared != next:
			_start_job(next))

func after_results() -> void:
	var done := results_stage if results_stage >= 0 else game.stage_index
	if done >= 2:
		var avg := 0.0
		for r in game.run_ranks: avg += float(r)
		avg /= maxf(1.0, game.run_ranks.size())
		final_rank = "S" if avg >= 85 else ("A" if avg >= 70 else ("B" if avg >= 55 else ("C" if avg >= 38 else "D")))
		ui.ending(game.scoring.total, final_rank)
		return
	ui.clear_screen()
	await ensure_stage(done + 1)
	if quitting: return
	ui.clear_screen()
	_begin_stage_play(done + 1)
	game.next_stage(done + 1)
	set_aiming(true)
	if bench.get("kind", "") == "flow": _attach_bot()

func finish_run() -> void:
	var total := game.scoring.total
	if Settings.qualifies(total):
		ui.name_entry(total, 3, final_rank, func(idx): ui.highscores(idx, quit_to_menu))
	else:
		ui.highscores(-1, quit_to_menu)

# ------------------------------------------------------------------ input & loop
func _input(e: InputEvent) -> void:
	if loading and e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
		quit_game()

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
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()
		return
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
	_stream_poll()
	if bench.get("kind", "") == "flow": _flow_tick()

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
	Character.anim_names = PackedStringArray()
	Character._tree_proto = null
	# static caches outlive the scene tree; release them while the rendering server still exists
	Objects.icon_cache.clear()
	Prefabs._tint_cache.clear()
	UI._glow = null
	loaded.clear()

## The only way the game quits (menu button, Esc while loading, window close, test modes):
## waits for every threaded load and shot writer to finish, releases everything, exits with code.
func quit_game(code := 0) -> void:
	if quitting: return
	quitting = true
	loading = false
	ui.clear_screen()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		var busy := false
		for p in inflight:
			if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				busy = true
				break
		if not busy: break
		await get_tree().process_frame
	for p in inflight:
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(p)
	inflight.clear()
	streaming.clear()
	ui.backdrop.wait_tasks()
	game.warming = false
	cleanup()
	print("QUIT_CLEAN code=%d" % code)
	get_tree().quit(code)

# ------------------------------------------------------------------ --flowtest (CI)
## Plays the real player path headless: menu -> start -> stage 1..3 with results screens in
## between (next stage prepared behind them) -> ending, then quits cleanly.
func _attach_bot() -> void:
	game.forced_branch = "left"
	game.dev_god = true
	autoplay = Autoplay.new(); autoplay.setup(self); game.autoplay = autoplay
	flow["zone_f0"] = Engine.get_process_frames()
	flow["zone"] = -1

func _flow_tick() -> void:
	if quitting: return
	var f := Engine.get_process_frames()
	if mode == "menu" and not flow.get("started", false) and prepared == 0 and preparing == -1:
		flow["started"] = true
		print("FLOW menu live at %d ms" % Time.get_ticks_msec())
		start_run("normal")
		return
	if mode != "game": return
	if game.state == "intro": game.rail.time = game.rail.duration
	if game.zone_idx != int(flow.get("zone", -1)):
		flow["zone"] = game.zone_idx
		flow["zone_f0"] = f
		flow["zones"] = int(flow.get("zones", 0)) + 1
	if game.state == "results":
		if not flow.has("results_f0"): flow["results_f0"] = f
		if f - int(flow["results_f0"]) > 60 * 4:
			flow.erase("results_f0")
			flow["stages"] = int(flow.get("stages", 0)) + 1
			print("FLOW stage %d cleared" % (results_stage + 1))
			if results_stage >= 2:
				print("FLOW_DONE stages=%d zones=%d" % [flow["stages"], flow["zones"]])
				quit_game(0)
			else:
				after_results()
		return
	if (game.state == "playing" or game.state == "intro") and f - int(flow.get("zone_f0", f)) > 60 * 240:
		print("FLOW_STUCK stage=%d zone=%d" % [game.stage_index + 1, game.zone_idx])
		quit_game(3)

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
	await ensure_stage(p["stage"])
	if quitting: return
	_report_load_time()
	ui.clear_screen()
	_begin_stage_play(p["stage"])
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
	quit_game(0 if int(bench.get("errors", 0)) == 0 else 3)
