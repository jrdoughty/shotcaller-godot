extends RefCounted

const GoalContract = preload("res://goap/goap_system/goal_contract.gd")
<<<<<<< HEAD


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
=======
var _Agent = load("res://goap/goap_system/agent.gd")


# Mock goal that extends GoalContract so production code paths (is_valid,
# priority) are exercised rather than a hand-rolled implementation.
class MockGoal extends GoalContract:
	var valid: bool = true
	var prio: int = 1
	var valid_calls: int = 0
	var priority_calls: int = 0
	var on_valid: Callable = Callable()

	func _init(v: bool = true, p: int = 1) -> void:
		valid = v
		prio = p

	func is_valid(_agent: Variant) -> bool:
		valid_calls += 1
		if not on_valid.is_null():
			on_valid.call()
		if not valid:
			return false
		return true

	func priority(_agent: Variant) -> int:
		priority_calls += 1
		return prio


# Helper to set up an agent with injected goals and a goal tracker.
# Returns [agent, recorder] where recorder.goals is populated by signals.
func _setup(goals: Array) -> Array:
	var agent = _Agent.new()
	agent._goals = goals  # inject mock goals directly

	var recorder = {"goals": []}
	agent.goal_changed.connect(func(g): recorder.goals.append(g))

	return [agent, recorder]


func run(harness: Node) -> void:
	# ---- 1. equal-priority tie-breaking ----
	# Production uses > (strict), so the *first* inserted goal wins ties.
	var m1 := MockGoal.new(true, 5)
	var m2 := MockGoal.new(true, 5)
	var setup_result = _setup([m1, m2])
	var agent = setup_result[0]
	var recorder = setup_result[1]
	var best = agent._get_best_goal()
	harness.check(best == m1, "Equal-priority: first inserted goal wins (strict > in _get_best_goal).")
	harness.check(m1.valid_calls >= 1, "Equal-priority: first goal's is_valid() was called.")
	harness.check(m2.valid_calls >= 1, "Equal-priority: second goal's is_valid() was called.")
	agent.free()

	# ---- 2. no valid goals ----
	var invalid_goal := MockGoal.new(false, 10)
	var setup_result2 = _setup([invalid_goal])
	var agent2 = setup_result2[0]
	var recorder2 = setup_result2[1]
	best = agent2._get_best_goal()
	harness.check(best == null, "No valid goals: _get_best_goal() returns null.")
	agent2.free()

	# ---- 3. is_valid() side effects ----
	# The first goal is invalid but has a side-effect that makes the second
	# goal valid, exercising the callback path inside is_valid().
	var flag = {"second_valid": false}
	var side_effect = func(): flag.second_valid = true

	var inv := MockGoal.new(false, 3)
	inv.on_valid = side_effect

	var valid := MockGoal.new(false, 3)  # initially invalid
	var setup_result3 = _setup([inv, valid])
	var agent3 = setup_result3[0]
	var recorder3 = setup_result3[1]
	best = agent3._get_best_goal()

	harness.check(flag.second_valid, "is_valid() side effect fired during iteration.")
	harness.check(inv.valid_calls >= 1, "is_valid side-effects: invalid goal was evaluated.")

	# The original invalid goal returns false, so it is skipped.
	# The second goal is *still* invalid (side-effect only set flag, did not change mock state).
	harness.check(best == null, "is_valid side-effect: second mock goal remains invalid (no state mutation in mock).")
	agent3.free()

	# ---- 4. priority changes while valid ----
	var prio_a := MockGoal.new(true, 5)
	var prio_b := MockGoal.new(true, 3)
	var setup_result4 = _setup([prio_a, prio_b])
	var agent4 = setup_result4[0]
	var recorder4 = setup_result4[1]

	best = agent4._get_best_goal()
	harness.check(best == prio_a, "Priority change: higher-priority goal (A=5) is selected first.")

	# B's priority increases above A's while A is still valid
	prio_b.prio = 10
	best = agent4._get_best_goal()
	harness.check(best == prio_b, "Priority change: _get_best_goal() reflects updated priority (B=10 > A=5).")

	# A's priority increases above B's
	prio_a.prio = 15
	best = agent4._get_best_goal()
	harness.check(best == prio_a, "Priority change: A regains lead (A=15 > B=10).")
	agent4.free()
>>>>>>> main
