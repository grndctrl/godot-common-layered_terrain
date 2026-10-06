@tool
class_name LayeredTerrainBiome
extends TileMapLayer
## One elevation band of a `LayeredTerrain`: a child TileMapLayer that draws its own cells.
## Holds the biome's settings (weight, atlas source, relief) and places its own tiles.
## The terrain lays the layer out (position, sorting) and picks which biome each cell belongs to.

## Share of the terrain's elevation range: the biome covers weight / (sum of all weights) of
## the terrain's lower_threshold..upper_threshold, stacked above the biomes before it in child order.
@export_range(0.0, 1.0, 0.001) var weight := 1.0:
	set(value):
		weight = value
		_settings_changed()

## Atlas source of this biome's tiles.
@export var source_id := 0:
	set(value):
		source_id = value
		_settings_changed()

## Relief: raises cells 0..`amplitude` px. Its frequency sets the size of the patches.
## Leave empty for a flat biome.
@export var relief_noise: FastNoiseLite:
	set(value):
		if relief_noise and relief_noise.changed.is_connected(_settings_changed):
			relief_noise.changed.disconnect(_settings_changed)
		relief_noise = value
		if relief_noise and not relief_noise.changed.is_connected(_settings_changed):
			relief_noise.changed.connect(_settings_changed)
		_settings_changed()

## Highest raise in px: 0 = flat, 1 = cells at 0 or +1 px, 2 = 0..+2 px.
## This many alternative tiles are made for the source. Keep
## `amplitude` + the terrain's `base_height` + this layer's index × its `layer_height` within the
## tiles' columns, or gaps show.
@export_range(0, 15) var amplitude := 0:
	set(value):
		amplitude = value
		_settings_changed()


func _settings_changed() -> void:
	var terrain := get_parent() as LayeredTerrain
	if terrain:
		terrain.queue_regenerate()


## The cell's raise in px, 0..amplitude: the relief noise (≈ −1..1) split into amplitude + 1
## equal bands, lowest band = 0 px.
func raise_at(cell: Vector2i) -> int:
	if not relief_noise:
		return 0
	var n := (relief_noise.get_noise_2dv(cell) + 1.0) * 0.5
	return clampi(floori(n * (amplitude + 1)), 0, amplitude)


## Puts this biome's tile, raised by the relief, on `cell`.
func place(cell: Vector2i) -> void:
	set_cell(cell, source_id, Vector2i.ZERO, raise_at(cell))


## Gives every tile of this biome's atlas source alternatives 1..amplitude:
## alternative r is alternative 0 drawn r px higher.
func ensure_raises() -> void:
	if not tile_set or not tile_set.has_source(source_id):
		return
	var source := tile_set.get_source(source_id) as TileSetAtlasSource
	if not source:
		return
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var base := source.get_tile_data(coords, 0)
		for r in range(1, amplitude + 1):
			if not source.has_alternative_tile(coords, r):
				source.create_alternative_tile(coords, r)
			var data := source.get_tile_data(coords, r)
			data.texture_origin = base.texture_origin + Vector2i(0, r)
			data.y_sort_origin = base.y_sort_origin
			data.z_index = base.z_index
