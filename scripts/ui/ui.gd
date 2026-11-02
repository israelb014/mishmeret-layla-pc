class_name UI
extends CanvasLayer
## Hebrew right-to-left UI: theme, HUD, callouts, crosshair and every screen.

signal action(name: String, arg)

const AMBER := Color("#ffb020")
const INK := Color("#0b0d12")
const CARD := Color(0.055, 0.067, 0.094, 0.86)
const TEXT := Color("#f4f1ea")
const MUTED := Color("#a7adb8")
const RADIUS := 18

var main: Node
var font_title: Font
var font_ui: Font
var theme_main := Theme.new()
var root := Control.new()
var hud := Control.new()
var screens := Control.new()
var flash := ColorRect.new()
var threat_layer := ThreatLayer.new()
var crosshair := TextureRect.new()
var callouts := VBoxContainer.new()
var title_layer := Control.new()
var perf_label := Label.new()
# HUD widgets
var shields_box := HBoxContainer.new()
var score_label: Label
var combo_label: Label
var zone_ring := Ring.new()
var zone_name: Label
var boss_box := VBoxContainer.new()
var boss_name: Label
var boss_bar_fill := ColorRect.new()
var weapon_label: Label
var weapon_icon := TextureRect.new()
var bullets := HBoxContainer.new()
var ammo_box := VBoxContainer.new()
var display_score := 0.0
var target_score := 0
var icons := {}

func setup(m: Node) -> void:
	main = m
	layer = 10
	font_title = load("res://assets/fonts/SecularOne-Regular.ttf")
	font_ui = load("res://assets/fonts/Rubik.ttf")
	_build_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL
	root.theme = theme_main
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 0.08, 0.04, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	threat_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	threat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	threat_layer.font = font_title; threat_layer.font_ui = font_ui
	for c in [threat_layer, hud, flash, title_layer, screens]:
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(c)
	_build_hud()
	crosshair.texture = load("res://assets/icons/crosshair.svg")
	crosshair.size = Vector2(72, 72)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crosshair.visible = false
	add_child(crosshair)
	apply_crosshair()
	Settings.changed.connect(func(k): if k == "crosshair": apply_crosshair())
	perf_label.position = Vector2(16, 120)
	perf_label.add_theme_font_size_override("font_size", 18)
	perf_label.add_theme_color_override("font_color", Color("#8cff3a"))
	perf_label.add_theme_color_override("font_outline_color", Color.BLACK)
	perf_label.add_theme_constant_override("outline_size", 6)
	perf_label.visible = false
	perf_label.text_direction = Control.TEXT_DIRECTION_LTR
	add_child(perf_label)

func icon(n: String) -> Texture2D:
	if not icons.has(n): icons[n] = load("res://assets/icons/%s.svg" % n)
	return icons[n]

func apply_crosshair() -> void:
	crosshair.modulate = Settings.CROSSHAIR.get(String(Settings.g("crosshair")), AMBER)

func _sb(bg: Color, border := Color(1, 1, 1, 0.09), radius := RADIUS, pad := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s

func _build_theme() -> void:
	var t := theme_main
	t.default_font = font_ui
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "Button", _sb(Color(0.08, 0.094, 0.13, 0.86)))
	t.set_stylebox("hover", "Button", _sb(Color(0.13, 0.12, 0.094, 0.94), Color(1, 0.69, 0.13, 0.6)))
	t.set_stylebox("pressed", "Button", _sb(Color(0.2, 0.16, 0.08, 0.95), AMBER))
	t.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), Color("#2ee6ff")))
	t.set_stylebox("disabled", "Button", _sb(Color(0.08, 0.09, 0.11, 0.5)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("icon_normal_color", "Button", AMBER)
	t.set_color("icon_hover_color", "Button", AMBER)
	t.set_constant("h_separation", "Button", 14)
	t.set_constant("icon_max_width", "Button", 26)
	t.set_font_size("font_size", "Button", 24)
	t.set_stylebox("panel", "PanelContainer", _sb(CARD))
	t.set_stylebox("normal", "LineEdit", _sb(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.12), 12, 14))
	t.set_stylebox("focus", "LineEdit", _sb(Color(0, 0, 0, 0.35), AMBER, 12, 14))
	t.set_font_size("font_size", "LineEdit", 28)
	t.set_icon("grabber", "HSlider", _dot(22, AMBER))
	t.set_icon("grabber_highlight", "HSlider", _dot(24, AMBER))
	var sl := StyleBoxFlat.new(); sl.bg_color = Color(1, 1, 1, 0.12); sl.set_corner_radius_all(4); sl.content_margin_top = 4; sl.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", sl)
	var fill := sl.duplicate(); fill.bg_color = AMBER
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_font_size("font_size", "OptionButton", 20)

func _dot(s: int, c: Color) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length()
			img.set_pixel(x, y, c if d < s / 2.0 - 2 else (INK if d < s / 2.0 else Color(0, 0, 0, 0)))
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ HUD
func _label(text: String, size: int, title := false, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_title if title else font_ui)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 8 if title else 5)
	return l

