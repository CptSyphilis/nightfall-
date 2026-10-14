extends Node2D
## A crate (or a dropped bag) you can search with E.

var opened := false
var small := false
var ammo := 0
var food := 0
var medkit := 0


func setup(rng: RandomNumberGenerator, is_small: bool) -> void:
	small = is_small
	ammo = rng.randi_range(0, 6 if small else 10)
	food = rng.randi_range(0, 1 if small else 2)
	medkit = 1 if rng.randf() < 0.2 else 0
	if ammo + food + medkit == 0:
		ammo = 4


func _ready() -> void:
	add_to_group("crates")


## Returns the loot once. Returns an empty Dictionary if already opened.
func open() -> Dictionary:
	if opened:
		return {}
	opened = true
	queue_redraw()
	return {"ammo": ammo, "food": food, "medkit": medkit}


func _draw() -> void:
	var s := 12.0 if small else 18.0
	var rect := Rect2(-s, -s * 0.8, s * 2, s * 1.6)
	if opened:
		draw_rect(rect, Color(0.25, 0.2, 0.14))
		draw_rect(rect.grow(-3), Color(0.12, 0.1, 0.08))
		return
	var wood := Color(0.55, 0.4, 0.22) if not small else Color(0.35, 0.4, 0.3)
	draw_rect(rect.grow(2), Color(0.1, 0.08, 0.05))
	draw_rect(rect, wood)
	draw_line(rect.position, rect.end, wood.darkened(0.35), 2.0)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), wood.darkened(0.35), 2.0)
