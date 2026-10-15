extends CharacterBody2D
## The survivor you control.
## WASD move, mouse aims, left click fires your ranged weapon,
## right click swings your melee weapon,
## Space dodges (you are invulnerable while rolling), Q is a shockwave.
## Weapon stats live in items.gd (WEAPONS).

signal died

const SPEED := 210.0
const DODGE_SPEED := 620.0
const DODGE_TIME := 0.22
const DODGE_COOLDOWN := 1.0
const MELEE_NOISE := 160.0
const GUN_NOISE := 650.0
const MAG_SIZE := 12
const RELOAD_TIME := 1.4
const SHOCK_COOLDOWN := 8.0
const SHOCK_RADIUS := 160.0
const SHOCK_DAMAGE := 50.0
const HUNGER_DRAIN := 0.35      # per second, 100 = full
const STARVE_DAMAGE := 3.0      # per second when hunger is 0
const REGEN := 0.6              # health per second when well fed

const HEAL_BANDAGE := 25.0
const HEAL_MEDKIT := 60.0
const WORKBENCH_RANGE := 90.0
const CHEST_RANGE := 300.0      # chests this close to a workbench share their items when crafting

const BulletScript := preload("res://scripts/bullet.gd")
const InventoryScript := preload("res://scripts/inventory.gd")
const Items := preload("res://scripts/items.gd")

# Sprites. Everything faces right (+X) and is rotated to aim_dir.
const TEX_BODY := preload("res://assets/player.svg")
const WEAPON_TEX := {
	"pistol": preload("res://assets/pistol.svg"),
	"bow": preload("res://assets/bow.svg"),
	"crossbow": preload("res://assets/crossbow.svg"),
	"club": preload("res://assets/club.svg"),
	"stone_axe": preload("res://assets/stone_axe.svg"),
	"spear": preload("res://assets/spear.svg"),
	"spiked_club": preload("res://assets/spiked_club.svg"),
	"machete": preload("res://assets/machete.svg"),
}

var radius := 14.0
var max_health := 100.0
var health := 100.0
var hunger := 100.0
var ammo_in_mag := 0            # rounds loaded in the pistol
var inventory = InventoryScript.new()

## Equipped weapons. "fists" = no melee weapon, "" = no ranged weapon.
var melee_weapon := "fists"
var ranged_weapon := ""

## Spare ammo and food live in the inventory. These are shortcuts to them.
var ammo_reserve: int:
	get:
		return inventory.count("ammo")
	set(value):
		inventory.set_count("ammo", value)

var food: int:
	get:
		return inventory.count("food")
	set(value):
		inventory.set_count("food", value)

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

var action_block := 0.0   # short pause on shooting after placing something
var dead := false
var controls_enabled := true
var use_mouse_aim := true          # false = aim is set from code (tests)
var using_controller := false      # true after the last input came from a gamepad
var controller_style := "xbox"     # "xbox" or "ps", decides the button names shown
var last_pad_device := -1          # for the F3 input checker
var web_r2 := 0.0                  # browser only: R2/RT read straight from the browser (see _poll_web_trigger)

# Browser version only. Godot 4.3's web build drops the analog triggers of
# standard gamepads, so R2/RT never arrives as normal input. This reads it
# straight from the browser's Gamepad API instead (button 7 = R2 / RT).
const JS_READ_R2 := "(function(){var g=navigator.getGamepads?navigator.getGamepads():[];var m=0;for(var i=0;i<g.length;i++){var p=g[i];if(p&&p.buttons&&p.buttons.length>7){var b=p.buttons[7];var v=(typeof b==='object')?(b.value||(b.pressed?1:0)):b;if(v>m)m=v;}}return m;})()"
var last_pad_input := "(nothing yet)"
var game: Node
var light: PointLight2D
var sprite: Sprite2D