func _build_hud() -> void:
	hud.visible = false
	# shields: top left
	# HUD positions are explicit screen corners (LTR layout); Hebrew labels keep RTL text direction
	hud.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_place(shields_box, Control.PRESET_TOP_LEFT, Rect2(26, 22, 300, 48))
	shields_box.add_theme_constant_override("separation", 6)
	hud.add_child(shields_box)
	# score: top right
	var sc := VBoxContainer.new()
	_place(sc, Control.PRESET_TOP_RIGHT, Rect2(-330, 14, 300, 140))
	sc.alignment = BoxContainer.ALIGNMENT_BEGIN
	var sl := _label("ניקוד", 18, false, Color(1, 1, 1, 0.8))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label = _label("0", 60, true)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.text_direction = Control.TEXT_DIRECTION_LTR
	combo_label = _label("", 22, true, AMBER)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.add_child(sl); sc.add_child(score_label); sc.add_child(combo_label)
	hud.add_child(sc)
	# zone progress ring: top centre
	_place(zone_ring, Control.PRESET_CENTER_TOP, Rect2(-48, 10, 96, 96))
	zone_ring.thickness = 9; zone_ring.font = font_title; zone_ring.font_size = 34
	zone_ring.track = Color(0.04, 0.05, 0.07, 0.6)
	hud.add_child(zone_ring)
	zone_name = _label("", 18)
	_place(zone_name, Control.PRESET_CENTER_TOP, Rect2(-200, 108, 400, 26))
	zone_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(zone_name)
	# boss bar
	_place(boss_box, Control.PRESET_CENTER_TOP, Rect2(-280, 140, 560, 60))
	boss_name = _label("", 26, true, Color("#ffd9c8"))
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bar_bg := PanelContainer.new()
	var bsb := _sb(Color(0.04, 0.05, 0.07, 0.8), Color(1, 1, 1, 0.3), 9, 2)
	bar_bg.add_theme_stylebox_override("panel", bsb)
	bar_bg.custom_minimum_size = Vector2(560, 20)
	boss_bar_fill.color = Color("#ff3b2f")
	boss_bar_fill.custom_minimum_size = Vector2(0, 16)
	boss_bar_fill.size_flags_horizontal = Control.SIZE_SHRINK_END
	bar_bg.add_child(boss_bar_fill)
	boss_box.add_child(boss_name); boss_box.add_child(bar_bg)
	boss_box.visible = false
	hud.add_child(boss_box)
	# ammo: bottom right
	_place(ammo_box, Control.PRESET_BOTTOM_RIGHT, Rect2(-420, -110, 394, 90))
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_BEGIN
	weapon_icon.custom_minimum_size = Vector2(56, 38)
	weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_icon.modulate = AMBER
	weapon_label = _label("אקדח", 22)
	wrow.add_child(weapon_icon); wrow.add_child(weapon_label)
	bullets.alignment = BoxContainer.ALIGNMENT_BEGIN
	bullets.add_theme_constant_override("separation", 4)
	ammo_box.add_child(wrow); ammo_box.add_child(bullets)
	hud.add_child(ammo_box)
	# callouts
	_place(callouts, Control.PRESET_CENTER, Rect2(-500, -260, 1000, 300))
	callouts.alignment = BoxContainer.ALIGNMENT_CENTER
	callouts.layout_direction = Control.LAYOUT_DIRECTION_RTL # runtime callout labels inherit RTL text
	hud.add_child(callouts)
	for l in hud.find_children("*", "Label", true, false):
		if (l as Label).text_direction == Control.TEXT_DIRECTION_INHERITED:
			(l as Label).text_direction = Control.TEXT_DIRECTION_RTL

