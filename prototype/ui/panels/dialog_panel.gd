extends Control
var game:Node


# self = game.ui.dialog


onready var display_name := $"%display_name"
onready var msg := $"%msg"
onready var control_delay := $"%control_delay"
onready var sprite := $"%sprite"

var can_hide := false

func _ready():
	game = get_tree().get_current_scene()
	game.connect("game_started", self, "campaign_start")


func campaign_start():
	yield(get_tree().create_timer(5), "timeout")
	var joan = game.player_leaders[0]
	show_msg(joan, "We are under attack!")


func show_msg(leader, msg_text):
	show()
	can_hide = false
	game.selection.select_unit(leader)
	# animate text
	msg.text = msg_text
	#var sprite = index of leader
	#$panel/portrait/sprite.region_rect.position.x = sprite * 64
	display_name.text = leader.name
	yield(get_tree().create_timer(2), "timeout")
	can_hide = true


func hide_msg():
	if can_hide:
		hide()


func _input(event):
	if event.is_pressed():
		game.ui.dialog.hide_msg()
