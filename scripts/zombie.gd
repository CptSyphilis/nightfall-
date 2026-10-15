extends CharacterBody2D
## A zombie. Only comes out at night.
##
## What it does (state):
##   wander      - shuffles around slowly
##   investigate - walks to a noise it heard (noise goes through walls)
##   chase       - saw you, comes for you (sight is blocked by walls)
##   siege       - horde zombie heading for your campfire (Maul style).
##                 Reaching it costs you a life, and the zombie is gone.
## Horde zombies go for the campfire, but turn on you if you get close.
## With no campfire they always know where you are and chase you.
##
## How it moves:
##   If nothing is in the way, it walks straight at its goal.
##   Otherwise it asks the navigation grid (nav_grid.gd) for a path around
##   buildings, trees, rocks and anything you built, and follows it.
##   It also keeps a little distance from other zombies, and if it stops
##   making progress it re-plans and steps sideways.
##   If there is NO open way to you (you walled yourself in), it walks up to
##   the nearest wall and smashes it. While any route is open it follows the
##   route instead, which is what makes maze building work.

const SIGHT_CHECK_TIME := 0.2    # how often it looks for you
const LINE_CHECK_TIME := 0.15    # how often it checks if the way ahead is clear
const STUCK_CHECK_TIME := 0.8

# Sprites face right (+X); the sprite turns to the walking direction.
const TEX_WALKERS := [
	preload("res://assets/zombie_1.svg"),
	preload("res://assets/zombie_2.svg"),
	preload("res://assets/zombie_3.svg"),
]
const TEX_HORDE := preload("res://assets/zombie_horde.svg")

var radius := 13.0
var max_health := 80.0
var health := 80.0
var speed := 70.0
var damage := 10.0
var sight := 240.0
var is_horde := false

var state := "wander"
var target_pos := Vector2.ZERO
var wander_timer := 0.0
var investigate_timer := 0.0
var attack_cd := 0.0
var knockback := Vector2.ZERO
var hurt_flash := 0.0
var slow_timer := 0.0        # set by spike traps: half speed while > 0
var dead := false

var game: Node
var player: Node2D
var _rng := RandomNumberGenerator.new()
var _color := Color(0.45, 0.55, 0.38)
var sprite: Sprite2D
var _facing := Vector2.DOWN

# Seeing the player
var _sight_timer := 0.0
var _sees_player := false
var _unseen_time := 0.0

# Path following
var _path := PackedVector2Array()
var _path_i := 0
var _path_goal := Vector2.INF
var _repath_timer := 0.0
var _line_timer := 0.0
var _goal_in_view := false
var _path_blocked := false     # true when no route reaches the goal: time to break walls

# Getting unstuck
var _stuck_timer := 0.0
var _stuck_check_pos := Vector2.ZERO
var _sidestep := Vector2.ZERO
var _sidestep_timer := 0.0


## Called before the zombie is added to the world. Later days = tougher zombies.
func setup(day: int, horde: bool) -> void:
	is_horde = horde
	max_health = 60.0 + day * 12.0
	health = max_health
	speed = 55.0 + day * 4.0 + (35.0 if horde else 0.0)
	damage = 8.0 + day * 2.0


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 16   # 16 = doors (the player walks through them, zombies don't)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	_rng.randomize()
	game = get_tree().get_first_node_in_group("game")
	player = get_tree().get_first_node_in_group("player")
	target_pos = global_position
	_stuck_check_pos = global_position
	# Spread out the timers so all zombies don't think on the same frame.
	_sight_timer = _rng.randf() * SIGHT_CHECK_TIME
	_line_timer = _rng.randf() * LINE_CHECK_TIME
	_color = Color(0.45, 0.55, 0.38).lerp(Color(0.55, 0.47, 0.36), _rng.randf())
	if is_horde:
		_color = _color.darkened(0.25)
		state = "chase"
	sprite = Sprite2D.new()
	sprite.texture = TEX_HORDE if is_horde else TEX_WALKERS[_rng.randi_range(0, TEX_WALKERS.size() - 1)]
	sprite.offset = Vector2(2, 0)    # the sprite's body centre sits 2 px left of the texture centre
	sprite.show_behind_parent = true
	# A little variety in skin and cloth tone.
	var shade := _rng.randf_range(0.88, 1.05)
	sprite.self_modulate = Color(shade, shade, shade)
	sprite.rotation = _facing.angle()
	add_child(sprite)


