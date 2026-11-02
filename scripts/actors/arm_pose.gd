class_name ArmPose
extends SkeletonModifier3D
## Procedural arm override applied after animation: hands up (surrender) or held hostage.
## weight 0..1 blends the pose in smoothly.

var weight := 0.0
var target := 0.0
var up_arm := PackedInt32Array()
var low_arm := PackedInt32Array()
var wrist := PackedInt32Array()
var character_basis := Basis()

func setup(sk: Skeleton3D) -> void:
	for side in ["L", "R"]:
		up_arm.append(_find(sk, "UpperArm", side))
		low_arm.append(_find(sk, "LowerArm", side))
		wrist.append(_find(sk, "Wrist", side))

static func _find(sk: Skeleton3D, base: String, side: String) -> int:
	for nm in [base + "." + side, base + side, base + "_" + side]:
		var i := sk.find_bone(nm)
		if i >= 0:
			return i
	return -1

func advance(dt: float) -> void:
	weight = move_toward(weight, target, dt * 4.0)

func _process_modification() -> void:
	if weight < 0.01:
		return
	var sk := get_skeleton()
	if sk == null or up_arm.size() < 2:
		return
	var inv := sk.global_transform.basis.inverse()
	var up := (inv * Vector3.UP).normalized()
	var fwd := (inv * (character_basis * Vector3.FORWARD * -1.0)).normalized()
	var right := (inv * (character_basis * Vector3.RIGHT)).normalized()
	for s in 2:
		var sign_x := 1.0 if s == 0 else -1.0
		var d_up := (up * 0.55 + right * 0.8 * sign_x).normalized()
		var d_low := (up + fwd * 0.15 + right * 0.1 * sign_x).normalized()
		_aim(sk, up_arm[s], low_arm[s], d_up)
		_aim(sk, low_arm[s], wrist[s], d_low)

func _aim(sk: Skeleton3D, b: int, child: int, dir: Vector3) -> void:
	if b < 0 or child < 0:
		return
	var gb := sk.get_bone_global_pose(b)
	var gc := sk.get_bone_global_pose(child)
	var cur := (gc.origin - gb.origin).normalized()
	if cur.length_squared() < 0.0001:
		return
	var delta := Quaternion(cur, dir)
	var new_global := Basis(delta) * gb.basis
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var local := (pg.inverse() * new_global).get_rotation_quaternion()
	var cur_local := sk.get_bone_pose_rotation(b)
	sk.set_bone_pose_rotation(b, cur_local.slerp(local, weight))
