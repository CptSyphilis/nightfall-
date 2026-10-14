extends StaticBody2D
## Something the player built: a chest or a workbench.
## Chests have their own inventory. Workbenches unlock extra recipes nearby.

const InventoryScript := preload("res://scripts/inventory.gd")

const SIZES := {
	"chest": Vector2(40, 28),
	"workbench": Vector2(60, 36),
}

var kind := "chest"
var size := Vector2(40, 28)
var storage   # Inventory, only for chests


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


func rect() -> Rect2:
	return Rect2(global_position - size / 2, size)


func _draw() -> void:
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