func _init() -> void:
	# You start with nothing but your fists. Find or craft everything else.
	pass


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

	# The body sprite. Only it rotates; health, rings and markers stay upright in _draw.
	sprite = Sprite2D.new()
	sprite.texture = TEX_BODY
	sprite.show_behind_parent = true
	add_child(sprite)

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
	_poll_web_trigger()
	light.energy = game.night_amount * 0.9

	# While the character screen is open you stand still
	# (the stick and D-pad are moving around the menu instead).
	var in_menu: bool = game.ui_open
	var move := Vector2.ZERO
	if controls_enabled and not in_menu:
		move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if use_mouse_aim and not in_menu:
		_update_aim(move)

	if dodge_timer > 0.0:
		velocity = dodge_dir * DODGE_SPEED
	else:
		velocity = move * SPEED
	move_and_slide()

	if controls_enabled:
		if Input.is_action_just_pressed("interact"):
			interact()   # also closes the menu when it is open
		if not in_menu:
			# No fighting while placing or building (the same buttons build and demolish).
			var building: bool = game.build != null and game.build.active
			var can_fight: bool = game.placing == "" and action_block <= 0.0 and not building
			if can_fight and (Input.is_action_pressed("shoot") or web_r2 > 0.5):
				shoot()
			if can_fight and Input.is_action_pressed("melee"):
				melee()
			if Input.is_action_just_pressed("heal"):
				heal()
			if Input.is_action_just_pressed("dodge"):
				dodge(move)
			if Input.is_action_just_pressed("ability") and not building:
				shockwave()
			if Input.is_action_just_pressed("reload") and not building:
				start_reload()
			if Input.is_action_just_pressed("eat"):
				eat()
	queue_redraw()


## Mouse: aim at the cursor. Controller: aim with the right stick,
## or face where you are walking when the right stick is let go.
func _update_aim(move: Vector2) -> void:
	if using_controller:
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		if stick.length() > 0.0:
			aim_dir = stick.normalized()
		elif move.length() > 0.0:
			aim_dir = move.normalized()
	else:
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length() > 1.0:
			aim_dir = to_mouse.normalized()


## Notice which device was used last, so aiming and button prompts follow it.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		last_pad_device = event.device
		last_pad_input = "button %d pressed" % event.button_index
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.2:
		last_pad_device = event.device
		last_pad_input = "axis %d = %.2f" % [event.axis, event.axis_value]
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		if not using_controller or controller_style == "keyboard":
			controller_style = style_from_name(pad_name(event.device))
		using_controller = true
	elif event is InputEventKey or event is InputEventMouseButton \
			or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		using_controller = false


func _poll_web_trigger() -> void:
	if not OS.has_feature("web"):
		return
	var v = JavaScriptBridge.eval(JS_READ_R2, true)
	web_r2 = float(v) if v != null else 0.0
	if web_r2 > 0.5 and not using_controller:
		using_controller = true
		controller_style = style_from_name(pad_name(0))


## The controller's real name. In the browser, Godot only reports
## "Standard Gamepad Mapping", so ask the browser for the actual name.
func pad_name(device: int) -> String:
	if OS.has_feature("web"):
		var id = JavaScriptBridge.eval("(function(){var g=navigator.getGamepads?navigator.getGamepads()[%d]:null;return g?g.id:'';})()" % maxi(device, 0), true)
		if id != null and str(id) != "":
			return str(id)
	return Input.get_joy_name(device)


## "ps" for PlayStation pads, "xbox" for everything else (Xbox and generic pads).
static func style_from_name(joy_name: String) -> String:
	var n := joy_name.to_lower()
	# Check Xbox first: "Xbox Wireless Controller" would otherwise match
	# "wireless controller", which is how PS4 pads name themselves on Linux.
	for word in ["xbox", "microsoft", "x-box"]:
		if word in n:
			return "xbox"
	# "054c" is Sony's USB vendor id, which browsers include in the pad name.
	for word in ["ps3", "ps4", "ps5", "playstation", "sony", "dualshock", "dualsense", "wireless controller", "054c"]:
		if word in n:
			return "ps"
	return "xbox"


## Which button names to show on screen: "keyboard", "xbox" or "ps".
func prompt_style() -> String:
	return controller_style if using_controller else "keyboard"


func _tick_timers(delta: float) -> void:
	dodge_cd = maxf(dodge_cd - delta, 0.0)
	melee_cd = maxf(melee_cd - delta, 0.0)
	shoot_cd = maxf(shoot_cd - delta, 0.0)
	shock_cd = maxf(shock_cd - delta, 0.0)
	swing_flash = maxf(swing_flash - delta, 0.0)
	shock_flash = maxf(shock_flash - delta, 0.0)
	muzzle_flash = maxf(muzzle_flash - delta, 0.0)
	hurt_flash = maxf(hurt_flash - delta, 0.0)
	action_block = maxf(action_block - delta, 0.0)
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

