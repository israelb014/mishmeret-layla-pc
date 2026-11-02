class_name Pools
extends Node3D
## Character pool: every model needed by a stage is instantiated during loading and reused.

var game: Node
var free := {}

func setup(g: Node) -> void:
	game = g
	name = "Pools"
	visible = false

func warm(model: String, n: int) -> void:
	if not free.has(model):
		free[model] = []
	while (free[model] as Array).size() < n:
		var c := Character.new()
		c.setup(game, model, {})
		c.visible = false
		add_child(c)
		(free[model] as Array).append(c)

func take_character(model: String, opts: Dictionary) -> Character:
	if not free.has(model):
		free[model] = []
	var arr: Array = free[model]
	var c: Character
	if arr.size() > 0:
		c = arr.pop_back()
		if c.get_parent(): c.get_parent().remove_child(c)
	else:
		push_warning("pool miss: %s" % model)
		c = Character.new()
		c.setup(game, model, {})
	c.configure(game, opts)
	return c

func give_character(c: Character) -> void:
	c.visible = false
	c.detach_weapon()
	if c.get_parent():
		c.get_parent().remove_child(c)
	add_child(c)
	(free[c.model] as Array).append(c)

## all pooled characters (used to warm shaders up in front of the camera)
func all_characters() -> Array:
	var a := []
	for arr in free.values(): a.append_array(arr)
	return a
