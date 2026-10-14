extends CharacterBody2D
## A zombie.
## wander      - shuffles around slowly
## investigate - walks to a noise it heard
## chase       - saw you, comes straight for you
## Horde zombies (spawned at night) always chase.

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
var dead := false

var game: Node
var player: Node2D
var _rng := RandomNumberGenerator.new()
var _color := Color(0.45, 0.55, 0.38)


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
	collision_mask = 1 | 2 | 4
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
	_color = Color(0.45, 0.55, 0.38).lerp(Color(0.55, 0.47, 0.36), _rng.randf())
	if is_horde:
		_color = _color.darkened(0.25)
		state = "chase"


func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_cd = maxf(attack_cd - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)

	var player_alive: bool = is_instance_valid(player) and not player.dead
	var dist := INF
	if player_alive:
		dist = global_position.distance_to(player.global_position)
		var view := sight * (1.5 if game != null and game.is_night else 1.0)
		if is_horde or dist < view:
			state = "chase"
		elif state == "chase" and dist > view * 1.8:
			hear(player.global_position)   # lost sight, go to last known spot
	elif state == "chase":
		state = "wander"

	var dir := Vector2.ZERO
	var move_speed := speed
	match state:
		"chase":
			dir = global_position.direction_to(player.global_position)
		"investigate":
			investigate_timer -= delta
			dir = global_position.direction_to(target_pos)
			if global_position.distance_to(target_pos) < 20.0 or investigate_timer <= 0.0:
				state = "wander"
		"wander":
			move_speed = speed * 0.35
			wander_timer -= delta
			if wander_timer <= 0.0:
				wander_timer = _rng.randf_range(2.0, 5.0)
				target_pos = global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(40.0, 160.0)
			if global_position.distance_to(target_pos) > 8.0:
				dir = global_position.direction_to(target_pos)

	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 1400.0 * delta)
	move_and_slide()

	if player_alive and dist < radius + player.radius + 10.0 and attack_cd <= 0.0:
		attack_cd = 1.0
		player.take_damage(damage)
	queue_redraw()


## Something made noise at pos. Go look unless already chasing.
func hear(pos: Vector2) -> void:
	if state == "chase" and not (is_instance_valid(player) and player.dead):
		if global_position.distance_to(player.global_position) < sight:
			return
	state = "investigate"
	target_pos = pos
	investigate_timer = 8.0


func take_damage(amount: float, push: Vector2 = Vector2.ZERO) -> void:
	if dead:
		return
	health -= amount
	knockback += push
	hurt_flash = 0.12
	if is_instance_valid(player) and not player.dead:
		state = "chase"
	if health <= 0.0:
		die()


func die() -> void:
	dead = true
	if game != null:
		game.on_zombie_killed(self)
	queue_free()


func _draw() -> void:
	var c := Color(1, 1, 1) if hurt_flash > 0.0 else _color
	var facing := velocity.normalized() if velocity.length() > 5.0 else Vector2.DOWN
	var side := facing.orthogonal()
	# Arms reaching forward.
	for s in [side, -side]:
		var a: Vector2 = s * 9.0
		var b: Vector2 = s * 7.0 + facing * 22.0
		draw_line(a, b, Color(0.08, 0.1, 0.06), 7.0)
		draw_line(a, b, c.lightened(0.1), 4.0)
	draw_circle(Vector2.ZERO, radius + 2.0, Color(0.08, 0.1, 0.06))
	draw_circle(Vector2.ZERO, radius, c)
	if health < max_health:
		var w := 26.0
		draw_rect(Rect2(-w / 2, -radius - 10, w, 4), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(-w / 2, -radius - 10, w * health / max_health, 4), Color(0.8, 0.2, 0.2))
