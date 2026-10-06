@tool
class_name LayeredTerrain
extends Node2D
## Stacked terrain: one `LayeredTerrainBiome` (a TileMapLayer) child per biome, lowest first.
## Layer i sits `base_height` + i × `layer_height` px up. The biomes split the elevation range
## `lower_threshold`..`upper_threshold` by their weights, in child order; cells outside it are left empty.
## Elevation picks each cell's biome, and
## the cell gets one tile on that biome's layer, raised 0..amplitude whole px by the biome's relief noise.
## A raise of r px is alternative tile r, whose `texture_origin` is r px above alternative 0's;
## `regenerate()` makes the alternatives each biome needs. The tiles should be columns deep enough
## to cover amplitude + base_height + i × layer_height below their ground, which fills the gap down to
## the lower layers. To stack terrains, give the upper one a narrower range and a `base_height`, and put the terrains under one Y-sorted parent. Edits in the inspector, and adding, removing or reordering biomes, regenerate the map live.
## Each cell depends only on its coordinates and the noises, so regenerating gives the same map.

## Elevation: picks the top biome of each cell.
@export var noise: FastNoiseLite:
	set(value):
		_swap_connection(noise, value)
		noise = value
		queue_regenerate()

## How far each layer sits above the one below, in px. Each biome's raise,
## amplitude + base_height + index × layer_height, must stay within the tiles' columns, or gaps show.
@export var layer_height := 8:
	set(value):
		layer_height = value
		queue_regenerate()

## Cells with elevation below this are left empty.
@export_range(0.0, 1.0, 0.001) var lower_threshold := 0.0:
	set(value):
		lower_threshold = value
		queue_regenerate()

## Cells with elevation above this are left empty.
@export_range(0.0, 1.0, 0.001) var upper_threshold := 1.0:
	set(value):
		upper_threshold = value
		queue_regenerate()

## Px every layer is lifted, to stack this terrain on another. Lifts the layers rather than this node,
## so this terrain still Y-sorts by grid row with the one below.
@export var base_height := 0:
	set(value):
		base_height = value
		queue_regenerate()

## Size of the map, in cells.
@export var map_size := Vector2i(36, 36):
	set(value):
		map_size = value
		queue_regenerate()

@export_tool_button("Regenerate") var regenerate_button := regenerate

var _queued := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		queue_regenerate()


func _swap_connection(old: Resource, new: Resource) -> void:
	if old and old.changed.is_connected(queue_regenerate):
		old.changed.disconnect(queue_regenerate)
	if new and not new.changed.is_connected(queue_regenerate):
		new.changed.connect(queue_regenerate)


func queue_regenerate() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	regenerate.call_deferred()


func regenerate() -> void:
	_queued = false
	y_sort_enabled = true
	var biomes := _biomes()
	for i in biomes.size():
		var biome := biomes[i]
		biome.clear()
		biome.y_sort_enabled = true
		biome.position.y = -(base_height + i * layer_height)
		# Cancel the raise when sorting, so all layers sort together by grid row.
		biome.y_sort_origin = base_height + i * layer_height
		biome.ensure_raises()
	_fill(_bounds())


## The cells to generate.
func _bounds() -> Rect2i:
	return Rect2i(Vector2i.ZERO, map_size)


## Generates every cell in `rect` that isn't in `skip`.
func _fill(rect: Rect2i, skip := Rect2i()) -> void:
	var biomes := _biomes()
	if not noise or biomes.is_empty():
		return
	var thresholds := _thresholds(biomes)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not skip.has_point(Vector2i(x, y)):
				_generate_cell(Vector2i(x, y), biomes, thresholds)


func _generate_cell(cell: Vector2i, biomes: Array[LayeredTerrainBiome], thresholds: PackedFloat32Array) -> void:
	# Noise is roughly -1..1; map it to 0..1 so it can be compared with the thresholds.
	var elevation := (noise.get_noise_2dv(cell) + 1.0) * 0.5
	if elevation < lower_threshold or elevation > upper_threshold:
		return
	biomes[_biome_index(elevation, thresholds)].place(cell)


## The biome children, in child order: lowest elevation first.
func _biomes() -> Array[LayeredTerrainBiome]:
	var biomes: Array[LayeredTerrainBiome] = []
	for child in get_children():
		if child is LayeredTerrainBiome:
			biomes.append(child)
	return biomes


## The top elevation of each biome: biome i covers its weight's share of
## lower_threshold..upper_threshold, above biome i − 1.
func _thresholds(biomes: Array[LayeredTerrainBiome]) -> PackedFloat32Array:
	var total := 0.0
	for biome in biomes:
		total += biome.weight
	var thresholds := PackedFloat32Array()
	var sum := 0.0
	for biome in biomes:
		sum += biome.weight
		var t := sum / total if total > 0.0 else 1.0
		thresholds.append(lower_threshold + (upper_threshold - lower_threshold) * t)
	return thresholds


func _biome_index(e: float, thresholds: PackedFloat32Array) -> int:
	for i in thresholds.size():
		if e <= thresholds[i]:
			return i
	return thresholds.size() - 1
