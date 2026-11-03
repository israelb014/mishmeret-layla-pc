class_name ProgressLine
extends Control
## Thin loading line along the bottom of the loading screen; glides toward the real progress.

var value := 0.0
var target := 0.0
var color := Color("#ffb020")
var track := Color(1, 1, 1, 0.14)

func glide_to(v: float) -> void:
	target = maxf(target, clampf(v, 0.0, 1.0))

func _process(dt: float) -> void:
	if value < target:
		value = move_toward(value, target, maxf(0.35, (target - value) * 5.0) * dt)
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), track)
	# right-to-left, like the rest of the Hebrew interface
	var w := size.x * value
	draw_rect(Rect2(Vector2(size.x - w, 0), Vector2(w, size.y)), color)