func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_cd = maxf(attack_cd - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	slow_timer = maxf(slow_timer - delta, 0.0)

	var player_alive: bool = is_instance_valid(player) and not player.dead
	var dist := INF
	if player_alive:
		dist = global_position.distance_to(player.global_position)
		_update_sight(delta, dist)
	elif state == "chase":
		state = "wander"

	# Decide where to go.
	var goal := global_position
	var has_goal := false
	var move_speed := speed
	match state:
		"chase":
			goal = player.global_position
			has_goal = true
		"siege":
			var fire: Node2D = game.campfire() if game != null else null
			if fire == null:
				state = "chase" if player_alive else "wander"
			else:
				goal = fire.global_position
				has_goal = true
				if global_position.distance_to(goal) < 16.0 + radius + 14.0:
					game.campfire_hit(self)
					return
		"investigate":
			investigate_timer -= delta
			goal = target_pos
			has_goal = true
			if global_position.distance_to(target_pos) < 24.0 or investigate_timer <= 0.0:
				state = "wander"
		"wander":
			move_speed = speed * 0.35
			wander_timer -= delta
			if wander_timer <= 0.0:
				_pick_wander_target()
			if global_position.distance_to(target_pos) > 8.0:
				goal = target_pos
				has_goal = true

	# Work out the direction to walk.
	var dir := Vector2.ZERO
	if has_goal:
		dir = _steer_towards(goal, delta)
	dir += _separation() * 0.7
	if _sidestep_timer > 0.0:
		_sidestep_timer -= delta
		dir += _sidestep
	if dir.length() > 1.0:
		dir = dir.normalized()

	if slow_timer > 0.0:
		move_speed *= 0.5
	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 1400.0 * delta)
	move_and_slide()
	_check_stuck(delta, has_goal)
	# Walled off: follow the route as far as it goes (through any maze),
	# and only start smashing once there is nowhere further to walk.
	if has_goal and _path_blocked and _path_i >= _path.size() - 1:
		_smash_what_is_in_the_way()

	if player_alive and dist < radius + player.radius + 10.0 and attack_cd <= 0.0:
		attack_cd = 1.0
		player.take_damage(damage)
	queue_redraw()


# ---------------------------------------------------------------- senses

func _update_sight(delta: float, dist: float) -> void:
	var view := sight * (1.5 if game != null and game.is_night else 1.0)
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = SIGHT_CHECK_TIME
		_sees_player = dist < view and clear_line(global_position, player.global_position, false)
	var fire: Node2D = game.campfire() if game != null else null
	if is_horde and fire != null and not (_sees_player and dist < 140.0):
		state = "siege"
		_unseen_time = 0.0
	elif is_horde or _sees_player:
		state = "chase"
		_unseen_time = 0.0
	elif state == "chase":
		# Lost you behind a wall or too far away: go to where you were last seen.
		_unseen_time += delta
		if _unseen_time > 2.5 or dist > view * 1.8:
			hear(player.global_position)


## Something made noise at pos. Go look, unless already chasing a visible player.
func hear(pos: Vector2) -> void:
	if state == "siege" or (state == "chase" and (is_horde or _sees_player)):
		return
	state = "investigate"
	target_pos = pos
	investigate_timer = 10.0
	_path.clear()


## True if nothing solid (walls, trees, rocks, buildings) is between a and b.
## wide = also check two side lines a zombie's width apart, so a "clear" line
## really means the zombie's body fits through.
func clear_line(a: Vector2, b: Vector2, wide: bool = true) -> bool:
	var space := get_world_2d().direct_space_state
	var offsets := [Vector2.ZERO]
	if wide:
		var side := (b - a).normalized().orthogonal() * (radius - 2.0)
		offsets = [Vector2.ZERO, side, -side]
	for off in offsets:
		var q := PhysicsRayQueryParameters2D.create(a + off, b + off, 1)
		if not space.intersect_ray(q).is_empty():
			return false
	return true


# ---------------------------------------------------------------- movement