## Anchors a control to a screen corner/edge; rect.position is the offset from that anchor point.
func _place(c: Control, preset: int, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y

func hud_show(v: bool) -> void:
	hud.visible = v
	threat_layer.visible = v

func hud_shields(n: int, hurt: bool) -> void:
	for c in shields_box.get_children(): c.queue_free()
	for i in 5:
		var tr := TextureRect.new()
		tr.texture = icon("shield" if i < n else "shieldEmpty")
		tr.custom_minimum_size = Vector2(44, 48)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.modulate = Color("#2ee6ff") if i < n else Color.WHITE
		shields_box.add_child(tr)
		if hurt and i == n:
			tr.pivot_offset = Vector2(22, 24)
			tr.scale = Vector2(1.5, 1.5)
			tr.modulate = Color("#ff3b2f")
			create_tween().tween_property(tr, "scale", Vector2.ONE, 0.5)

func hud_zones(done: int, total: int, nm: String) -> void:
	zone_ring.set_value(minf(1.0, float(done) / maxf(1.0, total)))
	zone_ring.label = str(mini(total, done + 1))
	zone_ring.sub = "/%d" % total
	if nm != "": zone_name.text = nm

func hud_score(total: int, mult: int, combo: int) -> void:
	target_score = total
	combo_label.text = ("×%d · רצף %d" % [mult, combo]) if mult > 1 else ""

func hud_weapon(w: PlayerWeapon) -> void:
	weapon_icon.texture = icon(w.id)
	weapon_label.text = String(w.def["name"]) + ("  %d" % w.ammo if w.special() else "")
	for c in bullets.get_children(): c.queue_free()
	var mx: int = int(w.def["mag"])
	var small := w.id == "mpistol"
	for i in mx:
		var tr := TextureRect.new()
		tr.texture = icon("shell" if w.id == "shotgun" else "bullet")
		tr.custom_minimum_size = Vector2(10, 22) if small else Vector2(22, 40)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.modulate = Color("#ffd54a") if i < w.ammo else Color(1, 1, 1, 0.18)
		bullets.add_child(tr)

func hud_reloading(_v: bool) -> void:
	bullets.modulate = Color(1, 1, 1, 0.4)
	create_tween().tween_property(bullets, "modulate", Color.WHITE, 0.6)

func hud_flash_ammo() -> void:
	ammo_box.modulate = Color(2.0, 0.6, 0.5)
	var tw := create_tween()
	tw.tween_property(ammo_box, "position:x", ammo_box.position.x - 8, 0.06)
	tw.tween_property(ammo_box, "position:x", ammo_box.position.x + 8, 0.08)
	tw.tween_property(ammo_box, "position:x", ammo_box.position.x, 0.06)
	tw.parallel().tween_property(ammo_box, "modulate", Color.WHITE, 0.4)

func callout(text: String, style := "info", sub := "") -> void:
	var col := Color.WHITE
	var size := 54
	match style:
		"warn": col = AMBER
		"bad": col = Color("#ff3b2f")
		"good": col = Color("#ffd54a")
		"clear": col = Color("#5ee27a"); size = 76
		"boss": col = Color("#ff8a5c"); size = 76
	var box := VBoxContainer.new()
	var l := _label(text, size, true, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	if sub != "":
		var s := _label(sub, 22, false, Color("#ffe3b0"))
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(s)
	callouts.add_child(box)
	while callouts.get_child_count() > 3:
		callouts.get_child(0).free()
	box.pivot_offset = Vector2(500, 40)
	box.scale = Vector2(1.6, 1.6)
	box.modulate.a = 0.0
	var dur := 1.9 if style == "clear" else 1.3
	var tw := box.create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(box, "modulate:a", 1.0, 0.12)
	tw.tween_interval(dur - 0.45)
	tw.tween_property(box, "modulate:a", 0.0, 0.3)
	tw.tween_callback(box.queue_free)

func popup(pos: Vector3, text: String, label: String, cls: String) -> void:
	threat_layer.add_popup(pos, text, label, cls)

func boss_bar(nm: String, frac: float) -> void:
	if frac < 0.0:
		boss_box.visible = false; return
	boss_box.visible = true
	boss_name.text = nm
	boss_bar_fill.custom_minimum_size.x = 556.0 * clampf(frac, 0, 1)
	boss_bar_fill.color = Color("#ff3b2f") if frac < 0.3 else Color("#ff7a1a")

func damage_flash() -> void:
	flash.color.a = 0.45
	create_tween().tween_property(flash, "color:a", 0.0, 0.45)

func stage_title(title: String, subtitle: String, dur: float, idx: int) -> void:
	for c in title_layer.get_children(): c.queue_free()
	if title == "": return
	var box := VBoxContainer.new()
	_place(box, Control.PRESET_CENTER, Rect2(-700, -200, 1400, 400))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var a := _label("שלב %d" % (idx + 1), 26, false, AMBER)
	var b := _label(title, 150, true)
	b.add_theme_color_override("font_shadow_color", Color("#b4570b"))
	b.add_theme_constant_override("shadow_offset_y", 7)
	var c := _label(subtitle, 30, false, Color("#ffe3b0"))
	var d := _label("לחיצה לדילוג", 18, false, Color(1, 1, 1, 0.6))
	for l in [a, b, c, d]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	title_layer.add_child(box)
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.5)
	tw.tween_interval(maxf(0.5, dur - 1.2))
	tw.tween_property(box, "modulate:a", 0.0, 0.7)

func _process(dt: float) -> void:
	if crosshair.visible:
		crosshair.position = main.aim_position() / get_viewport().get_visible_rect().size * Vector2(get_viewport().get_visible_rect().size) - Vector2(36, 36)
	if absf(display_score - target_score) > 0.5:
		display_score = lerpf(display_score, target_score, minf(1.0, dt * 10.0))
		if absf(display_score - target_score) < 2: display_score = target_score
		score_label.text = main.game._n(int(display_score))

# ------------------------------------------------------------------ screens
func clear_screen() -> void:
	for c in screens.get_children(): c.queue_free()
	screens.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _screen(dim := false) -> Control:
	clear_screen()
	screens.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.035, 0.05, 0.62 if dim else 0.45)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	screens.add_child(bg)
	var glow := TextureRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.texture = _glow_tex()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screens.add_child(glow)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screens.add_child(center)
	return center

