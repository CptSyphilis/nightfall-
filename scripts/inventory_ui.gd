extends Control
## The character screen (Tab or I).
## Left:   equipment slots and your stats.
## Middle: your inventory.
## Right:  crafting, or the chest's items when a chest is open.
## Click an item to use it, equip it, place it, or move it to/from a chest.

const Items := preload("res://scripts/items.gd")

var game: Node
var chest: Node = null   # the chest being looked at, or null
var _char: VBoxContainer
var _inv: VBoxContainer
var _side: VBoxContainer
var _last_signature := ""
var _focus_key := ""     # which button had controller focus, kept across rebuilds
var drop_mode := false   # when on, selecting an item drops the whole stack in a bag


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.09, 0.95)
	style.border_color = Color(0.4, 0.33, 0.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	panel.add_child(columns)
	_char = _column(columns, 230)
	columns.add_child(VSeparator.new())
	_inv = _column(columns, 310)
	columns.add_child(VSeparator.new())
	_side = _column(columns, 370)


func _column(parent: Control, width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	return box


# ---------------------------------------------------------------- open / close

func open() -> void:
	if game.game_over:
		return
	chest = null
	visible = true
	refresh(true)


func open_chest(c: Node) -> void:
	if game.game_over:
		return
	chest = c
	visible = true
	refresh(true)


func close() -> void:
	visible = false
	drop_mode = false
	chest = null


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("close_ui"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	if game.game_over:
		close()
		return
	# Walked away from the chest? Close it.
	if chest != null and (not is_instance_valid(chest) or chest.global_position.distance_to(game.player.global_position) > 100.0):
		close()
		return
	refresh()


# ---------------------------------------------------------------- building the window

## Rebuilds the buttons, but only when something actually changed.
func refresh(force: bool = false) -> void:
	var p = game.player
	var sig: String = p.inventory.signature() + str(p.near_workbench()) + p.melee_weapon + p.ranged_weapon + str(drop_mode) + str(p.backpack_level) \
		+ str(int(p.health)) + str(int(p.hunger)) + str(p.using_controller)
	if chest != null:
		sig += chest.storage.signature()
	for c in p.nearby_chests():
		sig += c.storage.signature()
	if not force and sig == _last_signature:
		return
	_last_signature = sig

	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and focused.has_meta("key"):
		_focus_key = focused.get_meta("key")

	for box in [_char, _inv, _side]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_build_character(p)
	_build_inventory(p)
	if chest != null:
		_build_chest()
	else:
		_build_crafting(p)
	if p.using_controller:
		_restore_focus.call_deferred()


## On a controller, keep the highlight on the same button after a rebuild
## (or put it on the first button when the screen opens).
func _restore_focus() -> void:
	var first: Button = null
	for b in find_children("*", "Button", true, false):
		if not b.is_visible_in_tree():
			continue
		if first == null:
			first = b
		if b.get_meta("key", "") == _focus_key:
			b.grab_focus()
			return
	if first != null:
		first.grab_focus()


func _build_character(p) -> void:
	_char.add_child(_title("Character"))
	_char.add_child(_small("Equipment  (select a slot to unequip)"))
	_char.add_child(_slot("Melee  -  " + game.hud.prompt("melee"), p.melee_weapon, "melee"))
	_char.add_child(_slot("Ranged  -  " + game.hud.prompt("shoot"), p.ranged_weapon, "ranged"))

	var m: Dictionary = p.melee_stats()
	var r: Dictionary = p.ranged_stats()
	_char.add_child(_title("Stats"))
	_char.add_child(_stat("Health", "%d / %d" % [p.health, p.max_health]))
	_char.add_child(_stat("Hunger", "%d%%" % p.hunger))
	_char.add_child(_stat("Backpack", ["none", "Backpack", "Large backpack"][p.backpack_level]))
	_char.add_child(_stat("Melee damage", "%d" % m["damage"]))
	_char.add_child(_stat("Melee reach", "%d" % m["range"]))
	if r.is_empty():
		_char.add_child(_stat("Ranged damage", "-"))
	else:
		_char.add_child(_stat("Ranged damage", "%d" % r["damage"]))
		_char.add_child(_stat("Ranged ammo", "%s  (%d)" % [Items.display_name(r["ammo"]), p.inventory.count(r["ammo"])]))
		_char.add_child(_stat("Noise", "quiet" if r["noise"] < 200.0 else "LOUD"))
	_char.add_child(_stat("Day", "%d" % game.day))
	_char.add_child(_stat("Kills", "%d" % game.kills))


func _build_inventory(p) -> void:
	var inv = p.inventory
	_inv.add_child(_title("Inventory   %d / %d slots" % [inv.slots_used(), inv.max_slots]))
	_inv.add_child(_item_grid(inv, _on_player_item, p))
	if chest == null:
		var tb := _button("Drop items: ON  (select to turn off)" if drop_mode else "Drop items: off")
		tb.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if drop_mode else Color(1, 1, 1, 0.75))
		tb.set_meta("key", "drop_toggle")
		tb.pressed.connect(_on_toggle_drop)
		_inv.add_child(tb)
	var hint := "Select an item to put it in the chest" if chest != null \
		else "Select a weapon to equip it.\nSelect food or medicine to use it.\nSelect a chest or workbench to place it."
	if drop_mode and chest == null:
		hint = "DROP MODE: select an item to drop the whole stack\nin a bag at your feet (search the bag to get it back)."
	_inv.add_child(_small(hint))


func _build_chest() -> void:
	var st = chest.storage
	_side.add_child(_title("Chest   %d / %d slots" % [st.slots_used(), st.max_slots]))
	_side.add_child(_item_grid(st, _on_chest_item, null))
	_side.add_child(_small("Select an item to take it"))
	_side.add_child(_small(_close_hint()))


func _build_crafting(p) -> void:
	_side.add_child(_title("Crafting"))
	var bench_txt := "No workbench nearby - [bench] recipes locked"
	if p.near_workbench():
		var n: int = p.nearby_chests().size()
		bench_txt = "Workbench nearby - all recipes unlocked"
		if n > 0:
			bench_txt += "\nAlso using items from %d nearby chest%s" % [n, "" if n == 1 else "s"]
	_side.add_child(_small(bench_txt))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(370, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true   # scroll along when the D-pad moves down the list
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for r in Items.RECIPES:
		list.add_child(_recipe_button(r))
	_side.add_child(scroll)
	_side.add_child(_small(_close_hint()))


func _item_grid(inv, on_click: Callable, p) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var ids: Array = inv.ids()
	if ids.is_empty():
		grid.add_child(_small("(empty)"))
	for id in ids:
		var text := Items.display_name(id)
		if Items.stack_size(id) > 1:
			text += "   %d" % inv.count(id)
		if p != null and (id == p.melee_weapon or id == p.ranged_weapon):
			text += "  [E]"
		var b := _button(text)
		b.custom_minimum_size = Vector2(150, 32)
		b.add_theme_color_override("font_color", Items.color(id))
		b.add_theme_color_override("font_hover_color", Items.color(id).lightened(0.3))
		b.set_meta("key", ("inv:" if p != null else "chest:") + id)
		b.pressed.connect(on_click.bind(id))
		grid.add_child(b)
	return grid


func _slot(label: String, weapon_id: String, slot: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_small(label))
	var name := "Fists" if weapon_id == "fists" else ("(empty)" if weapon_id == "" else Items.display_name(weapon_id))
	var b := _button(name)
	b.custom_minimum_size = Vector2(230, 38)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
	b.disabled = weapon_id == "fists" or weapon_id == ""
	b.set_meta("key", "slot:" + slot)
	b.pressed.connect(_on_unequip.bind(slot))
	box.add_child(b)
	return box


func _stat(label: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 14)
	row.add_child(l)
	row.add_child(v)
	return row


func _recipe_button(r: Dictionary) -> Button:
	var name := Items.display_name(r["id"])
	if r["amount"] > 1:
		name += " x%d" % r["amount"]
	var text := "%s   -   %s" % [name, Items.describe_cost(r["cost"])]
	if r["bench"]:
		text += "   [bench]"
	var b := _button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(350, 30)
	b.add_theme_font_size_override("font_size", 14)
	b.disabled = not game.player.can_craft(r["id"])
	b.set_meta("key", "craft:" + r["id"])
	b.pressed.connect(_on_craft.bind(r["id"]))
	return b


func _close_hint() -> String:
	match game.player.prompt_style():
		"xbox":
			return "Menu or B to close"
		"ps":
			return "Options or Circle to close"
	return "Tab / I / Esc to close"


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	# Controller: buttons take focus so the D-pad can move between them.
	# Mouse/keyboard: no focus, so Space / Enter never click a button by accident.
	b.focus_mode = Control.FOCUS_ALL if game.player.using_controller else Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	return b


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
	return l


func _small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return l


# ---------------------------------------------------------------- clicks

func _on_toggle_drop() -> void:
	drop_mode = not drop_mode
	refresh(true)


func _on_player_item(id: String) -> void:
	var p = game.player
	if drop_mode and chest == null:
		game.drop_items(id, p.inventory.count(id))
	elif chest != null:
		game.transfer(p.inventory, chest.storage, id, p.inventory.count(id))
	elif Items.is_weapon(id):
		p.equip(id)
	elif id == "food":
		p.eat()
	elif id == "bandage" or id == "medkit":
		p.heal_with(id)
	elif Items.is_placeable(id):
		close()
		game.start_placing(id)
	refresh(true)


func _on_chest_item(id: String) -> void:
	game.transfer(chest.storage, game.player.inventory, id, chest.storage.count(id))
	refresh(true)


func _on_unequip(slot: String) -> void:
	game.player.unequip(slot)
	refresh(true)


func _on_craft(id: String) -> void:
	game.player.craft(id)
	refresh(true)
