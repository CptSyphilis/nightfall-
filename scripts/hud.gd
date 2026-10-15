extends Control
## On-screen info: health, hunger, ammo, cooldowns, clock and messages.
## Everything is drawn with simple shapes and the built-in font.

const Items := preload("res://scripts/items.gd")
const Buildings := preload("res://scripts/buildings.gd")

const PROMPTS := {
	"keyboard": {"build": "B", "demolish": "right click", "choose": "wheel / 1-5", "melee": "right click", "interact": "E", "restart": "Enter", "shoot": "left click", "cancel": "right click", "inventory": "Tab"},
	"xbox":     {"build": "D-pad right", "demolish": "Y", "choose": "LB / RB", "melee": "RB", "interact": "X", "restart": "A", "shoot": "RT", "cancel": "B", "inventory": "Menu"},
	"ps":       {"build": "D-pad right", "demolish": "Triangle", "choose": "L1 / R1", "melee": "R1", "interact": "Square", "restart": "Cross", "shoot": "R2", "cancel": "Circle", "inventory": "Options"},
}

const CONTROL_HINTS := {
	"keyboard": "WASD move   LMB ranged   RMB melee / gather   Space dodge   Q shockwave   R reload   E use   F eat   H heal   Tab character",
	"xbox": "LS move   RS aim   RT ranged   RB melee / gather   A dodge   LB shockwave   Y reload   X use   D-pad up eat / down heal   Menu character",
	"ps": "L-stick move   R-stick aim   R2 ranged   R1 melee / gather   Cross dodge   L1 shockwave   Triangle reload   Square use   D-pad up eat / down heal   Options character",
}

var game: Node
var font: Font
var _message := ""
var _message_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func show_message(text: String, duration: float = 3.5) -> void:
	_message = text
	_message_time = duration


func _process(delta: float) -> void:
	_message_time = maxf(_message_time - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if game == null or game.player == null:
		return
	var p = game.player
	var w := size.x
	var h := size.y

	# Left: survival stats.
	_bar(Vector2(20, 20), "Health", p.health / p.max_health, Color(0.8, 0.2, 0.2))
	_bar(Vector2(20, 50), "Hunger", p.hunger / 100.0, Color(0.85, 0.6, 0.2))
	var inv = p.inventory
	_text(Vector2(20, 100), _ranged_line(p))
	_text(Vector2(20, 124), "Melee: %s" % ("Fists" if p.melee_weapon == "fists" else Items.display_name(p.melee_weapon)))
	_text(Vector2(20, 148), "Food %d   Bandages %d   Medkits %d" % [p.food, inv.count("bandage"), inv.count("medkit")])
	_text(Vector2(20, 172), "Dodge %s    Shockwave %s" % [_cd(p.dodge_cd), _cd(p.shock_cd)])
	_text(Vector2(20, 196), "Wood %d   Stone %d   Scrap %d   Cloth %d" % [inv.count("wood"), inv.count("stone"), inv.count("scrap"), inv.count("cloth")], 14, Color(1, 1, 1, 0.75))

	# Right: clock and kills.
	if game.is_night:
		_text(Vector2(w - 260, 34), "NIGHT %d   %ds" % [game.day, int(ceil(game.time_left()))], 22, Color(0.6, 0.7, 1.0))
		_text(Vector2(w - 260, 60), "Survive until dawn", 14, Color(1, 1, 1, 0.75))
	else:
		_text(Vector2(w - 260, 34), "Day %d" % game.day, 22, Color(1, 0.95, 0.7))
		var tip := "Use the campfire to start the night" if game.campfire() != null \
			else "Build a campfire (%s) to start the night" % prompt("build")
		_text(Vector2(w - 260, 60), tip, 14, Color(1, 1, 1, 0.75))
	_text(Vector2(w - 260, 84), "Kills %d" % game.kills)
	var lives_color := Color(1, 0.45, 0.35) if game.lives <= 3 else Color(1, 0.8, 0.5)
	_text(Vector2(w - 260, 108), "Campfire lives  %d / %d" % [game.lives, game.CAMPFIRE_LIVES], 16, lives_color)

	# Prompt when standing next to something you can use.
	if not p.dead and not game.ui_open:
		var what := ""
		if game.nearest_crate(p.global_position, 48.0) != null:
			what = "search"
		else:
			var s = game.nearest_usable(p.global_position, 64.0)
			if s != null:
				match s.kind:
					"chest":
						what = "open chest"
					"campfire":
						what = "" if game.is_night else "start the night"
					_:
						what = "use workbench"
		if what != "":
			_text_centered(h * 0.62, prompt("interact") + "  " + what, 18, Color(1, 1, 0.8))

	# Big message at the top.
	if _message_time > 0.0:
		var a := clampf(_message_time, 0.0, 1.0)
		_text_centered(110, _message, 24, Color(1, 1, 1, a))

	if game.show_input_debug:
		_draw_input_debug(p)

	# Controls reminder for whatever you are playing with.
	if game.build != null and game.build.active and not game.ui_open:
		_draw_build_bar(p, w, h)
	else:
		_text(Vector2(20, h - 16), CONTROL_HINTS[p.prompt_style()] + "   %s build" % prompt("build"), 14, Color(1, 1, 1, 0.55))

	if game.game_over:
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.65))
		_text_centered(h / 2 - 70, game.lose_reason, 22, Color(1, 0.8, 0.7))
		_text_centered(h / 2 - 30, "GAME OVER", 48, Color(0.9, 0.2, 0.2))
		_text_centered(h / 2 + 15, "Survived to day %d with %d kills" % [game.day, game.kills], 20)
		_text_centered(h / 2 + 50, "Press %s to try again" % prompt("restart"), 18, Color(1, 1, 1, 0.8))


