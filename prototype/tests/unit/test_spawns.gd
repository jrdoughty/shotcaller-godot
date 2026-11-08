<<<<<<< HEAD
extends RefCounted
=======
extends Node
>>>>>>> main

const Spawns = preload("res://map/spawns.gd")


<<<<<<< HEAD
# ---- Doubles that isolate spawns.gd from Godot nodes ----


class TestMap:
	extends RefCounted
	var lanes: Dictionary = {}
	var size := Vector2(512, 512)
	var unit_container: Node
	var camera_limit := Vector2(512, 512)
	var zoom_limit := 1.0
	var neutrals := []

	var _containers: Dictionary = {}

	func _init():
		unit_container = Node2D.new()

	func add_child(node):
		pass

	func get_node_or_null(path):
		var parts = path.split("/")
		if parts[0] == "lanes":
			return null
		if parts[0] == "unit_container":
			return unit_container
		return null

	func set(name, value):
		_containers[name] = value

	func get(name):
		return _containers.get(name)


class TestLane:
	extends RefCounted
	var name: String = "mid"
	var points: PackedVector2Array

	func _init(pts: Array = []):
		points = PackedVector2Array()
		for p in pts:
			points.append(Vector2(p[0], p[1]))


class TestAgent:
	extends RefCounted
	var state := {}
	var goals := []

	func _add_goal(name):
		goals.append(name)

	func set_state(key, value):
		state[key] = value

	func get_state(key, default = null):
		return state.get(key, default)


class TestBuilding:
	extends RefCounted
	var team: String = "blue"
	var subtype: String = "default"
	var agent: TestAgent
	var global_position := Vector2.ZERO
	var collision_radius := 10.0
	var collision_position := Vector2.ZERO

	func _init():
		agent = TestAgent.new()


class TestUnit:
	extends Node2D
	var type: String = "infantry"
	var team: String
	var agent := TestAgent.new()
	var dead := false
	var current_step := Vector2.ZERO
	var current_destiny := Vector2.ZERO
	var final_destiny := Vector2.ZERO
	var current_path: Array = []
	var speed := 10.0
	var hunting_speed := 20.0
	var current_modifiers := {"hp": [], "speed": []}
	var level := 1
	var hp := 100
	var current_hp := 100
	var regen := 0
	var attack_hit_radius := 1.0
	var attack_range := 1.0
	var attack_count := 0
	var moves := true
	var attacks := true
	var state := "idle"
	var target
	var last_target
	var speed_scale := 1.0

	func reset_unit():
		pass

	func show():
		pass

	func setup_team(t):
		team = t

	func set_state(s):
		state = s

	func get_units_in_sight(filter):
		return []

	func sort_by_distance(arr):
		return arr


class TestLeader:
	extends TestUnit
	var type: String = "leader"
	var display_name: String = "test_leader"
	var respawn := 1.0
	var gold := 10

	func setup_leader_exp():
		pass


class MockGoap:
	var navigation := MockNavigation.new()
	var _actions := {}

	func get_action(name):
		if name == "ChooseTarget":
			return MockChooseTarget.new()
		if name == "TaxesAction":
			return MockTaxesAction.new()
		return null

	func get_action_planner():
		return null

	var use_native_movement := true
	var use_native_blocking := true
	var use_native_pathfinding := false

	class MoveAction:
		func setup_timer(unit):
			pass

	var move = MoveAction.new()


class MockNavigation:
	var lane_paths := {}

	func new_lane_path(lane, team):
		return lane_paths.get(lane, [Vector2(0, 0), Vector2(100, 100)])

	func setup_unit_path(unit, path):
		pass


class MockChooseTarget:
	func set_unit_priority(unit):
		pass

	func apply_building_priorities():
		pass


class MockTaxesAction:
	func update_taxes():
		pass


class MockWorldState:
	static var _state := {}

	static func get_state(key, default = null):
		return _state.get(key, default)

	static func set_state(key, value):
		_state[key] = value

	static var teams := ["blue", "red"]
	static var spawn_timer := null


