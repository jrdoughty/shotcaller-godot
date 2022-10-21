#
# Goal contract
#
extends Node

var _goals = {
	"AttackEnemyGoal": AttackEnemyGoal.new()
}

func get_goal(goal_name, default = null):
	return _goals.get(goal_name, default)
  
  
func set_goal(goal_name, value):
  _goals[goal_name] = value
