# Layered Terrain

Procedural, stacked 2D tile terrain for Godot 4.4+. Noise elevation picks a biome for each cell, and each biome is a `TileMapLayer` node that draws its own cells, raised a few pixels above the one below. The result is terraced, pseudo-3D terrain that regenerates live in the editor.

Generation is deterministic: each cell depends only on its coordinates and the noises.

## Files

| Script | Class | Purpose |
|---|---|---|
| `layered_terrain.gd` | `LayeredTerrain` (Node2D) | Generates a fixed `map_size` map. |
| `infinite_layered_terrain.gd` | `InfiniteLayeredTerrain` (extends `LayeredTerrain`) | Streams a `map_size` window centred on a `follow` node. |
| `layered_terrain_biome.gd` | `LayeredTerrainBiome` (TileMapLayer) | One elevation band, a child of the terrain: weight, atlas source, relief noise and amplitude. |

## Requirements
Godot 4.4 or later (`TileMapLayer`, `@export_tool_button`).

## Setup
1. Copy the three `.gd` files (with their `.uid` files) into your project.
2. Add a `LayeredTerrain` (or `InfiniteLayeredTerrain`) node.
3. Add one `LayeredTerrainBiome` child per biome, lowest elevation first (child order sets both the elevation order and the stacking order), all sharing the same `TileSet`. There is no `biomes` array: each child is the biome.
4. Set up the `TileSet`: one atlas source per biome, with its base tile at `(0, 0)`. Other atlas columns are reserved for variations (only column 0 is used for now). Each tile should be a column tall enough to cover `amplitude + base_height + i × layer_height` px below its ground (*i* = the biome's index), so it fills the gap down to lower layers.
5. On the terrain node, assign a `FastNoiseLite` to `noise`. On each biome, set `weight` and `source_id`, and give it its own `relief_noise` and `amplitude` to make it bumpy.

The map regenerates whenever you edit a property, the noise, or a biome, and when you add, remove or reorder biome nodes. You can also press **Regenerate** in the inspector.

## How it works
- Noise (≈ −1..1) is mapped to elevation 0..1. Cells outside `lower_threshold..upper_threshold` are left empty. The biomes split that range by weight, in child order: biome *i* covers `weight / total weight` of the range, above biome *i* − 1. With the default range 0..1 and weights 0.25, 0.5, 0.25 the bands are 0..0.25, 0.25..0.75 and 0.75..1. Noise values cluster around the middle, so a band's share of the map isn't exactly its share of the range.
- The cell gets one tile on that biome's layer, raised 0..`amplitude` px by the biome's `relief_noise`: the noise is split into `amplitude + 1` equal bands, the lowest at 0 px. 
- A raise of *r* px is alternative tile *r*: alternative 0 with `texture_origin.y` moved *r* px up. each biome's `ensure_raises()` creates alternatives `1..amplitude` for every tile of its own atlas source and copies `texture_origin`, `y_sort_origin` and `z_index` from alternative 0, so they stay in sync. These alternatives are saved into the `TileSet`. The raise lives in the cell data, so saved maps and streaming need nothing extra.
- Layer `i` sits at `y = −(base_height + i × layer_height)`, and its `y_sort_origin` cancels that offset, so all layers Y-sort together by grid row.

## Properties

### LayeredTerrain
| Property | Default | Description |
|---|---|---|
| `noise` | — | `FastNoiseLite` for elevation. |
| `layer_height` | `8` | Pixels each layer sits above the one below. |
| `map_size` | `36×36` | Map size in cells; for the infinite variant, the window size. |
| `lower_threshold` | `0.0` | Cells with elevation below this are left empty. |
| `upper_threshold` | `1.0` | Cells with elevation above this are left empty. |
| `base_height` | `0` | Pixels every layer is lifted, to stack this terrain on another. |

### InfiniteLayeredTerrain
Adds `follow` (Node2D): the window stays centred on this node's cell, and cells are generated or erased as it moves. Leave it empty for a fixed window at the origin. Make `map_size` large enough to cover the screen.

### LayeredTerrainBiome
A `TileMapLayer`; these are its own properties. The terrain sets its position and sorting.

| Property | Default | Description |
|---|---|---|
| `weight` | `1.0` | 0..1. Share of the elevation range: `weight / total weight`, stacked in child order. |
| `source_id` | `0` | Atlas source ID of this biome's tiles. |
| `relief_noise` | — | `FastNoiseLite` that raises this biome's cells. Its frequency sets the patch size. Empty = flat. |
| `amplitude` | `0` | Highest raise in px: 0 = flat, 1 = cells at 0 or +1 px, 2 = 0..+2 px. Keep `amplitude + base_height + index × layer_height` within the tile column depth. |

## Stacking terrains
One terrain has one elevation `noise`, so to use different noises in different places (say, domain warp for the highlands but not the lowlands), stack several terrains as siblings:

1. The bottom terrain covers `0..1` (the default), so it fills every cell.
2. Each terrain above it covers part of *its own* noise, e.g. `lower_threshold = 0.6`. It places tiles only on those patches and leaves the rest empty, so the terrain below shows through.
3. Give each upper terrain a `base_height` at least the top of the terrain below (e.g. `layer_height × biome count`), so its layers sit above it. Where both have a tile, the upper tile's column covers the lower one.
4. Put the stacked terrains under one parent `Node2D` with `y_sort_enabled = true`. Otherwise each terrain draws as a whole, and the upper one always covers the lower one.

Use `base_height` rather than moving the terrain node up: moving the node shifts its Y-sort, and its tiles would draw behind the lower terrain's.

The terrains have different noises, so their ranges don't partition the map. If the bottom terrain doesn't cover `0..1`, some cells will be empty in every terrain (holes). Where terrains overlap, the upper one draws on top.
