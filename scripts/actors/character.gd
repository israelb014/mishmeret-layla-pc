class_name Character
extends Node3D
## Animated Quaternius character: outfit tint + rim light, shared animation library driven by an
## AnimationTree (cross-faded state transitions, time-seek/scale for held poses, hit reaction
## one-shot blended on top), weapon in the right hand, capsule hit shapes, procedural arm pose.

const OUTFIT_MATS := {
	"casual": ["White", "LightBlue", "Red_Dark"], "punk": ["Black", "LightBlue", "White"], "punkf": ["Black", "Pink", "Grey"],
	"swat": ["Swat", "Swat_Black"], "worker": ["Worker_Yellow", "Worker_Vest", "Grey", "Brown"], "suit": ["Suit", "Black", "Tie"],
	"beach": ["Red_Dark", "White"], "woman": ["Red", "LimeGreen", "Brown"], "farmer": ["LightBlue", "Brown2", "Beige"], "adventurer": ["Green", "LightGreen", "Brown2"],
}
const LOOPS := ["Idle", "Idle_Gun", "Idle_Gun_Pointing", "Idle_Neutral", "Idle_Sword", "Run", "Run_Back", "Run_Left", "Run_Right", "Run_Shoot", "Walk",
	"crouch", "crouch_walk", "sprint", "jog", "walk_ual", "walk_formal", "pistol_idle", "phone", "fold_arms", "idle_no", "driving"]
const WEAPON_HOLD := {
	"pistol": [Vector3(0, 0.07, 0.03), Vector3(0, 90, 90)], "pistol_b": [Vector3(0, 0.07, 0.03), Vector3(0, 90, 90)],
	"revolver": [Vector3(0, 0.07, 0.03), Vector3(0, 90, 90)], "smg": [Vector3(0, 0.08, 0.03), Vector3(0, 90, 90)], "smg_b": [Vector3(0, 0.08, 0.04), Vector3(0, 90, 90)],
	"shotgun": [Vector3(0, 0.08, 0.05), Vector3(0, 90, 90)], "knife": [Vector3(0, 0.07, 0.02), Vector3(0, 0, 90)], "grenade": [Vector3(0, 0.07, 0.02), Vector3.ZERO],
}

static var library: AnimationLibrary
static var anim_names: PackedStringArray
static var scenes := {}

static func init_library() -> void:
	if library != null:
		return
	var src: Node = (load("res://assets/anims/anims.glb") as PackedScene).instantiate()
	var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
	library = ap.get_animation_library("").duplicate(true)
	src.free()
	anim_names = library.get_animation_list()
	for n in anim_names:
		library.get_animation(n).loop_mode = Animation.LOOP_LINEAR if LOOPS.has(String(n)) else Animation.LOOP_NONE

var model := ""
var body: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var tree: AnimationTree
var arm: ArmPose
var materials: Array[BaseMaterial3D] = []
var body_materials: Array[BaseMaterial3D] = []
var base_colors: Array[Color] = []
var rim_mat: ShaderMaterial
var rims: Array[ShaderMaterial] = []
var weapon: Node3D
var weapon_name := ""
var hand: BoneAttachment3D
var hit_shapes: Array = []
var opacity := 1.0
var current := ""
var current_loop := true
var current_len := 1.0
var elapsed := 0.0
var speed := 1.0
var bones := {}

func setup(game: Node, mdl: String, opts: Dictionary = {}) -> void:
	model = mdl
	init_library()
	if not scenes.has(mdl):
		scenes[mdl] = load("res://assets/chars/%s.glb" % mdl)
	body = (scenes[mdl] as PackedScene).instantiate()
	add_child(body)
	if opts.has("scale"):
		body.scale *= float(opts["scale"])
	if opts.has("body_scale"):
		body.scale *= float(opts["body_scale"])
	skeleton = body.find_child("Skeleton3D", true, false)
	for i in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(i).replace(".", "")] = i
	# materials: one duplicate per surface; colours re-applied by configure() (pooled reuse)
	rim_mat = game.mats.rim(Color(1, 0.95, 0.84), 0.0)
	rims.append(rim_mat)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		m3.layers = 2 # characters: decals (layer 1 only) never project onto them
		for si in m3.mesh.get_surface_count():
			var src := m3.mesh.surface_get_material(si)
			if not (src is BaseMaterial3D):
				src = StandardMaterial3D.new() # surfaces without a material get a neutral one
			var m: BaseMaterial3D = src.duplicate()
			m.roughness = minf(m.roughness, 0.75)
			m.next_pass = rim_mat
			body_materials.append(m)
			base_colors.append(m.albedo_color)
			materials.append(m)
			m3.set_surface_override_material(si, m)
	# animation: player + tree
	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	body.add_child(player)
	player.add_animation_library("", library)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	body.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = _build_tree()
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	arm = ArmPose.new()
	skeleton.add_child(arm)
	arm.setup(skeleton)
	configure(game, opts)