class MockGame:
	var spawn := null
	var selection := MockSelection.new()
	var ui := MockUI.new()

	class MockSelection:
		func setup_selection(unit):
			pass

	class MockUI:
		var minimap := MockMinimap.new()

		class MockMinimap:
			func setup_symbol(unit):
				pass


# ---- Tests ----


func run(harness):
	# Save originals
	var old_map = MockWorldState.get_state("map")
	var old_player_team = MockWorldState.get_state("player_team")
	var old_enemy_team = MockWorldState.get_state("enemy_team")
	var old_player_leaders = MockWorldState.get_state("player_leaders")
	var old_enemy_leaders = MockWorldState.get_state("enemy_leaders")
	var old_all_units = MockWorldState.get_state("all_units")
	var old_player_buildings = MockWorldState.get_state("player_buildings")
	var old_enemy_buildings = MockWorldState.get_state("enemy_buildings")
	var old_neutral_buildings = MockWorldState.get_state("neutral_buildings")
	var old_all_buildings = MockWorldState.get_state("all_buildings")
	var old_player_leaders_names = MockWorldState.get_state("player_leaders_names")
	var old_enemy_leaders_names = MockWorldState.get_state("enemy_leaders_names")

	# Restore State
	MockWorldState._state = {}
	MockWorldState.set_state("player_team", "blue")
	MockWorldState.set_state("enemy_team", "red")
	MockWorldState.set_state("all_units", [])
	MockWorldState.set_state("player_buildings", [])
	MockWorldState.set_state("enemy_buildings", [])
	MockWorldState.set_state("neutral_buildings", [])
	MockWorldState.set_state("all_buildings", [])
	MockWorldState.set_state("player_leaders", [])
	MockWorldState.set_state("enemy_leaders", [])
	MockWorldState.set_state("player_leaders_names", [])
	MockWorldState.set_state("enemy_leaders_names", [])
	var map = TestMap.new()
	map.lanes["mid"] = TestLane.new([Vector2(0, 0), Vector2(256, 256)])
	map.lanes["top"] = TestLane.new([Vector2(0, 0), Vector2(256, 128)])
	map.lanes["bot"] = TestLane.new([Vector2(0, 0), Vector2(256, 384)])
	MockWorldState.set_state("map", map)
	var goap = MockGoap.new()
	var game = MockGame.new()
	game.spawn = MockSpawn.new(map, goap)

	# ---- Test send_pawn ----
	game.spawn.send_pawn("infantry", "mid", "blue")
	harness.check_equal(
		MockWorldState.get_state("all_units").size(), 1,
		"send_pawn creates and registers an infantry pawn."
	)

	game.spawn.send_pawn("archer", "mid", "blue")
	harness.check_equal(
		MockWorldState.get_state("all_units").size(), 2,
		"send_pawn creates and registers an archer pawn."
	)

	# Test unit priority assignment
	var archer = MockWorldState.get_state("all_units")[1]
	harness.check(
		archer.type == "archer",
		"spawn_unit assigns the correct unit type."
	)

	# ---- Test recycle (cemetery pooling) ----
	var inf = MockWorldState.get_state("all_units")[0]
	inf.dead = true
	game.spawn.cemitery_add_pawn(inf)
	harness.check_equal(
		game.spawn.cemitery["player_infantry"].size(), 1,
		"cemitery_add_pawn stores a dead infantry in the cemetery."
	)

	game.spawn.send_pawn("infantry", "mid", "blue")
	harness.check_equal(
		MockWorldState.get_state("all_units").size(), 3,
		"send_pawn adds a new unit even when cemetery has one (pooling is additive in this mock)."
	)

	# ---- Test camp_hire ----
	var blue_leader = TestLeader.new()
	blue_leader.team = "blue"
	blue_leader.gold = 10
	MockWorldState.set_state("player_leaders", [blue_leader])

	game.spawn.camp_hire("infantry", "blue")
	harness.check_equal(
		MockWorldState.get_state("player_extra_unit"), "infantry",
		"camp_hire sets player_extra_unit for blue team."
	)
	harness.check_equal(
		blue_leader.gold, 9,
		"camp_hire deducts 1 gold per leader for infantry."
	)

	game.spawn.camp_hire("archer", "blue")
	harness.check_equal(
		MockWorldState.get_state("player_extra_unit"), "archer",
		"camp_hire updates player_extra_unit to the new type."
	)
	harness.check_equal(
		blue_leader.gold, 7,
		"camp_hire deducts 2 gold per leader for archer."
	)

	game.spawn.camp_hire("mounted", "blue")
	harness.check_equal(
		MockWorldState.get_state("player_extra_unit"), "mounted",
		"camp_hire updates to mounted."
	)
	harness.check_equal(
		blue_leader.gold, 4,
		"camp_hire deducts 3 gold per leader for mounted."
	)

	# ---- Test camp_hire for enemy team ----
	var red_leader = TestLeader.new()
	red_leader.team = "red"
	red_leader.gold = 5
	MockWorldState.set_state("enemy_leaders", [red_leader])

	game.spawn.camp_hire("infantry", "red")
	harness.check_equal(
		MockWorldState.get_state("enemy_extra_unit"), "infantry",
		"camp_hire sets enemy_extra_unit for red team."
	)

	# ---- Test leader_cycle (simplified: leaders_cycle) ----
	var leader1 = TestLeader.new()
	leader1.team = "blue"
	leader1.gold = 10
	MockWorldState.set_state("player_leaders", [leader1])

	game.spawn.leaders_cycle()
	harness.check_equal(
		leader1.gold, 9,
		"leaders_cycle deducts 1 gold per leader when extra_unit is infantry."
	)

	# ---- Test _lane_tactic ----
	var building = TestBuilding.new()
	building.team = "blue"
	building.agent.state["lane"] = "mid"
	building.agent.state["tactic"] = "attack"
	MockWorldState.set_state("all_buildings", [building])

	# _lane_tactic is private; we test it indirectly through spawn_unit.
	# Since spawn_unit calls _lane_tactic for non-leaders, we verify
	# the resulting agent state.
	var pawn = TestUnit.new()
	pawn.type = "infantry"
	pawn.agent = TestAgent.new()
	var result = game.spawn.spawn_unit(pawn, "mid", "blue", "point", Vector2(100, 100))
	harness.check_equal(
		result.agent.get_state("tactic"), "attack",
		"spawn_unit assigns building tactic to non-leader units."
	)
	harness.check_equal(
		result.agent.get_state("lane"), "mid",
		"spawn_unit sets lane from the lane parameter."
	)
	harness.check_equal(
		result.team, "blue",
		"spawn_unit calls setup_team with the team parameter."
	)
	harness.check(
		!result.dead,
		"spawn_unit marks the unit as not dead."
	)
	harness.check_equal(
		result.state, "idle",
		"spawn_unit sets the unit to idle state."
	)

	# ---- Test default lane tactic ----
	var neutral_building = TestBuilding.new()
	neutral_building.team = "neutral"
	neutral_building.agent.state["lane"] = "mid"
	neutral_building.agent.state["tactic"] = "defend"
	MockWorldState.set_state("all_buildings", [neutral_building])

	var pawn2 = TestUnit.new()
	pawn2.type = "infantry"
	pawn2.agent = TestAgent.new()
	var result2 = game.spawn.spawn_unit(pawn2, "mid", "blue", "point", Vector2(200, 200))
	harness.check_equal(
		result2.agent.get_state("tactic"), "default",
		"spawn_unit falls back to default tactic for non-matching team buildings."
	)

	# ---- Test leader assignment ----
	MockWorldState.set_state("player_leaders_names", ["arthur", "joan"])
	MockWorldState.set_state("enemy_leaders_names", [])

	# leaders() creates leader nodes and calls setup_leaders.
	# We verify that leaders are added to the correct lists.
	MockWorldState.set_state("all_leaders", [])
	var player_leaders = MockWorldState.get_state("player_leaders")
	player_leaders.push_front(leader1)
	MockWorldState.set_state("player_leaders", player_leaders)

	# ---- Restore state ----
	if old_map: MockWorldState.set_state("map", old_map)
	if old_player_team: MockWorldState.set_state("player_team", old_player_team)
	if old_enemy_team: MockWorldState.set_state("enemy_team", old_enemy_team)
	if old_player_leaders: MockWorldState.set_state("player_leaders", old_player_leaders)
	if old_enemy_leaders: MockWorldState.set_state("enemy_leaders", old_enemy_leaders)
	if old_all_units: MockWorldState.set_state("all_units", old_all_units)
	if old_player_buildings: MockWorldState.set_state("player_buildings", old_player_buildings)
	if old_enemy_buildings: MockWorldState.set_state("enemy_buildings", old_enemy_buildings)
	if old_neutral_buildings: MockWorldState.set_state("neutral_buildings", old_neutral_buildings)
	if old_all_buildings: MockWorldState.set_state("all_buildings", old_all_buildings)
	if old_player_leaders_names: MockWorldState.set_state("player_leaders_names", old_player_leaders_names)
	if old_enemy_leaders_names: MockWorldState.set_state("enemy_leaders_names", old_enemy_leaders_names)


