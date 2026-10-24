extends RefCounted

const Planner = preload("res://goap/goap_system/planner.gd")


# Small contract doubles let planner behavior be tested without running a real agent.
class TestAgent:
	extends RefCounted
	var state := {}

	func get_state(state_name: String, default_value = null):
		return state.get(state_name, default_value)


class TestGoal:
	extends RefCounted
	var desired_state: Dictionary

	func _init(state: Dictionary):
		desired_state = state

	func get_desired_state(_agent) -> Dictionary:
		return desired_state


class TestAction:
	extends RefCounted
	var action_name: String
	var cost: int
	var preconditions: Dictionary
	var effects: Dictionary

	func _init(
		name: String, action_cost: int, action_preconditions: Dictionary, action_effects: Dictionary
	):
		action_name = name
		cost = action_cost
		preconditions = action_preconditions
		effects = action_effects

	func is_valid(_agent) -> bool:
		return true

	func get_cost(_agent) -> int:
		return cost

	func get_preconditions() -> Dictionary:
		return preconditions

	func get_effects() -> Dictionary:
		return effects

	func get_class_name() -> String:
		return action_name


func run(harness) -> void:
	var planner = Planner.new()
	var agent = TestAgent.new()
	var goal = TestGoal.new({"finished": true})
	var costly_action = TestAction.new("Costly", 5, {}, {"finished": true})
	var cheap_action = TestAction.new("Cheap", 1, {}, {"finished": true})
	planner.set_actions([costly_action, cheap_action])
	var cheapest_plan = planner.get_plan(agent, goal)
	harness.check_equal(cheapest_plan.size(), 1, "Planner returns a one-step solution.")
	if not cheapest_plan.is_empty():
		harness.check_equal(
			cheapest_plan[0].get_class_name(), "Cheap", "Planner selects the lowest-cost solution."
		)

	var prepare_action = TestAction.new("Prepare", 1, {}, {"ready": true})
	var finish_action = TestAction.new("Finish", 1, {"ready": true}, {"finished": true})
	# List the dependent action first to verify planning follows preconditions, not registry order.
	planner.set_actions([finish_action, prepare_action])
	var ordered_plan = planner.get_plan(agent, goal)
	harness.check_equal(ordered_plan.size(), 2, "Planner resolves action preconditions.")
	if ordered_plan.size() == 2:
		harness.check_equal(
			ordered_plan[0].get_class_name(),
			"Prepare",
			"Prerequisite action is planned before its dependent action."
		)
		harness.check_equal(
			ordered_plan[1].get_class_name(), "Finish", "Goal-producing action is planned last."
		)

	planner.set_actions([])
	harness.check(
		planner.get_plan(agent, goal).is_empty(),
		"Planner returns no plan when no action can satisfy the goal."
	)

	# --- Contradictory preconditions (documents current behavior) ---
	#
	# The goal requires has_weapon to stay true (it is true in the world now).
	# The only way to reach "finished" is an action whose precondition demands
	# has_weapon to be false. The current planner satisfies that precondition
	# by planning DropWeapon, which negates a fact the goal requires, leaving
	# the goal unsatisfied after the plan runs.
	var drop_weapon = TestAction.new("DropWeapon", 1, {}, {"has_weapon": false})
	var finish_no_weapon = TestAction.new(
		"FinishNoWeapon", 1, {"has_weapon": false}, {"finished": true}
	)
	var weapon_agent = TestAgent.new()
	weapon_agent.state = {"has_weapon": true}
	var weapon_goal = TestGoal.new({"finished": true, "has_weapon": true})
	planner.set_actions([drop_weapon, finish_no_weapon])
	var conflicting_plan = planner.get_plan(weapon_agent, weapon_goal)
	harness.check_equal(
		conflicting_plan.size(),
		2,
		"Planner plans the action that negates a satisfied goal fact (current behavior)."
	)
	if conflicting_plan.size() == 2:
		harness.check_equal(
			conflicting_plan[0].get_class_name(), "DropWeapon",
			"Negating action is planned first (current behavior)."
		)
		harness.check_equal(
			conflicting_plan[1].get_class_name(), "FinishNoWeapon",
			"Goal-producing action is planned after the negation (current behavior)."
		)

	# --- Precondition value vs unset state key ---
	# A precondition of `false` is not satisfied by an unset key: the agent
	# state reads null, and null != false, so the requirement is not met.
	var finish_needs_no_path = TestAction.new(
		"FinishNeedsNoPath", 1, {"has_path": false}, {"finished": true}
	)
	planner.set_actions([finish_needs_no_path])
	var path_goal = TestGoal.new({"finished": true})
	var empty_agent = TestAgent.new()
	harness.check(
		planner.get_plan(empty_agent, path_goal).is_empty(),
		"A false precondition is not satisfied by an unset state key."
	)
	empty_agent.state = {"has_path": false}
	harness.check_equal(
		planner.get_plan(empty_agent, path_goal).size(),
		1,
		"A false precondition is satisfied when the key is explicitly false."
	)

	# --- Unreachable multi-fact goal ---
	# Only one of the two required facts can be produced: no plan (and no
	# partial plan) may be returned.
	var only_a = TestAction.new("OnlyA", 1, {}, {"a": true})
	planner.set_actions([only_a])
	harness.check(
		planner.get_plan(TestAgent.new(), TestGoal.new({"a": true, "b": true})).is_empty(),
		"No plan is returned when one required fact cannot be produced."
	)

	# --- Precondition contradicting an outstanding requirement ---
	# The goal still requires b: true. X's precondition demands b: false while
	# Y can flip b. The current planner plans Y before X, leaving b false after
	# the plan runs and violating the goal.
	var x_action = TestAction.new("X", 1, {"b": false}, {"a": true})
	var y_action = TestAction.new("Y", 1, {}, {"b": false})
	planner.set_actions([x_action, y_action])
	var contradictory_plan = planner.get_plan(
		TestAgent.new(), TestGoal.new({"a": true, "b": true})
	)
	harness.check_equal(
		contradictory_plan.size(),
		2,
		"Planner plans a branch whose precondition contradicts an outstanding goal fact (current behavior)."
	)
	if contradictory_plan.size() == 2:
		harness.check_equal(
			contradictory_plan[0].get_class_name(), "Y",
			"Negating action is planned first (current behavior)."
		)
		harness.check_equal(
			contradictory_plan[1].get_class_name(), "X",
			"Contradicting action is planned after the negation (current behavior)."
		)
