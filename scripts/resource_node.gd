extends StaticBody2D
## A tree, rock or scrap pile. Hit it with melee (right click) to gather.
## Each hit gives some materials. It disappears after its last hit.

const Items := preload("res://scripts/items.gd")
const FloatingText := preload("res://scripts/floating_text.gd")

const TEXTURES := {
	"tree": preload("res://assets/tree.svg"),
	"rock": preload("res://assets/rock.svg"),
	"scrap": preload("res://assets/scrap.svg"),
}

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
	# Each one gets its own turn and a slight size change, so they don't all look the same.
	var tex: Texture2D = TEXTURES[kind]
	var sc := r.randf_range(0.92, 1.08)
	draw_set_transform(off, r.randf() * TAU, Vector2(sc, sc))
	draw_texture(tex, -tex.get_size() / 2)
	draw_set_transform(Vector2.ZERO)
	if hits_left < max_hits:
		var w := 30.0
		draw_rect(Rect2(-w / 2, -radius - 14, w, 4), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(-w / 2, -radius - 14, w * hits_left / max_hits, 4), Color(0.9, 0.8, 0.3))