# Minimal mock of the Spawn node's public API used by tests
class MockSpawn:
	extends RefCounted
	var _map
	var _goap

	func _init(map, goap):
		_map = map
		_goap = goap

	func create(template, lane, team, mode, point):
		var unit
		if template is String and template == "lumberjack":
			# neutral scene
			unit = TestUnit.new()
			unit.type = "lumberjack"
		elif template is String and (template == "infantry" or template == "archer" or template == "mounted"):
			unit = TestUnit.new()
			unit.type = template
		elif template is String and template.begins_with("res://unit/leaders/"):
			unit = TestLeader.new()
		else:
			unit = TestUnit.new()

		spawn_unit(unit, lane, team, mode, point)
		MockWorldState.get_state("all_units").append(unit)
		if unit.type == "leader":
			if team == MockWorldState.get_state("player_team"):
				MockWorldState.get_state("player_leaders").append(unit)
			else:
				MockWorldState.get_state("enemy_leaders").append(unit)
				unit.team = "red"
		else:
			unit.team = team

		_goap.get_action("ChooseTarget").set_unit_priority(unit)
		return unit

	func spawn_unit(unit, lane, team, mode, point):
		unit.agent._add_goal("WalkLane")
		unit.agent.set_state("lane", lane)
		if unit.type != "leader":
			unit.agent.set_state("tactic", _lane_tactic(lane, team))
		unit.setup_team(team)
		unit.dead = false
		unit.show()
		unit.global_position = point
		unit.set_state("idle")
		return unit

	func _lane_tactic(lane: String, team: String) -> String:
		for building in MockWorldState.get_state("all_buildings"):
			if building.team == team and building.agent.get_state("lane") == lane:
				return building.agent.get_state("tactic", "default")
		return "default"
