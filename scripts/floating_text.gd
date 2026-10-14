extends Node2D
## Small text that floats up and fades out, like "+2 Wood".

var text := ""
var color := Color.WHITE
var _life := 1.2


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	position.y -= 28.0 * delta
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var a := clampf(_life / 0.5, 0.0, 1.0)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, Vector2(-w / 2 + 1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, a))
	draw_string(font, Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(color, a))
