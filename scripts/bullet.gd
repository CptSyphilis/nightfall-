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
		draw_line(Vector2.ZERO, back, Color(0.6, 0.45, 0.25), 2.0)
		draw_line(Vector2.ZERO, -direction * 5.0, Color(0.8, 0.8, 0.85), 3.0)          # tip
		draw_line(back, back + (-direction).rotated(0.5) * 6.0, Color(0.9, 0.9, 0.9), 2.0)   # feathers
		draw_line(back, back + (-direction).rotated(-0.5) * 6.0, Color(0.9, 0.9, 0.9), 2.0)
	else:
		draw_line(Vector2.ZERO, -direction * 14.0, Color(1, 0.9, 0.5), 2.0)
