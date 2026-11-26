extends RefCounted

# =============================================================================
# Runtime editor tool tests (tests/unit/test_map_editor_tools.gd)
# =============================================================================
# Behavior tests for map/editor/map_editor.gd that unit-test its host logic
# headlessly by driving the real editor scene (the same shape the M4 scratch
# probe validated and the suite's asset test exercises): instantiate
# map_editor.tscn under the runner, switch modes through the ONE mode signal /
# the 1-4 key shortcuts, click through synthetic input events, and read back the
# edited scaffold — no awaits, so the sync unit harness accepts it, and no
# saves, so nothing touches user://maps.
#
# Coverage:
#   - Mode panel (M6): the four top-right buttons (labels "Lanes (1)"…
#     "Tiles (4)"), the single mode_requested signal, exclusive/one-lit button
#     states, per-mode tool-box visibility, keys 1-4 selecting modes, re-press
#     and Escape deselecting, the LineEdit/Ctrl guards on the digit keys, a tool
#     mode dropping on map install while Map mode survives, the boot mode, and
#     the UI contract that ONLY the log scrolls (no ScrollContainer anywhere).
#   - Right-click move (M6, kind-scoped): Lanes mode drags lane points only and
#     Buildings mode drags buildings only — each asserted by the OTHER kind
#     grabbing nothing. Drag math is the M5 one: 64px snap, one undo action per
#     drag, undo/redo round-trip, a no-motion grab leaves no history entry
#     (the windowed crash pull-request feedback), and the dragged lane shows in
#     the overlay.
#   - "Mirror paint" toggle (M5): on = a stroke writes its mirrored twin cells
#     (M3 contract), off = only where clicked (asymmetric maps authorable).
#     Asserted by cell VALUES and an erase->paint sequence, never by scaffold
#     cell counts, so the test cannot be flaked by scaffold paint overlap.
# =============================================================================

const EditorScene = preload("res://map/editor/map_editor.tscn")
const EditorUI = preload("res://map/editor/editor_ui.gd")
const LaneLogic = preload("res://addons/map_editor/lane_logic.gd")
const TileBrush = preload("res://addons/map_editor/tile_brush_logic.gd")


func run(harness) -> void:
	var editor: Node2D = (EditorScene as PackedScene).instantiate()
	harness.add_child(editor)
	_test_boot(harness, editor)
	if _booted(harness, editor):
		_test_mode_panel(harness, editor)
		_test_mirror_toggle(harness, editor)
		_test_move_building(harness, editor)
		_test_move_lane_point(harness, editor)
		_test_move_wiring(harness, editor)
	editor.free()


func _booted(harness, editor) -> bool:
	return editor != null and editor.map_root != null


# ---------------------------------------------------------------------------
# Boot: Map mode is lit, the tool panel + mode panel are built as contracted,
# the log is the only scrolling region, and a new map keeps Map mode.
# ---------------------------------------------------------------------------

