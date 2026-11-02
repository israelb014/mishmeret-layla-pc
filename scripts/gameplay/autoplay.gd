class_name Autoplay
extends RefCounted
## Automated player used by --benchmark and --autotest: aims at the most urgent visible threat,
## shoots grenades and pickups, picks route signs and reloads. Uses the real shooting code.

var main: Node
var game: Game
var cool := 0.0

func setup(m: Node) -> void:
	main = m
	game = m.game

func _aim(p: Vector3) -> bool:
	if game.camera.is_position_behind(p): return false
	var sp := game.camera.unproject_position(p)
	var vs := main.get_viewport().get_visible_rect().size
	if sp.x < 0 or sp.y < 0 or sp.x > vs.x or sp.y > vs.y: return false
	main.bot_aim = sp
	return true

func tick(dt: float) -> void:
	cool -= dt
	if game.state != "playing" or cool > 0.0: return
	var w := game.weapon
	if w.ammo <= 0 and not w.special():
		game.reload(); cool = 0.7; return
	if game.branch_signs != null:
		for s in game.branch_signs:
			if s.side == (game.forced_branch if game.forced_branch != "" else "left"):
				if _aim(s.board.global_position): game.try_fire(); cool = 0.4
		return
	var best = null
	var best_u := 1e9
	for o in game.objects:
		if o.get("is_grenade") and o.alive:
			best = o.pos; best_u = -1.0
	for o in game.objects:
		if o.get("is_pickup") and o.alive and best_u > 0.0:
			best = o.node.global_position; best_u = 0.0
	for a in game.actors:
		if not a.is_enemy or not a.alive or not a.c.visible: continue
		if a.state in ["hidden", "wait", "phase"] or (a.state == "intro" and a.t < 0.6): continue
		var u: float = a.threat["remaining"] if a.threat != null else 5.0
		if u < best_u:
			var pt = clear_shot(a)
			if pt != null:
				best_u = u; best = pt
	if best == null:
		for z in game.zones:
			for d in z.destructibles:
				if d["alive"] and d["kind"] == "crate" and d["opts"].get("weapon") != null:
					best = (d["obj"] as Node3D).global_position + Vector3(0, 0.4, 0)
	if best != null and _aim(best):
		game.try_fire()
		cool = 0.28

## First body point of an actor that a bullet would actually reach.
func clear_shot(a):
	for b in ["Chest", "Head", "Hips", "WristR"]:
		var pt: Vector3 = a.c.bone_pos(b)
		if game.camera.is_position_behind(pt): continue
		var sp := game.camera.unproject_position(pt)
		var o := game.camera.project_ray_origin(sp)
		var d := game.camera.project_ray_normal(sp)
		var own: Dictionary = a.c.hit_test(o, d)
		if own.is_empty(): continue
		var space := game.world.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(o, o + d * own["t"], Zone.L_WORLD | Zone.L_DESTRUCT)
		var r := space.intersect_ray(q)
		if r.is_empty(): return pt
		var dd = (r["collider"].get_meta("destructible") if r["collider"].has_meta("destructible") else null)
		if dd != null and (dd["kind"] == "glass" or not dd["alive"]): return pt
		if dd != null and dd["kind"] in ["bottle", "sign"]: return r["position"]
	return null
