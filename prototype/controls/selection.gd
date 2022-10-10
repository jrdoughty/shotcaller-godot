extends Node
var game:Node

# self = game.selection

func _ready():
	game = get_tree().get_current_scene()


func _unhandled_input(event):
	var point = game.camera.get_global_mouse_position()
	
	# KEYBOARD
	if event is InputEventKey:
		if not event.is_pressed():
			if game.selected_unit:
				match event.scancode:
					KEY_E: move(game.selected_unit, point)
					KEY_R: advance(game.selected_unit, point)
					KEY_Q: teleport(game.selected_unit, point)
					KEY_W: change_lane(game.selected_unit, point)
				
				if game.test.unit:
					# attack test
					match event.scancode:
						KEY_A: attack(game.selected_unit, point) 
						KEY_S: stand(game.selected_unit)
					
				game.unit.follow.draw_path(game.selected_unit)

	# CLICK SELECTION
	if event is InputEventMouseButton and not event.pressed: 
		if game.camera.zoom.x <= 1:
			match event.button_index:
				
				MOUSE_BUTTON_LEFT: 
					match game.control_state:
						"selection": select(point)
						"teleport": teleport(game.selected_unit, point)
						"advance": advance(game.selected_unit, point)
						"move": move(game.selected_unit, point)
						"lane": change_lane(game.selected_unit, point)
				
				MOUSE_BUTTON_RIGHT: 
					match game.control_state:
						"selection": advance(game.selected_unit, point)#deselect()
						"teleport": teleport(game.selected_unit, point)
						"advance": advance(game.selected_unit, point)
						"move": move(game.selected_unit, point)
						"lane": change_lane(game.selected_unit, point)
			game.unit.follow.draw_path(game.selected_unit)
		
		
		# MAP CLICK ZOOM IN
		else: 
			match event.button_index:
				MOUSE_BUTTON_LEFT: 
					if(game.camera._touches_info.num_touch_last_frame < 1 and game.camera._touches.size() == 0): #prevent touches converted to clicks from triggering a zoom
						game.camera.zoom_reset()
						game.camera.global_position = point - game.map.mid
	
	
	# TOUCH SELECTION
	if event is InputEventScreenTouch and event.pressed: 
		if game.camera.zoom.x <= 1:
			select(event.position)
		
		# MAP TOUCH ZOOM IN
		else: 
			if(game.camera._touches_info.num_touch_last_frame < 1):#prevent weird warps from taking one figure unchecked at a time
				game.camera.zoom_reset()
				game.camera.global_position = point - game.map.mid

func setup_selection(unit):
	if unit.selectable: game.selectable_units.append(unit)


func select(point):
	var unit_at_point = get_sel_unit_at_point(Vector2(point))
	if unit_at_point:
		select_unit(unit_at_point)


func select_unit(unit):
	deselect()
	game.selected_unit = unit
	
	if game.can_control(unit) and unit.type == "leader":
		game.selected_leader = unit
		game.ui.shop.update_buttons()
		game.ui.inventories.update_buttons()
		game.ui.controls_button.disabled = false
		game.ui.active_skills.update_buttons()
	else:
		game.selected_leader = null
		game.ui.shop.disable_all()
	
	game.unit.follow.draw_path(unit)
	game.unit.hud.show_selected(unit)
	game.ui.show_select()
	
	if unit.display_name == "blacksmith" and not game.ui.shop.visible: 
		game.ui.shop_button.button_down()


func deselect():
	game.control_state = "selection"
	
	if game.selected_unit:
		
		var unit = game.selected_unit
		game.unit.hud.hide_unselect(unit)
				
		if unit.display_name == "blacksmith" and game.ui.shop.visible: 
			game.ui.shop_button.button_down()
	
	var buttons = game.ui.leaders_icons.buttons_name
	for all_leader_name in buttons: 
		buttons[all_leader_name].button_pressed = false
	game.unit.follow.draw_path(null)
	game.selected_unit = null
	game.selected_leader = null
	game.ui.hide_unselect()


func get_sel_unit_at_point(point):
	for unit in game.selectable_units:
		var select_rad =  unit.selection_radius
		var select_pos = unit.global_position + unit.selection_position
		if game.utils.circle_point_collision(point, select_pos, select_rad):
			return unit


func advance(unit, point):
	if unit and unit.attacks and unit.moves and game.can_control(unit):
		var order_point = order(unit, point)
		game.unit.advance.smart(unit, order_point)

func attack(unit, point):
	if unit.attacks and game.can_control(unit):
		var order_point = order(unit, point)
		game.unit.attack.start(Callable(unit,order_point))

func teleport(unit, point):
	if unit.moves and game.can_control(unit):
		var order_point = order(unit, point)
		game.unit.follow.teleport(unit, order_point)

func change_lane(unit, point):
	if unit.moves and game.can_control(unit):
		var order_point = order(unit, point)
		game.unit.follow.change_lane(unit, order_point)

func move(unit, point):
	if unit.moves and game.can_control(unit):
		var order_point = order(unit, point)
		game.unit.move.smart(unit, order_point, "move")

func stand(unit):
	if game.can_control(unit):
		order(unit, null)
		game.unit.move.stand(unit)


func order(unit, point):
	unit.working = true
	unit.hunting = false
	game.unit.attack.set_target(unit, null)
	if point:
		var building = game.utils.get_building(point)
		if building:
			point.y += game.map.tile_size
			var oponent = unit.oponent_team()
			match building.team:
				"neutral": unit.after_arive = "conquer"
				unit.team: unit.after_arive = "stop"
				oponent: unit.after_arive = "attack"
			if building.display_name == "church":
				unit.after_arive = "pray"
		return point