func _test_boot(harness, editor) -> void:
	var ui = ui_of(editor)
	harness.check(editor.map_root == null, "the editor boots with no map")
	harness.check(ui != null, "the editor's tool panel exists")
	if ui == null:
		return

	# M6 acceptance: boot state is Map mode (3), so the file controls are what
	# the author sees first.
	harness.check(editor.mode == "map", "the editor boots into Map mode (3)")
	harness.check(_lit(ui) == ["map"], "only the Map (3) button is lit at boot")
	harness.check(_visible_tools(ui) == ["map"], "only Map mode's controls are shown at boot")

	# The UI contract: a top-right ModePanel row, a left ToolPanel, no
	# ScrollContainer anywhere, and the log carrying the only scrollbar.
	var mode_panel = ui.get_node_or_null("ModePanel/ModeButtons")
	harness.check(mode_panel != null, "the top-right ModePanel holds a ModeButtons row")
	if mode_panel == null:
		return
	harness.check(ui.get_node_or_null("ToolPanel/Tools") != null,
			"the left ToolPanel holds its Tools box directly (no scroll box)")
	var scrollers: Array[Node] = []
	_collect_scroll_containers(ui, scrollers)
	harness.check(scrollers.is_empty(), "no ScrollContainer exists: the log is the only scrolling region")
	harness.check(_log_contract_ok(ui),
			"the log expands, follows, stops the mouse and scrolls its own overflow")
	harness.check(_panels_stop_mouse(ui),
			"both panels swallow clicks while the full-screen UI layer ignores them (camera policy)")
	harness.check(_anchored_top_right(ui), "the ModePanel is anchored to the top-right corner")
	harness.check(_always_visible(ui), "Undo/Redo and the log are visible in Map mode")

	# Button wording + the key mapping the wording promises: "Lanes (1)" is
	# KEY_1, "Buildings (2)" is KEY_2, and so on.
	var digit_of := {"lane": "1", "building": "2", "map": "3", "tile": "4"}
	var key_of := {"lane": KEY_1, "building": KEY_2, "map": KEY_3, "tile": KEY_4}
	var labels_ok := true
	for mode_name in EditorUI.MODE_LABELS:
		var button: Button = ui._mode_buttons[mode_name]
		if button.text != EditorUI.MODE_LABELS[mode_name]:
			labels_ok = false
		if not button.text.contains("(%s)" % digit_of[mode_name]):
			labels_ok = false
		if EditorUI.MODE_KEYS[key_of[mode_name]] != mode_name:
			labels_ok = false
		if button.toggle_mode == false or button.button_group == null:
			labels_ok = false
	harness.check(labels_ok,
			"the mode buttons read Lanes (1) / Buildings (2) / Map (3) / Tiles (4) and are "
			+ "grouped toggles keyed 1-4")

	# The mechanism behind "re-pressing the active mode deselects" and "exactly
	# one lit": one shared ButtonGroup, and it permits unpressing.
	var group_ok := true
	var group: ButtonGroup = null
	for mode_name in EditorUI.MODE_LABELS:
		var mode_button: Button = ui._mode_buttons[mode_name]
		if group == null:
			group = mode_button.button_group
		if group == null or mode_button.button_group != group:
			group_ok = false
		elif not group.allow_unpress:
			group_ok = false
	harness.check(group_ok,
			"the mode buttons share one ButtonGroup with allow_unpress (a re-press deselects)")

	if editor.map_root != null:
		return
	ui.new_map_requested.emit()
	harness.check(editor.map_root != null, "New map installs a scaffold to edit")
	if editor.map_root == null:
		return
	# M6 acceptance: creating/opening a map keeps Map mode; only TOOL modes drop.
	harness.check(editor.mode == "map", "creating a map keeps Map mode active")
	harness.check(_lit(ui) == ["map"], "the Map (3) button stays lit after a map install")
	# Mirror defaults ON: a fresh session keeps the M3 twin-cell contract, and
	# the author opts OUT per map when they want asymmetry.
	harness.check(ui.mirror_enabled() == true,
			"Mirror paint defaults to on (M3 twin-cell contract)")


# ---------------------------------------------------------------------------
# Mode panel: one signal, exclusive buttons, per-mode tool boxes, keys 1-4
# ---------------------------------------------------------------------------

