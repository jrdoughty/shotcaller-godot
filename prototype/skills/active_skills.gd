extends ItemList

@onready var _game: Node = get_tree().get_current_scene()
@onready var _skill_buttons = $placeholder.get_children()
@onready var _tip = $tip

var player_leaders_skills = {}
var enemy_leaders_skills = {}
var _waiting_for_point = false

signal point(pos)

class ActiveSkill:
	var display_name
	var description
	var cooldown: int
	var current_cooldown: int
	var effects: Array # array of skill effects, looks like [Callable, Callable, ..]
	
	func _init(_display_name,_description,_cooldown,_effects):
		self.display_name = _display_name
		self.description = _description
		self.cooldown = _cooldown
		self.current_cooldown = 0
		self.effects = _effects
	
	func on_cooldown():
		return self.current_cooldown > 0

# "Bulding blocks" to write code for skills
# V V V
# Gets all units in unit radius, for AOE skills
func _get_units_in_radius(unit, radius):
	var unit_position = unit.global_position + unit.collision_position
	var units_in_near_blocks = _game.map.blocks.get_units_in_radius(unit_position, 2) # todo: maybe 1
	var units_in_radius = []
	for another_unit in units_in_near_blocks:
		if unit.global_position.distance_to(another_unit.global_position) <= radius:
			units_in_radius.append(another_unit)
	return units_in_radius

# Async func to get player point target
func _get_point_target():
	self._waiting_for_point = true
	var point = await self.point
	self._waiting_for_point = false
	return point
# ^ ^ ^

# Example how to write AOE skills
func rollo_basic():
	var leader = _game.selected_leader
	
	var targets = []
	for unit in _get_units_in_radius(leader, 100):
		if unit.team != leader.team:
			if unit.type == "leader" or unit.type == "pawn":
				targets.append(unit)
	
	if targets.size() >= 3:
		for unit in targets:
			_game.unit.attack.spell_hit(leader, unit, 100)
	
	return true


# Example how to write code for point target skill
func robin_special():
	var leader = _game.selected_leader
	# Wait for player to click checked map to get x and y position
	var point_target = await _get_point_target().completed
	# If player did not clicked then return false, means skill wasn't used and 
	# we didn't want to apply cooldown
	if point_target == null:
		return false
	# do what we need with position
	leader.global_position = _game.get_global_mouse_position()
	# return true, means skill was used and we need to apply cooldown
	return true


var active_skills = {
	"rollo": [
		ActiveSkill.new(
			"Wolf's teeth",
			"Deals damage in an AOE around it for 100 damage whenever >3 units are within range",
			120,
			[funcref(self, "rollo_basic")]
		)
	],
	"raja": [
		ActiveSkill.new(
			"Labh, son of Ganesha",
			"Spawn an elephant companion. Can only spawn one elephant at a time", 
			60,
			[funcref(self, "raja_basic")]
		)
	],
	"robin": [
		ActiveSkill.new(
			"Call of the forest",
			"Teleport",
			30,
			[funcref(self, "robin_special")]
		)
	],
	"osman": [],
	"takoda": [],
	"arthur": [],
	"lorne": [],
	"bokuden": [],
	"sida": [],
	"tomyris": [],
	"nagato": [],
	"hongi": [],
}


func _input(event):
	if self._waiting_for_point:
		if event is InputEventMouseButton:
			if event.pressed:
				if event.button_index == 1:
					emit_signal("point", get_global_mouse_position())
		elif Input.is_action_pressed("ui_cancel"):
			emit_signal("point", null)


func _ready():
	hide()
	clear()


func clear():
	for button in _skill_buttons:
		button.reset()


func update_buttons():
	clear()
	show()
	var leader = _game.selected_leader
	for index in active_skills[leader.display_name].size():
		_skill_buttons[index].setup(active_skills[leader.display_name][index])


func new_skills(leader, skills_storage):
	skills_storage[leader.display_name] = active_skills[leader.display_name].duplicate()


func build_leaders():
	for leader in _game.player_leaders:
		new_skills(leader, player_leaders_skills)
	for leader in _game.enemy_leaders:
		new_skills(leader, enemy_leaders_skills)


func _physics_process(delta):
	_tip.visible = self._waiting_for_point
	for skills in player_leaders_skills.values() + enemy_leaders_skills.values():
		for skill in skills:
			skill.current_cooldown = clamp(skill.current_cooldown - 1, 0, skill.current_cooldown)
