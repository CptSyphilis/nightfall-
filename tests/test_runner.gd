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


# ---- simulated controller input (goes through the real input system)
func joy_axis(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


func joy_button(button: JoyButton) -> void:
	for down in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = button
		ev.pressed = down
		Input.parse_input_event(ev)


func mapped_button(action: String, button: JoyButton) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return true
	return false


func mapped_axis(action: String, axis: JoyAxis) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and ev.axis == axis:
			return true
	return false


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

	# --- starting equipment
	check(p.ranged_weapon == "pistol" and p.melee_weapon == "fists", "you start with a pistol and fists")

	# --- melee kill (with a club)
	reset_player()
	p.inventory.set_count("club", 1)
	check(p.equip("club") and p.melee_weapon == "club", "equip a club")
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
	# Zombies killed earlier can drop a bag nearby; clear those first.
	for c in get_nodes_in_group("crates"):
		if c.global_position.distance_to(p.position) < 150:
			c.queue_free()
	await frames(1)
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

	# --- inventory basics
	var Inv = load("res://scripts/inventory.gd")
	var bag = Inv.new()
	bag.max_slots = 2
	check(bag.add("wood", 70) == 70 and bag.slots_used() == 2, "items stack (70 wood = 2 slots)")
	check(bag.add("stone", 5) == 0, "a full bag refuses new items")
	check(bag.add("wood", 40) == 30, "only what fits gets added")
	check(bag.remove("wood", 100) and bag.count("wood") == 0 and bag.is_empty(), "removing items frees space")
	check(not bag.remove("wood", 1), "cannot remove what you don't have")

	# --- gathering
	reset_player()
	p.inventory.set_count("wood", 0)
	var tree = game.spawn_resource("tree", p.position + Vector2(50, 0))
	await frames(1)
	check(p.melee(), "melee hits a tree")
	check(p.inventory.count("wood") >= 2, "chopping a tree gives wood")
	for i in 5:
		p.melee_cd = 0.0
		p.melee()
		await frames(1)
	check(not is_instance_valid(tree), "a tree disappears after its last hit")
	var rock = game.spawn_resource("rock", p.position + Vector2(55, 0))
	await frames(1)
	p.melee_cd = 0.0
	p.melee()
	check(p.inventory.count("stone") >= 1, "breaking a rock gives stone")
	rock.queue_free()
	await frames(1)

	# --- crafting
	reset_player()
	var inv = p.inventory
	for id in ["wood", "stone", "scrap", "cloth", "workbench", "chest", "bandage", "medkit"]:
		inv.set_count(id, 0)
	check(not p.can_craft("workbench"), "cannot craft without materials")
	inv.set_count("wood", 30)
	inv.set_count("stone", 10)
	inv.set_count("scrap", 10)
	inv.set_count("cloth", 10)
	check(p.craft("workbench"), "craft a workbench")
	check(inv.count("workbench") == 1 and inv.count("wood") == 20 and inv.count("stone") == 6, "crafting uses the right materials")
	check(p.craft("chest") and inv.count("chest") == 1, "craft a chest")
	check(p.craft("bandage") and inv.count("bandage") == 1, "craft a bandage by hand")
	check(not p.can_craft("ammo"), "ammo needs a workbench")

	# --- placing
	var spot: Vector2 = game.snap(p.position + Vector2(0, -80))
	check(game.can_place("workbench", spot), "free spot is placeable")
	check(not game.can_place("workbench", game.snap(p.position)), "cannot place on top of yourself")
	var ruin: Rect2 = game.ruins[0]
	check(not game.can_place("chest", ruin.get_center()), "cannot place inside a ruin")
	check(p.place_structure("workbench", spot), "place the workbench")
	check(inv.count("workbench") == 0 and get_nodes_in_group("structures").size() == 1, "workbench is now in the world")
	check(not game.can_place("chest", spot), "cannot place two things in one spot")
	check(p.near_workbench(), "player is near the workbench")
	var ammo_before: int = p.ammo_reserve
	check(p.craft("ammo") and p.ammo_reserve == ammo_before + 6, "craft ammo at the workbench")
	check(p.craft("medkit"), "craft a medkit at the workbench")

	# --- chest storage
	var chest_spot: Vector2 = game.snap(p.position + Vector2(-80, 0))
	check(p.place_structure("chest", chest_spot), "place the chest")
	var chest = game.nearest_structure(chest_spot, 5.0, "chest")
	check(chest != null and chest.storage != null, "chest has storage")
	var wood_now: int = inv.count("wood")
	check(game.transfer(inv, chest.storage, "wood", wood_now) == wood_now, "store wood in the chest")
	check(inv.count("wood") == 0 and chest.storage.count("wood") == wood_now, "wood moved into the chest")
	game.transfer(chest.storage, inv, "wood", wood_now)
	check(inv.count("wood") == wood_now and chest.storage.is_empty(), "take wood back out")

	# --- healing
	p.health = 50.0
	check(p.heal() and p.health == 75.0, "bandage heals 25")
	p.health = 30.0
	check(p.heal() and p.health == 90.0, "medkit heals 60 when out of bandages")

	# --- inventory window
	game.ui.open()
	await frames(1)
	check(game.ui_open, "inventory window opens")
	game.ui.close()
	check(not game.ui_open, "inventory window closes")
	game.ui.open_chest(chest)
	await frames(1)
	check(game.ui_open and game.ui.chest == chest, "chest window opens")
	p.position += Vector2(400, 0)
	await frames(3)
	check(not game.ui_open, "chest window closes when you walk away")
	p.position -= Vector2(400, 0)
	await frames(1)

	# --- weapons
	reset_player()
	for id in ["club", "stone_axe", "spear", "bow", "crossbow", "machete", "spiked_club"]:
		p.inventory.set_count(id, 0)
	p.unequip("melee")
	p.inventory.set_count("wood", 40)
	p.inventory.set_count("stone", 10)
	p.inventory.set_count("cloth", 6)
	check(p.craft("club") and p.craft("stone_axe") and p.craft("spear") and p.craft("bow"), "craft club, stone axe, spear and bow by hand")
	check(not p.can_craft("crossbow") or p.near_workbench(), "crossbow needs a workbench")

	# Fists are weak.
	z = game.spawn_zombie(p.position + Vector2(40, 0), false)
	await frames(1)
	var zh: float = z.health
	p.melee_cd = 0.0
	p.melee()
	check(is_equal_approx(zh - z.health, 18.0), "fists do 18 damage")
	await clear_zombies()

	# Spear reaches far but only straight ahead.
	reset_player()
	z = game.spawn_zombie(p.position + Vector2(100, 0), false)
	await frames(1)
	zh = z.health
	p.equip("club")
	p.melee()
	check(z.health == zh, "club cannot reach 100 pixels")
	p.equip("spear")
	p.melee_cd = 0.0
	p.melee()
	check(z.health < zh, "spear reaches 100 pixels")
	await clear_zombies()
	reset_player()
	z = game.spawn_zombie(p.position + Vector2(45, 45), false)
	await frames(1)
	zh = z.health
	p.melee()
	check(z.health == zh, "spear misses things off to the side")
	await clear_zombies()

	# Stone axe chops twice as much wood.
	reset_player()
	p.equip("stone_axe")
	p.inventory.set_count("wood", 0)
	tree = game.spawn_resource("tree", p.position + Vector2(50, 0))
	await frames(1)
	p.melee()
	check(p.inventory.count("wood") >= 4, "stone axe gathers double wood")
	tree.queue_free()
	await frames(1)

	# Bow uses arrows and is quiet.
	reset_player()
	p.inventory.set_count("arrow", 0)
	check(p.equip("bow") and p.ranged_weapon == "bow", "equip the bow")
	check(not p.shoot(), "bow cannot fire without arrows")
	check(p.craft("arrow") and p.inventory.count("arrow") == 5, "craft 5 arrows")
	var far_z = game.spawn_zombie(p.position + Vector2(-400, 0), false)
	z = game.spawn_zombie(p.position + Vector2(150, 0), false)
	await frames(1)
	far_z.state = "wander"
	zh = z.health
	var pistol_ammo: int = p.ammo_reserve
	var pistol_mag: int = p.ammo_in_mag
	check(p.shoot(), "bow fires")
	check(p.inventory.count("arrow") == 4 and p.ammo_reserve == pistol_ammo and p.ammo_in_mag == pistol_mag, "bow uses an arrow, not bullets")
	check(far_z.state == "wander", "bow is quiet (far zombie did not hear it)")
	await frames(15)
	check(not is_instance_valid(z) or z.health < zh, "arrow hits the zombie")
	await clear_zombies()

	# Pistol is loud.
	reset_player()
	p.equip("pistol")
	far_z = game.spawn_zombie(p.position + Vector2(-400, 0), false)
	await frames(1)
	far_z.state = "wander"
	p.shoot()
	check(far_z.state == "investigate", "pistol is loud (far zombie heard it)")
	await clear_zombies()

	# Losing an equipped weapon falls back safely.
	reset_player()
	p.equip("club")
	p.inventory.set_count("club", 0)
	p.melee()
	check(p.melee_weapon == "fists", "stored/lost weapon falls back to fists")
	check(not p.equip("crossbow"), "cannot equip a weapon you don't have")
	p.unequip("ranged")
	check(not p.shoot() and p.ranged_weapon == "", "no ranged weapon = no shooting")
	p.equip("pistol")

	# Character screen shows equipment.
	game.ui.open()
	await frames(1)
	check(game.ui_open and game.ui._char.get_child_count() > 3, "character screen shows equipment and stats")
	game.ui.close()

	# --- controller (Xbox / PlayStation)
	reset_player()
	check(mapped_axis("shoot", JOY_AXIS_TRIGGER_RIGHT) and mapped_button("melee", JOY_BUTTON_RIGHT_SHOULDER) \
		and mapped_button("dodge", JOY_BUTTON_A) and mapped_button("interact", JOY_BUTTON_X) \
		and mapped_button("inventory", JOY_BUTTON_START) and mapped_axis("move_left", JOY_AXIS_LEFT_X) \
		and mapped_axis("aim_up", JOY_AXIS_RIGHT_Y), "controller buttons and sticks are mapped")
	check(p.style_from_name("PS4 Controller") == "ps" and p.style_from_name("Sony Interactive Entertainment Wireless Controller") == "ps" \
		and p.style_from_name("DualSense Wireless Controller") == "ps" \
		and p.style_from_name("Wireless Controller (STANDARD GAMEPAD Vendor: 054c Product: 09cc)") == "ps" \
		and p.style_from_name("Xbox 360 Controller (XInput STANDARD GAMEPAD)") == "xbox" and p.style_from_name("Xbox Wireless Controller") == "xbox", \
		"PlayStation and Xbox pads are told apart")
	p.controls_enabled = true
	p.use_mouse_aim = true
	joy_axis(JOY_AXIS_RIGHT_X, 0.0)
	joy_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await frames(3)
	check(p.using_controller, "touching a stick switches to controller mode")
	check(p.aim_dir.distance_to(Vector2.UP) < 0.05, "right stick aims")
	joy_axis(JOY_AXIS_RIGHT_Y, 0.0)
	var start_pos: Vector2 = p.position
	joy_axis(JOY_AXIS_LEFT_X, 1.0)
	await frames(20)
	joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await frames(1)
	check(p.position.x > start_pos.x + 30, "left stick moves the player")
	check(p.aim_dir.distance_to(Vector2.RIGHT) < 0.05, "with the right stick released you face where you walk")
	var mag_before: int = p.ammo_in_mag
	joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames(2)
	joy_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await frames(1)
	check(p.ammo_in_mag < mag_before, "RT / R2 fires the ranged weapon")
	check(game.hud.prompt("interact") in ["X", "Square"], "on-screen prompts switch to controller buttons")

	game.ui.open()
	await frames(3)
	check(root.gui_get_focus_owner() is Button, "character screen highlights a button for the D-pad")
	joy_button(JOY_BUTTON_B)
	await frames(2)
	check(not game.ui_open, "B / Circle closes the character screen")
	joy_button(JOY_BUTTON_START)
	await frames(2)
	check(game.ui_open, "Menu / Options opens the character screen")
	joy_button(JOY_BUTTON_START)
	await frames(2)

	p.inventory.set_count("chest", 1)
	p.aim_dir = Vector2.RIGHT
	game.start_placing("chest")
	await frames(2)
	check(game.placement.global_position == game.snap(p.global_position + Vector2(80, 0)), "placement sits in front of you on a controller")
	var built_before: int = get_nodes_in_group("structures").size()
	joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames(2)
	joy_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await frames(1)
	check(get_nodes_in_group("structures").size() == built_before + 1 and game.placing == "", "RT / R2 places the chest")

	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(10, 0)
	Input.parse_input_event(mm)
	await frames(1)
	check(not p.using_controller and game.hud.prompt("interact") == "E", "moving the mouse switches back to mouse and keyboard")
	p.controls_enabled = false
	p.use_mouse_aim = false

	# --- death
	reset_player()
	p.take_damage(1000)
	await frames(1)
	check(p.dead and game.game_over, "player death ends the game")

	print("")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
