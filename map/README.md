# map/

Tile-map battlefields and everything that populates them.

- `maps/` — the playable map scenes (`three_lane_map.tscn` is the battle
  map). A map scene must expose `size`, `camera_limit`, `zoom_limit`,
  `lanes`, and `buildings/<team>/<building>` nodes — `map_manager.gd` and
  `spawns.gd` read them by path.
- `map_manager.gd` — instantiates maps, creates the unit/projectile/block
  containers, sets up buildings and lanes. Map-ready flows THROUGH the
  minimap UI (`ui/minimap.gd`) — headless runs rely on the
  `DisplayServer.get_name() == "headless"` guard there; do not remove it.
- `spawns.gd` — spawn timers, cemetery recycling, camp/lumberjack hiring.
  `camp_hire` pools team gold and refuses the hire when insufficient;
  `lumberjack_hire` splits the cost the same way but has NO affordability
  check (can drive leaders negative — do not assume a gate exists).
  Regression-tested in `tests/unit/test_spawns.gd`.
- `pathfind/` — jump-point pathfinding (the `Finder` autoload).
- `tool/mirror_tiles.gd` — @tool map-editor TileMap (mirror painting).
  Its coordinate math is regression-tested against production methods in
  `tests/unit/test_mirror_tiles.gd`.
- `../addons/map_editor/` — editor plugin (enable it in Project Settings →
  Plugins): a dock with **New map scene** (scaffolds a contract-satisfying
  map — tiles/ground|walls|trees TileMapLayers with the shared TileSets,
  fog, `buildings/<team>/<building>`, a default `mid` lane, `closest_tree`
  markers), **Validate open map** (checks the runtime contract that
  `map_manager.gd`/`spawns.gd` read by path, including building `subtype`
  matching a lane), and **Draw lanes** (canvas mode: left-click adds
  tile-snapped points to the selected lane, Escape exits, "New lane" adds a
  `lane_N` line — all undoable). Scaffold, validator, and lane logic are
  editor-free RefCounted code, regression-tested in
  `tests/unit/test_map_editor.gd` / `test_lane_logic.gd` /
  `test_map_loader.gd`.
- `editor/` — the **runtime** map editor (M4, M5, M6): `map_editor.tscn` with
  `map_editor.gd` / `editor_ui.gd` / `editor_camera.gd` / `lane_overlay.gd` /
  `map_store.gd`, opened by the main menu's **Map editor** button. It is a
  scene, not an EditorPlugin: it rebuilds what the dock gets from the editor
  (`UndoRedo.new()`, its own `Camera2D`, a lane overlay, viewport→world math)
  on top of the same editor-free logic (`lane_logic` / `building_logic` /
  `tile_brush_logic` / `map_scaffold` / `map_validator`). Authored maps are
  saved by `map_store.gd` into **`user://maps/<name>.tscn`** — never
  `res://`, which is read-only in exported builds — and Play hands the saved
  map to `game.gd` through WorldState's `pending_map` (player blue vs enemy
  red). Tile strokes write their mirrored twins like the dock ("Mirror paint"
  toggle, default on; off paints only where clicked so asymmetric maps are
  authorable).
  **Layout (M6):** a four-button panel sits at the **top-right** and picks the
  mode — **Lanes (1)**, **Buildings (2)**, **Map (3)**, **Tiles (4)** — with the
  main-row number keys as the same shortcut; the editor **boots into Map mode**,
  Escape or re-pressing the lit mode (button or key) exits to no tool, and
  opening/creating a map keeps Map mode while an active tool mode drops. The
  left panel shows **only the active mode's controls** (Lanes: lane dropdown +
  New lane; Buildings: building + team dropdowns; Map: map dropdown,
  Open/Refresh/New, name entry, Save/Delete/Validate/Play, Exit; Tiles: Mirror
  paint, brush, block, tile pickers) and never scrolls — Undo/Redo and the log
  are always visible, and the log is the **only** scrolling region (so the mouse
  wheel over it scrolls the log, over the map it zooms).
  **Move = right-click drag (M6):** in Lanes mode a right-press grabs the nearest
  **lane point** and drags it, in Buildings mode the nearest **building**
  (pre-placed ones included); each drag is one undo step, snaps to the 64px grid
  and is position-only (names, teams, subtypes and point counts never change); a
  grab with no motion leaves no history entry. Left-click keeps adding lane
  points / placing buildings; Tiles keeps left-paint / right-erase. The store and
  the tool behaviors are regression-tested in `tests/unit/test_map_store.gd` /
  `test_map_editor_tools.gd`; windowed feel and layout are manual checks
  (`plans/M4.md`, `plans/M5.md`, `plans/M6.md`).
- `map_manager.gd` resolves maps generically: preloaded shipping maps by var,
  then `res://map/maps/<name>.tscn`, then `user://maps/<name>.tscn`, and a
  full `res://`/`user://` path directly (the shipping path wins when a name
  exists in both) — so plugin- and runtime-authored maps load by name
  (`current_map = "my_map"`) or by path. Resolution is covered by
  `tests/unit/test_map_loader.gd`; booting a new map end-to-end is a manual
  check.
