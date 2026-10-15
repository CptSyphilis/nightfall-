extends Node2D
## Main game scene.
## Builds the map, runs the day/night cycle and spawns zombies.
## Everything is created from code, so there is only one tiny .tscn file.
##
## The loop:
##   Day   - no zombies and no timer. Gather, craft and build.
##   Night - starts when you use a campfire. Zombies hunt you until dawn.
##   Dawn  - the zombies are gone and a new day begins.

const WORLD_SIZE := Vector2(3200, 3200)
const SAFE_RADIUS := 320.0   # nothing spawns this close to the start point
const CELL := 32.0           # the building grid; everything on the map lines up with it
const ZOMBIE_DROP_CHANCE := 0.1   # chance a killed zombie drops a bag
const CAMPFIRE_LIVES := 10   # zombies reaching the campfire cost one each; at 0 you lose

const PlayerScript := preload("res://scripts/player.gd")
const ZombieScript := preload("res://scripts/zombie.gd")
const CrateScript := preload("res://scripts/loot_crate.gd")
const HudScript := preload("res://scripts/hud.gd")
const ResourceScript := preload("res://scripts/resource_node.gd")
const StructureScript := preload("res://scripts/structure.gd")
const InventoryUiScript := preload("res://scripts/inventory_ui.gd")
const PlacementScript := preload("res://scripts/placement.gd")
const FloatingTextScript := preload("res://scripts/floating_text.gd")
const NavGridScript := preload("res://scripts/nav_grid.gd")
const BuildModeScript := preload("res://scripts/build_mode.gd")
const GridOverlayScript := preload("res://scripts/grid_overlay.gd")
const Buildings := preload("res://scripts/buildings.gd")
const TEX_GRASS := preload("res://assets/grass_tile.svg")
const TEX_RUBBLE := preload("res://assets/rubble_tile.svg")

const DAY_COLOR := Color(1, 1, 1)
const NIGHT_COLOR := Color(0.28, 0.32, 0.5)

var player: CharacterBody2D
var hud: Control
var tint: CanvasModulate
var items_node: Node2D    # crates, trees, rocks, chests (drawn under characters)
var world_node: Node2D    # player, zombies, bullets
var ui: Control           # inventory / crafting window
var placement: Node2D     # green/red outline when placing a chest or workbench
var placing := ""         # item id being placed, "" when not placing
var build: Node2D         # build mode (walls, doors, traps, towers)
var show_input_debug := false   # F3: shows what the controller is sending

## True while the inventory window is open (combat is paused for the player).
var ui_open: bool:
	get:
		return ui != null and ui.visible

var day := 1
var is_night := false
var night_amount := 0.0   # 0 = full daylight, 1 = full night (used for the player's light)
var phase_time := 0.0
var kills := 0
var game_over := false
var lose_reason := ""
var lives := CAMPFIRE_LIVES
var spawning_enabled := true
var trickle_timer := 0.0
var horde_left := 0
var horde_timer := 0.0
var nav = null              # navigation grid zombies use to walk around things
var nav_dirty := false      # rebuild the grid (something was built or chopped down)
var _night_confirm_until := 0   # campfire needs a second press within 3 seconds

var ruins: Array[Rect2] = []
var rng := RandomNumberGenerator.new()
var _ground_specks: Array = []
var _road_cracks: Array = []


func _ready() -> void:
	add_to_group("game")
	setup_input()
	rng.randomize()
	_build_world()
	_spawn_player()
	_spawn_hud()
	_spawn_crates()
	_spawn_resources()
	nav = NavGridScript.new()
	nav.build(WORLD_SIZE, ruins, self)
	hud.show_message("Day 1 - gather and build. Build a campfire (B) and defend it at night.", 6.0)