func _test_mode_panel(harness, editor) -> void:
	var ui = ui_of(editor)

	editor._set_mode("")
	harness.check(editor.mode == "", "the mode test block starts from no tool mode")
	harness.check(_lit(ui).is_empty(), "no mode button is lit with no tool mode")
	harness.check(_visible_tools(ui).is_empty(), "no mode's controls are shown with no tool mode")
	harness.check(_always_visible(ui), "Undo/Redo and the log stay visible after deselecting")

	ui.mode_requested.emit("lane")
	harness.check(editor.mode == "lane", "the mode signal selects Lanes mode")
	harness.check(_lit(ui) == ["lane"], "exactly the Lanes (1) button is lit")
	harness.check(_visible_tools(ui) == ["lane"], "only LaneTools is visible in Lanes mode")
	harness.check(_always_visible(ui), "Undo/Redo and the log stay visible in Lanes mode")
	harness.check(ui.selected_lane_name() != "",
			"the lane dropdown still reports its selection (hidden is not cleared)")

	ui.mode_requested.emit("tile")
	harness.check(editor.mode == "tile", "the mode signal switches to Tiles mode")
	harness.check(_lit(ui) == ["tile"], "switching modes turns the previous button off")
	harness.check(not ui._mode_tools["lane"].visible, "LaneTools is hidden once Lanes mode is left")
	harness.check(ui._mode_tools["tile"].visible, "TileTools is visible in Tiles mode")
	# The pickers stay ALIVE across mode switches (only visibility toggles).
	harness.check(ui.selected_lane_name() != "",
			"the lane picked in Lanes mode survives the switch (building placement needs it)")
	harness.check(ui.selected_brush() != "", "the brush picker stays alive while TileTools hides")

	# An active TOOL mode drops on a map install; Map mode is the exception.
	ui.new_map_requested.emit()
	harness.check(editor.mode == "", "an active tool mode drops on map install")
	harness.check(_lit(ui).is_empty(), "no button is lit after a tool mode drops")
	editor._set_mode("map")
	harness.check(_visible_tools(ui) == ["map"], "Map mode's file controls come back")

	# Keyboard: 1-4 select the matching mode, 3 being the UI-only Map mode.
	var key_pairs: Array[Array] = [[KEY_1, "lane"], [KEY_2, "building"], [KEY_3, "map"],
			[KEY_4, "tile"]]
	for pair in key_pairs:
		editor._unhandled_input(_key(pair[0]))
		harness.check(editor.mode == pair[1], "key %s selects %s mode" % [pair[0], pair[1]])
		harness.check(_lit(ui) == [pair[1]], "key %s lights exactly one button" % pair[0])
		harness.check(_visible_tools(ui) == [pair[1]], "key %s shows exactly that mode's box" % pair[0])

	# Re-pressing the active mode's key deselects back to no tool.
	editor._unhandled_input(_key(KEY_4))
	harness.check(editor.mode == "", "re-pressing the active mode's key deselects")
	harness.check(_lit(ui).is_empty(), "deselecting turns every mode button off")
	harness.check(_visible_tools(ui).is_empty(), "deselecting hides every mode's controls")

	# Modifiers never select a mode.
	editor._unhandled_input(_key(KEY_2, true))
	harness.check(editor.mode == "", "Ctrl+2 does not select a mode")

	# The map name field must accept typed digits (acceptance #6 of the plan).
	var name_entry = ui._name_entry
	editor._set_mode("map")
	name_entry.text = "1234"
	name_entry.grab_focus()
	var focused = editor.get_viewport().gui_get_focus_owner()
	harness.check(focused == name_entry, "the map name field can hold keyboard focus")
	editor._unhandled_input(_key(KEY_1))
	editor._unhandled_input(_key(KEY_2))
	editor._unhandled_input(_key(KEY_3))
	editor._unhandled_input(_key(KEY_4))
	harness.check(editor.mode == "map", "typing digits in the name field does not switch modes")
	harness.check(name_entry.text == "1234", "the name field keeps the typed digits")
	name_entry.release_focus()

	# Escape exits any mode, including the UI-only Map mode.
	editor._unhandled_input(_key(KEY_1))
	editor._unhandled_input(_key(KEY_ESCAPE))
	harness.check(editor.mode == "", "Escape exits a mode")
	harness.check(_lit(ui).is_empty(), "Escape unlights every mode button")
	harness.check(_always_visible(ui), "Undo/Redo and the log are visible again after Escape")


# ---------------------------------------------------------------------------
# Mirror toggle: painted cells and their twins, gated by the UI toggle
# ---------------------------------------------------------------------------

