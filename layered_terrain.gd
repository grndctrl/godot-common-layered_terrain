@tool
class_name LayeredTerrain
extends Node2D
## Stacked terrain: one child TileMapLayer per biome (same order as `biomes`), each raised
## `layer_height` px above the previous one. Elevation picks each cell's biome, and the cell gets
## one tile on that layer with the biome's height ± roughness. The tiles should be columns deep
## enough to cover (layers − 1) × layer_height below their ground, which fills the gap down to the
## lower layers. Edits in the inspector regenerate the map live.
## Each cell depends only on its coordinates and `seed`, so regenerating gives the same map.

## Elevation: picks the top biome of each cell.
@export var noise: FastNoiseLite:
	set(value):
		_swap_connection(noise, value)
		noise = value
		_queue_regenerate()

## Ordered from lowest to highest threshold. Biome i is drawn on child TileMapLayer i.
@export var biomes: Array[LayeredTerrainBiome] = []:
	set(value):
		for b in biomes:
			_swap_connection(b, null)
		biomes = value
		for b in biomes:
			_swap_connection(null, b)
		_queue_regenerate()

## How far each layer sits above the one below, in px. The top layer's raise,
## (layers - 1) × layer_height, must stay within the tiles' columns, or gaps show.
@export var layer_height := 8:
	set(value):
		layer_height = value
		_queue_regenerate()

@export var seed := 0:
	set(value):
		seed = value
		_queue_regenerate()

## Size of the map, in cells.
@export var map_size := Vector2i(36, 36):
	set(value):
		map_size = value
		_queue_regenerate()

## Number of levels (atlas columns) in each biome's atlas source.
@export var levels := 3:
	set(value):
		levels = value
		_queue_regenerate()

@export_tool_button("Regenerate") var regenerate_button := regenerate

var _queued := false


func _swap_connection(old: Resource, new: Resource) -> void:
	if old and old.changed.is_connected(_queue_regenerate):
		old.changed.disconnect(_queue_regenerate)
	if new and not new.changed.is_connected(_queue_regenerate):
		new.changed.connect(_queue_regenerate)


func _queue_regenerate() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	regenerate.call_deferred()


func regenerate() -> void:
	_queued = false
	y_sort_enabled = true
	var layers := _layers()
	for i in layers.size():
		var layer := layers[i]
		layer.clear()
		layer.y_sort_enabled = true
		layer.position.y = -i * layer_height
		# Cancel the raise when sorting, so all layers sort together by grid row.
		layer.y_sort_origin = i * layer_height
	_fill(_bounds())


## The cells to generate.
func _bounds() -> Rect2i:
	return Rect2i(Vector2i.ZERO, map_size)


## Generates every cell in `rect` that isn't in `skip`.
func _fill(rect: Rect2i, skip := Rect2i()) -> void:
	if not noise or biomes.is_empty():
		return
	var layers := _layers()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not skip.has_point(Vector2i(x, y)):
				_generate_cell(Vector2i(x, y), layers)


func _generate_cell(cell: Vector2i, layers: Array[TileMapLayer]) -> void:
	# Noise is roughly -1..1; map it to 0..1 so it can be compared with the thresholds.
	var elevation := (noise.get_noise_2dv(cell) + 1.0) * 0.5
	var top := mini(_biome_index(elevation), layers.size() - 1)
	var biome := biomes[top]
	if biome:
		layers[top].set_cell(cell, biome.source_id, Vector2i(_rough_level(biome, cell), 0))


## The biome's height, stepped one level up or down with chance `roughness`.
## The random rolls come from a hash of the cell and `seed`.
func _rough_level(biome: LayeredTerrainBiome, cell: Vector2i) -> int:
	var h := hash(Vector3i(cell.x, cell.y, seed))
	var level := biome.height
	if (h & 0xFFFF) / 65536.0 < biome.roughness:
		var step := 1 if h & 0x10000 else -1
		if level + step < 0 or level + step >= levels:
			step = -step
		level += step
	return level


func _layers() -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = []
	for child in get_children():
		if child is TileMapLayer:
			layers.append(child)
	return layers


func _biome_index(e: float) -> int:
	for i in biomes.size():
		if biomes[i] and e <= biomes[i].threshold:
			return i
	return biomes.size() - 1