## (Re)apply outfit, rim light, weapon and reset state — used when taken from the pool.
func configure(game: Node, opts: Dictionary) -> void:
	var outfit: Array = OUTFIT_MATS.get(model, [])
	var tints: Dictionary = opts.get("outfit", {})
	for i in body_materials.size():
		var m := body_materials[i]
		var col: Color = base_colors[i]
		var idx := outfit.find(m.resource_name)
		var key = str(idx) if idx >= 0 else m.resource_name
		if tints.has(key):
			col = U.col(tints[key])
			if opts.get("saturate", false):
				col = Color.from_hsv(col.h, minf(1.0, col.s + 0.15), minf(1.0, col.v + 0.02))
		m.albedo_color = col
	rim_mat.set_shader_parameter("rim_color", opts.get("rim_color", Color(1, 0.95, 0.84)))
	rim_mat.set_shader_parameter("strength", float(opts.get("rim_strength", 0.5)) if opts.get("rim", false) else 0.0)
	opacity = -1.0
	set_opacity(1.0)
	arm.target = 0.0; arm.weight = 0.0
	position = Vector3.ZERO; rotation = Vector3.ZERO; scale = Vector3.ONE
	visible = true
	current = ""
	if opts.get("weapon"):
		attach_weapon(game, String(opts["weapon"]))
	else:
		detach_weapon()
	play("Idle", true, 0.0)

static var _tree_proto: AnimationNodeBlendTree
static func _build_tree() -> AnimationNodeBlendTree:
	if _tree_proto != null:
		return _tree_proto
	var bt := AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.2
	tr.allow_transition_to_self = true
	var i := 0
	for n in anim_names:
		var a := AnimationNodeAnimation.new()
		a.animation = n
		bt.add_node("a%d" % i, a, Vector2(0, i * 40))
		tr.add_input(String(n))
		i += 1
	bt.add_node("state", tr, Vector2(300, 0))
	for j in anim_names.size():
		bt.connect_node("state", j, "a%d" % j)
	var seek := AnimationNodeTimeSeek.new()
	bt.add_node("seek", seek, Vector2(450, 0))
	bt.connect_node("seek", 0, "state")
	var scale := AnimationNodeTimeScale.new()
	bt.add_node("scale", scale, Vector2(600, 0))
	bt.connect_node("scale", 0, "seek")
	var hit_anim := AnimationNodeAnimation.new()
	hit_anim.animation = "HitRecieve"
	bt.add_node("hit_anim", hit_anim, Vector2(600, 200))
	var os := AnimationNodeOneShot.new()
	os.fadein_time = 0.06
	os.fadeout_time = 0.25
	os.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	bt.add_node("hit", os, Vector2(800, 0))
	bt.connect_node("hit", 0, "scale")
	bt.connect_node("hit", 1, "hit_anim")
	bt.connect_node("output", 0, "hit")
	_tree_proto = bt
	return bt

func play(name: String, loop := true, fade := 0.2, spd := 1.0, from := 0.0) -> void:
	if not library.has_animation(name):
		push_warning("missing clip " + name)
		return
	if current == name and loop and current_loop:
		tree.set("parameters/scale/scale", spd)
		speed = spd
		return
	var anim := library.get_animation(name)
	(tree.tree_root.get_node("state") as AnimationNodeTransition).xfade_time = fade
	tree.set("parameters/state/transition_request", name)
	tree.set("parameters/scale/scale", spd)
	if from > 0.0:
		tree.set("parameters/seek/seek_request", from * anim.length)
	current = name
	current_loop = loop
	current_len = anim.length
	elapsed = from * anim.length
	speed = spd

## hold a clip at a normalised time (static pose)
func pose(name: String, t: float) -> void:
	play(name, false, 0.25, 0.0, t)
	tree.set("parameters/seek/seek_request", t * library.get_animation(name).length)

func clip_done() -> bool:
	return not current_loop and elapsed >= current_len

func hit_react() -> void:
	tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func attach_weapon(game: Node, wname: String) -> void:
	detach_weapon()
	var bi := bone("WristR")
	if bi < 0: return
	hand = BoneAttachment3D.new()
	hand.bone_idx = bi
	skeleton.add_child(hand)
	var hold: Array = WEAPON_HOLD.get(wname, WEAPON_HOLD["pistol"])
	var w: Node3D = game.prefabs.make(wname)
	var holder := Node3D.new()
	var s := Prefabs._rel_xf(self, skeleton).basis.get_scale().x
	if s <= 0.0: s = 1.0
	holder.scale = Vector3.ONE / s
	holder.position = hold[0] / s
	holder.rotation_degrees = hold[1]
	var sz: Vector3 = w.get_meta("size")
	w.position = Vector3(0, -sz.y * 0.55, -sz.z * 0.1)
	holder.add_child(w)
	hand.add_child(holder)
	weapon = holder
	weapon_name = wname

