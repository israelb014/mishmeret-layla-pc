class_name GeomCheck
extends RefCounted
## CI z-fighting scan (--geomcheck): looks for triangles of two DIFFERENT meshes (or two
## MultiMesh instances) that lie in the same plane (within 2 mm), face the same way and overlap
## by more than 4 cm^2 -- the faces that flicker against each other. Faces pointing in opposite
## directions are not reported: one of them is always culled or hidden inside the other volume.

const PLANE_EPS := 0.002
const MIN_AREA := 0.0004

var faces_cache := {} # Mesh -> PackedVector3Array (local triangles)
var tris := 0 # triangles scanned (coverage report)

## Returns the problems found in one built zone (positions relative to the zone).
func check_zone(root: Node3D) -> Array:
	var buckets := {} # quantised plane -> Array of [owner, n, d, a, b, c, label]
	var owner_id := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for ch in node.get_children(): stack.append(ch)
		if not (node is GeometryInstance3D) or not (node as GeometryInstance3D).visible: continue
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			owner_id += 1
			_add(buckets, owner_id, Prefabs._rel_xf(root, node), (node as MeshInstance3D).mesh, _label(root, node))
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var mm := (node as MultiMeshInstance3D).multimesh
			var base := Prefabs._rel_xf(root, node)
			for i in mm.instance_count:
				owner_id += 1
				_add(buckets, owner_id, base * mm.get_instance_transform(i), mm.mesh, "%s#%d" % [_label(root, node), i])
	var problems := []
	var seen := {}
	for key in buckets:
		var list: Array = buckets[key]
		# compare with the same bucket and the next plane-distance bucket (quantisation edge)
		var parts := (key as String).split(",")
		var nkey := "%s,%s,%s,%d" % [parts[0], parts[1], parts[2], int(parts[3]) + 1]
		var others: Array = list + (buckets[nkey] if buckets.has(nkey) else [])
		for i in list.size():
			var t1: Array = list[i]
			for j in range(i + 1, others.size()):
				var t2: Array = others[j]
				if t1[0] == t2[0]: continue
				if absf(float(t1[2]) - float(t2[2])) > PLANE_EPS: continue
				if (t1[1] as Vector3).dot(t2[1]) < 0.999: continue
				var pair := "%s|%s" % [t1[6], t2[6]] if String(t1[6]) < String(t2[6]) else "%s|%s" % [t2[6], t1[6]]
				if seen.has(pair): continue
				var area := _overlap(t1, t2)
				if area > MIN_AREA:
					seen[pair] = true
					problems.append("%s  <->  %s  (plane n=%s d=%.3f, overlap %.4f m2)" % [t1[6], t2[6], (t1[1] as Vector3).snapped(Vector3(0.01, 0.01, 0.01)), float(t1[2]), area])
	return problems

func _label(root: Node, n: Node) -> String:
	var p := String(root.get_path_to(n))
	return p if p.length() < 90 else "..." + p.right(87)

func _add(buckets: Dictionary, owner: int, xf: Transform3D, mesh: Mesh, label: String) -> void:
	var f: PackedVector3Array
	if faces_cache.has(mesh):
		f = faces_cache[mesh]
	else:
		f = mesh.get_faces()
		faces_cache[mesh] = f
	var i := 0
	while i + 2 < f.size():
		var a := xf * f[i]; var b := xf * f[i + 1]; var c := xf * f[i + 2]
		i += 3
		var cr := (b - a).cross(c - a)
		var ln := cr.length()
		if ln < 1e-5: continue
		tris += 1
		var n := cr / ln
		var d := n.dot(a)
		var key := "%d,%d,%d,%d" % [roundi(n.x * 100.0), roundi(n.y * 100.0), roundi(n.z * 100.0), floori(d / PLANE_EPS)]
		if not buckets.has(key): buckets[key] = []
		(buckets[key] as Array).append([owner, n, d, a, b, c, label])

## Overlapping area of two coplanar triangles (projected on their dominant plane).
func _overlap(t1: Array, t2: Array) -> float:
	var n: Vector3 = (t1[1] as Vector3).abs()
	var drop := 0 if n.x >= n.y and n.x >= n.z else (1 if n.y >= n.z else 2)
	var p1 := PackedVector2Array(); var p2 := PackedVector2Array()
	for k in 3:
		p1.append(_proj(t1[3 + k], drop)); p2.append(_proj(t2[3 + k], drop))
	# cheap bounding-box reject first
	var r1 := Rect2(p1[0], Vector2.ZERO).expand(p1[1]).expand(p1[2])
	var r2 := Rect2(p2[0], Vector2.ZERO).expand(p2[1]).expand(p2[2])
	if not r1.grow(-0.001).intersects(r2.grow(-0.001)): return 0.0
	var area := 0.0
	for poly in Geometry2D.intersect_polygons(p1, p2):
		area += absf(_shoelace(poly))
	# projected area -> real area
	var nn: Vector3 = t1[1]
	var scale := absf([nn.x, nn.y, nn.z][drop])
	return area / maxf(scale, 1e-3)

static func _proj(v: Vector3, drop: int) -> Vector2:
	return Vector2(v.y, v.z) if drop == 0 else (Vector2(v.x, v.z) if drop == 1 else Vector2(v.x, v.y))

static func _shoelace(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]; var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5