func _test_mirror_toggle(harness, editor) -> void:
	var map: Node = editor.map_root
	var ui = ui_of(editor)
	var ground: TileMapLayer = TileBrush.layer_for_brush(map, "ground")
	harness.check(ground != null, "the ground brush resolves to a TileMapLayer")
	if ground == null:
		return
	ui.mode_requested.emit("tile")
	harness.check(editor.mode == "tile", "Tiles mode is active for stroke tests")

	# A fixed off-center target on the 64px lane grid, expressed in the ground
	# layer's own space and projected to a viewport point — no dependency on
	# where the camera centered the view.
	var canvas: Transform2D = editor.get_viewport().get_canvas_transform()
	var local_target := Vector2(192, 256)
	var layer_xform := LaneLogic.viewport_to_node_xform(ground, canvas)
	var viewport_target: Vector2 = layer_xform * local_target

	# What the host paints: the default block option is the FULL TILE, i.e.
	# paint_cells_for_local over the map's tile size.
	var block_cells := TileBrush.paint_cells_for_local(ground, local_target,
			_map_tile_px(map))
	harness.check(block_cells.size() > 0, "the full-tile block covers cells to paint")
	var painted_source := int(ui.selected_tile().get("source_id", -1))
	harness.check(painted_source >= 0, "the tile picker offered a paintable tile")

	# --- mirror ON: stroke paints the clicked block AND its twins ---
	editor._paint_at(viewport_target, false)
	editor._commit_pending()
	var mirrored_ok := true
	for cell in block_cells:
		if ground.get_cell_source_id(cell) != painted_source:
			mirrored_ok = false
		var twin := TileBrush.mirrored_cell(cell, TileBrush.cell_size_of(ground),
				TileBrush.mirror_size_for(ground))
		if twin != cell and ground.get_cell_source_id(twin) != painted_source:
			mirrored_ok = false
	harness.check(mirrored_ok, "a mirror-on stroke paints its block and the mirrored twins")

	# --- erase with mirroring ON clears BOTH sides (proves cells are empty) ---
	editor._paint_at(viewport_target, true)
	editor._commit_pending()
	var erased := _all_cells_empty(ground, block_cells)
	harness.check(erased, "an erase stroke clears the block and its twins")

	# --- mirror OFF: only the clicked block paints; twins stay empty ---
	ui._mirror_toggle.button_pressed = false
	harness.check(not ui.mirror_enabled(), "the Mirror paint toggle is off when pressed off")
	editor._paint_at(viewport_target, false)
	editor._commit_pending()
	var only_clicked := true
	for cell in block_cells:
		if ground.get_cell_source_id(cell) != painted_source:
			only_clicked = false
		var twin := TileBrush.mirrored_cell(cell, TileBrush.cell_size_of(ground),
				TileBrush.mirror_size_for(ground))
		if twin != cell and ground.get_cell_source_id(twin) != -1:
			only_clicked = false
	harness.check(only_clicked, "a mirror-off stroke paints only where clicked (twins stay empty)")

	# One undo step reverts the asymmetric stroke back to the erased state;
	# redo reapplies it.
	editor.undo()
	var undone := true
	for cell in block_cells:
		var twin := TileBrush.mirrored_cell(cell, TileBrush.cell_size_of(ground),
				TileBrush.mirror_size_for(ground))
		if ground.get_cell_source_id(cell) != -1 or ground.get_cell_source_id(twin) != -1:
			undone = false
	harness.check(undone, "one undo reverts the whole mirror-off stroke")
	editor.redo()
	var redone := true
	for cell in block_cells:
		if ground.get_cell_source_id(cell) != painted_source:
			redone = false
	harness.check(redone, "redo reapplies the mirror-off stroke")
	editor.undo()  # leave the map clean for the move tests

	# --- Tiles mode keeps its own mouse contract: left paints, right ERASES
	# (M6 changed nothing here), and Escape exits.
	editor._handle_tile_input(_rclick(viewport_target, true))
	editor._commit_pending()
	var right_erases := true
	for cell in block_cells:
		if ground.get_cell_source_id(cell) != -1:
			right_erases = false
	harness.check(right_erases, "right-click still erases in Tiles mode")

	editor._unhandled_input(_key(KEY_ESCAPE))
	harness.check(editor.mode == "", "Escape exits tile mode")
	harness.check(editor._drag.is_empty(), "Tiles mode opens no move drag (no kind-scoped drag there)")


# ---------------------------------------------------------------------------
# Right-click move, Buildings mode: scaffold-preplaced buildings included
# ---------------------------------------------------------------------------

