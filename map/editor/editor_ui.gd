extends Control

# =============================================================================
# Runtime map editor UI (map/editor/editor_ui.gd)
# =============================================================================
# Built entirely from plain Controls in code: no EditorPlugin, no EditorInterface,
# no @tool, no FileDialog. It is the runtime counterpart of the plugin's
# editor_dock.gd (same tools, same pickers, same picker wording), and it makes
# NO decision about the map: every control emits a request signal and
# map_editor.gd does the work, which is also what keeps this file out of the
# headless tests.
#
# Shape (M6): a ModePanel row of four toggle buttons sits at the TOP-RIGHT of the
# screen and picks the mode — "Lanes (1)", "Buildings (2)", "Map (3)",
# "Tiles (4)". The left ToolPanel shows ONLY the active mode's controls, pinned:
# there is no ScrollContainer anywhere, so no control can ever scroll out of
# reach. The Undo/Redo row and the log are visible in every mode, and the log is
# the ONLY vertically scrolling region in the whole editor UI.
#
# Mouse policy: this node covers the whole screen, so it IGNORES mouse input and
# only the two panels swallow clicks (the log's scrollbar swallows its own).
# A click that lands on a panel never reaches map_editor.gd's _unhandled_input,
# which is how the map tools stay click-accurate next to the tool panel, and the
# mouse wheel over a panel scrolls the log instead of zooming the camera.
# =============================================================================

const MapStore = preload("res://map/editor/map_store.gd")
const BuildingLogic = preload("res://addons/map_editor/building_logic.gd")
const TileBrush = preload("res://addons/map_editor/tile_brush_logic.gd")

const PANEL_WIDTH := 300.0
const LOG_LINES := 80
const TILE_ICON_PX := 96

# The mode vocabulary is SHARED with the host: map_editor.gd keys its own
# `mode` variable with exactly these names (plus "" for no tool), reads MODE_KEYS
# for the 1-4 shortcuts, and MODE_LABELS is the one source of the button order:
# GDScript dictionaries preserve insertion order, so iterating this dictionary
# gives Lanes, Buildings, Map, Tiles everywhere (buttons, tool boxes, tests).
const MODE_LABELS := {
	"lane": "Lanes (1)",
	"building": "Buildings (2)",
	"map": "Map (3)",
	"tile": "Tiles (4)",
}
const MODE_TOOL_BOX_NAMES := {
	"lane": "LaneTools",
	"building": "BuildingTools",
	"map": "MapTools",
	"tile": "TileTools",
}
# Plain main-row digits only, no numpad, no modifiers (see map_editor.gd's
# _unhandled_input guard). KEY_3 is "map" because "map" is the UI-only mode: the
# file buttons act through signals, so no canvas click is ever routed to it.
const MODE_KEYS := {KEY_1: "lane", KEY_2: "building", KEY_3: "map", KEY_4: "tile"}
const MODE_TOOLTIPS := {
	"lane": "Left-click adds a snapped point to the selected lane. Right-click drag "
			+ "moves an existing lane point. Escape exits.",
	"building": "Left-click places the selected building under the selected team. "
			+ "Right-click drag moves a placed building. Escape exits.",
	"map": "File operations for the map being edited: open, save, validate, play, exit.",
	"tile": "Left-click paints the selected tile, right-click erases, drag works. "
			+ "Escape exits.",
}

signal new_map_requested
signal open_map_requested(map_name: String)
signal save_map_requested
signal delete_map_requested(map_name: String)
signal validate_requested
signal play_requested
signal exit_requested
# ONE signal for every mode: the mode name when a button lights, "" when it
# unlights (re-press, Escape-equivalent, or the host deselecting). M6 replaced
# the four per-tool mode signals with this.
signal mode_requested(mode_name: String)
signal new_lane_requested
signal lane_selected(lane_name: String)
signal undo_requested
signal redo_requested

# The map whose lanes/tiles fill the lane and tile pickers (set by the host;
# null when there is no map yet).
var map_root: Node2D = null

var _map_option: OptionButton
var _name_entry: LineEdit
var _lane_option: OptionButton
var _building_option: OptionButton
var _team_option: OptionButton
var _brush_option: OptionButton
var _tile_option: OptionButton
var _block_option: OptionButton
var _mirror_toggle: Button
var _log: RichTextLabel