func _physics_process(delta: float) -> void:
	if nav_dirty and nav != null:
		nav_dirty = false
		nav.build(WORLD_SIZE, ruins, self)
	if game_over:
		return
	phase_time += delta
	if is_night and phase_time >= night_length():
		start_day()
	_update_tint()
	if spawning_enabled and is_night:
		_update_spawning(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_input"):
		show_input_debug = not show_input_debug
	if game_over and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


# ---------------------------------------------------------------- day / night

## Nights get longer: 60 seconds on night 1, +10 each night, at most 2 minutes.
func night_length() -> float:
	return minf(60.0 + (day - 1) * 10.0, 120.0)


## Called when the player uses a campfire. The first press asks to confirm,
## a second press within 3 seconds starts the night.
func campfire_used() -> void:
	if is_night:
		hud.show_message("The fire is burning. Survive until dawn.", 2.5)
		return
	var now := Time.get_ticks_msec()
	if now < _night_confirm_until:
		_night_confirm_until = 0
		start_night()
	else:
		_night_confirm_until = now + 3000
		hud.show_message("Press %s again to start night %d" % [hud.prompt("interact"), day], 3.0)


func start_night() -> bool:
	if is_night:
		return false
	is_night = true
	phase_time = 0.0
	horde_left = 4 + day * 4
	horde_timer = 3.0
	trickle_timer = 1.0
	hud.show_message("Night %d - the horde is coming" % day)
	return true


func start_day() -> void:
	is_night = false
	phase_time = 0.0
	day += 1
	horde_left = 0
	# The dead do not walk in daylight.
	for z in get_tree().get_nodes_in_group("zombies"):
		z.dead = true
		z.queue_free()
	hud.show_message("Day %d - you survived the night. Build and gather." % day, 4.0)


## Seconds left of the night (0 during the day).
func time_left() -> float:
	return night_length() - phase_time if is_night else 0.0


func _update_tint() -> void:
	# 0 = full daylight, 1 = full night.
	# Darkens over 3 seconds after the fire is lit, brightens over the last 8 seconds.
	var t := 0.0
	if is_night:
		t = minf(clampf(phase_time / 3.0, 0.0, 1.0), clampf((night_length() - phase_time) / 8.0, 0.0, 1.0))
	night_amount = t
	tint.color = DAY_COLOR.lerp(NIGHT_COLOR, t)


# ---------------------------------------------------------------- spawning

## Only runs at night.
func _update_spawning(delta: float) -> void:
	# Wanderers keep shuffling in from the dark.
	trickle_timer -= delta
	if trickle_timer <= 0.0:
		trickle_timer = 2.5
		if zombie_count() < 12 + day * 3:
			spawn_zombie(_random_spawn_point(600, 1100), false)
	# At night, horde zombies arrive one by one and head straight for you.
	if horde_left > 0:
		horde_timer -= delta
		if horde_timer <= 0.0:
			horde_timer = 1.2
			horde_left -= 1
			spawn_zombie(_random_spawn_point(550, 800), true)


func spawn_zombie(pos: Vector2, horde: bool) -> CharacterBody2D:
	var z: CharacterBody2D = ZombieScript.new()
	z.position = pos
	z.setup(day, horde)
	world_node.add_child(z)
	return z


func spawn_crate(pos: Vector2, small: bool, contents: Dictionary = {}) -> Node2D:
	var crate: Node2D = CrateScript.new()
	crate.position = cell_center(pos)
	crate.setup(rng, small)
	if not contents.is_empty():
		crate.loot = contents
	items_node.add_child(crate)
	return crate


func zombie_count() -> int:
	return get_tree().get_nodes_in_group("zombies").size()


func _random_spawn_point(min_d: float, max_d: float) -> Vector2:
	var origin := player.global_position if player else WORLD_SIZE / 2
	for i in 20:
		var p := origin + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(min_d, max_d)
		p = p.clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))
		if point_is_free(p) and (nav == null or nav.is_free(p)) and p.distance_to(origin) > min_d * 0.6:
			return p
	return (origin + Vector2(max_d, 0)).clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))


func point_is_free(p: Vector2) -> bool:
	for r in ruins:
		if r.grow(24).has_point(p):
			return false
	return true


func spawn_resource(kind: String, pos: Vector2) -> StaticBody2D:
	var node: StaticBody2D = ResourceScript.new()
	node.position = cell_center(pos)
	node.setup(kind)
	items_node.add_child(node)
	nav_dirty = true    # zombies need to walk around it
	return node


func spawn_structure(kind: String, pos: Vector2) -> StaticBody2D:
	var s: StaticBody2D = StructureScript.new()
	s.position = pos
	s.setup(kind)
	items_node.add_child(s)
	if nav != null:
		nav.add_structure(s)   # zombies need to walk around it
	return s


## Adds a solid wall (used for ruins, and by the tests).
func add_wall(rect: Rect2) -> void:
	ruins.append(rect)
	_make_wall(rect)
	queue_redraw()
	if nav != null:
		nav.build(WORLD_SIZE, ruins, self)


