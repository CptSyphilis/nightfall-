extends Node2D
## Build mode (B on keyboard, D-pad right on a controller).
## Shows a preview square on the grid. Hold the build button and move
## to draw a line of walls, like building a maze in a Warcraft 3 "Maul" map.
## Hold the demolish button and move to remove a whole line the same way.
##
##                 Keyboard + mouse     Xbox          PlayStation
##   build         left click (hold)    RT (hold)     R2 (hold)
##   demolish      right click (hold)   Y (hold)      Triangle (hold)
##   choose piece  mouse wheel / 1-5    LB / RB       L1 / R1
##   exit          B or Esc             D-pad right   D-pad right (or B / Circle)

const Buildings := preload("res://scripts/buildings.gd")
const StructureScript := preload("res://scripts/structure.gd")
const BUILD_RANGE := 220.0

var game: Node
var active := false
var selected := "wood_wall"
const NO_CELL := Vector2i(-99999, -99999)
var _last_cell := NO_CELL          # last square built on while holding build
var _last_remove_cell := NO_CELL   # last square demolished while holding demolish


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
	_last_cell = NO_CELL
	_last_remove_cell = NO_CELL


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
	var p = game.player
	var build_held: bool = p.controls_enabled and (Input.is_action_pressed("shoot") or p.web_r2 > 0.5)
	var remove_held: bool = p.controls_enabled and Input.is_action_pressed("demolish")
	drag(global_position, build_held, remove_held)
	queue_redraw()


## Hold build or demolish and move: it builds (or removes) once on every
## new square the preview passes over. Each square is only done once per drag.
func drag(pos: Vector2, build_held: bool, remove_held: bool) -> void:
	var cell: Vector2i = game.nav.to_cell(pos)
	if build_held:
		if cell != _last_cell and in_range(pos) and game.build_piece(selected, pos):
			_last_cell = cell
	else:
		_last_cell = NO_CELL
	if remove_held and not build_held:
		if cell != _last_remove_cell and in_range(pos):
			_last_remove_cell = cell   # even if empty, so we don't retry every frame
			game.demolish_at(pos)
	else:
		_last_remove_cell = NO_CELL


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
		get_viewport().set_input_as_handled()   # demolishing happens in drag()
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
