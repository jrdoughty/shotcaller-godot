extends Node

@onready var unit : Unit = get_parent().get_parent().get_parent()
@onready var game = get_tree().get_current_scene()
var affected_units = {}

const RANGE = 100
const VALUE = 50

@export var icon : Texture2D
@export var ability_name = "Holy Shield"
@export var description = "The magic aura protects your soldiers" # (String, MULTILINE)
@export var status_effect_icon : Texture2D

func _on_update_timer_timeout():
	$update_timer.start()
	for other_unit in affected_units.keys():
		if (other_unit.global_position - unit.global_position).length() > RANGE:
			other_unit.modifiers.remove_at(other_unit, "hp", "holy_shield")
			affected_units.erase(other_unit)
			other_unit.status_effects.erase("holy_shield")

	for other_unit in unit.units_in_radius:
		if other_unit.team == unit.team and unit.type != "building":
			other_unit.modifiers.remove_at(other_unit, "hp", "holy_shield")
			other_unit.modifiers.add(other_unit, "hp", "holy_shield", VALUE)
			affected_units[other_unit] = true
			other_unit.status_effects["holy_shield"] = {
				icon = status_effect_icon,
				hint = "Holy Shield: Increases health by %d" % (VALUE)
			}
