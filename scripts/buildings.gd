extends RefCounted
## Everything you can build in build mode (B).
## Pieces are paid for straight from your inventory and snap to a 32x32 grid,
## the same grid zombies use to find their way. That makes maze building work:
## zombies always take the open route, so a longer maze = more time to shoot them.
## If there is no open route at all, they smash through the walls instead.
##
## To add a piece: add it to PIECES and ORDER, then give it a look in structure.gd.

const PIECES := {
	"campfire":   {"name": "Campfire",    "cost": {"wood": 6, "stone": 4},             "hp": 1.0},
	"wood_wall":  {"name": "Wood wall",   "cost": {"wood": 2},                         "hp": 120.0},
	"stone_wall": {"name": "Stone wall",  "cost": {"stone": 2, "wood": 1},             "hp": 350.0},
	"door":       {"name": "Door",        "cost": {"wood": 4, "scrap": 1},             "hp": 160.0},
	"spikes":     {"name": "Spike trap",  "cost": {"wood": 3, "stone": 1},             "hp": 80.0},
	"tower":      {"name": "Arrow tower", "cost": {"wood": 10, "stone": 6, "scrap": 3}, "hp": 300.0},
	"concrete_floor": {"name": "Concrete floor", "cost": {"concrete": 1},          "hp": 500.0},
}

const ORDER := ["campfire", "wood_wall", "stone_wall", "door", "spikes", "tower", "concrete_floor"]

## What each piece does, shown in build mode.
const INFO := {
	"campfire": "Starts the night. Defend it! Only one",
	"wood_wall": "Cheap wall for mazes",
	"stone_wall": "Tough wall",
	"door": "You walk through, zombies don't",
	"spikes": "Hurts and slows zombies walking over it",
	"tower": "Shoots zombies by itself",
	"concrete_floor": "Floor for your base. Build walls and chests on top",
}


## Floors lie under everything: you can build walls, traps and chests on top,
## and nobody bumps into them.
static func is_floor(kind: String) -> bool:
	return kind == "concrete_floor"


static func is_piece(kind: String) -> bool:
	return PIECES.has(kind)


static func display_name(kind: String) -> String:
	return PIECES[kind]["name"]


static func cost(kind: String) -> Dictionary:
	return PIECES[kind]["cost"]


## Half the materials back (rounded down) when you demolish a piece.
static func refund(kind: String) -> Dictionary:
	var back := {}
	for id in cost(kind):
		var n: int = cost(kind)[id] / 2
		if n > 0:
			back[id] = n
	return back