## Stats of the equipped melee weapon (falls back to fists if it is gone).
func melee_stats() -> Dictionary:
	if melee_weapon != "fists" and inventory.count(melee_weapon) <= 0:
		melee_weapon = "fists"
	return Items.weapon(melee_weapon)


## Stats of the equipped ranged weapon, or {} if none.
func ranged_stats() -> Dictionary:
	if ranged_weapon != "" and inventory.count(ranged_weapon) <= 0:
		ranged_weapon = ""
		reload_timer = 0.0
	return Items.weapon(ranged_weapon)


## Equip a weapon from your inventory into the right slot.
func equip(id: String) -> bool:
	if not Items.is_weapon(id) or inventory.count(id) <= 0:
		return false
	if Items.weapon(id)["type"] == "melee":
		melee_weapon = id
	else:
		ranged_weapon = id
		reload_timer = 0.0
	return true


## Empty a slot. "melee" goes back to fists, "ranged" to nothing.
func unequip(slot: String) -> void:
	if slot == "melee":
		melee_weapon = "fists"
	else:
		ranged_weapon = ""
		reload_timer = 0.0


func shoot() -> bool:
	var w := ranged_stats()
	if dead or w.is_empty() or shoot_cd > 0.0 or reload_timer > 0.0:
		return false
	if w["magazine"] > 0:
		# Guns: fire from the magazine, reload from spare ammo.
		if ammo_in_mag <= 0:
			start_reload()
			return false
		ammo_in_mag -= 1
		muzzle_flash = 0.06
	else:
		# Bows: each shot takes one arrow straight from the inventory.
		if not inventory.remove(w["ammo"], 1):
			return false
	shoot_cd = w["cooldown"]
	var b: Node2D = BulletScript.new()
	b.position = global_position + aim_dir * (radius + 8.0)
	b.direction = aim_dir
	b.damage = w["damage"]
	b.speed = w["speed"]
	b.life = w["life"]
	b.style = w["style"]
	game.world_node.add_child(b)
	game.make_noise(global_position, w["noise"])
	return true


func start_reload() -> bool:
	var w := ranged_stats()
	if w.is_empty() or w["magazine"] <= 0:
		return false
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
	var w := melee_stats()
	var reach: float = w["range"]
	var arc: float = w["arc"]
	melee_cd = w["cooldown"]
	swing_flash = 0.15
	var hits := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead:
			continue
		var to: Vector2 = z.global_position - global_position
		if to.length() > reach + z.radius:
			continue
		if absf(aim_dir.angle_to(to)) > arc + _arc_slack(to.length(), z.radius):
			continue
		z.take_damage(w["damage"], to.normalized() * w["knockback"])
		hits += 1
	# The same swing chops trees, breaks rocks and pulls apart scrap.
	var gather_bonus: Dictionary = w.get("gather", {})
	for r in get_tree().get_nodes_in_group("resources"):
		if r.depleted:
			continue
		var to: Vector2 = r.global_position - global_position
		if to.length() > reach + r.radius:
			continue
		if absf(aim_dir.angle_to(to)) > arc + _arc_slack(to.length(), r.radius):
			continue
		r.gather(self, gather_bonus.get(r.kind, 1))
		hits += 1
	game.make_noise(global_position, MELEE_NOISE)
	return hits > 0


## Extra angle so a narrow thrust (spear) still hits a target whose body
## overlaps the line, even if its center is slightly off to the side.
func _arc_slack(dist: float, target_radius: float) -> float:
	return atan2(target_radius, maxf(dist, 1.0)) * 0.6


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


## E key: search a crate, open a chest, or use a workbench (whatever is closest).
func interact() -> bool:
	if dead:
		return false
	if game.ui_open:
		game.ui.close()
		return true
	var crate: Node2D = game.nearest_crate(global_position, 48.0)
	if crate != null:
		return _search_crate(crate)
	var s: Node2D = game.nearest_usable(global_position, 64.0)
	if s != null:
		match s.kind:
			"chest":
				game.ui.open_chest(s)
			"campfire":
				game.campfire_used()
			_:
				game.ui.open()
		return true
	return false


