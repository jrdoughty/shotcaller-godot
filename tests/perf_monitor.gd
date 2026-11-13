extends Node

# Perf monitor: samples engine/game counters once per wall-clock second
# while the game runs. Enabled with -- --perf on game.tscn (wired via
# tests/debug_map.gd, which runs the debug scenario on the three-lane map
# with the real wave economy). Read-only diagnostic — never part of
# run_suite.sh gating.
#
# What the columns are for (see the fps-decay diagnosis in COVERAGE.md):
#   units — total entries in all_units (grows without bound; nothing erases
#           dead units — the root cause of the gradual fps decay)
#   dead  — dead units still in all_units (still fully simulated by the
#           GOAP pump every tick)
#   dup   — duplicate node entries in all_units (cemetery recycling)
#   nodes/objs/mem — distinguish "growing work" (flat memory, rising
#           per-tick cost) from a genuine leak (rising memory)

var ticks := 0
var last_ms := 0
var last_ticks := 0
var frames := 0


func _ready() -> void:
	var waited := 0
	while not WorldState.get_state("game_started") and waited < 600:
		await get_tree().process_frame
		waited += 1
	last_ms = Time.get_ticks_msec()
	set_process(true)


func _process(_delta: float) -> void:
	frames += 1
	var now: int = Time.get_ticks_msec()
	if now - last_ms < 1000:
		return
	var wall_dt: float = (now - last_ms) / 1000.0
	last_ms = now
	var ticks_per_s := (ticks - last_ticks) / wall_dt
	last_ticks = ticks

	var all_units: Array = WorldState.get_state("all_units")
	var dead := 0
	var ids := {}
	var duplicates := 0
	for unit in all_units:
		if not is_instance_valid(unit):
			continue
		if unit.dead:
			dead += 1
		var id = unit.get_instance_id()
		if ids.has(id):
			duplicates += 1
		ids[id] = true

	print("PERF: t=%3.0fs fps=%4d ticks/s=%3.0f units=%4d dead=%3d dup=%3d nodes=%5d objs=%6d mem=%dMB" % [
		now / 1000.0,
		frames / wall_dt,
		ticks_per_s,
		all_units.size(),
		dead,
		duplicates,
		get_tree().get_node_count(),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		OS.get_static_memory_usage() / 1048576,
	])

	# Orphan check: living, visible units NOT in all_units. The erase-on-death
	# variant removes corpses from the list, and recycle() revives them without
	# re-appending — every revival after that is an orphan (invisible to the
	# GOAP pump, collisions, selection, and UI). Expect 0 on main's pump.
	var orphans := 0
	var map = WorldState.get_state("map")
	var container = map.unit_container if map else null
	if container:
		var in_list := {}
		for unit in all_units:
			if is_instance_valid(unit):
				in_list[unit.get_instance_id()] = true
		for child in container.get_children():
			if not is_instance_valid(child) or not ("dead" in child):
				continue
			if child.dead or not child.visible:
				continue
			if not in_list.has(child.get_instance_id()):
				orphans += 1
	print("ORPHAN: t=%3.0fs living_not_in_all_units=%d list_size=%d" % [now / 1000.0, orphans, all_units.size()])

	frames = 0

	# --- Experiment attribution (exp/erase-ab only): every 10 s, print the
	# per-second pump/collision cost split by dead vs alive, plus planner
	# calls on corpses. Only active when DSH_GOAP_DIAG=1.
	if Goap.diag and int(now) % 10 == 0:
		var d: Dictionary = Goap.take_diag()
		var c: Dictionary = Collisions.take_diag()
		var per_tick := float(d["ticks"]) if d["ticks"] > 0 else 1.0
		var coll_per_tick := float(c["coll_us"]) / maxf(float(c["coll_ticks"]), 1.0)
		print("DIAG: mode=%s pump=%5.1fms/t (alive %5.1f dead %5.1f) goal=%4.1f plan=%4.1f follow=%4.1f ms/t | plans=%d (dead %d) | calls/t=%4.1f (dead %4.1f skipped_dead/t=%5.1f) | coll=%5.1fms/t n/t=%4.1f" % [
			Goap.pump_mode,
			float(d["pump_us"]) / 1000.0 / per_tick,
			float(d["pump_us_alive"]) / 1000.0 / per_tick,
			float(d["pump_us_dead"]) / 1000.0 / per_tick,
			(float(d["goal_alive"]) + float(d["goal_dead"])) / 1000.0 / per_tick,
			(float(d["plan_alive"]) + float(d["plan_dead"])) / 1000.0 / per_tick,
			(float(d["follow_alive"]) + float(d["follow_dead"])) / 1000.0 / per_tick,
			int(d["plans_alive"]) + int(d["plans_dead"]),
			int(d["plans_dead"]),
			float(d["calls_alive"] + d["calls_dead"]) / per_tick,
			float(d["calls_dead"]) / per_tick,
			float(d["skipped_dead"]) / per_tick,
			coll_per_tick / 1000.0,
			float(c["coll_n"]) / maxf(float(c["coll_ticks"]), 1.0),
		])


func _physics_process(_delta: float) -> void:
	ticks += 1
