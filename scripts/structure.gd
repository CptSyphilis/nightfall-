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

## Sprites, each the exact size of its grid footprint.
const TEXTURES := {
	"chest": preload("res://assets/chest.svg"),
	"workbench": preload("res://assets/workbench.svg"),
	"campfire": preload("res://assets/campfire.svg"),
	"wood_wall": preload("res://assets/wood_wall.svg"),
	"stone_wall": preload("res://assets/stone_wall.svg"),
	"door": preload("res://assets/door.svg"),
	"spikes": preload("res://assets/spikes.svg"),
	"tower": preload("res://assets/tower.svg"),
}
const TEX_TOWER_BOW := preload("res://assets/tower_bow.svg")

const LAYER_DOOR := 16   # only zombies bump into doors; the player walks through

const SIZES := {
	"chest": Vector2(32, 32),        # one grid square
	"workbench": Vector2(64, 32),    # two grid squares
	"campfire": Vector2(32, 32),
	"wood_wall": Vector2(32, 32),
	"stone_wall": Vector2(32, 32),
	"door": Vector2(32, 32),
	"spikes": Vector2(32, 32),
	"tower": Vector2(32, 32),
	"concrete_floor": Vector2(32, 32),
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
		"spikes", "concrete_floor":
			collision_layer = 0          # you walk over traps and floors
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
	return kind != "spikes" and not is_floor()


func is_floor() -> bool:
	return Buildings.is_floor(kind)


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
	if k == "concrete_floor":
		ci.draw_rect(r, Color(0.52, 0.52, 0.5))
		ci.draw_rect(r.grow(-1.0), Color(0.6, 0.6, 0.58))
		ci.draw_line(r.position + Vector2(5, 9), r.position + Vector2(12, 11), Color(0.5, 0.5, 0.48), 1.0)
		ci.draw_line(r.position + Vector2(20, 22), r.position + Vector2(26, 19), Color(0.5, 0.5, 0.48), 1.0)
		return
	# Soft drop shadow under the things that stand up off the ground.
	if k in ["chest", "workbench", "tower"]:
		ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.3))
	if TEXTURES.has(k):
		ci.draw_texture_rect(TEXTURES[k], r, false)
	else:
		ci.draw_rect(r, Color(0.5, 0.33, 0.18))
	match k:
		"campfire":
			# Procedural flame on top of the logs, so it keeps flickering.
			var f := sin(t * 8.0) * 1.5
			var g := sin(t * 13.0 + 1.0) * 1.0
			ci.draw_circle(Vector2(0, 0), 8.0 + f, Color(0.85, 0.3, 0.08, 0.55))
			ci.draw_circle(Vector2(0, -1), 6.5 + f, Color(0.95, 0.42, 0.1, 0.9))
			ci.draw_circle(Vector2(1 + g * 0.5, -3), 4.5 - f * 0.5, Color(1.0, 0.72, 0.2, 0.95))
			ci.draw_circle(Vector2(0, -4 + g * 0.5), 2.0, Color(1.0, 0.95, 0.7))
		"tower":
			# The mounted bow turns to point at the last target.
			ci.draw_set_transform(Vector2.ZERO, aim)
			ci.draw_texture(TEX_TOWER_BOW, -TEX_TOWER_BOW.get_size() / 2)
			ci.draw_set_transform(Vector2.ZERO)
