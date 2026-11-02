class_name Rail
extends RefCounted
## Camera rail: Curve3D (Catmull-Rom tangents) between zone stops with eased motion,
## look-target blending, walk bob, idle sway, FOV push for slow motion.

var camera: Camera3D
var pos := Vector3(0, 1.7, 0)
var look := Vector3(0, 1.6, -10)
var look_target := Vector3(0, 1.6, -10)
var look_start := Vector3.ZERO
var look_end = null
var moving := false
var curve: Curve3D
var length := 1.0
var duration := 1.0
var u := 0.0
var time := 0.0
var bob := 0.0
var sway := 0.0
var look_speed := 4.0
var fov := 62.0
var linear := false
var travel := false
var look_ahead := 0.1
var on_done: Callable

func _init(cam: Camera3D) -> void:
	camera = cam

## Builds a smooth Curve3D through the points with Catmull-Rom tangents.
static func catmull(points: Array) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = 0.25
	var n := points.size()
	for i in n:
		var p: Vector3 = points[i]
		var prev: Vector3 = points[maxi(0, i - 1)]
		var next: Vector3 = points[mini(n - 1, i + 1)]
		var tan := (next - prev) * 0.25
		c.add_point(p, -tan, tan)
	return c

func move_along(points: Array, opts: Dictionary = {}) -> void:
	var pts: Array = [pos]
	for p in points:
		if (p as Vector3).distance_to(pts[pts.size() - 1]) > 0.3:
			pts.append(p)
	if pts.size() < 2:
		pts.append(pos + Vector3(0, 0, -0.01))
	curve = catmull(pts)
	length = maxf(0.01, curve.get_baked_length())
	duration = float(opts["duration"]) if opts.get("duration") != null else clampf(length / 7.5, 1.2, 7.0)
	u = 0.0; time = 0.0
	moving = true
	linear = opts.get("linear", false)
	travel = opts.get("travel", false)
	look_start = look
	look_end = opts.get("look_end")
	look_ahead = float(opts.get("look_ahead", 0.1))
	on_done = opts.get("on_done", Callable())

func turn_to(target: Vector3, speed := 5.0) -> void:
	look_target = target
	look_speed = speed

func point_at(k: float) -> Vector3:
	return curve.sample_baked(clampf(k, 0.0, 1.0) * length, true)

func tangent_at(k: float) -> Vector3:
	var a := point_at(k - 0.01)
	var b := point_at(k + 0.01)
	var t := b - a
	return t.normalized() if t.length_squared() > 1e-8 else Vector3.FORWARD

func update(dt: float, paused: bool) -> void:
	if moving and not paused:
		time += dt
		var k := minf(1.0, time / duration)
		u = k if linear else U.smoother(k)
		pos = point_at(u)
		var ahead := point_at(minf(1.0, u + look_ahead))
		var tl := ahead - pos
		if tl.length_squared() < 1e-4:
			tl = tangent_at(u) * 5.0
		tl.y = 0
		var tgt := pos + tl.normalized() * 10.0
		tgt.y = pos.y - 0.25
		if look_end != null and not travel:
			var w := U.smooth(clampf((u - 0.45) / 0.55, 0.0, 1.0))
			tgt = tgt.lerp(look_end, w)
		var w0 := U.smooth(clampf(u / 0.2, 0.0, 1.0))
		look_target = tgt if travel else look_start.lerp(tgt, w0)
		look = look.lerp(look_target, minf(1.0, dt * 6.0)) if travel else look_target
		bob += dt * (0.0 if linear else 1.0) * 9.5
		if k >= 1.0:
			moving = false
			if look_end != null: look_target = look_end
			var cb := on_done
			on_done = Callable()
			if cb.is_valid(): cb.call()
	else:
		look = look.lerp(look_target, minf(1.0, dt * look_speed))
	sway += dt
	var bob_amt := sin(u * PI) if (moving and not linear) else 0.0
	var p := pos
	p.y += sin(bob) * 0.035 * bob_amt + sin(sway * 0.9) * 0.012
	p.x += cos(bob * 0.5) * 0.02 * bob_amt
	var l := look
	l.y += sin(sway * 0.7) * 0.02
	camera.position = p
	if p.distance_squared_to(l) > 1e-6:
		camera.look_at(l, Vector3.UP)
	if absf(camera.fov - fov) > 0.01:
		camera.fov += (fov - camera.fov) * minf(1.0, dt * 4.0)

func jump(p: Vector3, l: Vector3) -> void:
	pos = p; look = l; look_target = l; moving = false
