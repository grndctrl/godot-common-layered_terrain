@tool
class_name InfiniteLayeredTerrain
extends LayeredTerrain
## A `LayeredTerrain` that streams: it keeps the cells that can show in a viewport-sized view centred
## on `follow`, so it fills the screen at any resolution. `map_size` is not used.
## The map is split into `chunk_size` squares, each with its own TileMapLayer per biome (see
## `LayeredTerrainBiome.add_chunk_layer()`). A Y-sorted TileMapLayer draws one canvas item per row, so
## in a single layer a new column would redraw every row; a chunk is built or freed without touching
## the others. Chunks on screen are built at once; chunks within `margin` of the view are built ahead,
## nearest first, within `build_budget_ms` per frame.

## The view is centred on this node. Use the camera, so the view matches the screen.
## Leave empty for a fixed view at the origin.
@export var follow: Node2D:
	set(value):
		follow = value
		queue_regenerate()

## Side of a chunk, in cells. Smaller chunks build faster; bigger ones mean fewer nodes to sort.
@export_range(4, 128) var chunk_size := 32:
	set(value):
		chunk_size = value
		queue_regenerate()

## Px around the view where chunks are built ahead of time. Chunks are freed beyond twice this.
## Raise it if chunks appear at the screen edge while moving fast.
@export var margin := 128:
	set(value):
		margin = value
		queue_regenerate()

## Time per frame for building chunks ahead, in ms. The rest wait for the next frame.
@export var build_budget_ms := 2.0

var _chunks: Dictionary[Vector2i, Array] = {} ## Chunk -> its layers, one per biome.
var _pending: Array[Vector2i] = [] ## Chunks to build ahead, nearest last.
var _last_view := Rect2()


func _ready() -> void:
	regenerate()


func _validate_property(property: Dictionary) -> void:
	# The view sets the size instead.
	if property.name == "map_size":
		property.usage = PROPERTY_USAGE_NONE


func _process(_delta: float) -> void:
	if _queued:
		return
	var view := _view_rect()
	if view != _last_view:
		_last_view = view
		_update_chunks(view)
	_build_pending()


## Frees every chunk. The next `_process` builds the ones the view needs, before the frame is drawn.
func _populate() -> void:
	for biome in _biomes():
		biome.free_chunk_layers()
	_chunks.clear()
	_pending.clear()
	_last_view = Rect2()


## The area to fill, in this node's coordinates: the viewport's size, centred on `follow`.
func _view_rect() -> Rect2:
	var size := get_viewport_rect().size
	var centre := Vector2.ZERO
	if follow and follow.is_inside_tree():
		centre = to_local(follow.global_position)
	return Rect2(centre - size / 2, size)


## Builds the chunks `view` shows, queues those within `margin` of it and frees those beyond twice that.
func _update_chunks(view: Rect2) -> void:
	_pending.clear()
	var biomes := _biomes()
	if not noise or biomes.is_empty() or not biomes[0].tile_set:
		return
	var thresholds := _thresholds(biomes)
	var near := view.grow(margin)
	var far := view.grow(margin * 2)
	var centre := view.get_center()
	var distances := {}
	var keep := {}
	var area := _chunk_area(far, biomes[0])
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var chunk := Vector2i(x, y)
			var bounds := _chunk_bounds(chunk, biomes[0])
			if not bounds.intersects(far):
				continue
			keep[chunk] = true
			if _chunks.has(chunk):
				continue
			if bounds.intersects(view):
				# Already on screen: build it now rather than show a hole.
				_build_chunk(chunk, biomes, thresholds)
			elif bounds.intersects(near):
				_pending.append(chunk)
				distances[chunk] = bounds.get_center().distance_squared_to(centre)
	for chunk in _chunks.keys():
		if not keep.has(chunk):
			_free_chunk(chunk)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return distances[a] > distances[b])


## Builds queued chunks, nearest first: always one, then more while another chunk like the last
## still fits in `build_budget_ms`.
func _build_pending() -> void:
	if _pending.is_empty():
		return
	var biomes := _biomes()
	var thresholds := _thresholds(biomes)
	var start := Time.get_ticks_usec()
	var cost := 0
	while not _pending.is_empty() and Time.get_ticks_usec() - start + cost <= build_budget_ms * 1000.0:
		var t := Time.get_ticks_usec()
		_build_chunk(_pending.pop_back(), biomes, thresholds)
		cost = Time.get_ticks_usec() - t


func _build_chunk(chunk: Vector2i, biomes: Array[LayeredTerrainBiome], thresholds: PackedFloat32Array) -> void:
	var layers: Array[TileMapLayer] = []
	for biome in biomes:
		layers.append(biome.add_chunk_layer())
	var first := chunk * chunk_size
	for y in range(first.y, first.y + chunk_size):
		for x in range(first.x, first.x + chunk_size):
			var cell := Vector2i(x, y)
			var i := _biome_at(cell, thresholds)
			if i >= 0:
				biomes[i].place(cell, layers[i])
	# Update the layers now rather than at the end of the frame, so the budget counts it.
	for layer in layers:
		layer.update_internals()
	_chunks[chunk] = layers


func _free_chunk(chunk: Vector2i) -> void:
	for layer in _chunks[chunk]:
		if is_instance_valid(layer):
			layer.queue_free()
	_chunks.erase(chunk)


## The chunk that holds `cell`.
func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i((Vector2(cell) / chunk_size).floor())


## The chunks under the map-space bounding box of `rect`: every chunk it overlaps, and more.
func _chunk_area(rect: Rect2, layer: TileMapLayer) -> Rect2i:
	rect.position -= layer.position
	var lo := Vector2i.MAX
	var hi := Vector2i.MIN
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var cell := layer.local_to_map(corner)
		lo = lo.min(cell)
		hi = hi.max(cell)
	lo = _chunk_of(lo)
	hi = _chunk_of(hi)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## `chunk`'s area in this node's coordinates: the box around its corner cells, grown by two tiles
## to cover tiles taller than their cell.
func _chunk_bounds(chunk: Vector2i, layer: TileMapLayer) -> Rect2:
	var first := chunk * chunk_size
	var last := first + Vector2i.ONE * (chunk_size - 1)
	var bounds := Rect2(layer.map_to_local(first), Vector2.ZERO)
	bounds = bounds.expand(layer.map_to_local(Vector2i(last.x, first.y)))
	bounds = bounds.expand(layer.map_to_local(Vector2i(first.x, last.y)))
	bounds = bounds.expand(layer.map_to_local(last))
	var grow := Vector2(layer.tile_set.tile_size) * 2
	bounds = bounds.grow_individual(grow.x, grow.y, grow.x, grow.y)
	bounds.position += layer.position
	return bounds
