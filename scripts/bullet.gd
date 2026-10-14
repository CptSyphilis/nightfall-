extends Node2D
## A bullet. Each physics frame it casts a short ray along its path,
## so it can never skip through a thin wall or a zombie.

const SPEED := 1100.0
const LIFETIME := 0.8

var direction := Vector2.RIGHT
var damage := 45.0
var _life := LIFETIME


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	var step := direction * SPEED * delta
	# Layer 1 = walls, layer 3 (value 4) = zombies.
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, 1 | 4)
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
	draw_line(Vector2.ZERO, -direction * 14.0, Color(1, 0.9, 0.5), 2.0)
