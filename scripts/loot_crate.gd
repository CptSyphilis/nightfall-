extends Node2D
## A crate (or a dropped bag) you can search with E.

var opened := false
var small := false
var loot := {}   # item id -> amount

const TEX_CRATE := preload("res://assets/crate.svg")
const TEX_BAG := preload("res://assets/bag.svg")


# Chance that a crate holds each of these (0.25 = 25%).
const AMMO_CHANCE := 0.25
const ARROW_CHANCE := 0.12
const BANDAGE_CHANCE := 0.10
const WEAPON_CHANCE := 0.06


static func _maybe(rng: RandomNumberGenerator, chance: float, lo: int, hi: int) -> int:
	return rng.randi_range(lo, hi) if rng.randf() < chance else 0


func setup(rng: RandomNumberGenerator, is_small: bool) -> void:
	small = is_small
	# Loot is scarce on purpose: craft and farm what you need.
	# Medkits never show up in loot; you craft them at a workbench.
	var roll := {
		"food": rng.randi_range(0, 1 if small else 2),
		"cloth": rng.randi_range(0, 2 if small else 3),
		"scrap": rng.randi_range(0, 1 if small else 2),
		"ammo": _maybe(rng, AMMO_CHANCE, 1 if small else 2, 3 if small else 6),
		"arrow": _maybe(rng, ARROW_CHANCE, 1, 2 if small else 4),
		"bandage": _maybe(rng, BANDAGE_CHANCE, 1, 1),
	}
	# Big crates very rarely hold a weapon (the only way to find a pistol).
	if not small and rng.randf() < WEAPON_CHANCE:
		roll[["club", "machete", "bow", "pistol"][rng.randi_range(0, 3)]] = 1
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
