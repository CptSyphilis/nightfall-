extends StaticBody2D
## Something the player built.
##   chest, workbench, campfire  - placed from the inventory
##   wood_wall, stone_wall, door, spikes, tower - placed in build mode (see buildings.gd)
##
## Chests have their own inventory. Workbenches unlock extra recipes nearby.
## Campfires start the night and glow in the dark (and can't be destroyed).
## Zombies smash structures when they have no other way to reach you.

signal destroyed

const InventoryScript := preload("res://scripts/inventory.gd")
const Buildings := preload("res://scripts/buildings.gd")
const BulletScript := preload("res://scripts/bullet.gd")

const LAYER_DOOR := 16   # only zombies bump into doors; the player walks through

const SIZES := {
	"chest": Vector2(40, 28),
	"workbench": Vector2(60, 36),
	"campfire": Vector2(34, 34),
	"wood_wall": Vector2(32, 32),
	"stone_wall": Vector2(32, 32),
	"door": Vector2(32, 32),
	"spikes": Vector2(32, 32),
	"tower": Vector2(32, 32),
}

# Spike trap
const SPIKE_TICK := 0.6
const SPIKE_DAMAGE := 15.0
const SPIKE_WEAR := 4.0        # trap loses this much health per zombie it hurts
# Arrow tower
const TOWER_RANGE := 300.0
const TOWER_COOLDOWN := 1.2
const TOWER_DAMAGE := 28.0

var kind := "chest"
var size := Vector2(40, 28)
var max_hp := 200.0
var hp := 200.0
var breakable := true
var storage   # Inventory, only for chests
var light: PointLight2D   # only for campfires
var _t := 0.0
var _hit_flash := 0.0
var _tick := 0.0
var _aim := -PI / 2


func setup(k: String) -> void:
	kind = k
	size = SIZES[k]
	if Buildings.is_piece(k):
		max_hp = Buildings.PIECES[k]["hp"]
	hp = max_hp
	breakable = kind != "campfire"
	if kind == "chest":
		storage = InventoryScript.new()
		storage.max_slots = 20


func _ready() -> void:
	add_to_group("structures")
	collision_mask = 0
	match kind:
		"spikes":
			collision_layer = 0          # you walk over traps
		"door":
			collision_layer = LAYER_DOOR
		_:
			collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	if kind == "campfire":
		_add_light()


## True if zombies have to walk around it (traps don't count).
func blocks_path() -> bool:
	return kind != "spikes"


## True if the player can press E / Square on it.
func is_usable() -> bool:
	return kind in ["chest", "workbench", "campfire"]


func rect() -> Rect2:
	return Rect2(global_position - size / 2, size)


func take_damage(amount: float) -> void:
	if not breakable or hp <= 0.0:
		return
	hp -= amount
	_hit_flash = 0.12
	queue_redraw()
	if hp <= 0.0:
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.on_structure_destroyed(self)
		destroyed.emit()
		queue_free()


func _physics_process(delta: float) -> void:
	_t += delta
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	match kind:
		"campfire":
			var game := get_tree().get_first_node_in_group("game")
			if game and light:
				# Flickers a little, and only really shows in the dark.
				light.energy = game.night_amount * (1.1 + sin(_t * 9.0) * 0.08 + sin(_t * 23.0) * 0.05)
			queue_redraw()
		"spikes":
			_spike_tick(delta)
		"tower":
			_tower_tick(delta)
	if _hit_flash > 0.0:
		queue_redraw()


