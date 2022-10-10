extends CenterContainer

@onready var ability_preview_scene = preload("res://ui/leader_preview/ability_preview.tscn")
@onready var ability_container = $PanelContainer/VBoxContainer/VBoxContainer

func _ready():
	is_empty()
	
func prepare(leader):
	is_empty()
	var leader_scene = load("res://leaders/%s.tscn" % leader)
	var leader_instance = leader_scene.instantiate()
	$"%leader_name".text = leader
	for ability in leader_instance.get_node("behavior/abilities").get_children():
		var ability_preview = ability_preview_scene.instantiate()
		ability_preview.prepare(ability.icon, ability.ability_name, ability.description)
		ability_container.add_child(ability_preview)
	leader_instance.queue_free()


func is_empty():
	for child in ability_container.get_children():
		ability_container.remove_child(child)
