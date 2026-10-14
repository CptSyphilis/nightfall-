extends Node2D
## Main game scene.
## Builds the map, runs the day/night cycle and spawns zombies.
## Everything is created from code, so there is only one tiny .tscn file.

const WORLD_SIZE := Vector2(3200, 3200)
const DAY_LENGTH := 90.0     # seconds of daylight
const NIGHT_LENGTH := 60.0   # seconds of night (horde time)
const SAFE_RADIUS := 320.0   # nothing spawns this close to the start point

const PlayerScript := preload("res://scripts/player.gd")
const ZombieScript := preload("res://scripts/zombie.gd")
const CrateScript := preload("res://scripts/loot_crate.gd")
const HudScript := preload("res://scripts/hud.gd")
const ResourceScript := preload("res://scripts/resource_node.gd")
const StructureScript := preload("res://scripts/structure.gd")
const InventoryUiScript := preload("res://scripts/inventory_ui.gd")
const PlacementScript := preload("res://scripts/placement.gd")
const FloatingTextScript := preload("res://scripts/floating_text.gd")

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
var spawning_enabled := true
var trickle_timer := 0.0
var horde_left := 0
var horde_timer := 0.0

var ruins: Array[Rect2] = []
var rng := RandomNumberGenerator.new()
var _ground_specks: Array = []


func _ready() -> void:
	add_to_group("game")
	setup_input()
	rng.randomize()
	_build_world()
	_spawn_player()
	_spawn_hud()
	_spawn_crates()
	_spawn_resources()
	for i in 12:
		spawn_zombie(_random_spawn_point(500, 1300), false)
	hud.show_message("Day 1 - gather wood and stone, press Tab to craft", 5.0)


func _physics_process(delta: float) -> void:
	if game_over:
		return
	phase_time += delta
	if not is_night and phase_time >= DAY_LENGTH:
		start_night()
	elif is_night and phase_time >= NIGHT_LENGTH:
		start_day()
	_update_tint()
	if spawning_enabled:
		_update_spawning(delta)


func _unhandled_input(event: InputEvent) -> void:
	if game_over and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


# ---------------------------------------------------------------- day / night

func start_night() -> void:
	is_night = true
	phase_time = 0.0
	horde_left = 4 + day * 4
	horde_timer = 3.0
	hud.show_message("Night %d - the horde is coming" % day)


func start_day() -> void:
	is_night = false
	phase_time = 0.0
	day += 1
	horde_left = 0
	for z in get_tree().get_nodes_in_group("zombies"):
		z.is_horde = false
	hud.show_message("Day %d - you survived the night" % day)


func time_left() -> float:
	return (NIGHT_LENGTH if is_night else DAY_LENGTH) - phase_time


func _update_tint() -> void:
	# 0 = full daylight, 1 = full night. Fades over the last few seconds.
	var t := 0.0
	if is_night:
		t = clampf((NIGHT_LENGTH - phase_time) / 8.0, 0.0, 1.0)
	else:
		t = clampf((phase_time - (DAY_LENGTH - 10.0)) / 10.0, 0.0, 1.0)
	night_amount = t
	tint.color = DAY_COLOR.lerp(NIGHT_COLOR, t)


# ---------------------------------------------------------------- spawning

func _update_spawning(delta: float) -> void:
	# A slow trickle of wanderers all the time.
	trickle_timer -= delta
	if trickle_timer <= 0.0:
		trickle_timer = 2.5 if is_night else 4.0
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


func spawn_crate(pos: Vector2, small: bool) -> Node2D:
	var crate: Node2D = CrateScript.new()
	crate.position = pos
	crate.setup(rng, small)
	items_node.add_child(crate)
	return crate


func zombie_count() -> int:
	return get_tree().get_nodes_in_group("zombies").size()


func _random_spawn_point(min_d: float, max_d: float) -> Vector2:
	var origin := player.global_position if player else WORLD_SIZE / 2
	for i in 20:
		var p := origin + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(min_d, max_d)
		p = p.clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))
		if point_is_free(p) and p.distance_to(origin) > min_d * 0.6:
			return p
	return (origin + Vector2(max_d, 0)).clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))


func point_is_free(p: Vector2) -> bool:
	for r in ruins:
		if r.grow(24).has_point(p):
			return false
	return true


