# Layered Terrain

Procedural, stacked 2D tile terrain for Godot 4.4+. Noise elevation picks a biome for each cell, and each biome draws on its own `TileMapLayer`, raised a few pixels above the one below. The result is terraced, pseudo-3D terrain that regenerates live in the editor.

Generation is deterministic: each cell depends only on its coordinates and `seed`.

## Files

| Script | Class | Purpose |
|---|---|---|
| `layered_terrain.gd` | `LayeredTerrain` (Node2D) | Generates a fixed `map_size` map. |
| `infinite_layered_terrain.gd` | `InfiniteLayeredTerrain` (extends `LayeredTerrain`) | Streams a `map_size` window centred on a `follow` node. |
| `layered_terrain_biome.gd` | `LayeredTerrainBiome` (Resource) | One elevation band: threshold, atlas source, height, roughness. |

## Requirements
Godot 4.4 or later (`TileMapLayer`, `@export_tool_button`).

## Setup
1. Copy the three `.gd` files (with their `.uid` files) into your project.
2. Add a `LayeredTerrain` (or `InfiniteLayeredTerrain`) node.
3. Add one child `TileMapLayer` per biome, all sharing the same `TileSet`. Child order matches the `biomes` array: the first `TileMapLayer` draws biome 0.
4. Set up the `TileSet`: one atlas source per biome, with one tile per level in row 0 (column = level). Each tile should be a column tall enough to cover `(layers − 1) × layer_height` px below its ground, so it fills the gap down to lower layers.
5. On the terrain node, assign a `FastNoiseLite` to `noise` and add `LayeredTerrainBiome` resources to `biomes`, ordered from lowest to highest `threshold`.

The map regenerates whenever you edit a property, the noise, or a biome. You can also press **Regenerate** in the inspector.

## How it works
- Noise (≈ −1..1) is mapped to elevation 0..1. A cell takes the first biome whose `threshold` is ≥ its elevation; the last biome catches everything above.
- The cell gets one tile on that biome's layer, at atlas column `height`. With probability `roughness` it steps one level up or down (bounced back inside `0..levels − 1`), using a hash of the cell and `seed`.
- Layer `i` sits at `y = −i × layer_height`, and its `y_sort_origin` cancels that offset, so all layers Y-sort together by grid row.

## Properties

### LayeredTerrain
| Property | Default | Description |
|---|---|---|
| `noise` | — | `FastNoiseLite` for elevation. |
| `biomes` | `[]` | `LayeredTerrainBiome`s, lowest threshold first. |
| `layer_height` | `8` | Pixels each layer sits above the one below. |
| `seed` | `0` | Seed for roughness rolls. (Set the noise's own seed separately.) |
| `map_size` | `36×36` | Map size in cells; for the infinite variant, the window size. |
| `levels` | `3` | Number of level columns in each biome's atlas source. |

### InfiniteLayeredTerrain
Adds `follow` (Node2D): the window stays centred on this node's cell, and cells are generated or erased as it moves. Leave it empty for a fixed window at the origin. Make `map_size` large enough to cover the screen.

### LayeredTerrainBiome
| Property | Default | Description |
|---|---|---|
| `threshold` | `1.0` | Covers normalised elevation up to this value. |
| `source_id` | `0` | Atlas source ID of this biome's tiles. |
| `height` | `0` | Base level (atlas column). Must be below the terrain's `levels`. |
| `roughness` | `0.0` | Chance a cell steps one level up or down. |
