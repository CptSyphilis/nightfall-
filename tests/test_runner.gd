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
	# Most checks below need a gun, so give the test player a pistol.
	p.inventory.set_count("pistol", 1)
	p.ranged_weapon = "pistol"
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
	check(p.ranged_weapon == "" and p.melee_weapon == "fists", "you start with only your fists")
	check(p.inventory.is_empty(), "you start with an empty bag")
	check(game.ruins.size() > 10, "ruins were generated (%d)" % game.ruins.size())
	check(get_nodes_in_group("crates").size() >= 30, "crates were placed")
	check(game.nav != null, "zombie navigation grid is built")
	var on_grid := true
	for res in get_nodes_in_group("resources"):
		on_grid = on_grid and fposmod(res.position.x, 32.0) == 16.0 and fposmod(res.position.y, 32.0) == 16.0
	check(on_grid, "trees, rocks and scrap sit on the grid")
	var crates_on_grid := true
	for c in get_nodes_in_group("crates"):
		crates_on_grid = crates_on_grid and fposmod(c.position.x, 32.0) == 16.0 and fposmod(c.position.y, 32.0) == 16.0
	check(crates_on_grid, "crates sit on the grid")
	var ruins_on_grid := true
	for r in game.ruins:
		for v in [r.position.x, r.position.y, r.size.x, r.size.y]:
			ruins_on_grid = ruins_on_grid and fposmod(v, 32.0) == 0.0
	check(ruins_on_grid, "ruined buildings line up with the grid")
	check(game.campfire() == null, "there is no campfire at the start")
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
	await frames(1)
	check(not is_instance_valid(crate), "a searched crate disappears")
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

	# --- day / night cycle (campfire starts the night)
	reset_player()
	check(not game.is_night and game.zombie_count() == 0, "daytime has no zombies")
	game.phase_time = 100000.0
	await frames(2)
	check(not game.is_night, "daytime never ends on its own")
	p.inventory.set_count("wood", 12)
	p.inventory.set_count("stone", 8)
	check(game.build_piece("campfire", p.position + Vector2(0, 96)), "build a campfire")
	check(p.inventory.count("wood") == 6 and p.inventory.count("stone") == 4, "a campfire costs 6 wood and 4 stone")
	check(not game.build_piece("campfire", p.position + Vector2(96, 96)), "only one campfire is allowed")
	var fire = game.campfire()
	for c in get_nodes_in_group("crates"):
		if c.global_position.distance_to(fire.global_position) < 100:
			c.queue_free()
	await frames(1)
	p.position = fire.global_position + Vector2(0, 45)
	await frames(1)
	check(p.interact() and not game.is_night, "first press at the campfire only asks to confirm")
	p.interact()
	check(game.is_night, "second press starts the night")
	check(game.horde_left > 0, "a horde is queued for the night")
	game.phase_time = 5.0
	await frames(2)
	check(game.tint.color.v < 0.8, "the screen gets darker at night")
	check(fire.light.energy > 0.5, "the campfire glows at night")
	game.spawning_enabled = true
	game.horde_timer = 0.0
	await frames(2)
	game.spawning_enabled = false
	var horde_found := false
	for hz in get_nodes_in_group("zombies"):
		if hz.is_horde:
			horde_found = true
	check(horde_found, "horde zombies spawn at night")
	check(game.night_length() == 60.0, "the first night lasts 60 seconds")
	game.phase_time = game.night_length() - 0.01
	await frames(2)
	check(not game.is_night and game.day == 2, "surviving the night starts day 2")
	await frames(1)
	check(game.zombie_count() == 0, "zombies vanish at dawn")
	check(game.night_length() == 70.0, "the next night is longer")
	p.inventory.set_count("wood", 0)
	check(game.demolish_at(fire.global_position) and p.inventory.count("wood") == 6, "the campfire can be moved by day (full refund)")
	await frames(1)
	check(game.campfire() == null, "the campfire is gone after demolishing")
	reset_player()

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
	var spot: Vector2 = game.snap_for("workbench", p.position + Vector2(0, -80))
	check(game.can_place("workbench", spot), "free spot is placeable")
	check(not game.can_place("workbench", game.snap_for("workbench", p.position)), "cannot place on top of yourself")
	var ruin: Rect2 = game.ruins[0]
	check(not game.can_place("chest", ruin.get_center()), "cannot place inside a ruin")
	var built_count: int = get_nodes_in_group("structures").size()
	check(p.place_structure("workbench", spot), "place the workbench")
	check(inv.count("workbench") == 0 and get_nodes_in_group("structures").size() == built_count + 1, "workbench is now in the world")
	check(not game.can_place("chest", spot), "cannot place two things in one spot")
	check(p.near_workbench(), "player is near the workbench")
	var ammo_before: int = p.ammo_reserve
	check(p.craft("ammo") and p.ammo_reserve == ammo_before + 6, "craft ammo at the workbench")
	check(p.craft("medkit"), "craft a medkit at the workbench")

	# --- chest storage
	var chest_spot: Vector2 = game.snap_for("chest", p.position + Vector2(-80, 0))
	check(p.place_structure("chest", chest_spot), "place the chest")
	var chest = game.nearest_structure(chest_spot, 5.0, "chest")
	check(chest != null and chest.storage != null, "chest has storage")
	var wood_now: int = inv.count("wood")
	check(game.transfer(inv, chest.storage, "wood", wood_now) == wood_now, "store wood in the chest")
	check(inv.count("wood") == 0 and chest.storage.count("wood") == wood_now, "wood moved into the chest")
	game.transfer(chest.storage, inv, "wood", wood_now)
	check(inv.count("wood") == wood_now and chest.storage.is_empty(), "take wood back out")
	var chest_ok: bool = fposmod(chest.position.x - 16.0, 32.0) == 0.0 and fposmod(chest.position.y - 16.0, 32.0) == 0.0
	check(chest_ok, "a placed chest lines up with the grid")
	inv.set_count("wood", 0)
	inv.set_count("club", 0)
	chest.storage.add("wood", 10)
	check(p.nearby_chests().has(chest), "the workbench sees the nearby chest")
	check(p.can_craft("club") and p.craft("club"), "craft at the workbench using wood from the chest")
	check(chest.storage.count("wood") == 4 and inv.count("club") == 1, "the wood came out of the chest")
	inv.set_count("wood", wood_now)

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
	await frames(6)
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
	check(game.placement.global_position == game.snap_for("chest", p.global_position + Vector2(80, 0)), "placement sits in front of you on a controller")
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

	# --- build mode (walls, doors, traps, towers)
	reset_player()
	await clear_zombies()
	# Clear earlier test buildings and loot near the start.
	for st in get_nodes_in_group("structures"):
		if true:
			st.remove_from_group("structures")
			st.queue_free()
	for c in get_nodes_in_group("crates"):
		if c.global_position.distance_to(p.position) < 300:
			c.queue_free()
	for res in get_nodes_in_group("resources"):
		if res.global_position.distance_to(p.position) < 420:
			res.depleted = true
			res.remove_from_group("resources")
			res.queue_free()
	game.nav_dirty = true
	await frames(2)
	var nav = game.nav
	var home: Vector2i = nav.to_cell(p.position)
	var cellpos := func(dx: int, dy: int) -> Vector2: return nav.cell_center(home + Vector2i(dx, dy))
	var bag2 = p.inventory
	for id in ["wood", "stone", "scrap"]:
		bag2.set_count(id, 0)

	game.build.set_active(true)
	check(game.build.active, "B turns on build mode")
	check(not game.build_piece("wood_wall", cellpos.call(3, 0)), "cannot build without materials")
	bag2.set_count("wood", 200)
	bag2.set_count("stone", 100)
	bag2.set_count("scrap", 30)
	check(game.build_piece("wood_wall", cellpos.call(3, 0)), "build a wood wall")
	check(bag2.count("wood") == 198, "a wood wall costs 2 wood")
	check(not nav.is_free(cellpos.call(3, 0)), "zombies path around a new wall right away")
	check(game.build_piece("wood_wall", cellpos.call(3, 1)), "walls can sit right next to each other")
	check(not game.build_piece("wood_wall", cellpos.call(3, 1)), "cannot build two pieces in one square")
	check(not game.build_piece("wood_wall", cellpos.call(0, 0)), "cannot build on yourself")
	check(not game.can_build("wood_wall", game.ruins[0].get_center()), "cannot build inside a ruin")

	var wood_before: int = bag2.count("wood")
	check(game.demolish_at(cellpos.call(3, 1)), "demolish a wall")
	check(bag2.count("wood") == wood_before + 1, "demolishing gives half the cost back")
	await frames(2)
	check(nav.is_free(cellpos.call(3, 1)), "a demolished wall frees the path")
	game.demolish_at(cellpos.call(3, 0))
	await frames(2)

	# Drag to demolish: hold demolish and sweep over a line of walls.
	for i in 4:
		game.build_piece("wood_wall", cellpos.call(-2 + i, 3))
	var line_count := func() -> int:
		var n := 0
		for st in get_nodes_in_group("structures"):
			if st.kind == "wood_wall" and absf(st.global_position.y - cellpos.call(0, 3).y) < 1.0:
				n += 1
		return n
	check(line_count.call() == 4, "built a line of 4 walls to drag-remove")
	for i in 4:
		game.build.drag(cellpos.call(-2 + i, 3), false, true)
		game.build.drag(cellpos.call(-2 + i, 3), false, true)   # same square twice: only once
	await frames(2)
	check(line_count.call() == 0, "holding demolish and moving removes the whole line")
	game.build.drag(cellpos.call(0, 0), false, false)   # let go
	# Drag to build still works.
	for i in 3:
		game.build.drag(cellpos.call(-2 + i, 3), true, false)
	await frames(1)
	check(line_count.call() == 3, "holding build and moving still builds a line")
	game.build.drag(cellpos.call(0, 0), false, false)
	for i in 3:
		game.demolish_at(cellpos.call(-2 + i, 3))
	await frames(2)

	# Concrete floor: walkable, and other pieces sit on top of it.
	bag2.set_count("concrete", 0)
	bag2.set_count("stone", 100)
	var bench3 = game.spawn_structure("workbench", cellpos.call(-2, -1))
	check(p.craft("concrete") and bag2.count("concrete") == 2, "craft concrete at a workbench (3 stone = 2)")
	bench3.queue_free()
	await frames(1)
	check(game.build_piece("concrete_floor", cellpos.call(2, -3)) and bag2.count("concrete") == 1, "build a concrete floor (1 concrete)")
	check(nav.is_free(cellpos.call(2, -3)), "zombies can walk on floors")
	check(not game.build_piece("concrete_floor", cellpos.call(2, -3)), "cannot put two floors in one square")
	check(game.build_piece("concrete_floor", cellpos.call(0, 0)), "you can lay a floor under yourself")
	check(game.build_piece("wood_wall", cellpos.call(2, -3)), "a wall can be built on a floor")
	check(not nav.is_free(cellpos.call(2, -3)), "the wall on the floor still blocks zombies")
	game.demolish_at(cellpos.call(2, -3))
	var kinds_left := []
	for st in get_nodes_in_group("structures"):
		if st.global_position.distance_to(cellpos.call(2, -3)) < 1.0:
			kinds_left.append(st.kind)
	check(kinds_left == ["concrete_floor"], "demolish takes the wall first and leaves the floor")
	game.demolish_at(cellpos.call(2, -3))
	game.demolish_at(cellpos.call(0, 0))
	await frames(2)

	# Door: the player walks through, zombies don't.
	check(game.build_piece("door", cellpos.call(0, 3)), "build a door")
	var door = null
	for st in get_nodes_in_group("structures"):
		if st.kind == "door":
			door = st
	check(door != null and door.collision_layer == 16 and (p.collision_mask & 16) == 0, "the player can walk through doors")
	check(not nav.is_free(door.global_position), "zombies treat doors as walls")
	game.demolish_at(door.global_position)

	# Spike trap: zombies walk over it and get hurt.
	check(game.build_piece("spikes", cellpos.call(-3, -3)), "build a spike trap")
	check(nav.is_free(cellpos.call(-3, -3)), "zombies can walk over spike traps")
	z = game.spawn_zombie(cellpos.call(-3, -3), false)
	await frames(3)
	check(z.health < z.max_health and z.slow_timer > 0.0, "spikes hurt and slow zombies")
	await clear_zombies()

	# Arrow tower: shoots zombies on its own.
	check(game.build_piece("tower", cellpos.call(0, -4)), "build an arrow tower")
	z = game.spawn_zombie(cellpos.call(0, -4) + Vector2(220, -60), false)
	await frames(1)
	var zhp: float = z.health
	await frames(90)
	check(not is_instance_valid(z) or z.health < zhp, "the tower shoots zombies")
	await clear_zombies()

	# Maze: zombies follow the open route instead of breaking walls.
	for dy in range(-6, 7):
		if dy != 6:
			game.build_piece("wood_wall", cellpos.call(5, dy))
	await frames(2)
	var maze_walls := []
	for st in get_nodes_in_group("structures"):
		if st.kind == "wood_wall":
			maze_walls.append(st)
	check(maze_walls.size() == 12, "a 12-wall maze line was built")
	z = game.spawn_zombie(cellpos.call(9, 0), true)
	await frames(1)
	var got_me := false
	for i in 900:
		await physics_frame
		if p.health < p.max_health:
			got_me = true
			break
	var all_intact := true
	for wall in maze_walls:
		all_intact = all_intact and is_instance_valid(wall) and wall.hp == wall.max_hp
	check(got_me, "zombie finds the way through the maze gap")
	check(all_intact, "zombie does not break walls while a route is open")
	await clear_zombies()

	# Walled in: no route left, so zombies smash through.
	reset_player()
	var ring := []
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			if maxi(absi(dx), absi(dy)) == 2:
				game.build_piece("wood_wall", cellpos.call(dx, dy))
	for st in get_nodes_in_group("structures"):
		if st.kind == "wood_wall" and not st in maze_walls:
			ring.append(st)
	check(ring.size() == 16, "player is walled in by 16 walls")
	# The maze line is still standing in front of the base, like a Maul map.
	z = game.spawn_zombie(cellpos.call(9, 0), true)
	var smashed := false
	for i in 3000:   # the map is random, so some walks to the base are long
		await physics_frame
		for wall in ring:
			if not is_instance_valid(wall) or wall.hp < wall.max_hp:
				smashed = true
		if smashed:
			break
	check(smashed, "walled-in player: zombies smash the base walls")
	var maze_intact := true
	for wall in maze_walls:
		maze_intact = maze_intact and is_instance_valid(wall) and wall.hp == wall.max_hp
	check(maze_intact, "zombies walk the maze to the base instead of breaking the maze")
	await clear_zombies()
	for st in get_nodes_in_group("structures"):
		if true:
			st.remove_from_group("structures")
			st.queue_free()
	game.nav_dirty = true
	game.build.set_active(false)
	await frames(2)

	# --- zombie pathing and sight
	reset_player()
	await clear_zombies()
	var c0: Vector2 = p.position
	game.add_wall(Rect2(c0 + Vector2(70, -160), Vector2(40, 320)))
	await frames(1)
	check(not game.nav.is_free(c0 + Vector2(90, 0)) and game.nav.is_free(c0 + Vector2(200, 0)), "walls are marked on the navigation grid")
	var route: PackedVector2Array = game.nav.find_path(c0 + Vector2(220, 0), c0)
	var route_ok := route.size() > 2
	for pt in route:
		if pt.x > c0.x + 56 and pt.x < c0.x + 124 and absf(pt.y - c0.y) < 174:
			route_ok = false   # a path point inside the wall
	check(route_ok, "a path goes around the wall, not through it")
	z = game.spawn_zombie(c0 + Vector2(220, 0), true)   # horde zombies always hunt you
	await frames(1)
	var reached := false
	for i in 600:
		await physics_frame
		if p.health < p.max_health:
			reached = true
			break
	check(reached, "zombie walks around a wall to reach you")
	await clear_zombies()
	reset_player()
	z = game.spawn_zombie(c0 + Vector2(200, 0), false)
	await frames(30)
	check(z.state == "wander", "zombie cannot see you through a wall")
	game.make_noise(p.position, p.GUN_NOISE)
	check(z.state == "investigate", "but it still hears you through the wall")
	await clear_zombies()
	reset_player()
	var tree2 = game.spawn_resource("tree", c0 + Vector2(-150, -40))
	await frames(2)
	check(not game.nav.is_free(tree2.global_position), "trees block zombie paths")
	tree2.depleted = true
	tree2.queue_free()
	game.nav_dirty = true
	await frames(2)
	check(game.nav.is_free(c0 + Vector2(-150, -40)), "a chopped tree frees the path")

	# --- campfire siege (Maul style): zombies go for the campfire, 10 lives
	reset_player()
	await clear_zombies()
	p.inventory.set_count("wood", 20)
	p.inventory.set_count("stone", 20)
	check(game.build_piece("campfire", p.position + Vector2(-96, 0)), "build the campfire for the siege test")
	fire = game.campfire()
	p.position = fire.global_position + Vector2(-400, 0)   # stand well away from it
	await frames(1)
	check(game.lives == game.CAMPFIRE_LIVES, "you start with 10 campfire lives")
	z = game.spawn_zombie(fire.global_position + Vector2(300, 0), true)
	await frames(2)
	check(z.state == "siege", "horde zombies head for the campfire")
	var hit_fire := false
	for i in 900:
		await physics_frame
		if game.lives < game.CAMPFIRE_LIVES:
			hit_fire = true
			break
	check(hit_fire and game.lives == game.CAMPFIRE_LIVES - 1, "a zombie reaching the campfire costs one life")
	await frames(1)
	check(not is_instance_valid(z), "that zombie is gone afterwards")
	game.lives = 1
	z = game.spawn_zombie(fire.global_position + Vector2(60, 0), true)
	for i in 300:
		await physics_frame
		if game.game_over:
			break
	check(game.game_over and game.lives == 0 and "campfire" in game.lose_reason, "losing all campfire lives ends the game")
	game.game_over = false
	game.lose_reason = ""
	await clear_zombies()

	# --- loot rates
	var CrateScript = load("res://scripts/loot_crate.gd")
	var totals := {}
	for i in 2000:
		var lc = CrateScript.new()
		lc.setup(game.rng, i % 2 == 0)
		for id in lc.loot:
			totals[id] = totals.get(id, 0) + lc.loot[id]
		lc.free()
	check(totals.get("medkit", 0) == 0, "medkits are never found as loot")
	check(totals.get("bandage", 0) > 0, "bandages can be found as loot")
	check(totals.get("ammo", 0) / 2000.0 < 2.5, "ammo is rarer (%.1f per crate)" % (totals.get("ammo", 0) / 2000.0))
	check(totals.get("arrow", 0) / 2000.0 < 0.4, "arrows are rarer (%.2f per crate)" % (totals.get("arrow", 0) / 2000.0))
	check(game.ZOMBIE_DROP_CHANCE <= 0.1, "zombies drop bags less often")

	# --- backpack upgrades
	reset_player()
	p.inventory.max_slots = 16
	p.inventory.set_count("cloth", 30)
	p.inventory.set_count("wood", 5)
	p.inventory.set_count("scrap", 5)
	check(not p.can_craft("backpack_large"), "large backpack needs the medium one first")
	check(p.craft("backpack_medium") and p.inventory.max_slots == 20, "medium backpack gives 20 slots")
	check(p.inventory.count("backpack_medium") == 0, "the backpack is worn, not kept in the bag")
	check(not p.can_craft("backpack_medium"), "cannot craft the medium backpack twice")
	var bench2 = game.spawn_structure("workbench", p.position + Vector2(48, 0))
	check(p.craft("backpack_large") and p.inventory.max_slots == 24, "large backpack gives 24 slots")
	bench2.queue_free()
	p.inventory.max_slots = 16
	for id in ["cloth", "wood", "scrap"]:
		p.inventory.set_count(id, 0)
	await frames(1)

	# --- discard
	reset_player()
	for c in get_nodes_in_group("crates"):
		if c.global_position.distance_to(p.position) < 150:
			c.queue_free()
	await frames(1)
	p.inventory.set_count("club", 1)
	p.equip("club")
	p.inventory.set_count("stone", 7)
	check(p.discard("stone") and p.inventory.count("stone") == 0, "discard throws away a stack")
	check(p.discard("club") and p.melee_weapon == "fists", "discarding your equipped weapon unequips it")
	check(not p.discard("stone"), "cannot discard what you do not have")
	await frames(2)
	var bags := 0
	for c in get_nodes_in_group("crates"):
		if c.global_position.distance_to(p.position) < 40:
			bags += 1
	check(bags >= 1, "dropped items land in a bag at your feet")
	check(p.interact() and p.inventory.count("stone") + p.inventory.count("club") > 0, "you can pick dropped items back up")
	for c in get_nodes_in_group("crates"):
		if c.global_position.distance_to(p.position) < 150:
			c.queue_free()
	p.inventory.set_count("stone", 0)
	p.inventory.set_count("club", 0)
	p.inventory.set_count("wood", 4)
	game.ui.open()
	game.ui._on_discard_toggle()
	game.ui._on_player_item("wood")
	check(game.ui.discard_mode and p.inventory.count("wood") == 0, "discard mode in the character screen drops the item")
	game.ui.close()
	game.ui.open()
	check(not game.ui.discard_mode, "discard mode turns off when the screen reopens")
	game.ui.close()
	for c in get_nodes_in_group("crates"):
		if c.global_position.distance_to(p.position) < 150:
			c.queue_free()
	await frames(1)

	# --- campfire pointer (arrow at the screen edge)
	var Hud = load("res://scripts/hud.gd")
	var scr := Vector2(1280, 720)
	check(not Hud.campfire_pointer(Vector2(640, 360), scr, 40.0)["show"], "no campfire arrow when the fire is on screen")
	var right = Hud.campfire_pointer(Vector2(3000, 360), scr, 40.0)
	check(right["show"] and is_equal_approx(right["pos"].x, 1240.0) and is_equal_approx(right["pos"].y, 360.0), "fire far right: arrow on the right edge")
	check(absf(right["angle"]) < 0.01, "and it points right")
	var up_left = Hud.campfire_pointer(Vector2(-2000, -2000), scr, 40.0)
	var inside_screen: bool = Rect2(Vector2(39, 39), scr - Vector2(78, 78)).has_point(up_left["pos"])
	check(up_left["show"] and inside_screen, "fire up-left: arrow stays inside the screen")
	var fire2 = game.campfire()
	if fire2 == null:
		fire2 = game.spawn_structure("campfire", game.WORLD_SIZE / 2)
	var fire_home: Vector2 = fire2.global_position
	fire2.global_position = p.global_position + Vector2(1500, 0)
	game.hud.queue_redraw()
	await frames(3)
	var seen: Vector2 = game.hud.get_viewport().get_canvas_transform() * fire2.global_position
	check(Hud.campfire_pointer(seen, game.hud.size, 40.0)["show"], "an off-screen campfire in the game gets an arrow")
	fire2.global_position = fire_home
	await frames(1)

	# --- death
	reset_player()
	p.take_damage(1000)
	await frames(1)
	check(p.dead and game.game_over, "player death ends the game")

	print("")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
