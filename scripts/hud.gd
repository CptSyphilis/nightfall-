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

	if not p.dead and not game.game_over:
		_draw_danger_border(p, w, h)

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
		_text_centered(110, _message, 20, Color(1, 1, 1, a))   # smaller so it never runs into the corner text

	_draw_campfire_pointer()

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


## A red glow around the screen edge that pulses when health is low or you are
## starving, faster and stronger the worse it gets, and flashes when you get hit.
func _draw_danger_border(p, w: float, h: float) -> void:
	var danger := 0.0
	var low_health: float = p.max_health * 0.35
	if p.health < low_health:
		danger = 0.4 + 0.6 * (1.0 - p.health / low_health)
	if p.hunger < 20.0:
		danger = maxf(danger, 0.3 + 0.5 * (1.0 - p.hunger / 20.0))   # 0.8 once starving
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.55 + 0.45 * sin(t * (4.0 + 5.0 * danger))
	var a := danger * pulse * 0.55
	a = maxf(a, p.hurt_flash / 0.2 * 0.5)   # a quick flash on every hit
	if a <= 0.01:
		return
	var edge := Color(0.85, 0.05, 0.05, a)
	var clear := Color(0.85, 0.05, 0.05, 0.0)
	var d := minf(w, h) * 0.12   # how far the glow reaches in
	var o := [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]
	var i := [Vector2(d, d), Vector2(w - d, d), Vector2(w - d, h - d), Vector2(d, h - d)]
	for k in 4:
		var n := (k + 1) % 4
		draw_polygon(PackedVector2Array([o[k], o[n], i[n], i[k]]), PackedColorArray([edge, edge, clear, clear]))


## An arrow at the edge of the screen pointing to the campfire when you can't see it.
func _draw_campfire_pointer() -> void:
	var fire = game.campfire()
	if fire == null or game.game_over:
		return
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * fire.global_position
	var info := campfire_pointer(screen_pos, size, 40.0)
	if not info["show"]:
		return
	var at: Vector2 = info["pos"]
	var dir := Vector2.from_angle(info["angle"])
	var side := dir.orthogonal()
	var color := Color(1.0, 0.6, 0.25, 0.9) if not game.is_night else Color(1.0, 0.4, 0.2, 0.95)
	draw_colored_polygon(PackedVector2Array([at + dir * 16.0, at - dir * 8.0 + side * 10.0, at - dir * 8.0 - side * 10.0]), color)
	var dist := int(game.player.global_position.distance_to(fire.global_position) / 32.0)
	var label := "Campfire %dm" % dist
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(at - dir * 26.0 - Vector2(tw / 2.0, -4.0), label, 13, color)


## Where to draw the campfire arrow. If the campfire is on screen there is no arrow.
## Otherwise the arrow sits on the screen edge (margin pixels in), on the line from
## the screen center to the campfire, and points at it.
static func campfire_pointer(screen_pos: Vector2, screen_size: Vector2, margin: float) -> Dictionary:
	var inner := Rect2(Vector2(margin, margin), screen_size - Vector2(margin, margin) * 2.0)
	if Rect2(Vector2.ZERO, screen_size).has_point(screen_pos):
		return {"show": false}
	var center := screen_size / 2.0
	var d := screen_pos - center
	# Shrink the line until it touches the inner rectangle.
	var half := inner.size / 2.0
	var t := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
	return {"show": true, "pos": center + d * t, "angle": d.angle()}


## Build mode: the row of pieces at the bottom, what they cost, and the controls.
func _draw_build_bar(p, w: float, h: float) -> void:
	var gap := 8.0
	var n := Buildings.ORDER.size()
	# Slots shrink when there are many pieces, so the row always fits the screen.
	var slot := Vector2(minf(170.0, (w - 40.0 - gap * (n - 1)) / n), 62)
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
	var hint := "BUILD MODE   %s build (hold to drag)   %s demolish (hold to drag)   %s choose   %s exit" % [
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
