extends RefCounted
## A bag of items, used by the player and by chests.
## Items stack up to their stack size, and every stack takes one slot.
## Example: 70 wood with a stack size of 50 = 2 slots.

const Items := preload("res://scripts/items.gd")

var max_slots := 16
var _counts := {}   # item id -> total amount


func count(id: String) -> int:
	return _counts.get(id, 0)


## Item ids you have, in display order.
func ids() -> Array:
	var list := []
	for id in Items.ORDER:
		if count(id) > 0:
			list.append(id)
	return list


func is_empty() -> bool:
	return _counts.is_empty()


func slots_used() -> int:
	var used := 0
	for id in _counts:
		used += ceili(float(_counts[id]) / Items.stack_size(id))
	return used


## How many more of this item would fit.
func space_for(id: String) -> int:
	var stack := Items.stack_size(id)
	var room_in_last_stack := (stack - count(id) % stack) % stack
	var free_slots := maxi(max_slots - slots_used(), 0)
	return room_in_last_stack + free_slots * stack


## Adds as many as fit. Returns how many were actually added.
func add(id: String, amount: int) -> int:
	var added := mini(amount, space_for(id))
	if added > 0:
		_counts[id] = count(id) + added
	return added


## Removes the amount only if you have enough. Returns true on success.
func remove(id: String, amount: int) -> bool:
	if amount <= 0 or count(id) < amount:
		return false
	set_count(id, count(id) - amount)
	return true


func has_all(cost: Dictionary) -> bool:
	for id in cost:
		if count(id) < cost[id]:
			return false
	return true


func remove_all(cost: Dictionary) -> void:
	for id in cost:
		remove(id, cost[id])


## Sets an amount directly (ignores the slot limit).
func set_count(id: String, amount: int) -> void:
	if amount <= 0:
		_counts.erase(id)
	else:
		_counts[id] = amount


## Short text that changes whenever the contents change (used to refresh the UI).
func signature() -> String:
	return str(_counts)