func _test_move_building(harness, editor) -> void:
	var map: Node = editor.map_root
	var ui = ui_of(editor)
	var castle = map.get_node_or_null("buildings/blue/castle")
	harness.check(castle != null, "the scaffold has a pre-placed castle to move")
	if castle == null:
		return
	var team: Node2D = castle.get_parent()
	var canvas: Transform2D = editor.get_viewport().get_canvas_transform()
	var viewport_pos: Vector2 = LaneLogic.viewport_to_node_xform(team, canvas) * castle.position
	var orig: Vector2 = castle.position

	harness.check(editor.mode == "", "the editor starts a fresh mode for the move tests")
	ui.mode_requested.emit("building")
	harness.check(editor.mode == "building", "Buildings mode selected through the mode panel")
	harness.check(_lit(ui) == ["building"], "the Buildings (2) button is lit")

	# The left-click placement handler is LEFT-only: the right button falls
	# through to the drag machinery instead of placing anything.
	editor._handle_building_input(_rclick(viewport_pos, true))
	harness.check(editor._drag.is_empty(), "the building place handler ignores the right button")

	editor._handle_drag_input(_rclick(viewport_pos, true), "building")
	harness.check(not editor._drag.is_empty(), "a right-press on a building grabs it for dragging")
	if editor._drag.is_empty():
		return
	harness.check(editor._drag.get("node") == castle, "the drag grabbed the castle")
	harness.check(editor._drag.get("orig") == orig, "the drag remembered the original position")

	var pushed := viewport_pos + Vector2(256, 128)
	editor._handle_drag_input(_motion(pushed, MOUSE_BUTTON_MASK_RIGHT), "building")
	var moved: Vector2 = castle.position
	harness.check(moved != orig, "dragging moves the building")
	harness.check(int(moved.x) % 64 == 0 and int(moved.y) % 64 == 0,
			"a moved building lands on the 64px grid (%s)" % moved)

	editor._handle_drag_input(_rclick(viewport_pos, false), "building")
	harness.check(editor._drag.is_empty(), "release closes the drag")
	harness.check(castle.position == moved, "the drag committed the dragged position")

	editor.undo()
	harness.check(castle.position == orig, "one undo restores the original building position")
	editor.redo()
	harness.check(castle.position == moved, "redo re-applies the moved position")
	editor.undo()  # leave the scaffold where we found it
	harness.check(castle.position == orig, "the scaffold is restored for the next test")

	# A motion the UI panel ate (release over the panel): the drag must end
	# rather than follow the cursor forever.
	editor._handle_drag_input(_rclick(viewport_pos, true), "building")
	editor._handle_drag_input(_motion(viewport_pos + Vector2(128, 0), MOUSE_BUTTON_MASK_LEFT),
			"building")
	harness.check(editor._drag.is_empty(), "a drag whose release was eaten by the panel commits")
	editor._handle_drag_input(_rclick(viewport_pos, false), "building")
	editor.undo()
	harness.check(castle.position == orig, "the eaten-release drag is undoable as one action")


# ---------------------------------------------------------------------------
# Right-click move, Lanes mode: lane points
# ---------------------------------------------------------------------------

func _test_move_lane_point(harness, editor) -> void:
	var lane = editor.map_root.get_node_or_null("lanes/mid")
	harness.check(lane is Line2D, "the scaffold's mid lane is available")
	if not (lane is Line2D):
		return
	var ui = ui_of(editor)
	var count_before := (lane as Line2D).get_point_count()
	var canvas: Transform2D = editor.get_viewport().get_canvas_transform()
	var orig: Vector2 = (lane as Line2D).get_point_position(0)
	var viewport_pos: Vector2 = LaneLogic.viewport_to_node_xform(lane as CanvasItem, canvas) * orig

	# Still in Buildings mode from the previous test: switching must unlight it.
	harness.check(editor.mode == "building", "the lane test starts in Buildings mode")
	ui.mode_requested.emit("lane")
	harness.check(editor.mode == "lane", "the mode switch enters Lanes mode")
	harness.check(not ui._mode_buttons["building"].button_pressed,
			"entering Lanes mode turns the Buildings button off")
	harness.check(editor.lane_overlay.lane == lane,
			"Lanes mode lights the overlay for the selected lane")

	# The left-click add handler is LEFT-only: the right button adds no point.
	editor._handle_lane_input(_rclick(viewport_pos, true))
	harness.check(editor._drag.is_empty(), "the lane add handler ignores the right button")
	harness.check((lane as Line2D).get_point_count() == count_before,
			"a right-press adds no lane point")

	editor._handle_drag_input(_rclick(viewport_pos, true), "lane")
	harness.check(editor._drag.get("kind") == "lane" and int(editor._drag.get("index", -2)) == 0,
			"a right-press on a lane point grabs that point")
	if editor._drag.get("kind") != "lane":
		editor._commit_pending()
		return
	harness.check(editor.lane_overlay.lane == lane,
			"the dragged lane shows in the overlay (the lanes node is hidden by design)")

	var pushed := viewport_pos + Vector2(192, -128)
	editor._handle_drag_input(_motion(pushed, MOUSE_BUTTON_MASK_RIGHT), "lane")
	var moved: Vector2 = (lane as Line2D).get_point_position(0)
	harness.check(moved != orig, "dragging moves the lane point")
	harness.check(int(moved.x) % 64 == 0 and int(moved.y) % 64 == 0,
			"a moved lane point snaps to the 64px grid (%s)" % moved)
	harness.check((lane as Line2D).get_point_count() == count_before,
			"dragging a point never inserts or deletes points")
	harness.check(editor.lane_overlay.lane == lane,
			"the overlay still shows the lane being dragged")

	editor._handle_drag_input(_rclick(viewport_pos, false), "lane")
	harness.check(editor._drag.is_empty(), "release commits the lane-point drag")
	harness.check(editor.lane_overlay.lane == lane,
			"Lanes mode keeps its overlay after the drag ends (the tool is still editing)")

	editor.undo()
	harness.check((lane as Line2D).get_point_position(0) == orig,
			"one undo restores the original lane point")
	editor.redo()
	harness.check((lane as Line2D).get_point_position(0) == moved,
			"redo re-applies the moved lane point")
	editor.undo()  # scaffold state as found
	harness.check((lane as Line2D).get_point_position(0) == orig,
			"the lane is restored for the next test")

	# Escape leaves lane mode, which is what clears the overlay.
	editor._unhandled_input(_key(KEY_ESCAPE))
	harness.check(editor.mode == "", "Escape exits Lanes mode")
	harness.check(editor.lane_overlay.lane == null, "leaving Lanes mode clears the overlay")


