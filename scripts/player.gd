extends CharacterBody2D
## The survivor you control.
## WASD move, mouse aims, left click shoots, right click swings,
## Space dodges (you are invulnerable while rolling), Q is a shockwave.

signal died

const SPEED := 210.0
const DODGE_SPEED := 620.0
const DODGE_TIME := 0.22
const DODGE_COOLDOWN := 1.0
const MELEE_COOLDOWN := 0.45
const MELEE_RANGE := 70.0
const MELEE_ARC := 1.2          # radians to each side of the aim direction
const MELEE_DAMAGE := 35.0
const MELEE_NOISE := 160.0
const SHOOT_COOLDOWN := 0.18
const GUN_NOISE := 650.0
const MAG_SIZE := 12
const RELOAD_TIME := 1.4
const SHOCK_COOLDOWN := 8.0
const SHOCK_RADIUS := 160.0
const SHOCK_DAMAGE := 50.0
const HUNGER_DRAIN := 0.35      # per second, 100 = full
const STARVE_DAMAGE := 3.0      # per second when hunger is 0
const REGEN := 0.6              # health per second when well fed

const BulletScript := preload("res://scripts/bullet.gd")

var radius := 14.0
var max_health := 100.0
var health := 100.0
var hunger := 100.0
var ammo_in_mag := MAG_SIZE
var ammo_reserve := 24
var food := 1

var aim_dir := Vector2.RIGHT
var dodge_dir := Vector2.ZERO
var dodge_timer := 0.0
var dodge_cd := 0.0
var melee_cd := 0.0
var shoot_cd := 0.0
var reload_timer := 0.0
var shock_cd := 0.0

# Short timers used only for drawing effects.
var swing_flash := 0.0
var shock_flash := 0.0
var muzzle_flash := 0.0
var hurt_flash := 0.0

var dead := false
var controls_enabled := true
var use_mouse_aim := true
var game: Node
var light: PointLight2D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	game = get_tree().get_first_node_in_group("game")
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(game.WORLD_SIZE.x)
	cam.limit_bottom = int(game.WORLD_SIZE.y)
	add_child(cam)

	# A soft light around you that fades in at night.
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
	light.texture_scale = 2.4
	light.color = Color(1.0, 0.9, 0.7)
	light.energy = 0.0
	add_child(light)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_tick_timers(delta)
	_tick_survival(delta)
	light.energy = game.night_amount * 0.9

	var move := Vector2.ZERO
	if controls_enabled:
		move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if use_mouse_aim:
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length() > 1.0:
			aim_dir = to_mouse.normalized()

	if dodge_timer > 0.0:
		velocity = dodge_dir * DODGE_SPEED
	else:
		velocity = move * SPEED
	move_and_slide()

	if controls_enabled:
		if Input.is_action_pressed("shoot"):
			shoot()
		if Input.is_action_pressed("melee"):
			melee()
		if Input.is_action_just_pressed("dodge"):
			dodge(move)
		if Input.is_action_just_pressed("ability"):
			shockwave()
		if Input.is_action_just_pressed("reload"):
			start_reload()
		if Input.is_action_just_pressed("interact"):
			interact()
		if Input.is_action_just_pressed("eat"):
			eat()
	queue_redraw()


