class_name Ring
extends Control
## SVG-style progress ring drawn with arcs (loading, zone progress, rank, continue countdown).

@export var value := 0.0
@export var color := Color("#ffb020")
@export var track := Color(1, 1, 1, 0.12)
@export var thickness := 10.0
var label := ""
var sub := ""
var font: Font
var font_size := 40

func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0 - thickness
	var c := size / 2.0
	draw_arc(c, r, 0, TAU, 96, track, thickness, true)
	if value > 0.001:
		# starts at 12 o'clock, fills clockwise
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * clampf(value, 0, 1), 96, color, thickness, true)
	if label != "" and font:
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, c + Vector2(-ts.x / 2.0, ts.y * 0.3), label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)
	if sub != "" and font:
		var ss := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size * 0.4))
		draw_string(font, c + Vector2(-ss.x / 2.0, font_size * 0.75), sub, HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size * 0.4), Color(1, 1, 1, 0.7))

func set_value(v: float) -> void:
	value = v
	queue_redraw()

## Loading screen: the arc glides toward the real progress instead of jumping between frames.
var target := -1.0
func glide_to(v: float) -> void:
	target = maxf(v, target)
	set_process(true)

func _process(dt: float) -> void:
	if target < 0.0:
		set_process(false)
		return
	value = move_toward(value, target, maxf(0.6, (target - value) * 6.0) * dt)
	label = "%d%%" % int(round(value * 100.0))
	queue_redraw()