static var _glow: GradientTexture2D
func _glow_tex() -> GradientTexture2D:
	if _glow: return _glow
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.69, 0.13, 0.16)); g.set_color(1, Color(1, 0.69, 0.13, 0))
	_glow = GradientTexture2D.new()
	_glow.gradient = g; _glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.3); _glow.fill_to = Vector2(0.95, 0.75)
	return _glow

func _title(text: String, ic := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	if ic != "":
		var tr := TextureRect.new(); tr.texture = icon(ic); tr.custom_minimum_size = Vector2(46, 46)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.modulate = AMBER
		h.add_child(tr)
	h.add_child(_label(text, 58, true))
	return h

func _btn(text: String, ic: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	if ic != "": b.icon = icon(ic)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(440, 66)
	b.expand_icon = false
	if primary:
		b.add_theme_stylebox_override("normal", _sb(AMBER, Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("hover", _sb(Color("#ffc955"), Color(0, 0, 0, 0)))
		b.add_theme_color_override("font_color", Color("#1b1203"))
		b.add_theme_color_override("font_hover_color", Color("#1b1203"))
		b.add_theme_color_override("icon_normal_color", Color("#1b1203"))
		b.add_theme_color_override("icon_hover_color", Color("#1b1203"))
	b.pressed.connect(func(): Sfx.play("ui_click", 0.6, 1.0, 0.0); cb.call())
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", 0.25, 1.0, 0.0))
	return b

func _card(child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_child(child)
	return p

func _vbox(sep := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

func _appear(n: Control) -> void:
	n.modulate.a = 0.0
	n.create_tween().tween_property(n, "modulate:a", 1.0, 0.35)

func loading() -> Ring:
	var c := _screen()
	(screens.get_child(0) as ColorRect).color = INK
	var v := _vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var r := Ring.new()
	r.custom_minimum_size = Vector2(220, 220)
	r.font = font_title; r.font_size = 50; r.thickness = 12
	r.label = "0%"; r.sub = "טוען"
	var rc := CenterContainer.new(); rc.add_child(r)
	v.add_child(rc)
	var logo := _label("משמרת לילה", 84, true)
	logo.add_theme_color_override("font_shadow_color", Color("#b4570b")); logo.add_theme_constant_override("shadow_offset_y", 5)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(logo)
	var tip := _label("טיפ: ירי בנשק שביד האויב מנטרל אותו ומזכה ב־300 נקודות", 20, false, MUTED)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip)
	c.add_child(v)
	return r

func menu() -> void:
	var c := _screen()
	(screens.get_child(0) as ColorRect).color = Color(0.03, 0.035, 0.05, 0.25)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 90); m.add_theme_constant_override("margin_right", 90)
	screens.remove_child(c); c.queue_free()
	screens.add_child(m)
	var h := HBoxContainer.new()
	m.add_child(h)
	var v := _vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var badge := TextureRect.new(); badge.texture = icon("crosshair"); badge.custom_minimum_size = Vector2(64, 64)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; badge.modulate = AMBER
	v.add_child(badge)
	var logo := _label("משמרת לילה", 110, true)
	logo.add_theme_color_override("font_shadow_color", Color("#b4570b")); logo.add_theme_constant_override("shadow_offset_y", 6)
	v.add_child(logo)
	v.add_child(_label("מהדורת PC · שלושה שלבים. שש יריות במחסנית. אף אזרח לא נפגע.", 22, false, Color("#ffe3b0")))
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 16); v.add_child(sp)
	v.add_child(_btn("התחל", "play", func(): difficulty(0), true))
	v.add_child(_btn("בחירת שלב", "stages", stage_select))
	v.add_child(_btn("שיאים", "trophy", highscores.bind(-1, menu)))
	v.add_child(_btn("הגדרות", "gear", settings_screen.bind(menu)))
	v.add_child(_btn("קרדיטים", "info", credits))
	v.add_child(_btn("יציאה", "exit", func(): main.get_tree().quit()))
	v.add_child(_label("עכבר: כיוון וירי · R / רווח / קליק ימני: טעינה · Esc: השהיה · F1: מד ביצועים", 17, false, MUTED))
	h.add_child(v)
	_appear(v)

func difficulty(stage_i: int) -> void:
	var c := _screen()
	var v := _vbox(20)
	v.add_child(_title("בחירת רמת קושי"))
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 16)
	for d in [["easy", "קל", "זמן תגובה ארוך, מתאים להתחלה", 1], ["normal", "רגיל", "האתגר שתוכנן למשחק", 2], ["hard", "קשה", "אויבים יורים מהר יותר", 3]]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 190)
		b.text = "%s\n%s" % [d[1], d[2]]
		b.add_theme_font_size_override("font_size", 26)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var key: String = d[0]
		b.pressed.connect(func(): Sfx.play("ui_click", 0.6, 1.0, 0.0); main.start_run(key, stage_i))
		if key == "normal": b.add_theme_stylebox_override("normal", _sb(Color(0.08, 0.094, 0.13, 0.86), Color(1, 0.69, 0.13, 0.5)))
		h.add_child(b)
	v.add_child(h)
	v.add_child(_btn("חזרה", "back", menu))
	c.add_child(v); _appear(v)

func stage_select() -> void:
	var c := _screen()
	var v := _vbox(20)
	v.add_child(_title("בחירת שלב"))
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 16)
	var unlocked := int(Settings.g("unlocked"))
	for i in 3:
		var st: Dictionary = main.game.stages[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(320, 230)
		b.text = "%d\n%s\n%s" % [i + 1, st["title"], st["subtitle"] if i + 1 <= unlocked else "סיים את השלב הקודם"]
		b.add_theme_font_size_override("font_size", 26)
		b.disabled = i + 1 > unlocked
		if b.disabled: b.icon = icon("lock")
		var si := i
		b.pressed.connect(func(): Sfx.play("ui_click", 0.6, 1.0, 0.0); difficulty(si))
		h.add_child(b)
	v.add_child(h)
	v.add_child(_btn("חזרה", "back", menu))
	c.add_child(v); _appear(v)

func highscores(highlight := -1, back := Callable()) -> void:
	var c := _screen()
	var v := _vbox(18)
	v.add_child(_title("שיאים", "trophy"))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 10)
	var hs: Array = Settings.g("highscores")
	if hs.is_empty():
		var e := _label("עדיין אין שיאים. זה הזמן לקבוע את הראשון.", 22, false, MUTED)
		v.add_child(_card(e))
	else:
		for t in ["#", "שם", "ניקוד", "שלב", "דירוג"]: grid.add_child(_label(t, 20, false, MUTED))
		for i in hs.size():
			var col := AMBER if i == highlight else TEXT
			var row := [str(i + 1), String(hs[i]["name"]), main.game._n(int(hs[i]["score"])), str(hs[i]["stage"]), String(hs[i]["rank"])]
			for t in row: grid.add_child(_label(t, 22, false, col))
		v.add_child(_card(grid))
	v.add_child(_btn("חזרה", "back", back if back.is_valid() else menu))
	c.add_child(v); _appear(v)