func floating_text(pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	var f: Node2D = FloatingTextScript.new()
	f.position = pos
	f.text = text
	f.color = color
	f.z_index = 20
	world_node.add_child(f)


# ---------------------------------------------------------------- building

## The center of the grid square that `pos` is in.
func cell_center(pos: Vector2) -> Vector2:
	return (pos / CELL).floor() * CELL + Vector2(CELL, CELL) / 2.0


## Where a structure of this kind sits when placed near `pos`, lined up with the grid
## (a 64x32 workbench covers exactly two squares, a 32x32 chest exactly one).
func snap_for(kind: String, pos: Vector2) -> Vector2:
	var size: Vector2 = StructureScript.SIZES[kind]
	var top_left := ((pos - size / 2.0) / CELL).round() * CELL
	return top_left + size / 2.0


func snap(pos: Vector2) -> Vector2:
	return (pos / 16.0).round() * 16.0


func start_placing(id: String) -> void:
	if build != null:
		build.set_active(false)
	placing = id


func cancel_placing() -> void:
	placing = ""


## Checks that a structure fits here without overlapping anything.
func can_place(kind: String, pos: Vector2) -> bool:
	var size: Vector2 = StructureScript.SIZES[kind]
	var rect := Rect2(pos - size / 2, size)
	if not Rect2(Vector2(40, 40), WORLD_SIZE - Vector2(80, 80)).encloses(rect):
		return false
	for r in ruins:
		if r.grow(4).intersects(rect):
			return false
	for s in get_tree().get_nodes_in_group("structures"):
		if s.rect().grow(4).intersects(rect):
			return false
	for n in get_tree().get_nodes_in_group("resources"):
		if rect.grow(n.radius + 2).has_point(n.global_position):
			return false
	for body in [player] + get_tree().get_nodes_in_group("zombies"):
		if rect.grow(body.radius).has_point(body.global_position):
			return false
	return true


func nearest_structure(pos: Vector2, max_dist: float, kind: String = "") -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for s in get_tree().get_nodes_in_group("structures"):
		if kind != "" and s.kind != kind:
			continue
		var d: float = s.global_position.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = s
	return best


# ---------------------------------------------------------------- build mode

## True if a build piece fits in this grid square.
## Pieces may touch each other (that is how you make walls and mazes).
func can_build(kind: String, pos: Vector2) -> bool:
	if kind == "campfire" and campfire() != null:
		return false   # only one campfire
	var rect := Rect2(pos - Vector2(16, 16), Vector2(32, 32))
	if not Rect2(Vector2(32, 32), WORLD_SIZE - Vector2(64, 64)).encloses(rect):
		return false
	var inside := rect.grow(-1.0)
	for r in ruins:
		if r.intersects(inside):
			return false
	for s in get_tree().get_nodes_in_group("structures"):
		if s.rect().intersects(inside):
			return false
	for n in get_tree().get_nodes_in_group("resources"):
		if rect.grow(n.radius - 2.0).has_point(n.global_position):
			return false
	for body in [player] + get_tree().get_nodes_in_group("zombies"):
		if rect.grow(body.radius - 2.0).has_point(body.global_position):
			return false
	return true


## Pays for and places a piece. Returns true if it was built.
func build_piece(kind: String, pos: Vector2) -> bool:
	pos = nav.cell_center(nav.to_cell(pos))
	if kind == "campfire" and campfire() != null:
		hud.show_message("You can only have one campfire (demolish it to move it)", 2.0)
		return false
	if not Buildings.is_piece(kind) or not can_build(kind, pos):
		return false
	var cost: Dictionary = Buildings.cost(kind)
	if not player.inventory.has_all(cost):
		hud.show_message("Not enough materials: %s" % _describe(cost), 1.5)
		return false
	player.inventory.remove_all(cost)
	spawn_structure(kind, pos)
	return true


## Removes what you built at this spot. Build pieces give half their cost back,
## chests and workbenches go back into your inventory. Campfires stay.
func demolish_at(pos: Vector2) -> bool:
	for s in get_tree().get_nodes_in_group("structures"):
		if not s.rect().grow(2.0).has_point(pos):
			continue
		if s.kind == "campfire":
			if is_night:
				hud.show_message("You can't move the campfire at night", 1.5)
				return false
			for id in Buildings.cost("campfire"):   # full refund, so you can move it
				player.inventory.add(id, Buildings.cost("campfire")[id])
		elif Buildings.is_piece(s.kind):
			for id in Buildings.refund(s.kind):
				player.inventory.add(id, Buildings.refund(s.kind)[id])
		elif player.inventory.add(s.kind, 1) == 0:
			hud.show_message("Inventory full", 1.5)
			return false
		if s.storage != null and not s.storage.is_empty():
			_drop_contents(s)
		s.remove_from_group("structures")
		s.queue_free()
		nav_dirty = true
		return true
	return false


## Called by a structure when zombies break it.
func on_structure_destroyed(s: Node2D) -> void:
	s.remove_from_group("structures")
	nav_dirty = true
	if s.storage != null and not s.storage.is_empty():
		_drop_contents(s)
	var name: String = Buildings.display_name(s.kind) if Buildings.is_piece(s.kind) else s.kind.capitalize()
	floating_text(s.global_position, "%s destroyed" % name, Color(1, 0.5, 0.4))


func _drop_contents(s: Node2D) -> void:
	var contents := {}
	for id in s.storage.ids():
		contents[id] = s.storage.count(id)
	spawn_crate.call_deferred(s.global_position, false, contents)


func _describe(cost: Dictionary) -> String:
	var Items = load("res://scripts/items.gd")
	return Items.describe_cost(cost)


## The closest chest, workbench or campfire (things you can press E on).
func nearest_usable(pos: Vector2, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for s in get_tree().get_nodes_in_group("structures"):
		if not s.is_usable():
			continue
		var d: float = s.global_position.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = s
	return best


## Moves up to `amount` of an item from one inventory to another. Returns how many moved.
func transfer(from_inv, to_inv, id: String, amount: int) -> int:
	var moved: int = to_inv.add(id, mini(amount, from_inv.count(id)))
	from_inv.remove(id, moved)
	return moved


# ---------------------------------------------------------------- events used by other scripts

## Gunshots and fights make noise. Zombies inside the radius come to look.
func make_noise(pos: Vector2, radius: float) -> void:
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.distance_to(pos) <= radius:
			z.hear(pos)


func on_zombie_killed(z: Node2D) -> void:
	kills += 1
	if rng.randf() < ZOMBIE_DROP_CHANCE:
		spawn_crate.call_deferred(z.global_position, true)


func nearest_crate(pos: Vector2, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for c in get_tree().get_nodes_in_group("crates"):
		if c.opened:
			continue
		var d: float = c.global_position.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = c
	return best


func _on_player_died() -> void:
	game_over = true
	lose_reason = "You died"


## The campfire, or null if you have not built one yet. There can only be one.
func campfire() -> Node2D:
	for s in get_tree().get_nodes_in_group("structures"):
		if s.kind == "campfire":
			return s
	return null


## A zombie reached the campfire: it costs a life (and the zombie).
func campfire_hit(z: Node2D) -> void:
	if game_over:
		return
	z.dead = true
	z.queue_free()
	lives -= 1
	var fire := campfire()
	if fire != null:
		floating_text(fire.global_position + Vector2(0, -26), "-1 life", Color(1, 0.4, 0.3))
	if lives <= 0:
		lives = 0
		game_over = true
		lose_reason = "The zombies overran your campfire"
	else:
		hud.show_message("A zombie reached the campfire!  %d lives left" % lives, 2.0)


# ---------------------------------------------------------------- world building

func _build_world() -> void:
	tint = CanvasModulate.new()
	tint.color = DAY_COLOR
	add_child(tint)

	var grid := GridOverlayScript.new()
	grid.game = self
	add_child(grid)

	items_node = Node2D.new()
	add_child(items_node)
	world_node = Node2D.new()
	add_child(world_node)

	# Invisible walls around the map edge.
	_make_wall(Rect2(-40, -40, WORLD_SIZE.x + 80, 40))
	_make_wall(Rect2(-40, WORLD_SIZE.y, WORLD_SIZE.x + 80, 40))
	_make_wall(Rect2(-40, 0, 40, WORLD_SIZE.y))
	_make_wall(Rect2(WORLD_SIZE.x, 0, 40, WORLD_SIZE.y))

	# Ruined buildings you can hide behind.
	var center := WORLD_SIZE / 2
	var tries := 0
	while ruins.size() < 45 and tries < 600:
		tries += 1
		# Sizes and positions are whole grid squares so everything lines up.
		var size := (Vector2(rng.randf_range(96, 256), rng.randf_range(96, 224)) / CELL).round() * CELL
		var pos := (Vector2(
			rng.randf_range(100, WORLD_SIZE.x - 100 - size.x),
			rng.randf_range(100, WORLD_SIZE.y - 100 - size.y)) / CELL).round() * CELL
		var rect := Rect2(pos, size)
		# One extra grid square of margin, since snapping can move a ruin up to half a square closer.
		if rect.grow(SAFE_RADIUS + CELL).has_point(center):
			continue
		var overlaps := false
		for r in ruins:
			if r.grow(70).intersects(rect):
				overlaps = true
				break
		if overlaps:
			continue
		ruins.append(rect)
		_make_wall(rect)

	# Little patches of dirt and grass so the ground isn't flat.
	for i in 1800:
		var p := Vector2(rng.randf() * WORLD_SIZE.x, rng.randf() * WORLD_SIZE.y)
		var s := rng.randf_range(4, 14)
		var c := Color(0.27, 0.34, 0.2) if rng.randf() < 0.6 else Color(0.3, 0.27, 0.19)
		_ground_specks.append([Rect2(p, Vector2(s, s * 0.6)), c])
	# Cracks in the asphalt.
	for i in 160:
		var along := rng.randf() * WORLD_SIZE.x
		var across := WORLD_SIZE.y / 2 + rng.randf_range(-60, 60)
		var p := Vector2(along, across) if i % 2 == 0 else Vector2(across, along)
		var line := PackedVector2Array([p])
		for k in 3:
			p += Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9))
			line.append(p)
		_road_cracks.append(line)
	queue_redraw()


func _make_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _spawn_player() -> void:
	player = PlayerScript.new()
	player.position = WORLD_SIZE / 2
	world_node.add_child(player)
	player.died.connect(_on_player_died)


func _spawn_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.game = self
	layer.add_child(hud)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 2
	add_child(ui_layer)
	ui = InventoryUiScript.new()
	ui.game = self
	ui_layer.add_child(ui)

	placement = PlacementScript.new()
	placement.game = self
	world_node.add_child(placement)

	build = BuildModeScript.new()
	build.game = self
	world_node.add_child(build)


func _spawn_resources() -> void:
	var center := WORLD_SIZE / 2
	# A few close to the start, so you can begin gathering right away.
	var near := [["tree", 240.0, 0.9], ["tree", 280.0, 2.2], ["tree", 300.0, 4.0],
		["rock", 260.0, 1.5], ["rock", 290.0, 3.4], ["scrap", 250.0, 5.2]]
	for n in near:
		spawn_resource(n[0], center + Vector2.from_angle(n[2]) * n[1])
	# The rest scattered over the map, keeping off the roads.
	var counts := {"tree": 90, "rock": 45, "scrap": 35}
	var used := {}
	for n in get_tree().get_nodes_in_group("resources"):
		used[n.position] = true
	for kind in counts:
		var placed := 0
		var tries := 0
		while placed < counts[kind] and tries < 2000:
			tries += 1
			var p := Vector2(rng.randf_range(80, WORLD_SIZE.x - 80), rng.randf_range(80, WORLD_SIZE.y - 80))
			if not point_is_free(p) or p.distance_to(center) < 350:
				continue
			if absf(p.x - center.x) < 96 or absf(p.y - center.y) < 96:
				continue
			if used.has(cell_center(p)) or not point_is_free(cell_center(p)):
				continue
			used[cell_center(p)] = true
			spawn_resource(kind, p)
			placed += 1


func _spawn_crates() -> void:
	var center := WORLD_SIZE / 2
	# A few right next to the start so you are not empty-handed.
	spawn_crate(center + Vector2(90, 40), false)
	spawn_crate(center + Vector2(-110, -60), false)
	var placed := 0
	var tries := 0
	while placed < 40 and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(80, WORLD_SIZE.x - 80), rng.randf_range(80, WORLD_SIZE.y - 80))
		if point_is_free(p) and p.distance_to(center) > 200:
			spawn_crate(p, false)
			placed += 1


