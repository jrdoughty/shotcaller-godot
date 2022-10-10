extends CanvasLayer
var game:Node

# self = game.ui

var fps:Node
var top_label:Node
var buttons:Node
var stats:Node
var minimap:Node
var minimap_container:Node
var rect_layer: Node
var shop:Node
var controls_menu:Node
var orders_menu:Node
var main_menu:Node
var main_menu_background:Node
var leaders_icons:Node
var orders_button:Node
var shop_button:Node
var controls_button:Node
var menu_button:Node
var inventories:Node
var active_skills:Node

var timer:Timer

func _ready():
	game = get_tree().get_current_scene()

	fps = get_node("%fps")
	top_label = get_node("%main_label")
	shop = get_node("%shop")
	stats = get_node("%stats")
	minimap_container = get_node("%minimap_container")
	minimap = minimap_container.get_node("minimap")
	rect_layer = minimap_container.get_node("rect_layer")
	main_menu = get_node("%main_menu")
	main_menu_background = get_node("background/main")
	buttons = get_node("%buttons")
	orders_menu = get_node("%orders_menu")
	controls_menu = get_node("%controls_menu")
	leaders_icons = get_node("%leaders_icons")

	inventories = stats.get_node("inventories")

	controls_button = buttons.get_node("controls_button")
	shop_button = buttons.get_node("shop_button")
	orders_button = buttons.get_node("orders_button")
	
	active_skills = $bot_mid/stats/active_skills
	
	timer = Timer.new()
	timer.wait_time = 1
	get_node("top_mid").add_child(timer)
	timer.start()
# warning-ignore:return_value_discarded
	timer.connect("timeout",Callable(self,"count_time"))
	
	EventMachine.register_listener(Events.GAME_END, self, "handle_game_end")


func process():
	# if opt.show.fps:
	var f = Engine.get_frames_per_second()
	var n = game.all_units.size()
	fps.set_text('fps: '+str(f)+' u:'+str(n))

	# minimap display update
	if minimap:
		if minimap.update_map_texture:
			minimap.get_map_texture()
		if game.camera.zoom.x <= 1:
			minimap.move_symbols()
			minimap.follow_camera()

	# scale vertical main menu background to fit height
	var h = get_viewport().size.y
	var ratio = get_viewport().size.x / h
	if ratio < 1:
		var s = 1/ratio
		main_menu_background.scale = Vector2(s*1.666,s*1.666)
		main_menu_background.position = Vector2(-528,-300*s)
	else:
		main_menu_background.scale = Vector2(1.666,1.666)
		main_menu_background.position = Vector2(-528,-300)


func count_time():
	if not get_tree().paused:
		game.time += 1
		if game.ended:
			top_label.text = game.victory + ' WINS!'
		else:
			var array = [game.player_kills, game.player_deaths, game.time, game.enemy_kills, game.enemy_deaths]
			top_label.text = "player: %s/%s - time: %s - enemy: %s/%s" % array


func hide_all():
	for panel in self.get_children():
		panel.hide()


func show_all():
	for panel in self.get_children():
		panel.show()


func show_select():
	stats.update()
	if game.can_control(game.selected_unit):
		orders_button.disabled = false
	orders_menu.update()
	controls_menu.update()


func hide_unselect():
	stats.update()
	controls_menu.hide()
	orders_menu.hide()
	controls_button.disabled = true
	orders_button.disabled = true
	inventories.hide()
	shop.update_buttons()
	buttons_update()



func buttons_update():
	orders_button.set_pressed(orders_menu.visible)
	shop_button.set_pressed(shop.visible)
	controls_button.set_pressed(controls_menu.visible)

func handle_game_end(victor : String):
	game.ended = true
	game.victory = victor
	get_tree().paused = true
