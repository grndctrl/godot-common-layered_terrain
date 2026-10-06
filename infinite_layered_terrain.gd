@tool
class_name InfiniteLayeredTerrain
extends LayeredTerrain
## A `LayeredTerrain` that streams: only a `map_size` window of cells is kept, centred on `follow`,
## and cells are generated or erased as it moves. Make `map_size` large enough to cover the screen.

## The window stays centred on this node. Leave empty for a fixed window at the origin.
@export var follow: Node2D:
	set(value):
		follow = value
		_queue_regenerate()

var _current := Rect2i()


func _ready() -> void:
	regenerate()


func _process(_delta: float) -> void:
	var window := _bounds()
	if window == _current or _queued:
		return
	var layers := _layers()
	for y in range(_current.position.y, _current.end.y):
		for x in range(_current.position.x, _current.end.x):
			if not window.has_point(Vector2i(x, y)):
				for layer in layers:
					layer.erase_cell(Vector2i(x, y))
	_fill(window, _current)
	_current = window


func regenerate() -> void:
	super()
	_current = _bounds()


## `map_size` centred on `follow`'s cell.
func _bounds() -> Rect2i:
	var layers := _layers()
	if not follow or layers.is_empty() or not is_inside_tree() or not follow.is_inside_tree():
		return super()
	var centre := layers[0].local_to_map(layers[0].to_local(follow.global_position))
	return Rect2i(centre - map_size / 2, map_size)
