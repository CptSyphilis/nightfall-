extends StaticBody2D
## A tree, rock or scrap pile. Hit it with melee (right click) to gather.
## Each hit gives some materials. It disappears after its last hit.

const Items := preload("res://scripts/items.gd")
const FloatingText := preload("res://scripts/floating_text.gd")

const KINDS := {
	"tree":  {"radius": 16.0, "hits": 4, "item": "wood",  "min": 2, "max": 3},
	"rock":  {"radius": 20.0, "hits": 5, "item": "stone", "min": 1, "max": 3},
	"scrap": {"radius": 18.0, "hits": 3, "item": "scrap", "min": 1, "max": 2},
}

var kind := "tree"
var radius := 16.0
var hits_left := 4
var max_hits := 4
var depleted := false
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _shape_seed := 0


func setup(k: String) -> void:
	kind = k
	radius = KINDS[k]["radius"]
	max_hits = KINDS[k]["hits"]
	hits_left = max_hits


func _ready() -> void:
	add_to_group("resources")
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	_rng.randomize()
	_shape_seed = _rng.randi()


## Called by the player's melee swing. Puts materials in their inventory.
## multiplier > 1 when using the right tool (stone axe on trees, machete on scrap).
func gather(by: Node, multiplier: int = 1) -> int:
	if depleted:
		return 0
	var info: Dictionary = KINDS[kind]
	var item: String = info["item"]
	var amount: int = _rng.randi_range(info["min"], info["max"]) * multiplier
	var added: int = by.inventory.add(item, amount)
	var text := "+%d %s" % [added, Items.display_name(item)]
	# Scrap piles sometimes have old clothes in them.
	if kind == "scrap" and _rng.randf() < 0.4:
		if by.inventory.add("cloth", 1) > 0:
			text += "  +1 Cloth"
	if added < amount:
		text = "Inventory full"
	_popup(text, Items.color(item) if added > 0 else Color(1, 0.4, 0.4))

	hits_left -= 1
	_shake = 0.15
	if hits_left <= 0:
		depleted = true
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.nav_dirty = true   # zombies can walk here now
		queue_free()
	return added


func _popup(text: String, color: Color) -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.floating_text(global_position + Vector2(0, -radius - 10), text, color)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(_shake - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = _shape_seed
	var off := Vector2(sin(_shake * 80.0) * 3.0, 0) if _shake > 0.0 else Vector2.ZERO
	match kind:
		"tree":
			draw_circle(off + Vector2(4, 6), 34, Color(0, 0, 0, 0.25))      # shadow
			draw_circle(off, 34, Color(0.12, 0.22, 0.1))
			for i in 5:
				var p := Vector2.from_angle(r.randf() * TAU) * r.randf_range(6, 16)
				draw_circle(off + p, r.randf_range(14, 20), Color(0.16, 0.3, 0.13).lerp(Color(0.22, 0.36, 0.16), r.randf()))
			draw_circle(off, 7, Color(0.3, 0.2, 0.12))                       # trunk top
		"rock":
			var pts := PackedVector2Array()
			for i in 9:
				var a := TAU * i / 9.0
				pts.append(off + Vector2.from_angle(a) * radius * r.randf_range(0.85, 1.25))
			var outline := pts.duplicate()
			outline.append(pts[0])
			draw_colored_polygon(pts, Color(0.45, 0.45, 0.47))
			draw_polyline(outline, Color(0.15, 0.15, 0.16), 3.0)
			draw_circle(off + Vector2(-5, -5), 6, Color(0.55, 0.55, 0.58))
		"scrap":
			for i in 6:
				var c := Color(0.5, 0.3, 0.2).lerp(Color(0.45, 0.45, 0.48), r.randf())
				var p := off + Vector2(r.randf_range(-12, 12), r.randf_range(-10, 10))
				draw_set_transform(p, r.randf() * TAU)
				draw_rect(Rect2(-9, -4, 18, 8), Color(0.1, 0.08, 0.06))
				draw_rect(Rect2(-8, -3, 16, 6), c)
			draw_set_transform(Vector2.ZERO)
	if hits_left < max_hits:
		var w := 30.0
		draw_rect(Rect2(-w / 2, -radius - 14, w, 4), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(-w / 2, -radius - 14, w * hits_left / max_hits, 4), Color(0.9, 0.8, 0.3))
