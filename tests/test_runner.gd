extends SceneTree
## Headless test suite. Run from the project folder with:
##   godot --headless --path . -s res://tests/test_runner.gd
## Exit code 0 = all passed, 1 = something failed.

var passed := 0
var failed := 0
var game: Node
var p: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, name: String) -> void:
	if ok:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func clear_zombies() -> void:
	for z in get_nodes_in_group("zombies"):
		z.queue_free()
	await frames(2)


func reset_player() -> void:
	p.health = p.max_health
	p.hunger = 100.0
	p.dead = false
	p.position = game.WORLD_SIZE / 2
	p.aim_dir = Vector2.RIGHT
	p.dodge_timer = 0.0
	p.dodge_cd = 0.0
	p.melee_cd = 0.0
	p.shoot_cd = 0.0
	p.shock_cd = 0.0
	p.reload_timer = 0.0
	p.ammo_in_mag = p.MAG_SIZE
	p.ammo_reserve = 24
	p.collision_mask = 1 | 4


func _run() -> void:
	print("Running Nightfall Holdout tests")
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await frames(2)

	# --- world setup
	p = game.player
	check(p != null, "player exists")
	check(game.ruins.size() > 10, "ruins were generated (%d)" % game.ruins.size())
	check(get_nodes_in_group("crates").size() >= 30, "crates were placed")
	check(game.zombie_count() >= 10, "starting zombies spawned")
	var actions := ["move_up", "move_down", "move_left", "move_right", "shoot", "melee", "dodge", "ability", "reload", "interact", "eat", "restart"]
	var all_actions := true
	for a in actions:
		all_actions = all_actions and InputMap.has_action(a)
	check(all_actions, "all input actions registered")

	game.spawning_enabled = false
	p.controls_enabled = false
	p.use_mouse_aim = false
	await clear_zombies()
	# Remove crates near the start so they don't interfere with later checks.
	for c in get_nodes_in_group("crates"):
		if c.global_position.distance_to(game.WORLD_SIZE / 2) < 150:
			c.queue_free()
	await frames(1)

	# --- shooting
	reset_player()
	var z = game.spawn_zombie(p.position + Vector2(150, 0), false)
	await frames(1)
	var hp0: float = z.health
	check(p.shoot(), "shoot works with a loaded gun")
	check(p.ammo_in_mag == p.MAG_SIZE - 1, "shooting uses one bullet")
	await frames(10)
	check(not is_instance_valid(z) or z.health < hp0, "bullet hits the zombie")
	await clear_zombies()

	# --- melee kill
	reset_player()
	var kills0: int = game.kills
	z = game.spawn_zombie(p.position + Vector2(40, 0), false)
	await frames(1)
	for i in 4:
		if is_instance_valid(z):
			p.melee_cd = 0.0
			p.melee()
		await frames(1)
	check(not is_instance_valid(z), "melee swings kill a zombie")
	check(game.kills == kills0 + 1, "kill counter goes up")
	await clear_zombies()

	# --- melee misses behind you
	reset_player()
	z = game.spawn_zombie(p.position + Vector2(-40, 0), false)
	await frames(1)
	check(not p.melee(), "melee does not hit zombies behind you")
	await clear_zombies()

	# --- dodge invulnerability
	reset_player()
	p.dodge(Vector2.LEFT)
	p.take_damage(20)
	check(p.health == p.max_health, "no damage while dodging")
	await frames(20)
	p.take_damage(20)
	check(p.health == p.max_health - 20, "damage applies after the dodge ends")

	# --- reload
	reset_player()
	p.ammo_in_mag = 0
	p.ammo_reserve = 20
	check(p.start_reload(), "reload starts")
	await frames(100)
	check(p.ammo_in_mag == p.MAG_SIZE and p.ammo_reserve == 8, "reload fills mag from reserve")
	p.ammo_in_mag = 0
	p.ammo_reserve = 0
	check(not p.shoot(), "cannot shoot with no ammo at all")

	# --- hunger and eating
	reset_player()
	p.hunger = 0.0
	await frames(60)
	check(p.health < p.max_health, "starving hurts")
	reset_player()
	p.hunger = 30.0
	p.food = 2
	check(p.eat(), "eating works")
	check(p.food == 1 and p.hunger > 70.0, "eating uses food and fills hunger")

	# --- looting
	reset_player()
	var crate = game.spawn_crate(p.position + Vector2(20, 0), false)
	await frames(1)
	var before: int = p.ammo_reserve + p.food
	check(p.interact(), "searching a nearby crate works")
	check(crate.opened, "crate is marked as opened")
	check(p.ammo_reserve + p.food >= before, "loot was added")
	check(not p.interact(), "an opened crate cannot be searched twice")

	# --- noise draws zombies
	reset_player()
	z = game.spawn_zombie(p.position + Vector2(500, 0), false)
	await frames(2)
	z.state = "wander"
	game.make_noise(p.position, p.GUN_NOISE)
	check(z.state == "investigate", "gunshot noise makes far zombies investigate")
	await clear_zombies()

	# --- zombies chase and hurt you
	reset_player()
	z = game.spawn_zombie(p.position + Vector2(180, 0), false)
	await frames(240)
	check(p.health < p.max_health, "zombie chases and attacks the player")
	await clear_zombies()

	# --- shockwave
	reset_player()
	z = game.spawn_zombie(p.position + Vector2(80, 0), false)
	await frames(1)
	check(p.shockwave(), "shockwave fires")
	check(z.health < z.max_health, "shockwave damages nearby zombies")
	check(not p.shockwave(), "shockwave has a cooldown")
	await clear_zombies()

	# --- day / night cycle
	reset_player()
	game.phase_time = game.DAY_LENGTH - 0.01
	await frames(2)
	check(game.is_night, "day turns into night")
	check(game.horde_left > 0, "a horde is queued for the night")
	check(game.tint.color.v < 0.8, "the screen gets darker at night")
	game.spawning_enabled = true
	game.horde_timer = 0.0
	await frames(2)
	game.spawning_enabled = false
	var horde_found := false
	for hz in get_nodes_in_group("zombies"):
		if hz.is_horde:
			horde_found = true
	check(horde_found, "horde zombies spawn at night")
	game.phase_time = game.NIGHT_LENGTH - 0.01
	await frames(2)
	check(not game.is_night and game.day == 2, "surviving the night starts day 2")
	var still_horde := false
	for hz in get_nodes_in_group("zombies"):
		still_horde = still_horde or hz.is_horde
	check(not still_horde, "horde calms down at dawn")
	await clear_zombies()

	# --- death
	reset_player()
	p.take_damage(1000)
	await frames(1)
	check(p.dead and game.game_over, "player death ends the game")

	print("")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
