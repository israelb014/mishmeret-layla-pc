extends Node
## Audio: preloaded streams, pooled one-shot players, looping sounds, music crossfade.

const SFX := ["pistol", "mpistol", "shotgun", "magnum", "enemy_shot", "boss_mg", "reload", "click", "ricochet", "glass", "glass2",
	"metal", "wood", "hit_body", "explosion", "explosion2", "hurt", "scream", "scream2", "siren", "engine", "screech", "ui_click", "ui_hover",
	"zone_clear", "stage_clear", "pickup", "shield", "empty", "grenade_bounce", "knife", "thud", "bottle", "sign", "tire", "alarm", "train"]
const MUSIC := ["menu", "stage1", "stage2", "stage3", "boss", "results"]

var streams := {}
var music_streams := {}
var pool: Array[AudioStreamPlayer] = []
var pool_idx := 0
var loops := {}
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var music_name := ""
var _tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for n in SFX:
		streams[n] = load("res://assets/audio/sfx/%s.ogg" % n)
	for n in MUSIC:
		music_streams[n] = load("res://assets/audio/music/%s.ogg" % n)
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		pool.append(p)
	music_a = AudioStreamPlayer.new(); music_a.bus = "Music"; add_child(music_a)
	music_b = AudioStreamPlayer.new(); music_b.bus = "Music"; add_child(music_b)
	apply_volumes()
	Settings.changed.connect(func(k): if k == "music" or k == "sfx": apply_volumes())

func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.0001, float(Settings.g("music")) * 0.7)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(0.0001, float(Settings.g("sfx")))))

## One-shot sound. pan is ignored by the mono pool (kept for API parity).
func play(name: String, volume := 1.0, rate := 1.0, jitter := 0.06) -> void:
	var s = streams.get(name)
	if s == null:
		return
	var p := pool[pool_idx]
	pool_idx = (pool_idx + 1) % pool.size()
	p.stream = s
	p.volume_db = linear_to_db(maxf(0.0001, volume))
	p.pitch_scale = rate * (1.0 + randf_range(-jitter, jitter))
	p.play()

func loop(id: String, name: String, volume := 0.5, rate := 1.0) -> void:
	if loops.has(id):
		return
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	var s: AudioStream = streams[name].duplicate()
	if s is AudioStreamOggVorbis:
		s.loop = true
	p.stream = s
	p.pitch_scale = rate
	p.volume_db = -40.0
	add_child(p)
	p.play()
	create_tween().tween_property(p, "volume_db", linear_to_db(volume), 0.4)
	loops[id] = p

func stop_loop(id: String) -> void:
	var p: AudioStreamPlayer = loops.get(id)
	if p == null:
		return
	loops.erase(id)
	var t := create_tween()
	t.tween_property(p, "volume_db", -60.0, 0.35)
	t.tween_callback(p.queue_free)

func stop_all_loops() -> void:
	for id in loops.keys():
		stop_loop(id)

func play_music(name: String, fade := 1.2) -> void:
	if name == music_name:
		return
	music_name = name
	var old := music_a
	music_a = music_b
	music_b = old
	music_a.stream = music_streams[name]
	music_a.volume_db = -40.0
	music_a.pitch_scale = 1.0
	music_a.play()
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(music_a, "volume_db", 0.0, fade)
	_tween.tween_property(music_b, "volume_db", -60.0, fade)
	_tween.chain().tween_callback(music_b.stop)

func stop_music(fade := 1.0) -> void:
	music_name = ""
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(music_a, "volume_db", -60.0, fade)
	_tween.tween_callback(music_a.stop)

func set_music_rate(r: float) -> void:
	music_a.pitch_scale = r

func set_paused(p: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), p)
	music_a.stream_paused = p