func name_entry(score: int, stage_n: int, rank: String, done: Callable) -> void:
	var c := _screen()
	var v := _vbox(16)
	v.add_child(_title("שיא חדש!", "star"))
	var inner := _vbox(14)
	var sl := _label(main.game._n(score), 70, true, AMBER); sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(sl)
	inner.add_child(_label("השם שלך (עד 10 תווים)", 20, false, MUTED))
	var le := LineEdit.new()
	le.max_length = 10
	le.placeholder_text = "שוטר/ת"
	le.custom_minimum_size = Vector2(420, 64)
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(le)
	var save := func():
		var nm := le.text.strip_edges()
		if nm == "": nm = "שוטר/ת"
		var idx := Settings.add_highscore({"name": nm.substr(0, 10), "score": score, "stage": stage_n, "rank": rank})
		done.call(idx)
	le.text_submitted.connect(func(_t): save.call())
	inner.add_child(_btn("שמור", "star", save, true))
	v.add_child(_card(inner))
	c.add_child(v); _appear(v)
	le.grab_focus()

func _row(label: String, ic: String, ctl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var tr := TextureRect.new(); tr.texture = icon(ic); tr.custom_minimum_size = Vector2(28, 28)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.modulate = AMBER
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tr)
	var l := _label(label, 22); l.custom_minimum_size = Vector2(230, 0)
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	return h

