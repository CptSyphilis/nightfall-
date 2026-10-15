extends Node2D
## Build mode (B on keyboard, D-pad right on a controller).
## Shows a preview square on the grid. Hold the build button and move
## to draw a line of walls, like building a maze in a Warcraft 3 "Maul" map.
##
##                 Keyboard + mouse     Xbox          PlayStation
##   build         left click (hold)    RT (hold)     R2 (hold)
##   demolish      right click          Y             Triangle
##   choose piece  mouse wheel / 1-5    LB / RB       L1 / R1
##   exit          B or Esc             D-pad right   D-pad right (or B / Circle)

const Buildings := preload("res://scripts/buildings.gd")
const StructureScript := preload("res://scripts/structure.gd")
const BUILD_RANGE := 220.0

var game: Node
var active := false
var selected := "wood_wall"
var _last_cell := Vector2i(-99999, -99999)


func _ready() -> void:
	z_index = 10
	visible = false


func toggle() -> void:
	set_active(not active)


func set_active(on: bool) -> void:
	active = on
	if active:
		game.cancel_placing()
		game.ui.close()
		game.hud.show_message("Build mode - %s" % Buildings.display_name(selected), 1.5)
	_last_cell = Vector2i(-99999, -99999)


func select(kind: String) -> void:
	selected = kind
	game.hud.show_message(Buildings.display_name(selected), 1.0)


func cycle(step: int) -> void:
	var i := Buildings.ORDER.find(selected)
	select(Buildings.ORDER[wrapi(i + step, 0, Buildings.ORDER.size())])


## Where the preview square is: the grid cell under the mouse,
## or the cell in front of you when using a controller.
func target_position() -> Vector2:
	var p = game.player
	var spot: Vector2
	if p.using_controller:
		spot = p.global_position + p.aim_dir * 56.0
	else:
		spot = get_global_mouse_position()
	return game.nav.cell_center(game.nav.to_cell(spot))


func in_range(pos: Vector2) -> bool:
	return pos.distance_to(game.player.global_position) <= BUILD_RANGE


func _process(_delta: float) -> void:
	visible = active and not game.ui_open and not game.game_over
	if not visible:
		return
	global_position = target_position()
	# Hold the build button to keep placing as the preview moves to new squares.
	var p = game.player
	var held: bool = p.controls_enabled and (Input.is_action_pressed("shoot") or p.web_r2 > 0.5)
	if held:
		var cell: Vector2i = game.nav.to_cell(global_position)
		if cell != _last_cell and in_range(global_position) and game.build_piece(selected, global_position):
			_last_cell = cell
	else:
		_last_cell = Vector2i(-99999, -99999)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if game.game_over or game.ui_open:
		return
	if event.is_action_pressed("build_mode"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if event.is_action_pressed("close_ui"):
		set_active(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("demolish"):
		if in_range(global_position):
			game.demolish_at(global_position)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_next"):
		cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_prev"):
		cycle(-1)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.physical_keycode - KEY_1
		if n >= 0 and n < Buildings.ORDER.size():
			select(Buildings.ORDER[n])
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var size := Vector2(32, 32)
	var ok: bool = in_range(global_position) and game.can_build(selected, global_position) \
		and game.player.inventory.has_all(Buildings.cost(selected))
	var c := Color(0.3, 1.0, 0.4) if ok else Color(1.0, 0.3, 0.3)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	modulate = Color(1, 1, 1, 0.7)
	StructureScript.draw_piece(self, selected, size)
	draw_rect(Rect2(-size / 2, size), Color(c, 0.25))
	draw_rect(Rect2(-size / 2, size), c, false, 2.0)