# mode name -> the top-right Button, and mode name -> that mode's left-panel
# box. These two dictionaries are the whole mode plumbing.
var _mode_buttons: Dictionary[String, Button] = {}
var _mode_tools: Dictionary[String, Control] = {}

var _block_values: Array[int] = []
var _picker_tiles: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build() -> void:
	_build_mode_panel()

	var panel := PanelContainer.new()
	panel.name = "ToolPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = PANEL_WIDTH
	panel.offset_bottom = 0.0
	add_child(panel)

	# M6: NO ScrollContainer. Every mode's controls fit in its own box, the
	# History row is always there, and only the log at the bottom scrolls.
	var box := VBoxContainer.new()
	box.name = "Tools"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 0.0)
	panel.add_child(box)

	for mode_name: String in MODE_LABELS:
		var tools := VBoxContainer.new()
		tools.name = MODE_TOOL_BOX_NAMES[mode_name]
		tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(tools)
		_mode_tools[mode_name] = tools
		if mode_name == "lane":
			_fill_lane_tools(tools)
		elif mode_name == "building":
			_fill_building_tools(tools)
		elif mode_name == "map":
			_fill_map_tools(tools)
		else:
			_fill_tile_tools(tools)

	var history_row := HBoxContainer.new()
	history_row.name = "HistoryRow"
	box.add_child(history_row)
	# Named (not "Button"/"Button2") so the always-visible History row is
	# addressable from tests and from the scene tree.
	_add_button(history_row, "Undo", "undo_requested", "Ctrl+Z.").name = "Undo"
	_add_button(history_row, "Redo", "redo_requested", "Ctrl+Y.").name = "Redo"

	_log = RichTextLabel.new()
	_log.name = "Log"
	_log.bbcode_enabled = false
	# fit_content = false + EXPAND_FILL: the log takes the panel's remaining
	# height and scrolls its own overflow. This is the editor's only scrollbar.
	_log.fit_content = false
	_log.scroll_following = true
	# STOP, not IGNORE: its scrollbar has to be draggable, and ToolPanel's own
	# STOP already keeps log clicks from reaching the map tools.
	_log.mouse_filter = Control.MOUSE_FILTER_STOP
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 120.0)
	box.add_child(_log)

	# Nothing is lit until the host declares the boot mode (map_editor.gd's
	# _ready calls _set_mode("map")); visibility lives ONLY in set_mode_active.
	set_mode_active("", false)

	refresh_map_list()
	refresh_tile_picker()


# The top-right mode row (M6): one ButtonGroup, so only one mode can be lit,
# with allow_unpress so re-pressing the lit button deselects back to no tool.
func _build_mode_panel() -> void:
	var mode_panel := PanelContainer.new()
	mode_panel.name = "ModePanel"
	mode_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(mode_panel)
	mode_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT,
			Control.PRESET_MODE_MINSIZE, 8.0)
	mode_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var row := HBoxContainer.new()
	row.name = "ModeButtons"
	mode_panel.add_child(row)

	var group := ButtonGroup.new()
	group.allow_unpress = true
	for mode_name: String in MODE_LABELS:
		var button := Button.new()
		button.name = mode_name.capitalize() + "ModeButton"
		button.text = MODE_LABELS[mode_name]
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = MODE_TOOLTIPS[mode_name]
		button.toggled.connect(_on_mode_toggled.bind(mode_name))
		row.add_child(button)
		_mode_buttons[mode_name] = button


# --- Map mode: the file operations, in the old top-of-panel order --------------