func _seg(options: Array, current, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for o in options:
		var b := Button.new()
		b.text = String(o[1])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = str(o[0]) == str(current)
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_stylebox_override("pressed", _sb(AMBER, Color(0, 0, 0, 0), 10, 10))
		b.add_theme_stylebox_override("normal", _sb(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 10, 10))
		b.add_theme_stylebox_override("hover", _sb(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 10, 10))
		b.add_theme_color_override("font_pressed_color", Color("#1b1203"))
		var val = o[0]
		b.pressed.connect(func(): Sfx.play("ui_click", 0.5, 1.0, 0.0); cb.call(val))
		h.add_child(b)
	return h

func _toggle(v: bool, cb: Callable) -> CheckButton:
	var cbn := CheckButton.new()
	cbn.button_pressed = v
	cbn.toggled.connect(func(on): Sfx.play("ui_click", 0.5, 1.0, 0.0); cb.call(on))
	return cbn

func settings_screen(back: Callable) -> void:
	var c := _screen(true)
	var v := _vbox(14)
	v.add_child(_title("הגדרות", "gear"))
	var tabs := _vbox(6)
	var S := Settings
	var apply_gfx := func(k, val):
		S.set_value(k, val)
		S.apply_display()
		main.game.refresh_graphics()
	tabs.add_child(_row("מצב תצוגה", "monitor", _seg([["window", "חלון"], ["fullscreen", "מסך מלא"], ["borderless", "מסך מלא ללא גבולות"]], S.g("display"), func(val): apply_gfx.call("display", val))))
	var res := OptionButton.new()
	var resolutions := ["", "1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
	for r in resolutions: res.add_item("רזולוציית המסך" if r == "" else r)
	res.selected = maxi(0, resolutions.find(String(S.g("resolution"))))
	res.item_selected.connect(func(i): apply_gfx.call("resolution", resolutions[i]))
	tabs.add_child(_row("רזולוציה (בחלון)", "monitor", res))
	tabs.add_child(_row("סנכרון אנכי", "monitor", _toggle(bool(S.g("vsync")), func(on): apply_gfx.call("vsync", on))))
	tabs.add_child(_row("הגבלת תמונות לשנייה", "clock", _seg([[60, "60"], [120, "120"], [144, "144"], [0, "ללא"]], S.g("fps_limit"), func(val): apply_gfx.call("fps_limit", val))))
	tabs.add_child(_row("איכות גרפיקה", "monitor", _seg([["auto", "אוטומטי"], ["low", "נמוך"], ["medium", "בינוני"], ["high", "גבוה"], ["ultra", "אולטרה"]], S.g("preset"), func(val):
		S.apply_preset(val); S.apply_display(); main.game.refresh_graphics(); settings_screen(back))))
	tabs.add_child(_row("תאורה גלובלית (SDFGI)", "star", _toggle(bool(S.g("sdfgi")), func(on): apply_gfx.call("sdfgi", on))))
	tabs.add_child(_row("השתקפויות (SSR)", "star", _toggle(bool(S.g("ssr")), func(on): apply_gfx.call("ssr", on))))
	tabs.add_child(_row("ערפל נפחי", "star", _toggle(bool(S.g("vfog")), func(on): apply_gfx.call("vfog", on))))
	tabs.add_child(_row("איכות צללים", "star", _seg([[0, "כבוי"], [1, "נמוכה"], [2, "גבוהה"], [3, "אולטרה"]], S.g("shadows"), func(val): apply_gfx.call("shadows", val))))
	tabs.add_child(_row("החלקת קצוות", "crosshair", _seg([["taa", "TAA"], ["msaa", "MSAA ×4"], ["fxaa", "FXAA"], ["off", "כבוי"]], S.g("aa"), func(val): apply_gfx.call("aa", val))))
	tabs.add_child(_row("FSR 2", "monitor", _seg([["off", "כבוי"], ["quality", "איכות"], ["balanced", "מאוזן"], ["performance", "ביצועים"]], S.g("fsr"), func(val): apply_gfx.call("fsr", val))))
	for k in [["music", "עוצמת מוזיקה", "music"], ["sfx", "עוצמת אפקטים", "speaker"]]:
		var sl := HSlider.new(); sl.min_value = 0; sl.max_value = 1; sl.step = 0.05; sl.value = float(S.g(k[0]))
		sl.custom_minimum_size = Vector2(320, 30)
		var key: String = k[0]
		sl.value_changed.connect(func(val): S.set_value(key, val))
		tabs.add_child(_row(k[1], k[2], sl))
	tabs.add_child(_row("צבע הכוונת", "crosshair", _seg([["amber", "ענבר"], ["cyan", "תכלת"], ["lime", "ירוק"], ["magenta", "ורוד"]], S.g("crosshair"), func(val): S.set_value("crosshair", val))))
	tabs.add_child(_row("רעידת מסך", "shake", _toggle(bool(S.g("shake")), func(on): S.set_value("shake", on))))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1100, 760)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tabs)
	v.add_child(_card(scroll))
	v.add_child(_btn("חזרה", "back", back))
	c.add_child(v); _appear(v)

