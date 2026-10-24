extends Node

# self = GoapActionPlanner
var _actions: Array
const MAX_PLAN_DEPTH := 64


# Set actions available for planning.
# This can be changed at runtime for more dynamic options.
func set_actions(actions: Array):
	_actions = actions


# Receives a goal and returns a list of actions to be executed.
func get_plan(agent, goal) -> Array:
	var desired_state: Dictionary = goal.get_desired_state(agent)

	if desired_state.is_empty():
		return []
	return _find_best_plan(goal, desired_state, agent)


func _find_best_plan(goal, desired_state: Dictionary, agent):
	# Goal is set as root action.
	var root = {
		"action": goal,
		"state": desired_state,
		"children": [],
	}

	# Build plans will populate root with children.
	# In case it doesn't find a valid path, it will return false.
	if _build_plans(root, agent):
		var plans = _transform_tree_into_array(root, agent)

		if plans.is_empty():
			return []

		return _get_cheapest_plan(plans)

	return []


# Compares plan cost and returns the actions included in the cheapest one.
func _get_cheapest_plan(plans):
	var best_plan = null
	for plan in plans:
		if best_plan == null or plan.cost < best_plan.cost:
			best_plan = plan
	return best_plan.actions


# Builds graph with actions.
# Only includes valid plans that achieve the goal.
#
# This function uses recursion to build the graph. This is
# necessary because any new action included in the graph may
# add preconditions to the desired state that can be satisfied
# by previously considered actions, meaning that on every step we
# need to iterate from the beginning to find all solutions.
#
# Recursive planning is bounded and rejects repeated unsatisfied states.
#
# "satisfied" collects the expected values of facts that this branch already
# requires and that currently hold in the world (at this node or an ancestor).
# A planned action whose preconditions negate one of those facts would leave
# the goal unsatisfied after the plan runs, so such branches are rejected.
# Returns true if the path has a solution.
func _build_plans(
	step, agent, visited_states: Dictionary = {}, depth: int = 0, satisfied: Dictionary = {}
):
	var has_followup := false

	# Each node in the graph has its own desired state.
	var state: Dictionary = step.state.duplicate()

	# Check whether the current state is satisfied.
	var node_satisfied: Dictionary = {}
	for state_name in step.state:
		var actual_state = agent.get_state(state_name)
		if actual_state is Object:
			actual_state = true
		var world_state = WorldState.get_state(state_name)
		if world_state is Object:
			world_state = true
		var expected_state = state[state_name]
		if expected_state == actual_state or expected_state == world_state:
			state.erase(state_name)
			node_satisfied[state_name] = expected_state

	# If the state is empty, the branch already found a solution.
	if state.is_empty():
		return true
	if depth >= MAX_PLAN_DEPTH:
		return false

	var state_signature = _state_signature(state)
	if visited_states.has(state_signature):
		return false
	var next_visited_states = visited_states.duplicate()
	next_visited_states[state_signature] = true

	# Facts satisfied at this node or any ancestor, with their expected values.
	var satisfied_so_far: Dictionary = satisfied.duplicate()
	for state_name in node_satisfied:
		satisfied_so_far[state_name] = node_satisfied[state_name]

	for action in _actions:
		if not action.is_valid(agent):
			continue

		var should_use_action := false
		var effects: Dictionary = action.get_effects()
		var desired_state: Dictionary = state.duplicate()

		# Check whether the action should be used.
		for state_name in desired_state:
			if desired_state[state_name] == effects.get(state_name):
				desired_state.erase(state_name)
				should_use_action = true

		if should_use_action:
			# Add action preconditions to the desired state. A precondition
			# that contradicts an outstanding requirement in this branch, or
			# a fact that an ancestor already requires to stay satisfied,
			# would make the plan unable to achieve the goal: reject it.
			var preconditions: Dictionary = action.get_preconditions()
			var conflicts := false
			for precondition in preconditions:
				var value = preconditions[precondition]
				if (
					(
						desired_state.has(precondition)
						and desired_state[precondition] != value
					)
					or (
						satisfied_so_far.has(precondition)
						and satisfied_so_far[precondition] != value
					)
				):
					conflicts = true
					break
			if conflicts:
				continue
			for precondition in preconditions:
				desired_state[precondition] = preconditions[precondition]

			var step_node = {
				"action": action,
				"state": desired_state,
				"children": [],
			}

			# If desired state is empty, this action can be included.
			# If it is not empty, _build_plans is called again recursively
			# so it can try to find actions that satisfy the current state.
			if desired_state.is_empty() or _build_plans(
				step_node, agent, next_visited_states, depth + 1, satisfied_so_far
			):
				step.children.append(step_node)
				has_followup = true

	return has_followup


func _state_signature(state: Dictionary) -> String:
	var state_names = state.keys()
	state_names.sort()
	var values: Array[String] = []
	for state_name in state_names:
		values.append("%s=%s" % [str(state_name), var_to_str(state[state_name])])
	return ";".join(values)


# Transforms graph with actions into a list of actions and calculates cost.
func _transform_tree_into_array(p, agent):
	var plans = []

	if p.children.is_empty() and p.action.has_method("get_cost"):
		plans.append({"actions": [p.action], "cost": p.action.get_cost(agent)})
		return plans

	for child in p.children:
		for child_plan in _transform_tree_into_array(child, agent):
			if p.action.has_method("get_cost"):
				child_plan.actions.append(p.action)
				child_plan.cost += p.action.get_cost(agent)
			plans.append(child_plan)

	return plans


# Prints a plan. Used for debugging only.
func _print_plan(plan):
	var actions = []
	for action in plan.actions:
		actions.append(action.get_class_name())
	print("action_planner: ", {"cost": plan.cost, "actions": actions})
