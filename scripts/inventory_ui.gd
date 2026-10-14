extends Control
## The inventory window (Tab or I).
## Left side: your items. Right side: crafting, or the chest's items when a chest is open.
## Click an item to use it, place it, or move it between you and a chest.

const Items := preload("res://scripts/items.gd")

var game: Node
var chest: Node = null   # the chest being looked at, or null
var _left: VBoxContainer
var _right: VBoxContainer
var _last_signature := ""


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
	style.bg_color = Color(0.07, 0.08, 0.09, 0.94)
	style.border_color = Color(0.4, 0.33, 0.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	panel.add_child(columns)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(310, 0)
	columns.add_child(_left)
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(360, 0)
	columns.add_child(_right)


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
	var sig: String = p.inventory.signature() + str(p.near_workbench())
	if chest != null:
		sig += chest.storage.signature()
	if not force and sig == _last_signature:
		return
	_last_signature = sig

	for box in [_left, _right]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()

	# Left: player inventory.
	var inv = p.inventory
	_left.add_child(_title("Inventory   %d / %d slots" % [inv.slots_used(), inv.max_slots]))
	_left.add_child(_item_grid(inv, _on_player_item))
	var hint := "Click an item to put it in the chest" if chest != null \
		else "Click food or medicine to use it.\nClick a chest or workbench to place it."
	_left.add_child(_small(hint))

	# Right: chest or crafting.
	if chest != null:
		var st = chest.storage
		_right.add_child(_title("Chest   %d / %d slots" % [st.slots_used(), st.max_slots]))
		_right.add_child(_item_grid(st, _on_chest_item))
		_right.add_child(_small("Click an item to take it"))
	else:
		_right.add_child(_title("Crafting"))
		var bench_txt := "Workbench nearby - all recipes unlocked" if p.near_workbench() \
			else "No workbench nearby - some recipes locked"
		_right.add_child(_small(bench_txt))
		for r in Items.RECIPES:
			_right.add_child(_recipe_button(r))
	_right.add_child(_small("Tab / I / Esc to close"))


func _item_grid(inv, on_click: Callable) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var ids: Array = inv.ids()
	if ids.is_empty():
		grid.add_child(_small("(empty)"))
	for id in ids:
		var b := _button("%s   %d" % [Items.display_name(id), inv.count(id)])
		b.custom_minimum_size = Vector2(150, 34)
		b.add_theme_color_override("font_color", Items.color(id))
		b.add_theme_color_override("font_hover_color", Items.color(id).lightened(0.3))
		b.pressed.connect(on_click.bind(id))
		grid.add_child(b)
	return grid


func _recipe_button(r: Dictionary) -> Button:
	var name := Items.display_name(r["id"])
	if r["amount"] > 1:
		name += " x%d" % r["amount"]
	var text := "%s   -   %s" % [name, Items.describe_cost(r["cost"])]
	if r["bench"]:
		text += "   [bench]"
	var b := _button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(360, 34)
	b.disabled = not game.player.can_craft(r["id"])
	b.pressed.connect(_on_craft.bind(r["id"]))
	return b


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE           # so Space / Enter don't click it
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

func _on_player_item(id: String) -> void:
	var p = game.player
	if chest != null:
		game.transfer(p.inventory, chest.storage, id, p.inventory.count(id))
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


func _on_craft(id: String) -> void:
	game.player.craft(id)
	refresh(true)
