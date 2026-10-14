extends RefCounted
## All item types and crafting recipes in one place.
## To add a new item: add it to DATA and ORDER. To add a recipe: add it to RECIPES.

const DATA := {
	"ammo":      {"name": "Ammo",        "stack": 120, "color": Color(0.95, 0.85, 0.4)},
	"food":      {"name": "Canned food", "stack": 10,  "color": Color(0.95, 0.65, 0.3)},
	"bandage":   {"name": "Bandage",     "stack": 10,  "color": Color(0.95, 0.95, 0.95)},
	"medkit":    {"name": "Medkit",      "stack": 5,   "color": Color(0.95, 0.4, 0.4)},
	"wood":      {"name": "Wood",        "stack": 50,  "color": Color(0.75, 0.55, 0.35)},
	"stone":     {"name": "Stone",       "stack": 50,  "color": Color(0.7, 0.7, 0.75)},
	"scrap":     {"name": "Scrap metal", "stack": 30,  "color": Color(0.8, 0.5, 0.35)},
	"cloth":     {"name": "Cloth",       "stack": 30,  "color": Color(0.85, 0.82, 0.7)},
	"workbench": {"name": "Workbench",   "stack": 5,   "color": Color(0.6, 0.85, 0.6), "placeable": true},
	"chest":     {"name": "Chest",       "stack": 5,   "color": Color(0.6, 0.85, 0.6), "placeable": true},
}

## The order items are listed in the inventory.
const ORDER := ["ammo", "food", "bandage", "medkit", "wood", "stone", "scrap", "cloth", "workbench", "chest"]

## bench = true means you must stand near a placed workbench to craft it.
const RECIPES := [
	{"id": "workbench", "amount": 1, "cost": {"wood": 10, "stone": 4}, "bench": false},
	{"id": "chest",     "amount": 1, "cost": {"wood": 12},             "bench": false},
	{"id": "bandage",   "amount": 1, "cost": {"cloth": 2},             "bench": false},
	{"id": "ammo",      "amount": 6, "cost": {"scrap": 2, "stone": 1}, "bench": true},
	{"id": "medkit",    "amount": 1, "cost": {"cloth": 3, "scrap": 2}, "bench": true},
]


static func display_name(id: String) -> String:
	return DATA[id]["name"]


static func stack_size(id: String) -> int:
	return DATA[id]["stack"]


static func color(id: String) -> Color:
	return DATA[id]["color"]


static func is_placeable(id: String) -> bool:
	return DATA[id].get("placeable", false)


static func recipe(id: String) -> Dictionary:
	for r in RECIPES:
		if r["id"] == id:
			return r
	return {}


## Turns {"wood": 10, "stone": 4} into "10 Wood, 4 Stone".
static func describe_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		parts.append("%d %s" % [cost[id], display_name(id)])
	return ", ".join(parts)