func credits() -> void:
	var c := _screen()
	var v := _vbox(12)
	v.add_child(_title("קרדיטים", "info"))
	v.add_child(_label("כל הדמויות, הרכבים, האביזרים, המשטחים, השמיים, הצלילים והמוזיקה במשחק הם נכסים בנחלת הכלל (CC0). הגופנים ברישיון OFL.", 20, false, MUTED))
	var list := _vbox(4)
	for cr in U.load_json("res://data/credits.json"):
		var row := _vbox(0)
		var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 18)
		var nm := _label(String(cr["name"]), 18); nm.custom_minimum_size = Vector2(560, 0); nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		top.add_child(nm)
		var au := _label(String(cr["author"]), 17, false, Color("#ffe3b0")); au.custom_minimum_size = Vector2(250, 0); au.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		top.add_child(au)
		top.add_child(_label(String(cr["license"]), 17, false, Color("#5ee27a")))
		row.add_child(top)
		var use := _label(String(cr["usage"]) + "  ·  " + String(cr["source"]), 14, false, MUTED)
		use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(use)
		list.add_child(row)
		list.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1300, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	scroll.name = "CreditsScroll"
	v.add_child(_card(scroll))
	v.add_child(_btn("חזרה", "back", menu))
	c.add_child(v); _appear(v)

func pause() -> void:
	var c := _screen(true)
	var v := _vbox(14)
	v.add_child(_title("השהיה"))
	v.add_child(_btn("המשך", "play", func(): main.resume(), true))
	v.add_child(_btn("התחל שלב מחדש", "restart", func(): main.restart_stage()))
	v.add_child(_btn("הגדרות", "gear", settings_screen.bind(pause)))
	v.add_child(_btn("יציאה לתפריט", "exit", func(): main.quit_to_menu()))
	c.add_child(v); _appear(v)

