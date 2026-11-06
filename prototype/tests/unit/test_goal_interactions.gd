extends RefCounted

const GoalContract = preload("res://goap/goap_system/goal_contract.gd")


# Minimal goal mock that exposes configurable priority, validity, and desired-state behavior.
class TestGoal:
	extends RefCounted
	var _class_name: String
	var _priority_fn: Callable
	var _is_valid_fn: Callable
	var _desired_state_fn: Callable

	func _init(
		class_name: String,
		priority_fn: Callable,
		is_valid_fn: Callable,
		desired_state_fn: Callable = Callable()
	):
		_class_name = class_name
		_priority_fn = priority_fn
		_is_valid_fn = is_valid_fn
		_desired_state_fn = desired_state_fn

	func get_class_name() -> String:
		return _class_name

	func is_valid(agent) -> bool:
		return _is_valid_fn.call(agent)

	func priority(agent) -> int:
		return _priority_fn.call(agent)

	func get_desired_state(agent) -> Dictionary:
		if _desired_state_fn.is_null():
			return {}
		return _desired_state_fn.call(agent)


# Minimal agent mock that exposes a configurable state dictionary.
class TestAgent:
	extends RefCounted
	var _state: Dictionary = {}

	func get_state(state_name: String, default = null):
		return _state.get(state_name, default)

	func set_state(state_name: String, value):
		_state[state_name] = value

	func set_goals(goals: Array):
		_goals = goals

	var _goals: Array = []

	func get_best_goal():
		var highest_priority = null
		for goal in _goals:
			if goal.is_valid(self) and (
				highest_priority == null
				or goal.priority(self) > highest_priority.priority(self)
			):
				highest_priority = goal
		return highest_priority


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func run(harness) -> void:
	harness.check_equal(
		_test_priority_ordering(),
		true,
		"Goal with the highest valid priority is selected."
	)

	harness.check(
		_test_validity_filtering(),
		"Invalid goals are excluded from selection."
	)

	harness.check(
		_test_state_independence(),
		"Changing one goal's state does not affect another goal's validity or priority."
	)

	harness.check(
		_test_conditional_validity(),
		"Goals that become valid/invalid based on agent state are filtered correctly."
	)


# ---------------------------------------------------------------------------
# Priority ordering
# ---------------------------------------------------------------------------

func _test_priority_ordering() -> bool:
	var agent = TestAgent.new()

	var low_goal = TestGoal.new(
		"LowPriority",
		func(_agent): return 1,
		func(_agent): return true
	)
	var mid_goal = TestGoal.new(
		"MidPriority",
		func(_agent): return 5,
		func(_agent): return true
	)
	var high_goal = TestGoal.new(
		"HighPriority",
		func(_agent): return 10,
		func(_agent): return true
	)

	agent.set_goals([low_goal, mid_goal, high_goal])
	var selected = agent.get_best_goal()
	return selected.get_class_name() == "HighPriority"


# ---------------------------------------------------------------------------
# Validity filtering
# ---------------------------------------------------------------------------

func _test_validity_filtering() -> bool:
	var agent = TestAgent.new()

	var always_valid = TestGoal.new(
		"AlwaysValid",
		func(_agent): return 1,
		func(_agent): return true
	)
	var conditional_valid = TestGoal.new(
		"ConditionalValid",
		func(_agent): return 5,
		func(agent): return agent.get_state("is_valid_goal", false)
	)

	# Initially only AlwaysValid is valid
	agent.set_goals([always_valid, conditional_valid])
	var selected = agent.get_best_goal()
	if selected.get_class_name() != "AlwaysValid":
		return false

	# Now make the conditional goal valid — it should win on priority
	agent.set_state("is_valid_goal", true)
	selected = agent.get_best_goal()
	return selected.get_class_name() == "ConditionalValid"


# ---------------------------------------------------------------------------
# State independence
# ---------------------------------------------------------------------------

func _test_state_independence() -> bool:
	var agent = TestAgent.new()

	# Goal A's validity depends on "state_a"
	var goal_a = TestGoal.new(
		"GoalA",
		func(_agent): return 3,
		func(agent): return agent.get_state("state_a", false)
	)

	# Goal B's validity depends on "state_b" — a completely separate state key
	var goal_b = TestGoal.new(
		"GoalB",
		func(_agent): return 3,
		func(agent): return agent.get_state("state_b", false)
	)

	agent.set_goals([goal_a, goal_b])

	# Enable only Goal A
	agent.set_state("state_a", true)
	var selected = agent.get_best_goal()
	if selected.get_class_name() != "GoalA":
		return false

	# Enable only Goal B — Goal A should no longer win even though both have same priority
	agent.set_state("state_a", false)
	agent.set_state("state_b", true)
	selected = agent.get_best_goal()
	return selected.get_class_name() == "GoalB"


# ---------------------------------------------------------------------------
# Conditional validity
# ---------------------------------------------------------------------------

func _test_conditional_validity() -> bool:
	var agent = TestAgent.new()

	var combat_goal = TestGoal.new(
		"Combat",
		func(_agent): return 8,
		func(agent): return agent.get_state("has_enemy_nearby", false)
	)

	var gather_goal = TestGoal.new(
		"Gather",
		func(_agent): return 2,
		func(_agent): return true
	)

	agent.set_goals([combat_goal, gather_goal])

	# No enemy nearby — gather should be selected
	agent.set_state("has_enemy_nearby", false)
	var selected = agent.get_best_goal()
	if selected.get_class_name() != "Gather":
		return false

	# Enemy appears — combat has higher priority and is now valid
	agent.set_state("has_enemy_nearby", true)
	selected = agent.get_best_goal()
	if selected.get_class_name() != "Combat":
		return false

	# Enemy leaves again — should revert to gather
	agent.set_state("has_enemy_nearby", false)
	selected = agent.get_best_goal()
	return selected.get_class_name() == "Gather"
