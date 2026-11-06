extends RefCounted

# We can't rely on the Skills autoload because passive_skills.gd's preload of
# leader_passives.tres may fail at autoload init time. Instead, create an
# instance directly from the preloaded script.
const PassiveSkillsScript = preload("res://skills/passive_skills.gd")


# Minimal doubles for hit_modifiers testing.
class TestUnit:
	extends RefCounted
	var display_name: String = ""
	var type: String = "pawn"
	var ranged: bool = false
	var attacks: bool = false
	var current_hp: int = 100
	var hp: int = 100
	var defense: int = 0
	var damage: int = 10
	var attack_count: int = 0
	var agent = null
	var target = null
	var current_modifiers: Dictionary
	var attack_range: float = 1.0
	var attack_hit_radius: float = 24.0

	func _init():
		current_modifiers = Modifiers.new_modifiers()

	func get_units_in_sight(_filters = {}):
		return []

	func get_units_in_attack_range(_filters = {}):
		return []


class TestProjectile:
	extends RefCounted
	var targets = null


class TestAgent:
	extends RefCounted
	var state := {}
	var unit

	func _init(u):
		unit = u

	func get_unit():
		return unit

	func get_state(name: String, default = null):
		return state.get(name, default)

	func set_state(name: String, value) -> void:
		state[name] = value


func run(harness) -> void:
	# Create an instance directly. The autoload may not be initialized,
	# but the script itself is valid.
	var skills = PassiveSkillsScript.new()

	# --- get_value() for leader passives ---

	# Non-leader units always return 0.
	var pawn = TestUnit.new()
	pawn.type = "pawn"
	harness.check_equal(skills.get_value(pawn, "dodge"), 0, "Non-leaders return 0 for all skills.")
	harness.check_equal(skills.get_value(pawn, "critical"), 0, "Pawns have no critical skill.")

	# Leader lookup by display_name.
	var arthur = TestUnit.new()
	arthur.type = "leader"
	arthur.display_name = "arthur"
	# arthur is in LEADER_PASSIVES with known attributes.
	var arthur_dodge = skills.get_value(arthur, "dodge")
	harness.check(arthur_dodge >= 0, "Leader passive skill lookup returns a numeric value.")

	# Unknown leader skill returns 0.
	harness.check_equal(skills.get_value(arthur, "nonexistent_skill"), 0, "Unknown skill returns 0.")

	# --- hit_modifiers() base case ---

	var attacker = TestUnit.new()
	attacker.type = "leader"
	attacker.display_name = "arthur"
	attacker.damage = 15

	var target_unit = TestUnit.new()
	target_unit.type = "leader"
	target_unit.display_name = "joan"
	target_unit.defense = 5

	var projectile = TestProjectile.new()

	# No modifiers passed: damage comes from Modifiers.get_value(attacker, "damage").
	var mods = skills.hit_modifiers(attacker, target_unit, projectile, {})
	harness.check(mods.has("damage"), "hit_modifiers always includes a damage key.")
	harness.check(mods.has("dodge"), "hit_modifiers always includes a dodge key.")
	harness.check(mods.has("counter"), "hit_modifiers always includes a counter key.")
	harness.check(mods.has("pierce"), "hit_modifiers always includes a pierce key.")
	harness.check(mods.has("cleave"), "hit_modifiers always includes a cleave key.")
	harness.check_equal(mods["dodge"], false, "Dodge starts false unless leader dodge skill triggers.")
	harness.check_equal(mods["counter"], true, "Counter starts true.")
	harness.check_equal(mods["pierce"], false, "Pierce starts false unless leader pierce skill triggers.")

	# --- hit_modifiers() with pre-set damage ---

	var mods_explicit = skills.hit_modifiers(attacker, target_unit, projectile, {"damage": 50})
	harness.check_equal(
		mods_explicit["damage"], 50, "Pre-set damage overrides Modifiers.get_value."
	)

	# --- hit_modifiers() cleave modifier ---

	var mods_cleave = skills.hit_modifiers(attacker, target_unit, projectile, {
		"damage": 20, "cleave": true
	})
	harness.check_equal(mods_cleave["cleave"], true, "Cleave flag is preserved when passed.")

	# --- hit_modifiers() counter interaction ---

	var melee_attacker = TestUnit.new()
	melee_attacker.type = "leader"
	melee_attacker.display_name = "arthur"
	melee_attacker.ranged = false
	melee_attacker.damage = 10

	var defensive_target = TestUnit.new()
	defensive_target.type = "leader"
	defensive_target.display_name = "joan"
	defensive_target.defense = 3

	# Normal counter: counter is true, so no counter-damage.
	var normal_mods = skills.hit_modifiers(melee_attacker, defensive_target, projectile, {
		"damage": 10
	})
	harness.check_equal(normal_mods["counter"], true, "Counter defaults to true.")

	# --- hit_modifiers() with explicit counter=false ---

	var counter_active_mods = skills.hit_modifiers(melee_attacker, defensive_target, projectile, {
		"damage": 10, "counter": false
	})
	harness.check_equal(counter_active_mods["counter"], false, "Explicit counter=false is passed through.")

	# --- hit_modifiers() pierce ---

	var pierce_attacker = TestUnit.new()
	pierce_attacker.type = "leader"
	pierce_attacker.display_name = "arthur"
	pierce_attacker.damage = 15

	var pierce_mods = skills.hit_modifiers(pierce_attacker, defensive_target, projectile, {"damage": 10})
	harness.check(pierce_mods.has("pierce"), "Pierce field always exists.")

	# --- hit_modifiers() critical ---

	var crit_mods = skills.hit_modifiers(pierce_attacker, defensive_target, projectile, {"damage": 10})
	harness.check(crit_mods["damage"] is int or crit_mods["damage"] is float,
		"Critical damage remains numeric.")

	# --- hit_modifiers() bleed ---

	var bleed_target = TestUnit.new()
	bleed_target.type = "leader"
	bleed_target.display_name = "joan"
	var bleed_attacker = TestUnit.new()
	bleed_attacker.type = "leader"
	bleed_attacker.display_name = "arthur"
	bleed_attacker.damage = 10
	bleed_attacker.attack_count = 3

	var bleed_mods = skills.hit_modifiers(bleed_attacker, bleed_target, projectile, {"damage": 10})
	harness.check(bleed_mods["damage"] >= 10, "Bleed can only increase damage.")

	# --- hit_modifiers() agile interaction ---

	var agile_target = TestUnit.new()
	agile_target.type = "leader"
	agile_target.display_name = "joan"
	var agile_attacker = TestUnit.new()
	agile_attacker.type = "leader"
	agile_attacker.display_name = "arthur"
	agile_attacker.damage = 10
	agile_attacker.attack_count = 1

	skills.hit_modifiers(agile_attacker, agile_target, projectile, {"damage": 10})
	var final_attack_speed = agile_target.current_modifiers["attack_speed"].size()
	harness.check(final_attack_speed >= 0, "Agile modifier management does not crash.")

	skills.free()