## Returns the direction to walk to reach `goal`, going around obstacles.
func _steer_towards(goal: Vector2, delta: float) -> Vector2:
	_line_timer -= delta
	if _line_timer <= 0.0:
		_line_timer = LINE_CHECK_TIME
		_goal_in_view = clear_line(global_position, goal)
		# Cut corners: if the waypoint after next is already reachable, skip ahead.
		if not _goal_in_view and _path_i + 1 < _path.size() and clear_line(global_position, _path[_path_i + 1]):
			_path_i += 1

	if _goal_in_view or game == null or game.nav == null:
		_path.clear()
		_path_blocked = false
		return global_position.direction_to(goal)

	_repath_timer -= delta
	if _path.is_empty() or _repath_timer <= 0.0 or goal.distance_to(_path_goal) > 48.0:
		_repath(goal)

	while _path_i < _path.size() and global_position.distance_to(_path[_path_i]) < 14.0:
		_path_i += 1
	if _path_i < _path.size():
		return global_position.direction_to(_path[_path_i])
	return global_position.direction_to(goal)


func _repath(goal: Vector2) -> void:
	_path = game.nav.find_path(global_position, goal)
	_path_i = 1 if _path.size() > 1 else 0    # point 0 is the square we stand on
	_path_goal = goal
	_repath_timer = _rng.randf_range(0.5, 0.9)
	# The path ends as close as it can get. If that is still far from the goal,
	# the way is walled off.
	_path_blocked = _path.is_empty() or _path[_path.size() - 1].distance_to(goal) > 48.0


## Hit whatever built thing we are pressed against (only used when walled off).
func _smash_what_is_in_the_way() -> void:
	if attack_cd > 0.0:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i).get_collider()
		if c != null and c.is_in_group("structures") and c.breakable:
			attack_cd = 1.0
			c.take_damage(damage * 1.5)
			return


## A small push away from zombies that are too close, so crowds don't jam.
func _separation() -> Vector2:
	var push := Vector2.ZERO
	var reach := radius * 2.5
	for z in get_tree().get_nodes_in_group("zombies"):
		if z == self or z.dead:
			continue
		var d: Vector2 = global_position - z.global_position
		var l := d.length()
		if l > 0.01 and l < reach:
			push += d / l * (1.0 - l / reach)
	return push


## If it has barely moved for a while, plan a new path and step sideways.
func _check_stuck(delta: float, trying_to_move: bool) -> void:
	_stuck_timer += delta
	if _stuck_timer < STUCK_CHECK_TIME:
		return
	_stuck_timer = 0.0
	var moved := global_position.distance_to(_stuck_check_pos)
	_stuck_check_pos = global_position
	if trying_to_move and moved < 10.0:
		_repath_timer = 0.0
		_line_timer = 0.0
		var side := velocity.orthogonal().normalized() if velocity.length() > 1.0 else Vector2.from_angle(_rng.randf() * TAU)
		_sidestep = side * (1.0 if _rng.randf() < 0.5 else -1.0)
		_sidestep_timer = 0.4
		if state == "wander":
			wander_timer = 0.0   # pick somewhere else to shuffle to


func _pick_wander_target() -> void:
	wander_timer = _rng.randf_range(2.0, 5.0)
	for i in 6:
		var t := global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(40.0, 160.0)
		if game == null or game.nav == null or game.nav.is_free(t):
			target_pos = t
			return
	target_pos = global_position


# ---------------------------------------------------------------- damage

func take_damage(amount: float, push: Vector2 = Vector2.ZERO) -> void:
	if dead:
		return
	health -= amount
	knockback += push
	hurt_flash = 0.12
	if is_instance_valid(player) and not player.dead:
		state = "chase"
		_unseen_time = 0.0
	if health <= 0.0:
		die()


func die() -> void:
	dead = true
	if game != null:
		game.on_zombie_killed(self)
	queue_free()


func _draw() -> void:
	if velocity.length() > 5.0:
		# Turn smoothly, so knockback and sidesteps don't make the sprite twitch.
		_facing = _facing.slerp(velocity.normalized(), 0.25).normalized()
	if sprite != null:
		sprite.rotation = _facing.angle()
		sprite.modulate = Color(2.2, 2.2, 2.2) if hurt_flash > 0.0 else Color(1, 1, 1)
	if health < max_health:
		var w := 26.0
		draw_rect(Rect2(-w / 2, -radius - 10, w, 4), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(-w / 2, -radius - 10, w * health / max_health, 4), Color(0.8, 0.2, 0.2))