func _fill_map_tools(box: VBoxContainer) -> void:
	_map_option = OptionButton.new()
	_map_option.tooltip_text = "Maps saved in user://maps/ (shipping maps are not editable)."
	box.add_child(_map_option)
	# Choosing a saved map pre-fills the name field, so Save writes back into
	# the map that is open instead of minting a second file.
	_map_option.item_selected.connect(func(_index: int) -> void:
		_name_entry.text = selected_map_name())

	var map_row := HBoxContainer.new()
	box.add_child(map_row)
	_add_button(map_row, "Open", "open_map_requested", "Open the selected map for editing.")
	var refresh := _add_button(map_row, "Refresh", "", "Re-read user://maps/.")
	refresh.pressed.connect(refresh_map_list)
	_add_button(map_row, "New map", "new_map_requested", "Create a fresh scaffolded map.")

	_name_entry = LineEdit.new()
	_name_entry.text = "untitled"
	_name_entry.tooltip_text = "Saved as user://maps/<name>.tscn"
	box.add_child(_name_entry)

	var file_row := HBoxContainer.new()
	box.add_child(file_row)
	_add_button(file_row, "Save", "save_map_requested",
			"Save into user://maps/ (validation problems are logged, never blocking).")
	_add_button(file_row, "Delete", "delete_map_requested", "Delete the selected saved map.")
	_add_button(file_row, "Validate", "validate_requested", "Report map problems without saving.")
	_add_button(file_row, "Play", "play_requested", "Save and boot the map: player blue vs enemy red.")
	_add_button(box, "Exit", "exit_requested", "Back to the main menu (unsaved edits are lost).")


# --- Lane mode ------------------------------------------------------------------

func _fill_lane_tools(box: VBoxContainer) -> void:
	_lane_option = OptionButton.new()
	# Wording follows the mode panel: the old "Draw lanes" toggle is gone, the
	# Lanes (1) button IS the mode.
	_lane_option.tooltip_text = "The lane that Lanes mode edits."
	box.add_child(_lane_option)
	_lane_option.item_selected.connect(func(index: int) -> void:
		lane_selected.emit(_lane_option.get_item_text(index)))
	var lane_row := HBoxContainer.new()
	box.add_child(lane_row)
	_add_button(lane_row, "New lane", "new_lane_requested", "Add an empty lane and select it.")


# --- Building mode ---------------------------------------------------------------

func _fill_building_tools(box: VBoxContainer) -> void:
	_building_option = OptionButton.new()
	_building_option.tooltip_text = "Building scene to instantiate (res://unit/buildings/)."
	box.add_child(_building_option)
	for path in BuildingLogic.list_building_scenes():
		# OptionButton.add_item returns void in 4.7: the index is the count first.
		var building_index := _building_option.item_count
		_building_option.add_item(path.get_file().get_basename())
		_building_option.set_item_metadata(building_index, path)
	_team_option = OptionButton.new()
	_team_option.tooltip_text = "neutral places into the first team directory the map already has."
	box.add_child(_team_option)
	for team in BuildingLogic.TEAM_DIRECTORIES:
		_team_option.add_item(team)
	_team_option.add_item("neutral")
	_team_option.select(0)


# --- Tile mode -------------------------------------------------------------------

func _fill_tile_tools(box: VBoxContainer) -> void:
	_mirror_toggle = Button.new()
	_mirror_toggle.text = "Mirror paint"
	_mirror_toggle.toggle_mode = true
	_mirror_toggle.button_pressed = true
	_mirror_toggle.tooltip_text = ("Also paint the mirrored twin across the map center, "
			+ "matching the scaffold's symmetric look (the M3 dock contract). Turn off "
			+ "to author asymmetric maps.")
	box.add_child(_mirror_toggle)
	_brush_option = OptionButton.new()
	_brush_option.tooltip_text = "Which TileMapLayer the clicks paint."
	box.add_child(_brush_option)
	for brush in TileBrush.BRUSHES.keys():
		var brush_index := _brush_option.item_count
		_brush_option.add_item(brush)
		_brush_option.set_item_metadata(brush_index, brush)
	_brush_option.select(0)
	_brush_option.item_selected.connect(func(_index: int) -> void: refresh_tile_picker())

	_block_option = OptionButton.new()
	_block_option.tooltip_text = ("How many cells one click covers. The full-tile size "
			+ "(largest) keeps the whole 64px tile painted; smaller sizes paint detail.")
	box.add_child(_block_option)

	_tile_option = OptionButton.new()
	_tile_option.tooltip_text = ("Tile to paint — (source, atlas) pairs of the layer's TileSet. "
			+ "For walls, the source picks the team (0 = blue).")
	box.add_child(_tile_option)


