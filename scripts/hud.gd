extends Control
## On-screen info: health, hunger, ammo, cooldowns, clock and messages.
## Everything is drawn with simple shapes and the built-in font.

const Items := preload("res://scripts/items.gd")

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
	var phase := "NIGHT" if game.is_night else "Day"
	var clock := "%s %d   %ds" % [phase, game.day, int(ceil(game.time_left()))]
	var clock_color := Color(0.6, 0.7, 1.0) if game.is_night else Color(1, 0.95, 0.7)
	_text(Vector2(w - 260, 34), clock, 22, clock_color)
	_text(Vector2(w - 260, 60), "Kills %d" % game.kills)

	# Prompt when standing next to something you can use.
	if not p.dead and not game.ui_open:
		var prompt := ""
		if game.nearest_crate(p.global_position, 48.0) != null:
			prompt = "E  search"
		else:
			var s = game.nearest_structure(p.global_position, 64.0)
			if s != null:
				prompt = "E  open chest" if s.kind == "chest" else "E  use workbench"
		if prompt != "":
			_text_centered(h * 0.62, prompt, 18, Color(1, 1, 0.8))

	# Big message at the top.
	if _message_time > 0.0:
		var a := clampf(_message_time, 0.0, 1.0)
		_text_centered(110, _message, 24, Color(1, 1, 1, a))

	# Controls reminder.
	_text(Vector2(20, h - 16), "WASD move   LMB ranged   RMB melee / gather   Space dodge   Q shockwave   R reload   E use   F eat   H heal   Tab character", 14, Color(1, 1, 1, 0.55))

	if game.game_over:
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.65))
		_text_centered(h / 2 - 30, "YOU DIED", 48, Color(0.9, 0.2, 0.2))
		_text_centered(h / 2 + 15, "Survived to day %d with %d kills" % [game.day, game.kills], 20)
		_text_centered(h / 2 + 50, "Press Enter to try again", 18, Color(1, 1, 1, 0.8))


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
