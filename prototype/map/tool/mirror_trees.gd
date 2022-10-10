@tool
extends TileMap

@export var map_size = Vector2(2112,2112)

func set_cell(tile: int, pos:Vector2i, flip_x = false, flip_y = false, transpose = false, autotile_coord = Vector2.ZERO) -> void:
	var cell_pos = map_to_local(Vector2i(pos.x, pos.y))
	var mirrored_cell_point = local_to_map(Vector2i( (map_size.x - cell_pos.x) - cell_quadrant_size, (map_size.x - (cell_pos.y)) - cell_quadrant_size))#Quadrant size????
		
	super.set_cell( tile, 
		pos, false, false,
		transpose, 
		autotile_coord)

	super.set_cell(
		tile,
		mirrored_cell_point,
		flip_x,
		flip_y,
		transpose,
		get_cell_autotile_coord(pos.x, pos.y))