func _search_crate(crate: Node2D) -> bool:
	var loot: Dictionary = crate.open()
	if loot.is_empty():
		return false
	var parts: Array[String] = []
	var left_behind := false
	for id in loot:
		var added: int = inventory.add(id, loot[id])
		if added > 0:
			parts.append("%d %s" % [added, Items.display_name(id)])
		if added < loot[id]:
			left_behind = true
	var msg := "Found " + ", ".join(parts) if not parts.is_empty() else "Found nothing useful"
	if left_behind:
		msg += "  (inventory full, some left behind)"
	game.hud.show_message(msg, 2.5)
	return true


## Throws away a whole stack. It lands in a bag at your feet, so you can pick it up again.
func discard(id: String) -> bool:
	var amount: int = inventory.count(id)
	if dead or amount <= 0:
		return false
	inventory.set_count(id, 0)
	if id == melee_weapon:
		unequip("melee")
	if id == ranged_weapon:
		unequip("ranged")
	game.spawn_crate(global_position, true, {id: amount})
	game.hud.show_message("Dropped %d %s" % [amount, Items.display_name(id)], 1.5)
	return true


## H key: use a bandage, or a medkit if you have no bandages.
func heal() -> bool:
	if inventory.count("bandage") > 0:
		return heal_with("bandage")
	return heal_with("medkit")


func heal_with(id: String) -> bool:
	if dead or health >= max_health or not inventory.remove(id, 1):
		return false
	health = minf(health + (HEAL_BANDAGE if id == "bandage" else HEAL_MEDKIT), max_health)
	return true


# ---------------------------------------------------------------- crafting and building

## Chests close to the workbench you are standing at. Crafting there can use
## their items as well as your own. Empty if you are not at a workbench.
func nearby_chests() -> Array:
	var bench: Node2D = game.nearest_structure(global_position, WORKBENCH_RANGE, "workbench")
	if bench == null:
		return []
	var chests := []
	for s in get_tree().get_nodes_in_group("structures"):
		if s.kind == "chest" and s.global_position.distance_to(bench.global_position) <= CHEST_RANGE:
			chests.append(s)
	return chests


## How many of an item you can use for crafting right now (yours + nearby chests).
func material_count(id: String) -> int:
	var total: int = inventory.count(id)
	for c in nearby_chests():
		total += c.storage.count(id)
	return total


func can_afford(cost: Dictionary) -> bool:
	for id in cost:
		if material_count(id) < cost[id]:
			return false
	return true


## Takes the cost from your inventory first, then from nearby chests.
func pay(cost: Dictionary) -> void:
	var chests := nearby_chests()
	for id in cost:
		var left: int = cost[id]
		var mine := mini(left, inventory.count(id))
		inventory.remove(id, mine)
		left -= mine
		for c in chests:
			if left <= 0:
				break
			var take := mini(left, c.storage.count(id))
			c.storage.remove(id, take)
			left -= take


func near_workbench() -> bool:
	return game.nearest_structure(global_position, WORKBENCH_RANGE, "workbench") != null


func can_craft(id: String) -> bool:
	var r: Dictionary = Items.recipe(id)
	if r.is_empty() or dead:
		return false
	if r["bench"] and not near_workbench():
		return false
	if not can_afford(r["cost"]):
		return false
	if r.has("slots"):
		return inventory.max_slots == r["from_slots"]   # upgrades go in order
	return inventory.space_for(id) >= r["amount"]


func craft(id: String) -> bool:
	if not can_craft(id):
		return false
	var r: Dictionary = Items.recipe(id)
	pay(r["cost"])
	if r.has("slots"):
		inventory.max_slots = r["slots"]   # backpacks are worn right away
	else:
		inventory.add(id, r["amount"])
	game.floating_text(global_position + Vector2(0, -30), "Crafted %s" % Items.display_name(id), Color(0.6, 1, 0.6))
	return true


## Puts a chest or workbench from your inventory into the world.
func place_structure(id: String, pos: Vector2) -> bool:
	pos = game.snap_for(id, pos)
	if dead or inventory.count(id) <= 0 or not game.can_place(id, pos):
		return false
	inventory.remove(id, 1)
	game.spawn_structure(id, pos)
	game.cancel_placing()
	action_block = 0.25
	return true


