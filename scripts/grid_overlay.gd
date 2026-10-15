extends Node2D
## Faint grid lines shown while building or placing something,
## so you can see exactly where walls and furniture will line up.

var game: Node


func _process(_delta: float) -> void:
	var on: bool = game.build != null and (game.build.active or game.placing != "")
	visible = on and not game.game_over
	if visible:
		queue_redraw()


func _draw() -> void:
	var cell: float = game.CELL
	# Only draw the part of the map that is on screen.
	var view := get_canvas_transform().affine_inverse() * get_viewport_rect()
	var x0 := floorf(view.position.x / cell) * cell
	var y0 := floorf(view.position.y / cell) * cell
	var color := Color(1, 1, 1, 0.07)
	var x := x0
	while x <= view.end.x:
		draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), color, 1.0)
		x += cell
	var y := y0
	while y <= view.end.y:
		draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), color, 1.0)
		y += cell
	# A soft ring showing how far from you that you can build.
	draw_arc(game.player.global_position, game.build.BUILD_RANGE, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 2.0)