func spawn_resource(kind: String, pos: Vector2) -> StaticBody2D:
	var node: StaticBody2D = ResourceScript.new()
	node.position = pos
	node.setup(kind)
	items_node.add_child(node)
	return node


func spawn_structure(kind: String, pos: Vector2) -> StaticBody2D:
	var s: StaticBody2D = StructureScript.new()
	s.position = pos
	s.setup(kind)
	items_node.add_child(s)
	return s


func floating_text(pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	var f: Node2D = FloatingTextScript.new()
	f.position = pos
	f.text = text
	f.color = color
	f.z_index = 20
	world_node.add_child(f)


# ---------------------------------------------------------------- building

func snap(pos: Vector2) -> Vector2:
	return (pos / 16.0).round() * 16.0


func start_placing(id: String) -> void:
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
	if rng.randf() < 0.2:
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


# ---------------------------------------------------------------- world building

func _build_world() -> void:
	tint = CanvasModulate.new()
	tint.color = DAY_COLOR
	add_child(tint)

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
		var size := Vector2(rng.randf_range(80, 260), rng.randf_range(80, 220))
		var pos := Vector2(
			rng.randf_range(100, WORLD_SIZE.x - 100 - size.x),
			rng.randf_range(100, WORLD_SIZE.y - 100 - size.y))
		var rect := Rect2(pos, size)
		if rect.grow(SAFE_RADIUS).has_point(center):
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


func _spawn_resources() -> void:
	var center := WORLD_SIZE / 2
	# A few close to the start, so you can begin gathering right away.
	var near := [["tree", 240.0, 0.9], ["tree", 280.0, 2.2], ["tree", 300.0, 4.0],
		["rock", 260.0, 1.5], ["rock", 290.0, 3.4], ["scrap", 250.0, 5.2]]
	for n in near:
		spawn_resource(n[0], center + Vector2.from_angle(n[2]) * n[1])
	# The rest scattered over the map, keeping off the roads.
	var counts := {"tree": 90, "rock": 45, "scrap": 35}
	for kind in counts:
		var placed := 0
		var tries := 0
		while placed < counts[kind] and tries < 2000:
			tries += 1
			var p := Vector2(rng.randf_range(80, WORLD_SIZE.x - 80), rng.randf_range(80, WORLD_SIZE.y - 80))
			if not point_is_free(p) or p.distance_to(center) < 350:
				continue
			if absf(p.x - center.x) < 90 or absf(p.y - center.y) < 90:
				continue
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
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color(0.23, 0.3, 0.18))
	# Two cracked roads crossing the map.
	draw_rect(Rect2(0, WORLD_SIZE.y / 2 - 60, WORLD_SIZE.x, 120), Color(0.22, 0.22, 0.22))
	draw_rect(Rect2(WORLD_SIZE.x / 2 - 60, 0, 120, WORLD_SIZE.y), Color(0.22, 0.22, 0.22))
	for s in _ground_specks:
		draw_rect(s[0], s[1])
	for r in ruins:
		draw_rect(r.grow(6), Color(0.17, 0.16, 0.15))
		draw_rect(r, Color(0.37, 0.34, 0.31))
		draw_rect(r.grow(-12), Color(0.3, 0.27, 0.25))


# ---------------------------------------------------------------- controls

static func setup_input() -> void:
	_add_key("move_up", KEY_W)
	_add_key("move_down", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("dodge", KEY_SPACE)
	_add_key("ability", KEY_Q)
	_add_key("reload", KEY_R)
	_add_key("interact", KEY_E)
	_add_key("eat", KEY_F)
	_add_key("restart", KEY_ENTER)
	_add_key("heal", KEY_H)
	if not InputMap.has_action("inventory"):
		_add_key("inventory", KEY_TAB)
		InputMap.action_add_event("inventory", _key_event(KEY_I))
	_add_key("close_ui", KEY_ESCAPE)
	_add_mouse("shoot", MOUSE_BUTTON_LEFT)
	_add_mouse("melee", MOUSE_BUTTON_RIGHT)


static func _add_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	InputMap.action_add_event(action, _key_event(key))


static func _key_event(key: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	return ev


static func _add_mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
