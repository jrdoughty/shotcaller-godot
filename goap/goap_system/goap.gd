extends Node

# Goap global class.
# This class is an autoload accessible globally.
# Access the autoload list in the Godot settings.
#
# Initializes the planner and exposes reusable GOAP/gameplay services.
# In your game, you might want to have different planners
# for different enemy/NPC types, and even change the set of actions at runtime.


var _action_planner = preload("res://goap/goap_system/planner.gd").new()
var _actions = preload("res://goap/game_logic/action_registry.gd").new()
var _goals = preload("res://goap/game_logic/goal_registry.gd").new()


# --- EXPERIMENT SCAFFOLDING (exp/erase-ab only; env-gated, off by default) ---
# DSH_GOAP_MODE = base | guard | stagger   -> which pump variant runs
# DSH_GOAP_DIAG = 1                        -> per-unit pump cost attribution
# With no env vars set this is byte-equivalent behavior to main's pump.
var pump_mode := ""
var diag := false
var _stagger_rng := RandomNumberGenerator.new()
var _us := {"alive": 0, "dead": 0}
var _calls := {"alive": 0, "dead": 0}
var _skipped_dead := 0
var _cost := {
	"goal_alive": 0, "goal_dead": 0,
	"plan_alive": 0, "plan_dead": 0,
	"follow_alive": 0, "follow_dead": 0,
}
var _plans := {"alive": 0, "dead": 0}
var _ticks := 0


func _ready():
	pump_mode = OS.get_environment("DSH_GOAP_MODE")
	if pump_mode == "":
		pump_mode = "base"
	diag = OS.get_environment("DSH_GOAP_DIAG") == "1"
	# Dedicated RNG stream so the experiment's phase randomization never
	# consumes the game's global RNG (that would change the simulation).
	_stagger_rng.seed = 20261112
	_action_planner.set_actions(_actions.get_all_actions())


func get_action_planner():
	return _action_planner


func get_goal(goal):
	return _goals.get_goal(goal)


func get_action(action):
	return _actions.get_action(action)


# --- experiment-only diagnostic accounting ---
func diag_cost(dead: bool, kind: String, us: int) -> void:
	_cost[kind + ("_dead" if dead else "_alive")] += us


func diag_plan(dead: bool) -> void:
	if dead:
		_plans["dead"] += 1
	else:
		_plans["alive"] += 1


func take_diag() -> Dictionary:
	var out := _cost.duplicate(true)
	out["pump_us"] = _us["alive"] + _us["dead"]
	out["pump_us_alive"] = _us["alive"]
	out["pump_us_dead"] = _us["dead"]
	out["calls_alive"] = _calls["alive"]
	out["calls_dead"] = _calls["dead"]
	out["skipped_dead"] = _skipped_dead
	out["plans_alive"] = _plans["alive"]
	out["plans_dead"] = _plans["dead"]
	out["ticks"] = _ticks
	_cost["goal_alive"] = 0
	_cost["goal_dead"] = 0
	_cost["plan_alive"] = 0
	_cost["plan_dead"] = 0
	_cost["follow_alive"] = 0
	_cost["follow_dead"] = 0
	_us["alive"] = 0
	_us["dead"] = 0
	_calls["alive"] = 0
	_calls["dead"] = 0
	_skipped_dead = 0
	_plans["alive"] = 0
	_plans["dead"] = 0
	_ticks = 0
	return out


func diag_us(dead: bool, unit, t0: int) -> void:
	var spent := Time.get_ticks_usec() - t0
	var key := "dead" if unit.dead else "alive"
	_us[key] += spent
	_calls[key] += 1


# The pump (see DECISIONS.md D13). Deliberately named without a leading
# underscore: it is called from game.gd, it is not a Godot virtual.
func physics_process(units, delta):
	if diag:
		_ticks += 1
	match pump_mode:
		"guard":
			# Variant C: skip corpses, do not mutate all_units.
			if diag:
				for unit in units:
					if unit.agent and not unit.dead:
						var t0 := Time.get_ticks_usec()
						unit.agent.goap_process(delta)
						diag_us(unit.dead, unit, t0)
					elif unit.agent:
						_skipped_dead += 1
			else:
				for unit in units:
					if unit.agent and not unit.dead:
						unit.agent.goap_process(delta)
		"stagger":
			# Variant E: d15ca30's ai_delay stagger alone (no dead guard, no erase).
			if diag:
				for unit in units:
					if unit.agent:
						if unit.ai_delay < 0:
							unit.ai_delay = _stagger_rng.randi_range(0, 6)
						if unit.ai_delay == 0:
							var t0 := Time.get_ticks_usec()
							unit.agent.goap_process(delta)
							diag_us(unit.dead, unit, t0)
							unit.ai_delay = 6
						else:
							unit.ai_delay -= 1
			else:
				for unit in units:
					if unit.agent:
						if unit.ai_delay < 0:
							unit.ai_delay = _stagger_rng.randi_range(0, 6)
						if unit.ai_delay == 0:
							unit.agent.goap_process(delta)
							unit.ai_delay = 6
						else:
							unit.ai_delay -= 1
		_:
			# Variant A: upstream's pump — every unit with an agent, dead or alive.
			if diag:
				for unit in units:
					if unit.agent:
						var t0 := Time.get_ticks_usec()
						unit.agent.goap_process(delta)
						diag_us(unit.dead, unit, t0)
			else:
				for unit in units:
					if unit.agent:
						unit.agent.goap_process(delta)
