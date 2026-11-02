extends Node
## Persistent settings, progress and high scores (user://). Applied on launch.

const PATH := "user://settings.cfg"
const CROSSHAIR := {"amber": Color("#ffb020"), "cyan": Color("#2ee6ff"), "lime": Color("#8cff3a"), "magenta": Color("#ff3fb4")}
const PRESETS := {
	"low": {"sdfgi": false, "ssr": false, "ssao": false, "ssil": false, "vfog": false, "shadows": 0, "aa": "fxaa", "fsr": "off", "glow": true, "lamp_shadows": false, "particles": 0.5, "lod_bias": 0.6},
	"medium": {"sdfgi": false, "ssr": true, "ssao": true, "ssil": false, "vfog": true, "shadows": 1, "aa": "taa", "fsr": "off", "glow": true, "lamp_shadows": false, "particles": 0.75, "lod_bias": 1.0},
	"high": {"sdfgi": true, "ssr": true, "ssao": true, "ssil": true, "vfog": true, "shadows": 2, "aa": "taa", "fsr": "off", "glow": true, "lamp_shadows": true, "particles": 1.0, "lod_bias": 1.5},
	"ultra": {"sdfgi": true, "ssr": true, "ssao": true, "ssil": true, "vfog": true, "shadows": 3, "aa": "taa", "fsr": "off", "glow": true, "lamp_shadows": true, "particles": 1.0, "lod_bias": 2.5},
}

var data := {
	"display": "borderless", # window | fullscreen | borderless
	"resolution": "", # "" = native
	"vsync": true,
	"fps_limit": 0, # 0 = unlimited, else 60/120/144
	"preset": "auto", # low | medium | high | ultra | auto
	"resolved": "", # what "auto" measured last time
	"sdfgi": true, "ssr": true, "ssao": true, "ssil": true, "vfog": true, "shadows": 2, "aa": "taa", "fsr": "off",
	"music": 0.6, "sfx": 0.8, "crosshair": "amber", "shake": true,
	"unlocked": 1, "highscores": [],
}
signal changed(key: String)
## Display mode forced from the command line for this launch only (never saved):
## "--windowed"/"-w" or "--fullscreen"/"-f". Overrides the saved display settings.
var cli_display := ""

func _ready() -> void:
	_load()
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if args.has("--windowed") or args.has("-w"):
		cli_display = "window"
	elif args.has("--fullscreen") or args.has("-f"):
		cli_display = "borderless"
	elif DisplayServer.get_name() != "headless" and get_window().mode == Window.MODE_WINDOWED \
			and int(ProjectSettings.get_setting("display/window/size/mode", 0)) != Window.MODE_WINDOWED:
		# the engine consumed a windowed-mode argument before scripts could see it
		cli_display = "window"

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in data.keys():
			if cfg.has_section_key("s", k):
				data[k] = cfg.get_value("s", k)

func save() -> void:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("s", k, data[k])
	cfg.save(PATH)

func g(key: String):
	return data.get(key)

func set_value(key: String, v) -> void:
	data[key] = v
	if key == "display" or key == "resolution":
		cli_display = "" # the player chose a mode in the settings screen
	save()
	changed.emit(key)

## "auto" uses the preset measured on this machine (see Main._auto_probe), or "high" until measured.
func effective_preset() -> String:
	if data["preset"] == "auto":
		return data["resolved"] if PRESETS.has(data["resolved"]) else "high"
	return data["preset"] if PRESETS.has(data["preset"]) else "high"

func apply_preset(name: String) -> void:
	data["preset"] = name
	var p: Dictionary = PRESETS[effective_preset()]
	for k in ["sdfgi", "ssr", "ssao", "ssil", "vfog", "shadows", "aa", "fsr"]:
		data[k] = p[k]
	save()
	changed.emit("preset")

func preset_value(key: String):
	return PRESETS[effective_preset()].get(key)

func unlock_stage(n: int) -> void:
	if n > int(data["unlocked"]):
		set_value("unlocked", mini(3, n))

func qualifies(score: int) -> bool:
	var hs: Array = data["highscores"]
	return score > 0 and (hs.size() < 10 or score > int(hs[hs.size() - 1]["score"]))

func add_highscore(entry: Dictionary) -> int:
	var hs: Array = data["highscores"].duplicate()
	entry["date"] = Time.get_unix_time_from_system()
	hs.append(entry)
	hs.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	hs = hs.slice(0, 10)
	set_value("highscores", hs)
	return hs.find(entry)

## Window / display settings
func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var w := get_window()
	var mode := cli_display if cli_display != "" else String(data["display"])
	match mode:
		"window":
			w.mode = Window.MODE_WINDOWED
			w.borderless = false
			var r := String(data["resolution"])
			if r == "" and cli_display == "window":
				r = "1280x720"
			if r != "":
				var p := r.split("x")
				w.size = Vector2i(int(p[0]), int(p[1]))
				w.move_to_center()
		"borderless":
			w.mode = Window.MODE_FULLSCREEN
		_:
			w.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if data["vsync"] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(data["fps_limit"])
	var vp := get_viewport()
	vp.use_taa = data["aa"] == "taa"
	vp.msaa_3d = Viewport.MSAA_4X if data["aa"] == "msaa" else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if data["aa"] == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	match String(data["fsr"]):
		"quality":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.77
		"balanced":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.67
		"performance":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.59
		_:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
	if data["fsr"] != "off":
		vp.use_taa = false # FSR 2 provides its own temporal AA
	vp.mesh_lod_threshold = 1.0 / float(preset_value("lod_bias"))
