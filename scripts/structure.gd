extends StaticBody2D
## Something the player built: a chest, a workbench or a campfire.
## Chests have their own inventory. Workbenches unlock extra recipes nearby.
## Campfires start the night when used, and glow in the dark.

const InventoryScript := preload("res://scripts/inventory.gd")

const SIZES := {
	"chest": Vector2(40, 28),
	"workbench": Vector2(60, 36),
	"campfire": Vector2(34, 34),
}

var kind := "chest"
var size := Vector2(40, 28)
var storage   # Inventory, only for chests
var light: PointLight2D   # only for campfires
var _t := 0.0


func setup(k: String) -> void:
	kind = k
	size = SIZES[k]
	if kind == "chest":
		storage = InventoryScript.new()
		storage.max_slots = 20


func _ready() -> void:
	add_to_group("structures")
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	if kind == "campfire":
		_add_light()


func _add_light() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	light = PointLight2D.new()
	light.texture = tex
	light.texture_scale = 2.0
	light.color = Color(1.0, 0.6, 0.3)
	light.energy = 0.0
	add_child(light)


func _process(delta: float) -> void:
	if kind != "campfire":
		return
	_t += delta
	var game := get_tree().get_first_node_in_group("game")
	if game and light:
		# Flickers a little, and only really shows in the dark.
		light.energy = game.night_amount * (1.1 + sin(_t * 9.0) * 0.08 + sin(_t * 23.0) * 0.05)
	queue_redraw()


func rect() -> Rect2:
	return Rect2(global_position - size / 2, size)


func _draw() -> void:
	if kind == "campfire":
		_draw_campfire()
		return
	var r := Rect2(-size / 2, size)
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.3))   # shadow
	if kind == "chest":
		draw_rect(r.grow(2), Color(0.1, 0.07, 0.04))
		draw_rect(r, Color(0.5, 0.33, 0.18))
		draw_rect(Rect2(r.position.x, -3, r.size.x, 6), Color(0.35, 0.35, 0.38))   # metal band
		draw_rect(Rect2(-4, -5, 8, 10), Color(0.85, 0.7, 0.3))                      # lock
	else:
		draw_rect(r.grow(2), Color(0.1, 0.07, 0.04))
		draw_rect(r, Color(0.42, 0.3, 0.18))
		for i in 4:
			var x := r.position.x + 6 + i * (r.size.x - 12) / 3.0
			draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(0.32, 0.22, 0.12), 2.0)
		# A saw and a hammer lying on top.
		draw_rect(Rect2(-24, -12, 20, 6), Color(0.7, 0.7, 0.72))
		draw_line(Vector2(6, 8), Vector2(22, -8), Color(0.3, 0.2, 0.1), 3.0)
		draw_rect(Rect2(18, -12, 10, 6), Color(0.4, 0.4, 0.42))


func _draw_campfire() -> void:
	# Ring of stones.
	for i in 9:
		var p := Vector2.from_angle(TAU * i / 9.0) * 14.0
		draw_circle(p, 5.0, Color(0.1, 0.1, 0.1))
		draw_circle(p, 4.0, Color(0.5, 0.5, 0.52))
	# Crossed logs.
	draw_line(Vector2(-9, -6), Vector2(9, 6), Color(0.35, 0.22, 0.12), 5.0)
	draw_line(Vector2(-9, 6), Vector2(9, -6), Color(0.3, 0.19, 0.1), 5.0)
	# Flames, moving a little.
	var f := sin(_t * 8.0) * 1.5
	draw_circle(Vector2(0, -1), 7.0 + f, Color(0.95, 0.4, 0.1, 0.9))
	draw_circle(Vector2(1, -3), 4.5 - f * 0.5, Color(1.0, 0.75, 0.2, 0.95))
	draw_circle(Vector2(0, -4), 2.0, Color(1.0, 0.95, 0.7))