# A grab with no move leaves NO history entry, and each mode only grabs its own
# kind: lane points in Lanes mode, buildings in Buildings mode.
func _test_move_wiring(harness, editor) -> void:
	var ui = ui_of(editor)
	var history_before: int = editor.undo_redo.get_history_count()

	# Lanes mode must not grab a building, even landed exactly on it.
	var castle = editor.map_root.get_node("buildings/blue/castle")
	var castle_vp: Vector2 = LaneLogic.viewport_to_node_xform(castle.get_parent(),
			editor.get_viewport().get_canvas_transform()) * castle.get("position")
	ui.mode_requested.emit("lane")
	editor._handle_drag_input(_rclick(castle_vp, true), "lane")
	harness.check(editor._drag.is_empty(), "Lanes mode never grabs a building")
	editor._handle_drag_input(_rclick(castle_vp, false), "lane")

	# Buildings mode must not grab a lane point, even landed exactly on it.
	var lane = editor.map_root.get_node("lanes/mid")
	var lane_vp: Vector2 = LaneLogic.viewport_to_node_xform(lane as CanvasItem,
			editor.get_viewport().get_canvas_transform()) * (lane as Line2D).get_point_position(0)
	ui.mode_requested.emit("building")
	editor._handle_drag_input(_rclick(lane_vp, true), "building")
	harness.check(editor._drag.is_empty(), "Buildings mode never grabs a lane point")
	editor._handle_drag_input(_rclick(lane_vp, false), "building")

	# The top-left viewport corner is far from every lane point and building of
	# the fit-framed scaffold (the panel itself is not in play: handlers are
	# invoked directly, not through routed input).
	editor._handle_drag_input(_rclick(Vector2.ZERO, true), "building")
	harness.check(editor._drag.is_empty(), "a right-press on empty ground grabs nothing")
	editor._handle_drag_input(_rclick(Vector2.ZERO, false), "building")

	# The windowed crash (pull request feedback): press a GRABBABLE building,
	# release without any motion. Nothing may error, no history entry may
	# appear, the drag state must clear, and the building stays put.
	var before: Vector2 = castle.get("position")
	editor._handle_drag_input(_rclick(castle_vp, true), "building")
	harness.check(not editor._drag.is_empty(), "the crash-path press grabbed the building")
	editor._handle_drag_input(_rclick(castle_vp, false), "building")
	harness.check(editor._drag.is_empty(), "a press-release with no motion ends the drag cleanly")
	harness.check(editor.undo_redo.get_history_count() == history_before,
			"a press-release with no motion commits no history entry")
	harness.check(castle.get("position") == before, "a no-motion grab leaves the building in place")
	harness.check(editor.undo_redo.get_history_count() == history_before,
			"the kind-scoped refusals committed no history entry either")

	# The drag was grabbable in Buildings mode only.
	editor._handle_drag_input(_rclick(castle_vp, true), "building")
	harness.check(not editor._drag.is_empty(), "Buildings mode grabs the scaffold castle")
	editor._handle_drag_input(_rclick(castle_vp, false), "building")

	# A mode switch commits an open drag exactly like release does.
	editor._handle_drag_input(_rclick(castle_vp, true), "building")
	ui.mode_requested.emit("")
	harness.check(editor._drag.is_empty(), "deselecting commits an open drag")
	harness.check(editor.mode == "", "the deselect reached no tool mode")

	# Escape exits the mode and unlights its button; History + log stay visible.
	ui.mode_requested.emit("tile")
	harness.check(_lit(ui) == ["tile"], "Tiles mode is lit after the switch")
	editor._unhandled_input(_key(KEY_ESCAPE))
	harness.check(editor.mode == "", "Escape exits the active mode")
	harness.check(_lit(ui).is_empty(), "Escape unlights the mode button")
	harness.check(_always_visible(ui), "Undo/Redo and the log are visible with no mode")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func ui_of(editor) -> Node:
	return editor.get_node("UILayer/EditorUI")


