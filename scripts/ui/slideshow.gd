class_name Slideshow
extends Control
## Opaque backdrop for loading, the menu (until stage 1 is ready) and the results screen:
## real in-game camera shots that cross-fade every 4 seconds with a slow push-in.
## Shots come from the player's own game (captured into user://loading/ while playing, see
## Main.capture_shot) and fall back to the shots bundled with the game (res://assets/loading/).

const KEYS := ["street", "port", "station", "boss"]
const HOLD := 4.0
const FADE := 1.2
const PUSH := 0.06

var tex: Array = []
var front := TextureRect.new()
var back := TextureRect.new()
var shade := TextureRect.new()
var idx := 0
var front_age := 0.0
var back_age := 0.0

## Loads the shots (player captures override the bundled ones).
static func load_shots() -> Array:
	var out := []
	for k in KEYS:
		var user := "user://loading/%s.jpg" % k
		if FileAccess.file_exists(user):
			var img := Image.load_from_file(user)
			if img != null and not img.is_empty():
				out.append(ImageTexture.create_from_image(img))
				continue
		var res := "res://assets/loading/%s.jpg" % k
		if ResourceLoader.exists(res):
			out.append(load(res))
	return out

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var base := ColorRect.new()
	base.color = Color(0.03, 0.035, 0.05)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	for r in [back, front]:
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
	# darker top and bottom so the title and the tip always read
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

func set_shots(textures: Array) -> void:
	tex = textures
	front_age = FADE
	back_age = 0.0
	back.texture = null
	back.modulate.a = 0.0
	if tex.is_empty():
		front.texture = null
		return
	idx = randi() % tex.size()
	front.texture = tex[idx]
	front.modulate.a = 1.0

func _process(dt: float) -> void:
	if tex.is_empty() or not is_visible_in_tree():
		return
	var c := size * 0.5
	front.pivot_offset = c
	back.pivot_offset = c
	front_age += dt
	front.scale = Vector2.ONE * (1.0 + PUSH * minf(1.0, front_age / (HOLD + 2.0 * FADE)))
	if tex.size() < 2 or front_age < FADE + HOLD:
		return
	# the next shot fades in on top (just under the shade) and starts its own push-in
	if back.texture == null:
		back.texture = tex[(idx + 1) % tex.size()]
		back_age = 0.0
		move_child(back, get_child_count() - 2)
	back_age += dt
	back.modulate.a = clampf(back_age / FADE, 0.0, 1.0)
	back.scale = Vector2.ONE * (1.0 + PUSH * minf(1.0, back_age / (HOLD + 2.0 * FADE)))
	if back_age >= FADE:
		var old := front
		front = back
		back = old
		front_age = back_age
		back.texture = null
		back.modulate.a = 0.0
		back.scale = Vector2.ONE
		idx = (idx + 1) % tex.size()