func _draw() -> void:
	draw_texture_rect(TEX_GRASS, Rect2(Vector2.ZERO, WORLD_SIZE), true)
	for s in _ground_specks:
		draw_rect(s[0], Color(s[1], 0.55))
	# Two cracked roads crossing the map.
	var road := Color(0.2, 0.2, 0.21)
	var h := Rect2(0, WORLD_SIZE.y / 2 - 64, WORLD_SIZE.x, 128)
	var v := Rect2(WORLD_SIZE.x / 2 - 64, 0, 128, WORLD_SIZE.y)
	for rr in [h, v]:
		draw_rect(rr.grow(3), Color(0.25, 0.24, 0.2))    # gravel shoulder
		draw_rect(rr, road)
	var paint := Color(0.55, 0.5, 0.33, 0.6)
	for i in int(WORLD_SIZE.x / 64.0):
		var x := i * 64.0 + 12.0
		if absf(x + 16.0 - WORLD_SIZE.x / 2) > 80.0:
			draw_rect(Rect2(x, WORLD_SIZE.y / 2 - 1.5, 32, 3), paint)
		if absf(x + 16.0 - WORLD_SIZE.y / 2) > 80.0:
			draw_rect(Rect2(WORLD_SIZE.x / 2 - 1.5, x, 3, 32), paint)
	for c in _road_cracks:
		draw_polyline(c, Color(0.12, 0.12, 0.12), 1.5)
	for r in ruins:
		draw_rect(r.grow(6), Color(0.13, 0.12, 0.11))
		draw_texture_rect(TEX_RUBBLE, r, true)
		draw_rect(r.grow(-1), Color(0.24, 0.22, 0.2), false, 4.0)   # broken wall tops
		draw_rect(r.grow(-12), Color(0, 0, 0, 0.18))