func detach_weapon() -> void:
	if hand:
		hand.queue_free()
	hand = null; weapon = null; weapon_name = ""

func bone(n: String) -> int:
	return bones.get(n, -1)

func bone_pos(n: String) -> Vector3:
	var i: int = bones.get(n, -1)
	if i < 0: return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin

func muzzle() -> Vector3:
	if weapon:
		return weapon.global_position + forward() * 0.25
	return bone_pos("WristR")

func forward() -> Vector3:
	return global_transform.basis.z.normalized()

func face_towards(p: Vector3, rate := 1.0) -> void:
	var lp := p
	if get_parent():
		lp = get_parent().to_local(p) if get_parent() is Node3D else p
	var target := atan2(lp.x - position.x, lp.z - position.z)
	rotation.y = lerp_angle(rotation.y, target, minf(1.0, rate))

func set_opacity(a: float) -> void:
	if is_equal_approx(a, opacity):
		return
	opacity = a
	# per-instance fade: no material/shader changes at runtime
	for gi in find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).transparency = 1.0 - a
	for r in rims:
		r.set_shader_parameter("alpha", a)

func set_surrender(t: float) -> void:
	arm.target = t

## Advance animation manually (called by the game's fixed update so headless runs are deterministic)
func step(dt: float) -> void:
	elapsed += dt * speed
	arm.character_basis = global_transform.basis.orthonormalized()
	arm.advance(dt)
	tree.advance(dt)

func update_hit_shapes() -> void:
	hit_shapes.clear()
	var head := bone_pos("Head"); var neck := bone_pos("Neck"); var hips := bone_pos("Hips"); var chest := bone_pos("Chest")
	var head_c := head + (head - neck).normalized() * 0.1
	hit_shapes.append(["head", head_c, head_c, 0.15])
	hit_shapes.append(["torso", hips.lerp(chest, 0.15), neck.lerp(chest, 0.25), 0.21])
	for s in ["L", "R"]:
		hit_shapes.append(["legs", bone_pos("UpperLeg" + s), bone_pos("LowerLeg" + s), 0.11])
		hit_shapes.append(["legs", bone_pos("LowerLeg" + s), bone_pos("Foot" + s), 0.095])
		hit_shapes.append(["torso", bone_pos("UpperArm" + s), bone_pos("LowerArm" + s), 0.075])
		hit_shapes.append(["torso", bone_pos("LowerArm" + s), bone_pos("Wrist" + s), 0.065])
	if weapon and weapon_name != "grenade":
		var c := weapon.global_position
		var r := 0.13 if weapon_name.begins_with("pistol") or weapon_name == "revolver" else 0.17
		hit_shapes.append(["weapon", c + forward() * 0.05, c + forward() * 0.05, r])

const ORDER := ["head", "torso", "legs", "weapon"]
## returns {part, t, point} or {}
func hit_test(from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for s in hit_shapes:
		var t := ray_capsule(from, dir, s[1], s[2], s[3])
		if t < 0.0: continue
		if best.is_empty() or t < best["t"] - 0.03 or (absf(t - best["t"]) <= 0.03 and ORDER.find(s[0]) < ORDER.find(best["part"])):
			best = {"part": s[0], "t": t, "point": from + dir * t}
	return best

static func ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-6:
		var ao := o - a
		var bq := ao.dot(d)
		var c := ao.length_squared() - r * r
		var disc := bq * bq - c
		if disc < 0.0: return -1.0
		var t := -bq - sqrt(disc)
		return t if t > 0.0 else -1.0
	var rr := o - a
	var a11 := d.dot(d); var a12 := d.dot(ab); var a22 := ab.dot(ab); var b1 := d.dot(rr); var b2 := ab.dot(rr)
	var den := a11 * a22 - a12 * a12
	var u := 0.0
	if den > 1e-8:
		u = (a11 * b2 - a12 * b1) / den
	u = clampf(u, 0.0, 1.0)
	var s := maxf(0.0, (a12 * u - b1) / a11)
	var p1 := o + d * s
	var p2 := a + ab * u
	var dist := p1.distance_to(p2)
	if dist > r: return -1.0
	return maxf(0.01, s - sqrt(maxf(0.0, r * r - dist * dist)))
