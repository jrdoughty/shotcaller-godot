extends Node2D

# self = game

var paused:bool = true
var time:int = 0
var player_kills:int = 0
var player_deaths:int = 0
var player_choose_leaders:Array = []
var player_leaders:Array = []
var player_units:Array = []
var player_buildings:Array = []
var enemy_kills = 0
var enemy_deaths = 0
var enemy_choose_leaders:Array = []
var enemy_leaders:Array = []
var enemy_units:Array = []
var enemy_buildings:Array = []
var all_units:Array = []
var selectable_units:Array = []
var neutral_buildings:Array = []
var all_buildings:Array = []

var selected_unit:Node2D
var selected_leader:Node2D

var player_team:String = "blue"
var enemy_team:String = "red"

var rng = RandomNumberGenerator.new()

@onready var maps = get_node("maps")
@onready var camera = get_node("camera")
@onready var unit = get_node("unit")
@onready var collision = get_node("collision")
@onready var ui = get_node("ui")
@onready var selection = get_node("selection")
@onready var utils = get_node("utils")
@onready var test = get_node("test")

var map:Node

var control_state = "selection"

var built:bool = false
var started:bool = false
var ended:bool = false

var victory:String


func _ready():
	get_tree().paused = true


func _process(delta: float) -> void:
	if started: camera.process()
	ui.process()


func build():
	if not built:
		built = true
		
		if test.unit: # debug units
			ui.main_menu.get_node("container/play_button").play_down()


func start():
	if not started:
		started = true
		paused = false
		
		maps.setup_buildings()
		map.blocks.setup_quadtree()
		#Engine.time_scale = 3
		
		rng.randomize()
		maps.setup_lanes()
		ui.orders_menu.build()
		unit.follow.setup_pathfind()
		
		if test.unit:
			test.spawn_unit()
		elif test.stress:
			test.spawn_random_units()
		else: 
			unit.spawn.start()
			ui.get_node("score_board").visible = false
			await get_tree().create_timer(4).timeout
			unit.spawn.leaders()
			maps.setup_leaders()


func _physics_process(delta):
	if started: collision.process(delta)


func can_control(unit1):
	return (unit1 and not unit1.dead) # and unit.team == game.player_team 
