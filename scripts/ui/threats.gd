class_name ThreatLayer
extends Control
## Enemy threat rings (original design): an arc that empties clockwise, four rotating tick
## marks, amber -> orange -> red, pulsing in the last 25%. Also draws score popups.

var game: Node
var t := 0.0
var popups: Array = [] # [world_pos, text, label, cls, age]
var font: Font
var font_ui: Font

func _process(dt: float) -> void:
	t += dt
	for p in popups: p[4] += dt
	popups = popups.filter(func(p): return p[4] < 1.1)
	queue_redraw()

func add_popup(pos: Vector3, text: String, label: String, cls: String) -> void:
	if popups.size() > 24: popups.pop_front()
	popups.append([pos, text, label, cls, 0.0])

func _draw() -> void:
	if game == null or game.camera == null: return
	var cam: Camera3D = game.camera
	var list := []
	for a in game.actors:
		if a.alive and a.threat != null and a.c.visible: list.append(a)
	for o in game.objects:
		if o.get("is_grenade") and o.alive and o.threat != null: list.append(o)
	for a in list:
		var p: Vector3 = a.ring_anchor()
		if cam.is_position_behind(p): continue
		var sp := cam.unproject_position(p)
		var th: Dictionary = a.threat
		var dist := cam.global_position.distance_to(p)
		var px := clampf((0.75 / maxf(1.0, dist)) * size.y * 0.9, 30.0, 110.0)
		var frac := clampf(float(th["remaining"]) / float(th["duration"]), 0.0, 1.0)
		var col := Color("#ffb020") if frac > 0.6 else (Color("#ff7a1a") if frac > 0.25 else Color("#ff2a2a"))
		var pulse := 1.0 + sin(t * 26.0) * 0.08 if frac < 0.25 else 1.0
		var r := px * 0.77 * pulse
		draw_arc(sp, r, 0, TAU, 64, Color(0, 0, 0, 0.55), 11.0 * px / 60.0, true)
		# remaining arc: from the sweeping edge clockwise round to 12 o'clock
		if frac > 0.0:
			var start := -PI / 2.0 + TAU * (1.0 - frac)
			draw_arc(sp, r, start, -PI / 2.0 + TAU, 64, col, (9.0 if frac < 0.25 else 7.0) * px / 60.0, true)
		var rot := t * deg_to_rad(140.0)
		for k in 4:
			var ang := rot + k * PI / 2.0
			var dir := Vector2(cos(ang), sin(ang))
			var perp := Vector2(-dir.y, dir.x)
			var tip := sp + dir * (r + px * 0.2)
			var b1 := sp + dir * (r + px * 0.06) + perp * px * 0.08
			var b2 := sp + dir * (r + px * 0.06) - perp * px * 0.08
			draw_colored_polygon(PackedVector2Array([tip, b1, b2]), col)
			draw_polyline(PackedVector2Array([tip, b1, b2, tip]), Color("#0b0d12"), 1.5, true)
	for p in popups:
		var wp: Vector3 = p[0]
		if cam.is_position_behind(wp): continue
		var age: float = p[4]
		var sp := cam.unproject_position(wp) + Vector2(0, -60.0 * age)
		var a := clampf(1.0 - (age - 0.6) / 0.5, 0.0, 1.0)
		var col := Color.WHITE
		match String(p[3]):
			"gold": col = Color("#ffd54a")
			"hot": col = Color("#ff7a1a")
			"bad": col = Color("#ff3b2f")
		if String(p[1]) != "":
			var s := String(p[1])
			var ts := font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, 36)
			draw_string_outline(font, sp - Vector2(ts.x / 2, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, 6, Color(0, 0, 0, a))
			draw_string(font, sp - Vector2(ts.x / 2, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(col, a))
		if String(p[2]) != "":
			var l := String(p[2])
			var ls := font_ui.get_string_size(l, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
			draw_string_outline(font_ui, sp + Vector2(-ls.x / 2, 24), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, a))
			draw_string(font_ui, sp + Vector2(-ls.x / 2, 24), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(Color("#ffe3b0") if String(p[3]) != "bad" else Color("#ff3b2f"), a))
