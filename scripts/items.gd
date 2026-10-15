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
	"arrow":     {"name": "Arrows",      "stack": 50,  "color": Color(0.85, 0.75, 0.55)},
	"concrete":  {"name": "Concrete",    "stack": 50,  "color": Color(0.78, 0.78, 0.76)},
	"workbench": {"name": "Workbench",   "stack": 5,   "color": Color(0.6, 0.85, 0.6), "placeable": true},
	"chest":     {"name": "Chest",       "stack": 5,   "color": Color(0.6, 0.85, 0.6), "placeable": true},
	# Backpack upgrades are used up right away: they give you more inventory slots.
	"backpack_medium": {"name": "Medium backpack", "stack": 1, "color": Color(0.7, 0.6, 0.45)},
	"backpack_large":  {"name": "Large backpack",  "stack": 1, "color": Color(0.7, 0.6, 0.45)},
	# Weapons (one per slot).
	"pistol":      {"name": "Pistol",      "stack": 1, "color": Color(0.55, 0.75, 1.0), "weapon": true},
	"bow":         {"name": "Bow",         "stack": 1, "color": Color(0.55, 0.75, 1.0), "weapon": true},
	"crossbow":    {"name": "Crossbow",    "stack": 1, "color": Color(0.55, 0.75, 1.0), "weapon": true},
	"club":        {"name": "Club",        "stack": 1, "color": Color(1.0, 0.65, 0.55), "weapon": true},
	"stone_axe":   {"name": "Stone axe",   "stack": 1, "color": Color(1.0, 0.65, 0.55), "weapon": true},
	"spear":       {"name": "Spear",       "stack": 1, "color": Color(1.0, 0.65, 0.55), "weapon": true},
	"spiked_club": {"name": "Spiked club", "stack": 1, "color": Color(1.0, 0.65, 0.55), "weapon": true},
	"machete":     {"name": "Machete",     "stack": 1, "color": Color(1.0, 0.65, 0.55), "weapon": true},
}

## The order items are listed in the inventory.
const ORDER := ["pistol", "bow", "crossbow", "club", "stone_axe", "spear", "spiked_club", "machete",
	"ammo", "arrow", "food", "bandage", "medkit", "wood", "stone", "scrap", "cloth", "concrete", "workbench", "chest"]

## Weapon stats.
## Melee:  damage, range (pixels), arc (radians each side, small = narrow thrust),
##         cooldown (seconds between swings), knockback, gather (bonus per resource type).
## Ranged: damage, cooldown, ammo (item used), magazine (0 = no reloading),
##         noise (how far zombies hear it), speed and life of the projectile.
const WEAPONS := {
	"fists":       {"type": "melee", "damage": 18.0, "range": 50.0,  "arc": 0.9,  "cooldown": 0.40, "knockback": 200.0},
	"club":        {"type": "melee", "damage": 38.0, "range": 70.0,  "arc": 1.2,  "cooldown": 0.55, "knockback": 450.0},
	"stone_axe":   {"type": "melee", "damage": 30.0, "range": 65.0,  "arc": 1.0,  "cooldown": 0.50, "knockback": 300.0, "gather": {"tree": 2}},
	"spear":       {"type": "melee", "damage": 45.0, "range": 115.0, "arc": 0.3,  "cooldown": 0.60, "knockback": 250.0},
	"spiked_club": {"type": "melee", "damage": 60.0, "range": 72.0,  "arc": 1.2,  "cooldown": 0.60, "knockback": 550.0},
	"machete":     {"type": "melee", "damage": 45.0, "range": 72.0,  "arc": 1.3,  "cooldown": 0.38, "knockback": 220.0, "gather": {"scrap": 2}},
	"pistol":   {"type": "ranged", "damage": 45.0, "cooldown": 0.18, "ammo": "ammo",  "magazine": 12, "noise": 650.0, "speed": 1100.0, "life": 0.8, "style": "bullet"},
	"bow":      {"type": "ranged", "damage": 55.0, "cooldown": 0.75, "ammo": "arrow", "magazine": 0,  "noise": 90.0,  "speed": 700.0,  "life": 0.9, "style": "arrow"},
	"crossbow": {"type": "ranged", "damage": 95.0, "cooldown": 1.40, "ammo": "arrow", "magazine": 0,  "noise": 140.0, "speed": 950.0,  "life": 0.9, "style": "arrow"},
}

## bench = true means you must stand near a placed workbench to craft it.
## slots = a backpack upgrade: crafting it sets your inventory to that many slots.
##         from_slots = the backpack you need first (upgrades go in order).
const RECIPES := [
	{"id": "backpack_medium", "amount": 1, "cost": {"cloth": 8, "wood": 2},     "bench": false, "slots": 20, "from_slots": 16},
	{"id": "backpack_large",  "amount": 1, "cost": {"cloth": 12, "scrap": 4},   "bench": true,  "slots": 24, "from_slots": 20},
	{"id": "workbench",   "amount": 1, "cost": {"wood": 10, "stone": 4},            "bench": false},
	{"id": "chest",       "amount": 1, "cost": {"wood": 12},                        "bench": false},
	{"id": "bandage",     "amount": 1, "cost": {"cloth": 2},                        "bench": false},
	{"id": "club",        "amount": 1, "cost": {"wood": 6},                         "bench": false},
	{"id": "stone_axe",   "amount": 1, "cost": {"wood": 5, "stone": 3},             "bench": false},
	{"id": "spear",       "amount": 1, "cost": {"wood": 6, "stone": 2},             "bench": false},
	{"id": "bow",         "amount": 1, "cost": {"wood": 8, "cloth": 2},             "bench": false},
	{"id": "arrow",       "amount": 5, "cost": {"wood": 2, "stone": 1},             "bench": false},
	{"id": "spiked_club", "amount": 1, "cost": {"wood": 6, "scrap": 3},             "bench": true},
	{"id": "machete",     "amount": 1, "cost": {"scrap": 5, "wood": 1},             "bench": true},
	{"id": "crossbow",    "amount": 1, "cost": {"wood": 10, "scrap": 4, "cloth": 2}, "bench": true},
	{"id": "ammo",        "amount": 6, "cost": {"scrap": 2, "stone": 1},            "bench": true},
	{"id": "medkit",      "amount": 1, "cost": {"cloth": 3, "scrap": 2},            "bench": true},
	{"id": "concrete",    "amount": 2, "cost": {"stone": 3},                        "bench": true},
]


static func is_weapon(id: String) -> bool:
	return WEAPONS.has(id) and id != "fists"


static func weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


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