func _add_button(parent: Control, text: String, signal_name: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	if signal_name != "":
		button.pressed.connect(_emit_request.bind(signal_name))
	parent.add_child(button)
	return button


# Signal names as strings keep the button wiring in one helper; the payload is
# the selected map name where the request needs one.
func _emit_request(signal_name: String) -> void:
	match signal_name:
		"open_map_requested":
			open_map_requested.emit(selected_map_name())
		"delete_map_requested":
			delete_map_requested.emit(selected_map_name())
		_:
			_emit_no_payload(signal_name)


func _emit_no_payload(signal_name: String) -> void:
	match signal_name:
		"new_map_requested":
			new_map_requested.emit()
		"save_map_requested":
			save_map_requested.emit()
		"validate_requested":
			validate_requested.emit()
		"play_requested":
			play_requested.emit()
		"exit_requested":
			exit_requested.emit()
		"new_lane_requested":
			new_lane_requested.emit()
		"undo_requested":
			undo_requested.emit()
		"redo_requested":
			redo_requested.emit()


# ---------------------------------------------------------------------------
# Host-facing state
# ---------------------------------------------------------------------------

func set_map_root(map: Node2D) -> void:
	map_root = map
	refresh_lanes()
	refresh_tile_picker()


func set_map_name(name: String) -> void:
	_name_entry.text = name


func map_name() -> String:
	return _name_entry.text


func log_line(line: String) -> void:
	_log.text += line + "\n"
	var lines := _log.text.split("\n")
	if lines.size() > LOG_LINES:
		_log.text = "\n".join(lines.slice(lines.size() - LOG_LINES, lines.size()))


# The ONE place mode visibility is driven from. Hidden Controls keep their
# state (pickers stay alive across mode switches), and set_pressed_no_signal
# keeps the ButtonGroup from echoing back into mode_requested.
func set_mode_active(mode_name: String, active: bool) -> void:
	var shown := active and mode_name != ""
	for m in _mode_tools:
		_mode_tools[m].visible = shown and m == mode_name
	for m in _mode_buttons:
		_mode_buttons[m].set_pressed_no_signal(shown and m == mode_name)

func _on_mode_toggled(active: bool, mode_name: String) -> void:
	mode_requested.emit(mode_name if active else "")


# ---------------------------------------------------------------------------
# Pickers
# ---------------------------------------------------------------------------

func refresh_map_list() -> void:
	var previous := selected_map_name()
	_map_option.clear()
	var maps := MapStore.list_maps()
	for map_name in maps:
		_map_option.add_item(map_name)
	_map_option.disabled = maps.is_empty()
	if maps.is_empty():
		return
	var keep := 0
	for i in maps.size():
		if maps[i] == previous:
			keep = i
			break
	_map_option.select(keep)


func refresh_lanes() -> void:
	var previous := selected_lane_name()
	_lane_option.clear()
	var lanes_node: Node = null
	if map_root != null:
		lanes_node = map_root.get_node_or_null("lanes")
	if lanes_node != null:
		for child in lanes_node.get_children():
			if child is Line2D:
				_lane_option.add_item(String(child.name))
	_lane_option.disabled = _lane_option.item_count == 0
	if _lane_option.item_count == 0:
		return
	var keep := 0
	for i in _lane_option.item_count:
		if _lane_option.get_item_text(i) == previous:
			keep = i
			break
	_lane_option.select(keep)


func select_lane(lane_name: String) -> void:
	for i in _lane_option.item_count:
		if _lane_option.get_item_text(i) == lane_name:
			_lane_option.select(i)
			return


# Rebuild the tile and block pickers from the selected brush's layer. No map or
# no layer (a hand-made map missing tiles/…): clear and disable, so the tile
# tool refuses instead of painting into nothing. Called by the host on map
# install, mode change and undo/redo, and by the brush dropdown itself — on
# hidden controls on purpose, so the pickers are never stale.
func refresh_tile_picker() -> void:
	# Preserve what the user picked when the list can offer it again: the host
	# refreshes the picker after undo/redo and after map install, and resetting
	# the tile mid-session would be a footgun.
	var keep_tile: Dictionary = selected_tile()
	var keep_block := -1
	if not _block_values.is_empty():
		keep_block = selected_block_cells()
	_picker_tiles = []
	_block_values = []
	_tile_option.clear()
	_block_option.clear()

	var layer: TileMapLayer = null
	if map_root != null:
		layer = TileBrush.layer_for_brush(map_root, selected_brush())
	if layer == null:
		_tile_option.disabled = true
		_tile_option.add_item("no tiles")
		_block_option.disabled = true
		return

	_block_option.disabled = false
	var map_tile := 64
	var exported = map_root.get("tile_size")
	if (exported is int or exported is float) and exported > 0:
		map_tile = int(exported)
	var options: Array[int] = TileBrush.block_options_for(TileBrush.cell_size_of(layer), map_tile)
	for i in options.size():
		var label := "%dx%d" % [options[i], options[i]]
		if i == options.size() - 1 and options[i] > 1:
			label += " (full tile)"
		_block_option.add_item(label)
		_block_values.append(options[i])
	var block_selection := _block_values.size() - 1  # default: the full tile
	if keep_block > 0:
		for i in _block_values.size():
			if _block_values[i] == keep_block:
				block_selection = i
				break
	_block_option.select(block_selection)

	_picker_tiles = TileBrush.list_layer_tiles(layer)
	if _picker_tiles.is_empty():
		_tile_option.disabled = true
		_tile_option.add_item("no tiles")
		return
	_tile_option.disabled = false
	for tile in _picker_tiles:
		_tile_option.add_item("s%d %s" % [tile.source_id, tile.atlas_coords])
		var icon: Texture2D = TileBrush.tile_icon(layer.tile_set, tile.source_id, tile.atlas_coords,
				TILE_ICON_PX)
		if icon != null:
			_tile_option.get_popup().set_item_icon(_tile_option.item_count - 1, icon)
	var tile_selection := 0
	if not keep_tile.is_empty():
		for i in _picker_tiles.size():
			if _picker_tiles[i] == keep_tile:
				tile_selection = i
				break
	_tile_option.select(tile_selection)  # selected defaults to -1 until told otherwise


# ---------------------------------------------------------------------------
# Getters the host reads while it works
# ---------------------------------------------------------------------------

func selected_map_name() -> String:
	if _map_option == null or _map_option.selected < 0 or _map_option.selected >= _map_option.item_count:
		return ""
	return _map_option.get_item_text(_map_option.selected)


func selected_lane_name() -> String:
	if _lane_option == null or _lane_option.selected < 0 or _lane_option.selected >= _lane_option.item_count:
		return ""
	return _lane_option.get_item_text(_lane_option.selected)


func selected_building_scene() -> String:
	if _building_option == null or _building_option.selected < 0 \
			or _building_option.selected >= _building_option.item_count:
		return ""
	var metadata = _building_option.get_item_metadata(_building_option.selected)
	return metadata if metadata is String else ""


func selected_team() -> String:
	if _team_option == null or _team_option.selected < 0 or _team_option.selected >= _team_option.item_count:
		return "neutral"
	return _team_option.get_item_text(_team_option.selected)


func selected_brush() -> String:
	if _brush_option == null or _brush_option.selected < 0 or _brush_option.selected >= _brush_option.item_count:
		return ""
	var metadata = _brush_option.get_item_metadata(_brush_option.selected)
	return metadata if metadata is String else ""


func selected_tile() -> Dictionary:
	if _tile_option == null or _tile_option.selected < 0 or _tile_option.selected >= _picker_tiles.size():
		return {}
	return _picker_tiles[_tile_option.selected]


func selected_block_cells() -> int:
	if _block_values.is_empty() or _block_option == null \
			or _block_option.selected < 0 or _block_option.selected >= _block_values.size():
		return 1
	return _block_values[_block_option.selected]


func selected_block_is_full_tile() -> bool:
	return _block_values.is_empty() \
			or (_block_option != null and _block_option.selected >= _block_values.size() - 1)


# Read live by the host at every paint event: on = strokes write their mirrored
# twin cells (the scaffold's symmetric look), off = only where clicked.
func mirror_enabled() -> bool:
	return _mirror_toggle != null and _mirror_toggle.button_pressed