func _spike_tick(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = SPIKE_TICK
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead or z.global_position.distance_to(global_position) > 16.0 + z.radius:
			continue
		z.take_damage(SPIKE_DAMAGE)
		z.slow_timer = 1.0
		take_damage(SPIKE_WEAR)
		if hp <= 0.0:
			return


func _tower_tick(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	var best: Node2D = null
	var best_d := TOWER_RANGE
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead:
			continue
		var d: float = z.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = z
	if best == null:
		_tick = 0.2   # look again soon
		return
	_tick = TOWER_COOLDOWN
	var dir := global_position.direction_to(best.global_position)
	_aim = dir.angle()
	var b: Node2D = BulletScript.new()
	b.position = global_position + dir * 18.0
	b.direction = dir
	b.damage = TOWER_DAMAGE
	b.speed = 800.0
	b.life = TOWER_RANGE / 800.0 + 0.1
	b.style = "arrow"
	b.mask = 4           # tower arrows fly over walls and only hit zombies
	var game := get_tree().get_first_node_in_group("game")
	game.world_node.add_child(b)
	queue_redraw()


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


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_piece(self, kind, size, _t, _aim)
	if _hit_flash > 0.0:
		draw_rect(Rect2(-size / 2, size), Color(1, 1, 1, 0.5))
	if breakable and hp < max_hp:
		var w := size.x
		draw_rect(Rect2(-w / 2, -size.y / 2 - 8, w, 4), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(-w / 2, -size.y / 2 - 8, w * hp / max_hp, 4), Color(0.9, 0.6, 0.2))


## Draws a structure onto any canvas item (also used for the build mode preview).
static func draw_piece(ci: CanvasItem, k: String, sz: Vector2, t: float = 0.0, aim: float = -PI / 2) -> void:
	var r := Rect2(-sz / 2, sz)
	var outline := Color(0.1, 0.07, 0.04)
	match k:
		"campfire":
			for i in 9:
				var p := Vector2.from_angle(TAU * i / 9.0) * 14.0
				ci.draw_circle(p, 5.0, Color(0.1, 0.1, 0.1))
				ci.draw_circle(p, 4.0, Color(0.5, 0.5, 0.52))
			ci.draw_line(Vector2(-9, -6), Vector2(9, 6), Color(0.35, 0.22, 0.12), 5.0)
			ci.draw_line(Vector2(-9, 6), Vector2(9, -6), Color(0.3, 0.19, 0.1), 5.0)
			var f := sin(t * 8.0) * 1.5
			ci.draw_circle(Vector2(0, -1), 7.0 + f, Color(0.95, 0.4, 0.1, 0.9))
			ci.draw_circle(Vector2(1, -3), 4.5 - f * 0.5, Color(1.0, 0.75, 0.2, 0.95))
			ci.draw_circle(Vector2(0, -4), 2.0, Color(1.0, 0.95, 0.7))
		"chest":
			ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.3))
			ci.draw_rect(r.grow(2), outline)
			ci.draw_rect(r, Color(0.5, 0.33, 0.18))
			ci.draw_rect(Rect2(r.position.x, -3, r.size.x, 6), Color(0.35, 0.35, 0.38))
			ci.draw_rect(Rect2(-4, -5, 8, 10), Color(0.85, 0.7, 0.3))
		"workbench":
			ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.3))
			ci.draw_rect(r.grow(2), outline)
			ci.draw_rect(r, Color(0.42, 0.3, 0.18))
			for i in 4:
				var x := r.position.x + 6 + i * (r.size.x - 12) / 3.0
				ci.draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(0.32, 0.22, 0.12), 2.0)
			ci.draw_rect(Rect2(-24, -12, 20, 6), Color(0.7, 0.7, 0.72))
			ci.draw_line(Vector2(6, 8), Vector2(22, -8), Color(0.3, 0.2, 0.1), 3.0)
			ci.draw_rect(Rect2(18, -12, 10, 6), Color(0.4, 0.4, 0.42))
		"wood_wall":
			ci.draw_rect(r, outline)
			var inner := r.grow(-2)
			ci.draw_rect(inner, Color(0.52, 0.36, 0.2))
			for i in range(1, 4):
				var y := inner.position.y + inner.size.y * i / 4.0
				ci.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(0.36, 0.24, 0.13), 2.0)
			for p in [Vector2(-9, -9), Vector2(9, -9), Vector2(-9, 9), Vector2(9, 9)]:
				ci.draw_circle(p, 1.5, Color(0.25, 0.25, 0.27))
		"stone_wall":
			ci.draw_rect(r, Color(0.12, 0.12, 0.13))
			var inner := r.grow(-2)
			ci.draw_rect(inner, Color(0.5, 0.5, 0.53))
			var mortar := Color(0.32, 0.32, 0.34)
			for row in 3:
				var y := inner.position.y + inner.size.y * row / 3.0
				ci.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), mortar, 2.0)
				var shift := 7.0 if row % 2 == 0 else 0.0
				for x in [inner.position.x + 7.0 + shift, inner.position.x + 21.0 + shift]:
					if x < inner.end.x - 2:
						ci.draw_line(Vector2(x, y), Vector2(x, y + inner.size.y / 3.0), mortar, 2.0)
		"door":
			ci.draw_rect(r, outline)
			ci.draw_rect(r.grow(-2), Color(0.3, 0.2, 0.11))
			ci.draw_rect(r.grow(-6), Color(0.6, 0.42, 0.22))
			ci.draw_line(Vector2(0, r.position.y + 6), Vector2(0, r.end.y - 6), Color(0.4, 0.27, 0.14), 2.0)
			ci.draw_circle(Vector2(7, 0), 2.5, Color(0.85, 0.75, 0.35))
		"spikes":
			ci.draw_rect(r.grow(-2), Color(0.15, 0.12, 0.08, 0.6))
			for p in [Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8), Vector2(8, 8), Vector2(0, 0)]:
				var tri := PackedVector2Array([p + Vector2(-4, 4), p + Vector2(4, 4), p + Vector2(0, -6)])
				ci.draw_colored_polygon(tri, Color(0.75, 0.75, 0.78))
				ci.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.2, 0.2, 0.22), 1.0)
		"tower":
			ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.3))
			ci.draw_rect(r, Color(0.12, 0.12, 0.13))
			ci.draw_rect(r.grow(-2), Color(0.45, 0.45, 0.48))
			ci.draw_circle(Vector2.ZERO, 12.0, Color(0.1, 0.07, 0.04))
			ci.draw_circle(Vector2.ZERO, 10.5, Color(0.5, 0.34, 0.18))
			# A mounted bow pointing at the last target.
			var c := Vector2.from_angle(aim) * 4.0
			ci.draw_arc(c, 9.0, aim - 1.3, aim + 1.3, 10, Color(0.3, 0.2, 0.1), 3.0)
			ci.draw_line(Vector2.ZERO, Vector2.from_angle(aim) * 13.0, Color(0.85, 0.8, 0.7), 2.0)