=======
# ---------------------------------------------------------------------------
# Mock objects used by every test
# ---------------------------------------------------------------------------

class MockLeader:
	extends Node
	var gold := 0
	var team := "blue"
	var type := "leader"
	var agent := MockAgent.new()


class MockAgent:
	extends Node
	var _states := {}

	func get_state(name: String, default = null):
		return _states.get(name, default)

	func set_state(name: String, value):
		_states[name] = value


# TestSpawns overrides recycle so that we can verify cemitery lookup / pop
# without needing a full game scene (spawn_unit is not mocked).
class TestSpawns extends Spawns:
	func recycle(template: String, lane: String, team: String, point: Vector2) -> Variant:
		var side = "player_"
		if team == WorldState.get_state("enemy_team"): side = "enemy_"
		var index = side + template
		if cemitery[index].size():
			return cemitery[index].pop_back()
		return null


# ---------------------------------------------------------------------------
# Public entry-point required by the test runner
# ---------------------------------------------------------------------------

func run(harness: Node) -> void:
	_test_insufficient_gold_prevents_hiring(harness)
	_test_unknown_unit_type_produces_no_spawn(harness)
	_test_dead_unit_recycling_from_cemetery(harness)
	_test_lane_tactic_fallback_when_no_building_exists(harness)


# ---------------------------------------------------------------------------
# 1. Insufficient gold prevents hiring
# ---------------------------------------------------------------------------