## Build mode: the row of pieces at the bottom, what they cost, and the controls.
func _draw_build_bar(p, w: float, h: float) -> void:
	var slot := Vector2(170, 62)
	var gap := 8.0
	var n := Buildings.ORDER.size()
	var x0 := (w - (slot.x * n + gap * (n - 1))) / 2.0
	var y0 := h - 112.0
	for i in n:
		var kind: String = Buildings.ORDER[i]
		var r := Rect2(Vector2(x0 + i * (slot.x + gap), y0), slot)
		var chosen: bool = kind == game.build.selected
		var afford: bool = p.inventory.has_all(Buildings.cost(kind))
		draw_rect(r, Color(0.05, 0.05, 0.06, 0.85))
		draw_rect(r, Color(1, 0.85, 0.4) if chosen else Color(1, 1, 1, 0.25), false, 3.0 if chosen else 1.0)
		_text(r.position + Vector2(8, 18), "%d  %s" % [i + 1, Buildings.display_name(kind)], 15, Color(1, 0.92, 0.75) if chosen else Color.WHITE)
		_text(r.position + Vector2(8, 37), Items.describe_cost(Buildings.cost(kind)), 13, Color(0.7, 1, 0.7) if afford else Color(1, 0.45, 0.4))
		_text(r.position + Vector2(8, 54), Buildings.INFO[kind], 11, Color(1, 1, 1, 0.6))
	var hint := "BUILD MODE   %s build (hold to drag)   %s demolish   %s choose   %s exit" % [
		prompt("shoot"), prompt("demolish"), prompt("choose"), prompt("build")]
	_text_centered(h - 18.0, hint, 15, Color(1, 0.92, 0.75))


## F3 input checker: shows what the controller sends, to fix button mapping problems.
func _draw_input_debug(p) -> void:
	var lines: Array[String] = ["INPUT CHECKER (F3 to hide)"]
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		lines.append("No controller detected")
	for d in pads:
		var known := "standard layout" if Input.is_joy_known(d) else "UNKNOWN layout"
		lines.append("Pad %d: %s  (%s)" % [d, p.pad_name(d), known])
	lines.append("Last input: %s" % p.last_pad_input)
	lines.append("R2/RT axis: %.2f   shoot pressed: %s" % [
		Input.get_joy_axis(maxi(p.last_pad_device, 0), JOY_AXIS_TRIGGER_RIGHT),
		"YES" if Input.is_action_pressed("shoot") else "no"])
	if OS.has_feature("web"):
		lines.append("Browser R2/RT: %.2f" % p.web_r2)
	lines.append("Prompts: %s" % p.prompt_style())
	var y := 240.0
	draw_rect(Rect2(14, y - 22, 560, 22 * lines.size() + 12), Color(0, 0, 0, 0.75))
	for line in lines:
		_text(Vector2(24, y), line, 15, Color(0.6, 1.0, 0.6))
		y += 22.0


## Button name for an action, matching the device in use.
## Example: prompt("interact") = "E", "X" (Xbox) or "Square" (PlayStation).
func prompt(action: String) -> String:
	var style: String = game.player.prompt_style() if game and game.player else "keyboard"
	return PROMPTS[style].get(action, action)


func _bar(pos: Vector2, label: String, fill: float, color: Color) -> void:
	var bw := 220.0
	draw_rect(Rect2(pos, Vector2(bw, 20)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(pos + Vector2(2, 2), Vector2((bw - 4) * clampf(fill, 0.0, 1.0), 16)), color)
	_text(pos + Vector2(8, 15), label, 14)


func _text(pos: Vector2, text: String, font_size: int = 16, color: Color = Color.WHITE) -> void:
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, color.a * 0.8))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _text_centered(y: float, text: String, font_size: int = 16, color: Color = Color.WHITE) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(Vector2((size.x - tw) / 2, y), text, font_size, color)


func _ranged_line(p) -> String:
	if p.ranged_weapon == "":
		return "Ranged: none"
	var name := Items.display_name(p.ranged_weapon)
	if p.ranged_weapon == "pistol":
		var reload_txt := "  reloading..." if p.reload_timer > 0.0 else ""
		return "%s  %d / %d%s" % [name, p.ammo_in_mag, p.ammo_reserve, reload_txt]
	return "%s  arrows %d" % [name, p.inventory.count("arrow")]


func _cd(t: float) -> String:
	return "ready" if t <= 0.0 else "%.1fs" % t