# ---------------------------------------------------------------- controls
# Every action works on keyboard + mouse AND on a controller.
# Xbox and PlayStation pads use the same button numbers in Godot:
#   A = Cross, B = Circle, X = Square, Y = Triangle, LB/RB = L1/R1, LT/RT = L2/R2.

static func setup_input() -> void:
	if InputMap.has_action("move_up"):
		return   # already set up (the scene was restarted)
	_action("move_up",    0.25, [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("move_down",  0.25, [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action("move_left",  0.25, [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("move_right", 0.25, [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("aim_up",     0.25, [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action("aim_down",   0.25, [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_action("aim_left",   0.25, [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action("aim_right",  0.25, [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action("shoot",     0.5, [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("melee",     0.5, [_mouse(MOUSE_BUTTON_RIGHT), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_action("dodge",     0.5, [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_action("ability",   0.5, [_key(KEY_Q), _button(JOY_BUTTON_LEFT_SHOULDER)])
	_action("reload",    0.5, [_key(KEY_R), _button(JOY_BUTTON_Y)])
	_action("interact",  0.5, [_key(KEY_E), _button(JOY_BUTTON_X)])
	_action("eat",       0.5, [_key(KEY_F), _button(JOY_BUTTON_DPAD_UP)])
	_action("heal",      0.5, [_key(KEY_H), _button(JOY_BUTTON_DPAD_DOWN)])
	_action("inventory", 0.5, [_key(KEY_TAB), _key(KEY_I), _button(JOY_BUTTON_START)])
	_action("close_ui",  0.5, [_key(KEY_ESCAPE), _button(JOY_BUTTON_B)])
	_action("restart",   0.5, [_key(KEY_ENTER), _button(JOY_BUTTON_A)])
	_action("debug_input", 0.5, [_key(KEY_F3)])
	_action("build_mode", 0.5, [_key(KEY_B), _button(JOY_BUTTON_DPAD_RIGHT)])
	_action("demolish",   0.5, [_mouse(MOUSE_BUTTON_RIGHT), _button(JOY_BUTTON_Y)])
	_action("build_next", 0.5, [_mouse(MOUSE_BUTTON_WHEEL_DOWN), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_action("build_prev", 0.5, [_mouse(MOUSE_BUTTON_WHEEL_UP), _button(JOY_BUTTON_LEFT_SHOULDER)])
	# Let the left stick move around menus too (the D-pad already does).
	InputMap.action_add_event("ui_up", _axis(JOY_AXIS_LEFT_Y, -1.0))
	InputMap.action_add_event("ui_down", _axis(JOY_AXIS_LEFT_Y, 1.0))
	InputMap.action_add_event("ui_left", _axis(JOY_AXIS_LEFT_X, -1.0))
	InputMap.action_add_event("ui_right", _axis(JOY_AXIS_LEFT_X, 1.0))


static func _action(action: String, deadzone: float, events: Array) -> void:
	InputMap.add_action(action, deadzone)
	for ev in events:
		InputMap.action_add_event(action, ev)


static func _key(key: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	return ev


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	return ev


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = -1          # any controller
	ev.button_index = button
	return ev


static func _axis(axis: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis
	ev.axis_value = direction
	return ev
