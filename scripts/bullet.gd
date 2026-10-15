extends Node2D
## A bullet or an arrow. Each physics frame it casts a short ray along its path,
## so it can never skip through a thin wall or a zombie.
## The weapon that fires it sets damage, speed, life and style.

var direction := Vector2.RIGHT
var damage := 45.0
var speed := 1100.0
var life := 0.8
var style := "bullet"   # "bullet" or "arrow"
var mask := 1 | 4       # what it can hit: 1 = walls/trees/rocks, 4 = zombies


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var step := direction * speed * delta
	# Layer 1 = walls/trees/rocks, layer 3 (value 4) = zombies.
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, mask)
	# Slow arrows can start a frame already inside a zombie walking into them.
	# Without this the ray would ignore that zombie and fly straight through.
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var target: Object = hit["collider"]
		if target.is_in_group("zombies"):
			target.take_damage(damage, direction * 120.0)
		queue_free()
		return
	global_position += step
	queue_redraw()


func _draw() -> void:
	if style == "arrow":
		var back := -direction * 22.0
		var side := direction.orthogonal()
		draw_line(Vector2.ZERO, back, Color(0.1, 0.07, 0.04), 3.5)
		draw_line(Vector2.ZERO, back, Color(0.66, 0.5, 0.3), 1.8)
		draw_colored_polygon(PackedVector2Array([direction * 3.0, -direction * 4.0 + side * 2.5, -direction * 4.0 - side * 2.5]), Color(0.72, 0.73, 0.76))   # tip
		draw_line(back, back - direction * 2.0 + side * 4.0, Color(0.78, 0.74, 0.66), 2.0)   # feathers
		draw_line(back, back - direction * 2.0 - side * 4.0, Color(0.78, 0.74, 0.66), 2.0)
	else:
		draw_line(Vector2.ZERO, -direction * 16.0, Color(1, 0.7, 0.3, 0.45), 3.5)   # glow trail
		draw_line(Vector2.ZERO, -direction * 12.0, Color(1, 0.92, 0.6), 1.6)
