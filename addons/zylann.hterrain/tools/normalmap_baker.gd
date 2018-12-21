tool
extends Node

# Bakes normals asynchronously in the editor as the heightmap gets modified.
# This is probably not a nice method GPU-wise, but it's way faster than GDScript.

const HTerrainData = preload("../hterrain_data.gd")

const VIEWPORT_SIZE = 64

const STATE_PENDING = 0
const STATE_PROCESSING = 1

var _viewport = null
var _ci = null
var _pending_tiles_grid = {}
var _pending_tiles_queue = []
var _processing_tile = null
var _terrain_data = null


func _ready():
	_viewport = Viewport.new()
	_viewport.size = Vector2(VIEWPORT_SIZE + 2, VIEWPORT_SIZE + 2)
	_viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_v_flip = true
	_viewport.world = World.new()
	_viewport.own_world = true
	add_child(_viewport)
	
	var mat = ShaderMaterial.new()
	mat.shader = load("res://addons/zylann.hterrain/tools/bump2normal_tex.shader")
	
	_ci = TextureRect.new()
	_ci.material = mat
	_viewport.add_child(_ci)
	
	set_process(false)


func set_terrain_data(data):
	if data == _terrain_data:
		return

	_pending_tiles_grid.clear()
	_pending_tiles_queue.clear()
	_processing_tile = null
	_ci.texture = null
	set_process(false)
	
	if data == null:
		_terrain_data.disconnect("map_changed", self, "_on_terrain_data_map_changed")
		_terrain_data.disconnect("resolution_changed", self, "_on_terrain_data_resolution_changed")

	_terrain_data = data
	
	if _terrain_data != null:
		_terrain_data.connect("map_changed", self, "_on_terrain_data_map_changed")
		_terrain_data.connect("resolution_changed", self, "_on_terrain_data_resolution_changed")
		_ci.texture = data.get_texture(HTerrainData.CHANNEL_HEIGHT)


func _on_terrain_data_map_changed(maptype, index):
	if maptype == HTerrainData.CHANNEL_HEIGHT:
		_ci.texture = _terrain_data.get_texture(HTerrainData.CHANNEL_HEIGHT)


func _on_terrain_data_resolution_changed():
	# TODO Workaround issue https://github.com/godotengine/godot/issues/24463
	_ci.update()


func request_tiles_in_region(min_pos, size):
	assert(is_inside_tree())
	assert(_terrain_data != null)
	var res = _terrain_data.get_resolution()
	
	min_pos -= Vector2(1, 1)
	var max_pos = min_pos + size + Vector2(1, 1)
	var tmin = (min_pos / VIEWPORT_SIZE).floor()
	var tmax = (max_pos / VIEWPORT_SIZE).ceil()
	var ntx = res / VIEWPORT_SIZE
	var nty = res / VIEWPORT_SIZE
	tmin.x = clamp(tmin.x, 0, ntx)
	tmin.y = clamp(tmin.y, 0, nty)
	tmax.x = clamp(tmax.x, 0, ntx)
	tmax.y = clamp(tmax.y, 0, nty)
	
#	print("min: ", min_pos, ", max: ", max_pos)
#	print("tmin: ", tmin, ", tmax: ", tmax)
	
	for y in range(tmin.y, tmax.y):
		for x in range(tmin.x, tmax.x):
			request_tile(Vector2(x, y))


func request_tile(tpos):
	assert(tpos == tpos.round())
	if _pending_tiles_grid.has(tpos):
		var state = _pending_tiles_grid[tpos]
		if state == STATE_PENDING:
			return
	_pending_tiles_grid[tpos] = STATE_PENDING
	_pending_tiles_queue.push_front(tpos)
	set_process(true)


func _process(delta):
	if not is_processing():
		return
	
	if _processing_tile != null and _terrain_data != null:
		#var time_before = OS.get_ticks_msec()
		var src = _viewport.get_texture().get_data()
		var dst = _terrain_data.get_image(HTerrainData.CHANNEL_NORMAL)
		
		src.convert(dst.get_format())
		#src.save_png("test_normal.png")
		var pos = _processing_tile * VIEWPORT_SIZE
		var w = src.get_width() - 1
		var h = src.get_height() - 1
		dst.blit_rect(src, Rect2(1, 1, w, h), pos)
		_terrain_data.notify_region_change([int(pos.x), int(pos.y)], [w, h], HTerrainData.CHANNEL_NORMAL)
		
		if _pending_tiles_grid[_processing_tile] == STATE_PROCESSING:
			_pending_tiles_grid.erase(_processing_tile)
		_processing_tile = null
		#print("Spent ", OS.get_ticks_msec() - time_before, " ms downloading viewport")

	if _has_pending_tiles():
		var tpos = _pending_tiles_queue[-1]
		_pending_tiles_queue.pop_back()
		_ci.rect_position = -VIEWPORT_SIZE * tpos + Vector2(1, 1)
		_viewport.render_target_update_mode = Viewport.UPDATE_ONCE
		_processing_tile = tpos
		_pending_tiles_grid[tpos] = STATE_PROCESSING
	else:
		set_process(false)


func _has_pending_tiles():
	return len(_pending_tiles_queue) > 0