func show_game_over(left: int, score: int) -> void:
	var c := _screen(true)
	var v := _vbox(14)
	var t := _title("המשחק נגמר"); (t.get_child(0) as Label).add_theme_color_override("font_color", Color("#ff3b2f"))
	v.add_child(t)
	var inner := _vbox(12)
	if left > 0:
		var r := Ring.new(); r.custom_minimum_size = Vector2(160, 160); r.color = Color("#ff3b2f"); r.font = font_title; r.font_size = 64
		r.value = 1.0; r.label = "10"
		var rc := CenterContainer.new(); rc.add_child(r); inner.add_child(rc)
		inner.add_child(_label("להמשיך? הניקוד יתאפס, ההתקדמות בשלב תישמר.", 22))
		inner.add_child(_label("נותרו %d המשכים" % left, 20, false, MUTED))
		inner.add_child(_btn("המשך", "play", func(): main.continue_run(), true))
		var tw := r.create_tween()
		tw.tween_method(func(x: float):
			r.set_value(x / 10.0); r.label = str(ceili(x)), 10.0, 0.0, 10.0)
		tw.tween_callback(func(): if is_instance_valid(r) and r.is_inside_tree(): main.end_run())
	else:
		inner.add_child(_label("נגמרו ההמשכים.", 22))
	inner.add_child(_label("ניקוד: %s" % main.game._n(score), 26, true, AMBER))
	inner.add_child(_btn("סיום", "exit", func(): main.end_run()))
	v.add_child(_card(inner))
	c.add_child(v); _appear(v)

func show_results(d: Dictionary) -> void:
	var c := _screen()
	var v := _vbox(16)
	v.add_child(_title("%s — הושלם" % d["stage"]["title"]))
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 18)
	var rank: Dictionary = d["rank"]
	var rk := _vbox(4)
	var r := Ring.new(); r.custom_minimum_size = Vector2(240, 240); r.font = font_title; r.font_size = 110; r.thickness = 14
	r.color = {"S": Color("#ffd54a"), "A": AMBER, "B": Color("#2ee6ff"), "C": Color("#5ee27a"), "D": Color("#b0b6c2")}[rank["letter"]]
	r.label = rank["letter"]
	rk.add_child(r)
	var rl := _label("דירוג", 20, false, MUTED); rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rk.add_child(rl)
	r.create_tween().tween_method(r.set_value, 0.0, float(rank["value"]) / 100.0, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	h.add_child(_card(rk))
	var st: Dictionary = d["stats"]
	var stats := _vbox(8)
	var secs := int(st["time"])
	for row in [["star", "ניקוד בשלב", main.game._n(int(st["score"]))], ["target", "דיוק", "%d%%" % d["accuracy"]], ["hand", "נטרולים נקיים", str(st["disarms"])],
			["head", "פגיעות ראש", str(st["heads"])], ["person", "אזרחים שנפגעו", str(st["civilians"])], ["clock", "זמן", "%d:%02d" % [secs / 60, secs % 60]],
			["trophy", "ניקוד כולל", main.game._n(int(d["total"]))]]:
		var hr := HBoxContainer.new(); hr.add_theme_constant_override("separation", 14)
		var tr := TextureRect.new(); tr.texture = icon(row[0]); tr.custom_minimum_size = Vector2(28, 28); tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.modulate = AMBER
		hr.add_child(tr)
		var l := _label(row[1], 22); l.custom_minimum_size = Vector2(300, 0); hr.add_child(l)
		var val := _label(row[2], 30, true, AMBER if row[0] == "trophy" else (Color("#ff3b2f") if row[0] == "person" and int(st["civilians"]) > 0 else TEXT))
		val.text_direction = Control.TEXT_DIRECTION_LTR
		hr.add_child(val)
		stats.add_child(hr)
	h.add_child(_card(stats))
	v.add_child(h)
	v.add_child(_btn("לסיום" if d["last"] else "לשלב הבא", "play", func(): main.after_results(), true))
	c.add_child(v); _appear(v)

func ending(total: int, rank: String) -> void:
	var c := _screen()
	var v := _vbox(16)
	var logo := _label("המשמרת הסתיימה", 100, true); logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_color_override("font_shadow_color", Color("#b4570b")); logo.add_theme_constant_override("shadow_offset_y", 6)
	v.add_child(logo)
	var sub := _label("הרחוב, הנמל והתחנה נקיים. העיר יכולה לישון בשקט.", 24, false, MUTED); sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var inner := _vbox(10)
	var r := Ring.new(); r.custom_minimum_size = Vector2(240, 240); r.font = font_title; r.font_size = 110; r.thickness = 14; r.label = rank
	var rc := CenterContainer.new(); rc.add_child(r); inner.add_child(rc)
	r.create_tween().tween_method(r.set_value, 0.0, 0.98, 2.0)
	var fl := _label("ניקוד סופי: %s" % main.game._n(total), 30, true, AMBER); fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(fl)
	v.add_child(_card(inner))
	v.add_child(_btn("המשך", "trophy", func(): main.finish_run(), true))
	c.add_child(v); _appear(v)