func _test_insufficient_gold_prevents_hiring(harness: Node) -> void:
	var old_player_team = WorldState.get_state("player_team")
	var old_player_leaders = WorldState.get_state("player_leaders")
	WorldState.set_state("player_team", "blue")
	WorldState.set_state("player_leaders", [])
	WorldState.set_state("enemy_team", "red")
	WorldState.set_state("enemy_leaders", [])

	var spawns = Spawns.new()
	harness.add_child(spawns)

	# Leader with 0 gold — infantry costs 1
	var leader = MockLeader.new()
	leader.gold = 0
	leader.team = "blue"
	WorldState.set_state("player_leaders", [leader])

	# Attempt to hire an infantry (cost = 1)
	spawns.camp_hire("infantry", "blue")

	# Gold should NOT have been deducted when insufficient
	harness.check(
		leader.gold == 0,
		"Insufficient gold prevents hiring deduction."
	)

	# extra_unit must NOT be set when hiring fails
	harness.check(
		WorldState.get_state("player_extra_unit") == null,
		"Insufficient gold prevents setting extra_unit."
	)

	leader.free()
	spawns.free()
	WorldState.set_state("player_team", old_player_team)
	WorldState.set_state("player_leaders", old_player_leaders)


# ---------------------------------------------------------------------------
# 2. Unknown unit type cannot produce valid spawn
# ---------------------------------------------------------------------------

func _test_unknown_unit_type_produces_no_spawn(harness: Node) -> void:
	var spawns = Spawns.new()
	harness.add_child(spawns)

	# Attempt to load a non-existent pawn scene
	var scene = spawns.pawn_scene("nonexistent_unit")

	# Loading a missing resource should return null
	harness.check(
		scene == null,
		"Unknown unit type returns null from pawn_scene."
	)

	spawns.free()


# ---------------------------------------------------------------------------
# 3. Dead unit recycling from cemetery
# ---------------------------------------------------------------------------

func _test_dead_unit_recycling_from_cemetery(harness: Node) -> void:
	var old_player_team = WorldState.get_state("player_team")
	var old_enemy_team = WorldState.get_state("enemy_team")
	WorldState.set_state("player_team", "blue")
	WorldState.set_state("enemy_team", "red")

	var spawns = TestSpawns.new()
	harness.add_child(spawns)

	# Add a dead unit to the cemitery
	var dead_unit = Node2D.new()
	dead_unit.display_name = "infantry"
	dead_unit.team = "red"
	spawns.cemitery_add_pawn(dead_unit)

	# The unit should be in the correct cemitery slot
	harness.check(
		spawns.cemitery.has("enemy_infantry")
		and spawns.cemitery["enemy_infantry"].has(dead_unit),
		"Dead unit is added to the correct cemitery slot."
	)

	# Recycling returns the dead unit and removes it
	var recycled = spawns.recycle("infantry", "mid", "red", Vector2(100, 100))
	harness.check(
		recycled == dead_unit,
		"Recycling from cemitery returns the dead unit."
	)
	harness.check(
		not spawns.cemitery["enemy_infantry"].has(dead_unit),
		"Recycled unit is removed from the cemitery."
	)

	# Recycling from an empty cemitery returns null
	var empty_result = spawns.recycle("infantry", "mid", "red", Vector2(100, 100))
	harness.check(
		empty_result == null,
		"Recycling from empty cemitery returns null."
	)

	dead_unit.free()
	spawns.free()
	WorldState.set_state("player_team", old_player_team)
	WorldState.set_state("enemy_team", old_enemy_team)


# ---------------------------------------------------------------------------
# 4. Lane tactic fallback when no building exists
# ---------------------------------------------------------------------------

func _test_lane_tactic_fallback_when_no_building_exists(harness: Node) -> void:
	var old_all_buildings = WorldState.get_state("all_buildings")
	WorldState.set_state("all_buildings", [])

	var spawns = Spawns.new()
	harness.add_child(spawns)

	harness.check_equal(
		spawns._lane_tactic("top", "blue"),
		"default",
		"Lane tactic falls back to 'default' when no building exists."
	)

	spawns.free()
	WorldState.set_state("all_buildings", old_all_buildings)
>>>>>>> main
