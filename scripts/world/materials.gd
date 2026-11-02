class_name Materials
extends RefCounted
## PBR surface materials (Poly Haven: albedo / normal / ORM / height) with world-space
## triplanar mapping, facade variants for Israeli buildings, and the character rim light.

const SETS := ["asphalt", "pavers", "limestone", "plaster", "concrete", "brick", "corrugated", "planks", "deck", "tiles", "facade_tiles", "shutter"]
const HEIGHT_SETS := ["asphalt", "limestone", "deck", "tiles"]

var cache := {}
var rim_shader: Shader

func _init() -> void:
	rim_shader = Shader.new()
	rim_shader.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back;
uniform vec3 rim_color : source_color = vec3(1.0, 0.95, 0.84);
uniform float strength = 0.5;
uniform float alpha = 1.0;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = rim_color * strength * pow(f, 2.6) * alpha;
}
"""

func textures_of(set_name: String) -> Array:
	var a := []
	for m in ["color", "normal", "orm"]:
		a.append("res://assets/tex/%s/%s.jpg" % [set_name, m])
	return a

## scale: metres per texture repeat (world triplanar)
func get_mat(set_name: String, color := Color.WHITE, scale := 4.0, metallic := 0.0, key := "") -> ORMMaterial3D:
	var k := key if key != "" else "%s|%s|%s|%s" % [set_name, color.to_html(), scale, metallic]
	if cache.has(k):
		return cache[k]
	var m := ORMMaterial3D.new()
	m.resource_name = "pbr_" + set_name
	m.albedo_texture = load("res://assets/tex/%s/color.jpg" % set_name)
	m.albedo_color = color
	m.normal_enabled = true
	m.normal_texture = load("res://assets/tex/%s/normal.jpg" % set_name)
	m.orm_texture = load("res://assets/tex/%s/orm.jpg" % set_name)
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	cache[k] = m
	return m

## Facade materials used to reskin the Downtown City buildings into Israeli streets.
func facade(variant: String) -> Material:
	var V := {
		"limestone": ["limestone", Color("#f3e4c4"), 3.0], "limestone_warm": ["limestone", Color("#f6d9a8"), 3.0],
		"plaster_white": ["plaster", Color("#f7f3ea"), 2.5], "plaster_cream": ["plaster", Color("#f6e3b8"), 2.5],
		"plaster_peach": ["plaster", Color("#f2c6a0"), 2.5], "plaster_blue": ["plaster", Color("#cfe2ef"), 2.5],
		"concrete": ["concrete", Color("#e6e2d8"), 3.0], "brick": ["brick", Color.WHITE, 3.0],
	}
	var v: Array = V.get(variant, V["limestone"])
	return get_mat(v[0], v[1], v[2])

func paint(color: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var k := "paint|%s|%s|%s" % [color.to_html(), rough, metal]
	if cache.has(k): return cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	cache[k] = m
	return m

func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var k := "emis|%s|%s" % [color.to_html(), energy]
	if cache.has(k): return cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	cache[k] = m
	return m

func glass() -> StandardMaterial3D:
	if cache.has("glass"): return cache["glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.89, 0.94, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.03
	m.metallic = 0.6
	m.metallic_specular = 0.9
	cache["glass"] = m
	return m

## Rim-light pass added on top of a character material (enemies read against any background)
func rim(color: Color, strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = rim_shader
	m.set_shader_parameter("rim_color", color)
	m.set_shader_parameter("strength", strength)
	return m
