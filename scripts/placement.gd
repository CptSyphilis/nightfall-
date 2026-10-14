extends Node2D
## Placement mode: shows a green (ok) or red (blocked) outline where the
## structure will go.
## Mouse: it follows the cursor. Left click places, right click or Esc cancels.
## Controller: it sits in front of you where you aim. RT / R2 places, B / Circle or RB / R1 cancels.

const StructureScript := preload("res://scripts/structure.gd")
const PLACE_RANGE := 150.0

var game: Node


func _ready() -> void:
	z_index = 10


func _process(_delta: float) -> void:
	visible = game.placing != ""
	if not visible:
		return
	var p = game.player
	if p.using_controller:
		global_position = game.snap(p.global_position + p.aim_dir * 80.0)
	else:
		global_position = game.snap(get_global_mouse_position())
	queue_redraw()


func is_valid() -> bool:
	if game.placing == "":
		return false
	if global_position.distance_to(game.player.global_position) > PLACE_RANGE:
		return false
	return game.can_place(game.placing, global_position)


func _unhandled_input(event: InputEvent) -> void:
	if game.placing == "":
		return
	# "shoot" = left click or RT/R2, "melee" = right click or RB/R1.
	if event.is_action_pressed("shoot"):
		if is_valid():
			game.player.place_structure(game.placing, global_position)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("melee") or event.is_action_pressed("close_ui"):
		game.cancel_placing()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if game.placing == "":
		return
	var size: Vector2 = StructureScript.SIZES[game.placing]
	var ok := is_valid()
	var c := Color(0.3, 1.0, 0.4) if ok else Color(1.0, 0.3, 0.3)
	draw_rect(Rect2(-size / 2, size), Color(c, 0.25))
	draw_rect(Rect2(-size / 2, size), c, false, 2.0)
	var font := ThemeDB.fallback_font
	var hint: String
	if not ok:
		hint = "Can't place here"
	else:
		hint = game.hud.prompt("shoot") + " place   " + game.hud.prompt("cancel") + " cancel"
	var w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(-w / 2, -size.y / 2 - 10), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
