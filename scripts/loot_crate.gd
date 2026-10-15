extends Node2D
## A crate (or a dropped bag) you can search with E.

var opened := false
var small := false
var loot := {}   # item id -> amount

const TEX_CRATE := preload("res://assets/crate.svg")
const TEX_BAG := preload("res://assets/bag.svg")


## Loot chances. Change these numbers to make loot more or less common.
const AMMO_SMALL := 3          # small bags: 0 to this many bullets
const AMMO_BIG := 5            # big crates: 0 to this many bullets
const ARROW_CHANCE := 0.10     # chance of finding 1-4 arrows
const BANDAGE_CHANCE := 0.40   # chance of finding bandages (1, or 1-2 in big crates)
const WEAPON_CHANCE := 0.08    # big crates only
const WEAPONS := ["machete", "club", "bow", "pistol"]


func setup(rng: RandomNumberGenerator, is_small: bool) -> void:
	small = is_small
	var roll := {
		"ammo": rng.randi_range(0, AMMO_SMALL if small else AMMO_BIG),
		"food": rng.randi_range(0, 1 if small else 2),
		"cloth": rng.randi_range(0, 2 if small else 3),
		"scrap": rng.randi_range(0, 1 if small else 2),
		"bandage": (1 if small else rng.randi_range(1, 2)) if rng.randf() < BANDAGE_CHANCE else 0,
		"arrow": rng.randi_range(1, 4) if rng.randf() < ARROW_CHANCE else 0,
	}
	# Medkits are never found as loot. Craft them at a workbench.
	if not small and rng.randf() < WEAPON_CHANCE:
		roll[WEAPONS[rng.randi_range(0, WEAPONS.size() - 1)]] = 1
	for id in roll:
		if roll[id] > 0:
			loot[id] = roll[id]
	if loot.is_empty():
		loot["cloth"] = 1


func _ready() -> void:
	add_to_group("crates")


## Returns the loot once. Returns an empty Dictionary if already opened.
func open() -> Dictionary:
	if opened:
		return {}
	opened = true
	queue_free()   # searched crates disappear
	return loot


func _draw() -> void:
	var s := 12.0 if small else 18.0
	var rect := Rect2(-s, -s * 0.8, s * 2, s * 1.6)
	if opened:
		draw_rect(rect, Color(0.25, 0.2, 0.14))
		draw_rect(rect.grow(-3), Color(0.12, 0.1, 0.08))
		return
	var tex: Texture2D = TEX_BAG if small else TEX_CRATE
	if not small:
		draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.3))
	draw_texture_rect(tex, rect.grow(2) if not small else Rect2(-tex.get_size() / 2, tex.get_size()), false)