func _tick_timers(delta: float) -> void:
	dodge_cd = maxf(dodge_cd - delta, 0.0)
	melee_cd = maxf(melee_cd - delta, 0.0)
	shoot_cd = maxf(shoot_cd - delta, 0.0)
	shock_cd = maxf(shock_cd - delta, 0.0)
	swing_flash = maxf(swing_flash - delta, 0.0)
	shock_flash = maxf(shock_flash - delta, 0.0)
	muzzle_flash = maxf(muzzle_flash - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	if dodge_timer > 0.0:
		dodge_timer -= delta
		if dodge_timer <= 0.0:
			dodge_timer = 0.0
			collision_mask = 1 | 4   # bump into zombies again
	if reload_timer > 0.0:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reload_timer = 0.0
			_finish_reload()


func _tick_survival(delta: float) -> void:
	hunger = maxf(hunger - HUNGER_DRAIN * delta, 0.0)
	if hunger <= 0.0:
		take_damage(STARVE_DAMAGE * delta, false)
	elif hunger > 60.0 and health < max_health:
		health = minf(health + REGEN * delta, max_health)


# ---------------------------------------------------------------- actions

func shoot() -> bool:
	if dead or shoot_cd > 0.0 or reload_timer > 0.0:
		return false
	if ammo_in_mag <= 0:
		start_reload()
		return false
	ammo_in_mag -= 1
	shoot_cd = SHOOT_COOLDOWN
	muzzle_flash = 0.06
	var b: Node2D = BulletScript.new()
	b.position = global_position + aim_dir * (radius + 8.0)
	b.direction = aim_dir
	game.world_node.add_child(b)
	game.make_noise(global_position, GUN_NOISE)
	return true


func start_reload() -> bool:
	if reload_timer > 0.0 or ammo_in_mag >= MAG_SIZE or ammo_reserve <= 0:
		return false
	reload_timer = RELOAD_TIME
	return true


func _finish_reload() -> void:
	var taken := mini(MAG_SIZE - ammo_in_mag, ammo_reserve)
	ammo_in_mag += taken
	ammo_reserve -= taken


## Swing in an arc in front of you. Returns true if anything was hit.
func melee() -> bool:
	if dead or melee_cd > 0.0:
		return false
	melee_cd = MELEE_COOLDOWN
	swing_flash = 0.15
	var hits := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead:
			continue
		var to: Vector2 = z.global_position - global_position
		if to.length() > MELEE_RANGE + z.radius:
			continue
		if absf(aim_dir.angle_to(to)) > MELEE_ARC:
			continue
		z.take_damage(MELEE_DAMAGE, to.normalized() * 380.0)
		hits += 1
	game.make_noise(global_position, MELEE_NOISE)
	return hits > 0


## Quick roll. You pass through zombies and take no damage while rolling.
func dodge(dir: Vector2) -> bool:
	if dead or dodge_cd > 0.0:
		return false
	if dir == Vector2.ZERO:
		dir = aim_dir
	dodge_dir = dir.normalized()
	dodge_timer = DODGE_TIME
	dodge_cd = DODGE_COOLDOWN
	collision_mask = 1   # walls only
	return true


## Knock back and damage every zombie close to you.
func shockwave() -> bool:
	if dead or shock_cd > 0.0:
		return false
	shock_cd = SHOCK_COOLDOWN
	shock_flash = 0.3
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead:
			continue
		var to: Vector2 = z.global_position - global_position
		if to.length() <= SHOCK_RADIUS + z.radius:
			z.take_damage(SHOCK_DAMAGE, to.normalized() * 650.0)
	game.make_noise(global_position, 300.0)
	return true


func eat() -> bool:
	if dead or food <= 0 or hunger >= 95.0:
		return false
	food -= 1
	hunger = minf(hunger + 45.0, 100.0)
	return true


## Search the nearest crate within reach.
func interact() -> bool:
	if dead:
		return false
	var crate: Node2D = game.nearest_crate(global_position, 48.0)
	if crate == null:
		return false
	var loot: Dictionary = crate.open()
	if loot.is_empty():
		return false
	ammo_reserve += loot.ammo
	food += loot.food
	health = minf(health + loot.medkit * 30.0, max_health)
	var parts: Array[String] = []
	if loot.ammo > 0:
		parts.append("%d ammo" % loot.ammo)
	if loot.food > 0:
		parts.append("%d food" % loot.food)
	if loot.medkit > 0:
		parts.append("a medkit")
	game.hud.show_message("Found " + ", ".join(parts), 2.0)
	return true


func take_damage(amount: float, flash: bool = true) -> void:
	if dead or dodge_timer > 0.0:
		return
	health -= amount
	if flash:
		hurt_flash = 0.2
	if health <= 0.0:
		health = 0.0
		dead = true
		queue_redraw()
		died.emit()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var body := Color(0.3, 0.55, 0.85)
	if hurt_flash > 0.0:
		body = Color(1, 0.4, 0.4)
	if dead:
		body = Color(0.3, 0.3, 0.3)
	if dodge_timer > 0.0:
		draw_circle(-dodge_dir * 16.0, radius, Color(body, 0.3))
	draw_circle(Vector2.ZERO, radius + 2.0, Color(0.08, 0.08, 0.1))
	draw_circle(Vector2.ZERO, radius, body)
	draw_line(aim_dir * 6.0, aim_dir * (radius + 12.0), Color(0.12, 0.12, 0.12), 5.0)
	if muzzle_flash > 0.0:
		draw_circle(aim_dir * (radius + 16.0), 6.0, Color(1, 0.85, 0.4))
	if swing_flash > 0.0:
		var a := aim_dir.angle()
		draw_arc(Vector2.ZERO, MELEE_RANGE * 0.8, a - MELEE_ARC, a + MELEE_ARC, 16, Color(1, 1, 1, 0.7), 4.0)
	if shock_flash > 0.0:
		var k := shock_flash / 0.3
		draw_arc(Vector2.ZERO, SHOCK_RADIUS * (1.0 - k), 0.0, TAU, 40, Color(0.6, 0.8, 1.0, k), 6.0)
