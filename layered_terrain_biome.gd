@tool
class_name LayeredTerrainBiome
extends Resource
## One elevation band of a LayeredTerrain: an atlas source and a level (atlas column).

## Covers normalised elevation up to this value.
@export_range(0.0, 1.0) var threshold := 1.0:
	set(value):
		threshold = value
		emit_changed()

## Atlas source of this biome's tiles.
@export var source_id := 0:
	set(value):
		source_id = value
		emit_changed()

## Base level: the atlas column of the top tile. Must be below the terrain's `levels`.
@export_range(0, 15) var height := 0:
	set(value):
		height = value
		emit_changed()

## Chance a cell steps one level up or down.
@export_range(0.0, 1.0) var roughness := 0.0:
	set(value):
		roughness = value
		emit_changed()