# Which mode buttons are lit / which per-mode tool boxes are visible, as ordered
# lists so one assertion covers "exactly one, and the right one".
func _lit(ui) -> Array:
	var lit: Array = []
	for mode_name in ui._mode_buttons:
		if ui._mode_buttons[mode_name].button_pressed:
			lit.append(mode_name)
	return lit


func _visible_tools(ui) -> Array:
	var shown: Array = []
	for mode_name in ui._mode_tools:
		if ui._mode_tools[mode_name].visible:
			shown.append(mode_name)
	return shown


func _always_visible(ui) -> bool:
	var history = ui.get_node_or_null("ToolPanel/Tools/HistoryRow")
	if history == null or not history.visible:
		return false
	var undo_button = ui.get_node_or_null("ToolPanel/Tools/HistoryRow/Undo")
	var redo_button = ui.get_node_or_null("ToolPanel/Tools/HistoryRow/Redo")
	if undo_button == null or redo_button == null:
		return false
	if not undo_button.visible or not redo_button.visible:
		return false
	return ui._log != null and ui._log.visible


func _log_contract_ok(ui) -> bool:
	var log = ui._log
	if log == null:
		return false
	if log.fit_content:
		return false
	if not log.scroll_following:
		return false
	if log.mouse_filter != Control.MOUSE_FILTER_STOP:
		return false
	if not (log.size_flags_vertical & Control.SIZE_EXPAND_FILL):
		return false
	return log.get_parent() == ui.get_node_or_null("ToolPanel/Tools")


func _panels_stop_mouse(ui) -> bool:
	if ui.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	var tool_panel = ui.get_node_or_null("ToolPanel")
	var mode_panel = ui.get_node_or_null("ModePanel")
	if tool_panel == null or mode_panel == null:
		return false
	return tool_panel.mouse_filter == Control.MOUSE_FILTER_STOP \
			and mode_panel.mouse_filter == Control.MOUSE_FILTER_STOP


# The corner check is anchor-based (the layout preset itself is not a readable
# property): TOP_RIGHT anchors the panel's left AND right edges to the right
# side and its top to 0, and it grows leftwards so four buttons never spill off
# the screen.
func _anchored_top_right(ui) -> bool:
	var mode_panel = ui.get_node_or_null("ModePanel")
	if mode_panel == null:
		return false
	if mode_panel.anchor_left != 1.0 or mode_panel.anchor_right != 1.0:
		return false
	if mode_panel.anchor_top != 0.0 or mode_panel.anchor_bottom != 0.0:
		return false
	return mode_panel.grow_horizontal == Control.GROW_DIRECTION_BEGIN


func _collect_scroll_containers(node: Node, found: Array[Node]) -> void:
	for child in node.get_children():
		if child is ScrollContainer:
			found.append(child)
		_collect_scroll_containers(child, found)


func _map_tile_px(map: Node) -> int:
	var raw = map.get("tile_size")
	if (raw is int or raw is float) and raw > 0:
		return int(raw)
	return 64


func _all_cells_empty(layer: TileMapLayer, cells: Array[Vector2i]) -> bool:
	for cell in cells:
		var twin := TileBrush.mirrored_cell(cell, TileBrush.cell_size_of(layer),
				TileBrush.mirror_size_for(layer))
		if layer.get_cell_source_id(cell) != -1:
			return false
		if twin != cell and layer.get_cell_source_id(twin) != -1:
			return false
	return true


func _click(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	return e


# The M6 grab/release event: MOUSE_BUTTON_RIGHT, used for both press and release.
func _rclick(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = pressed
	e.position = pos
	return e


func _motion(pos: Vector2, mask: int) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.button_mask = mask
	return e


func _key(keycode: Key, ctrl: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	e.ctrl_pressed = ctrl
	return e
