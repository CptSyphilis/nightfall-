extends RefCounted
## The map as a grid of 32x32 squares, used by zombies to find a way around things.
## A square is "solid" when a zombie could not stand there: inside a ruin,
## a tree, a rock, or something the player built.
## Godot's AStarGrid2D does the actual path finding.

const CELL := 32.0
const CLEARANCE := 14.0   # roughly a zombie's radius, so paths don't hug walls too tightly

var astar := AStarGrid2D.new()


func build(world_size: Vector2, ruins: Array[Rect2], game: Node) -> void:
	astar.region = Rect2i(0, 0, ceili(world_size.x / CELL), ceili(world_size.y / CELL))
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL, CELL) / 2.0      # path points are square centers
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	# update() keeps old solid squares when the map size is unchanged,
	# so clear everything before marking what is solid now.
	astar.fill_solid_region(astar.region, false)
	for r in ruins:
		_block_rect(r)
	for res in game.get_tree().get_nodes_in_group("resources"):
		if not res.depleted:
			_block_circle(res.global_position, res.radius)
	for s in game.get_tree().get_nodes_in_group("structures"):
		add_structure(s)


## Marks one new structure as solid (quick, no full rebuild needed).
func add_structure(s: Node2D) -> void:
	if s.blocks_path():
		_block_rect(s.rect())


func to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) * CELL + Vector2(CELL, CELL) / 2.0


func is_free(pos: Vector2) -> bool:
	var c := to_cell(pos)
	return astar.is_in_boundsv(c) and not astar.is_point_solid(c)


## A list of points from `from` to `to` that goes around obstacles.
## If `to` cannot be reached, the path ends as close to it as possible.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := _nearest_free(to_cell(from))
	var b := _nearest_free(to_cell(to))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	return astar.get_point_path(a, b, true)


# ---------------------------------------------------------------- helpers

## Blocks every square whose center is inside the rectangle (plus clearance).
func _block_rect(rect: Rect2) -> void:
	var g := rect.grow(CLEARANCE)
	var a := to_cell(g.position)
	var b := to_cell(g.end)
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			var c := Vector2i(x, y)
			if astar.is_in_boundsv(c) and g.has_point(cell_center(c)):
				astar.set_point_solid(c, true)


func _block_circle(center: Vector2, r: float) -> void:
	var reach := r + CLEARANCE
	var a := to_cell(center - Vector2(reach, reach))
	var b := to_cell(center + Vector2(reach, reach))
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			var c := Vector2i(x, y)
			if astar.is_in_boundsv(c) and cell_center(c).distance_to(center) <= reach:
				astar.set_point_solid(c, true)


## The closest walkable square (a zombie pressed against a wall may be on a solid one).
## Returns (-1, -1) if nothing is free nearby.
func _nearest_free(c: Vector2i) -> Vector2i:
	for ring in 4:
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var n := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(n) and not astar.is_point_solid(n):
					return n
	return Vector2i(-1, -1)