func take_damage(amount: float, flash: bool = true) -> void:
	if dead or dodge_timer > 0.0:
		return
	health -= amount
	if flash:
		hurt_flash = 0.2
		if using_controller:
			for pad in Input.get_connected_joypads():
				Input.start_joy_vibration(pad, 0.4, 0.7, 0.18)
	if health <= 0.0:
		health = 0.0
		dead = true
		queue_redraw()
		died.emit()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var tint := Color(1, 1, 1)
	if hurt_flash > 0.0:
		tint = Color(1.6, 0.55, 0.5)
	if dead:
		tint = Color(0.45, 0.45, 0.45)
	if sprite != null:
		sprite.rotation = aim_dir.angle()
		sprite.modulate = tint
	if dodge_timer > 0.0:
		# A faded copy trailing behind the roll.
		draw_set_transform(-dodge_dir * 16.0, aim_dir.angle())
		draw_texture(TEX_BODY, -TEX_BODY.get_size() / 2, Color(tint, 0.3))
		draw_set_transform(Vector2.ZERO)
	if swing_flash > 0.0:
		_draw_swing()
	else:
		_draw_ranged_weapon()
	# On a controller there is no mouse cursor, so show where you are aiming.
	if using_controller and not dead:
		var mark := aim_dir * 90.0
		draw_arc(mark, 7.0, 0.0, TAU, 16, Color(1, 1, 1, 0.55), 2.0)
		draw_circle(mark, 2.0, Color(1, 1, 1, 0.7))
	if muzzle_flash > 0.0:
		var m := aim_dir * (radius + 16.0)
		draw_circle(m, 6.0, Color(1, 0.6, 0.2, 0.8))
		draw_circle(m, 3.5, Color(1, 0.92, 0.6))
	if shock_flash > 0.0:
		var k := shock_flash / 0.3
		draw_arc(Vector2.ZERO, SHOCK_RADIUS * (1.0 - k), 0.0, TAU, 40, Color(0.6, 0.8, 1.0, k), 6.0)


## The ranged weapon held in front of you (grip at your hands, about 10 px forward).
func _draw_ranged_weapon() -> void:
	if not WEAPON_TEX.has(ranged_weapon):
		return
	var tex: Texture2D = WEAPON_TEX[ranged_weapon]
	var at := {"pistol": Vector2(8, 0), "bow": Vector2(8, 0), "crossbow": Vector2(2, 0)}
	var p: Vector2 = at.get(ranged_weapon, Vector2(8, 0))
	draw_set_transform(Vector2.ZERO, aim_dir.angle())
	draw_texture(tex, p - Vector2(0, tex.get_height() / 2.0))
	draw_set_transform(Vector2.ZERO)


## The melee weapon sweeping through its arc during a swing.
func _draw_swing() -> void:
	var w := melee_stats()
	var reach: float = w["range"]
	var arc: float = w["arc"]
	var a := aim_dir.angle()
	var t := 1.0 - swing_flash / 0.15        # 0 -> 1 over the swing
	if melee_weapon == "spear":
		# A straight thrust forward. The spear tip ends 10 px past the thrust point.
		var tip_d := lerpf(radius, reach, sin(t * PI)) + 10.0
		var tex: Texture2D = WEAPON_TEX["spear"]
		draw_set_transform(Vector2.ZERO, a)
		draw_texture(tex, Vector2(tip_d - tex.get_width(), -tex.get_height() / 2.0))
		draw_set_transform(Vector2.ZERO)
		return
	draw_arc(Vector2.ZERO, reach * 0.8, a - arc, a + arc, 16, Color(1, 1, 1, 0.35), 3.0)
	var ang := a - arc + 2.0 * arc * t
	var dir := Vector2.from_angle(ang)
	if melee_weapon == "fists" or not WEAPON_TEX.has(melee_weapon):
		var fist := dir * (radius + 6.0)
		draw_circle(fist, 6.5, Color(0.08, 0.08, 0.1))
		draw_circle(fist, 5.0, Color(0.71, 0.55, 0.42))
		return
	# The weapon runs from the hands out to the end of its reach.
	var tex: Texture2D = WEAPON_TEX[melee_weapon]
	var length := reach * 0.85 + 4.0
	var h := tex.get_height() * length / tex.get_width()
	draw_set_transform(Vector2.ZERO, ang)
	draw_texture_rect(tex, Rect2(6.0, -h / 2.0, length - 6.0, h), false)
	draw_set_transform(Vector2.ZERO)
