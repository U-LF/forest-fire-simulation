extends Node

signal tree_stats_updated(total: int, healthy: int, damaged: int, burnt: int)

@export var map_size: int = 2048
@export var terrain_size: float = 4000.0

var vp_a: SubViewport
var vp_b: SubViewport
var rect_a: ColorRect
var rect_b: ColorRect
var sim_mat_a: ShaderMaterial
var sim_mat_b: ShaderMaterial

var current_vp_is_a: bool = true

var _stats_timer: float = 0.0
var _stats_interval: float = 1.0
var _is_calculating_stats: bool = false

var ml_http_request: HTTPRequest
var _ml_timer: float = 0.0
var _ml_interval: float = 0.01
var _is_ml_predicting: bool = false
var _ml_predicted_burn_set: Dictionary = {}


func _ready() -> void:
	vp_a = SubViewport.new()
	vp_b = SubViewport.new()
	vp_a.size = Vector2(map_size, map_size)
	vp_b.size = Vector2(map_size, map_size)
	vp_a.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp_b.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	# Crucial: Never clear the background, so the fire data accumulates frame by frame
	vp_a.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	vp_b.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	
	vp_a.transparent_bg = true
	vp_b.transparent_bg = true
	vp_a.disable_3d = true
	vp_b.disable_3d = true
	vp_a.use_hdr_2d = true # CRITICAL: Enables 16-bit float precision so small values accumulate!
	vp_b.use_hdr_2d = true
	
	add_child(vp_a)
	add_child(vp_b)
	
	ml_http_request = HTTPRequest.new()
	add_child(ml_http_request)
	ml_http_request.request_completed.connect(_on_ml_prediction_completed)
	
	var sim_shader = load("res://resources/fire_sim.gdshader")
	sim_mat_a = ShaderMaterial.new()
	sim_mat_a.shader = sim_shader
	sim_mat_b = ShaderMaterial.new()
	sim_mat_b.shader = sim_shader
	
	rect_a = ColorRect.new()
	rect_b = ColorRect.new()
	rect_a.size = Vector2(map_size, map_size)
	rect_b.size = Vector2(map_size, map_size)
	rect_a.material = sim_mat_a
	rect_b.material = sim_mat_b
	
	vp_a.add_child(rect_a)
	vp_b.add_child(rect_b)
	# Connect the textures
	sim_mat_a.set_shader_parameter("state_tex", vp_b.get_texture())
	sim_mat_b.set_shader_parameter("state_tex", vp_a.get_texture())
	
	call_deferred("_inject_to_terrain")
	call_deferred("_setup_particles")
	
	# Find camera and connect
	call_deferred("_connect_to_camera")

var _global_time: float = 0.0
var fire_particles: GPUParticles3D
var fire_proc_mat: ShaderMaterial
var ember_particles: GPUParticles3D
var ember_proc_mat: ShaderMaterial

func _setup_particles() -> void:
	var terrain = get_parent().get_node_or_null("Terrain")
	if not terrain or not terrain.terrain_material: return
	
	var height_map = terrain.terrain_material.get_shader_parameter("macro_noise")
	
	# --- Fire Particles ---
	fire_proc_mat = ShaderMaterial.new()
	fire_proc_mat.shader = load("res://resources/fire_particles.gdshader")
	fire_proc_mat.set_shader_parameter("burn_map", vp_a.get_texture())
	fire_proc_mat.set_shader_parameter("height_map", height_map)
	fire_proc_mat.set_shader_parameter("terrain_size", terrain_size)
	var noise_scale = 1400.0
	if terrain and "terrain_scale" in terrain:
		noise_scale = terrain.terrain_scale
	fire_proc_mat.set_shader_parameter("noise_scale", noise_scale)
	fire_proc_mat.set_shader_parameter("height_scale", 120.0)
	fire_proc_mat.set_shader_parameter("spawn_radius", 600.0)
	
	sim_mat_a.set_shader_parameter("ignite_radius", 0.005) # Realistic brush size (20m radius)
	sim_mat_b.set_shader_parameter("ignite_radius", 0.005)
	
	var draw_mat = ShaderMaterial.new()
	draw_mat.shader = load("res://resources/fire_visual.gdshader")
	
	var quad = QuadMesh.new()
	quad.material = draw_mat
	
	fire_particles = GPUParticles3D.new()
	fire_particles.amount = 50000
	fire_particles.process_material = fire_proc_mat
	fire_particles.draw_pass_1 = quad
	fire_particles.lifetime = 6.0 # Much longer lifetime to show they stay in place
	fire_particles.explosiveness = 0.0
	fire_particles.fixed_fps = 0
	fire_particles.interpolate = false # Disable engine interpolation for custom shaders
	fire_particles.local_coords = false 
	fire_particles.visibility_aabb = AABB(Vector3(-2000, -100, -2000), Vector3(4000, 1000, 4000))
	fire_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(fire_particles)
	
	# --- Ember Particles ---
	ember_proc_mat = ShaderMaterial.new()
	ember_proc_mat.shader = load("res://resources/ember_particles.gdshader")
	ember_proc_mat.set_shader_parameter("burn_map", vp_a.get_texture())
	ember_proc_mat.set_shader_parameter("height_map", height_map)
	ember_proc_mat.set_shader_parameter("terrain_size", terrain_size)
	ember_proc_mat.set_shader_parameter("noise_scale", noise_scale)
	ember_proc_mat.set_shader_parameter("height_scale", 120.0)
	ember_proc_mat.set_shader_parameter("spawn_radius", 600.0)
	
	var ember_draw_mat = StandardMaterial3D.new()
	ember_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_draw_mat.albedo_color = Color(1.0, 0.4, 0.1, 1.0)
	ember_draw_mat.emission_enabled = true
	ember_draw_mat.emission = Color(1.0, 0.3, 0.05)
	ember_draw_mat.emission_energy_multiplier = 4.0 # More subtle glow
	ember_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD # Additive for "heat" look
	ember_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_draw_mat.billboard_keep_scale = true
	
	var ember_quad = QuadMesh.new()
	ember_quad.size = Vector2(0.8, 0.8) # Base size, will be scaled down by the shader
	ember_quad.material = ember_draw_mat
	
	ember_particles = GPUParticles3D.new()
	ember_particles.amount = 40000 # Double density
	ember_particles.process_material = ember_proc_mat
	ember_particles.draw_pass_1 = ember_quad
	ember_particles.lifetime = 4.0 # Longer, slower drift
	ember_particles.explosiveness = 0.0
	ember_particles.fixed_fps = 0
	ember_particles.interpolate = false # Disable engine interpolation for custom shaders
	ember_particles.local_coords = false
	ember_particles.visibility_aabb = AABB(Vector3(-2000, -100, -2000), Vector3(4000, 500, 4000))
	ember_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(ember_particles)

func _inject_to_terrain() -> void:
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.terrain_material:
		terrain.terrain_material.set_shader_parameter("burn_map", vp_a.get_texture())

func _connect_to_camera() -> void:
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_signal("fire_started"):
		cam.fire_started.connect(_on_fire_started)

var _ignite_frames: int = 0

func _process(_delta: float) -> void:
	_global_time += _delta

	if current_vp_is_a:
		vp_a.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp_b.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		vp_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp_b.render_target_update_mode = SubViewport.UPDATE_ONCE

	current_vp_is_a = not current_vp_is_a

	# Update Shader Time
	sim_mat_a.set_shader_parameter("delta_time", _delta)
	sim_mat_a.set_shader_parameter("global_time", _global_time)
	sim_mat_b.set_shader_parameter("delta_time", _delta)
	sim_mat_b.set_shader_parameter("global_time", _global_time)

	if _ignite_frames > 0:
		_ignite_frames -= 1
	else:
		# Clear ignition after allowing it to render
		sim_mat_a.set_shader_parameter("ignite_pos", Vector2(-1, -1))
		sim_mat_b.set_shader_parameter("ignite_pos", Vector2(-1, -1))
	
	# Update Particle Offset
	if fire_particles and fire_proc_mat:
		var cam = get_viewport().get_camera_3d()
		if cam:
			var cam_pos = cam.global_position
			var world_offset = Vector3(cam_pos.x, 0, cam_pos.z)
			# Do NOT move fire_particles.global_position anymore
			fire_proc_mat.set_shader_parameter("world_offset", world_offset)
			
			if ember_particles and ember_proc_mat:
				# Do NOT move ember_particles.global_position anymore
				ember_proc_mat.set_shader_parameter("world_offset", world_offset)
				
	# Update Wind for Fire/Embers
	var weather_mgr = get_parent().get_node_or_null("WeatherManager")
	if weather_mgr and "current_wind" in weather_mgr:
		var wind = weather_mgr.current_wind
		var temp = weather_mgr.current_temp
		var rh = weather_mgr.current_rh
		var rain = weather_mgr.current_rain
		var moisture = 0.0
		if "current_moisture" in weather_mgr:
			moisture = weather_mgr.current_moisture
		var time_scale = 1.0
		if "time_scale" in weather_mgr:
			time_scale = weather_mgr.time_scale
		
		# Update Simulation Material
		sim_mat_a.set_shader_parameter("current_temp", temp)
		sim_mat_a.set_shader_parameter("current_rh", rh)
		sim_mat_a.set_shader_parameter("current_wind", wind)
		sim_mat_a.set_shader_parameter("current_wind_dir", weather_mgr.current_wind_dir)
		sim_mat_a.set_shader_parameter("current_rain", rain)
		sim_mat_a.set_shader_parameter("current_moisture", moisture)
		sim_mat_a.set_shader_parameter("sim_speed", time_scale)
		
		sim_mat_b.set_shader_parameter("current_temp", temp)
		sim_mat_b.set_shader_parameter("current_rh", rh)
		sim_mat_b.set_shader_parameter("current_wind", wind)
		sim_mat_b.set_shader_parameter("current_wind_dir", weather_mgr.current_wind_dir)
		sim_mat_b.set_shader_parameter("current_rain", rain)
		sim_mat_b.set_shader_parameter("current_moisture", moisture)
		sim_mat_b.set_shader_parameter("sim_speed", time_scale)
		
		if fire_proc_mat:
			fire_proc_mat.set_shader_parameter("wind_speed", wind * 0.5)
			fire_proc_mat.set_shader_parameter("wind_strength", wind * 0.1)
		if ember_proc_mat:
			ember_proc_mat.set_shader_parameter("wind_speed", wind * 0.5)
			ember_proc_mat.set_shader_parameter("wind_strength", wind * 0.1)

	_stats_timer += _delta
	if _stats_timer >= _stats_interval and not _is_calculating_stats:
		_stats_timer = 0.0
		_start_tree_stats_calculation()

	_ml_timer += _delta
	if _ml_timer >= _ml_interval and not _is_ml_predicting:
		_ml_timer = 0.0
		_start_ml_inference()

func _start_tree_stats_calculation() -> void:
	var forest_gen = get_parent().get_node_or_null("Forest")
	if not forest_gen: return
	
	var burn_tex = vp_a.get_texture()
	if not burn_tex: return
	
	_is_calculating_stats = true
	var img = burn_tex.get_image()
	if not img:
		_is_calculating_stats = false
		return
		
	var tree_positions = forest_gen.get_all_tree_positions()
	WorkerThreadPool.add_task(_calculate_stats_task.bind(img, tree_positions))

func _calculate_stats_task(img: Image, tree_positions: Array) -> void:
	var total = tree_positions.size()
	var healthy = 0
	var damaged = 0
	var burnt = 0
	
	var img_width = img.get_width()
	var img_height = img.get_height()
	
	for pos in tree_positions:
		var uv_x = (pos.x / terrain_size) + 0.5
		var uv_y = (pos.z / terrain_size) + 0.5
		
		if uv_x >= 0.0 and uv_x <= 1.0 and uv_y >= 0.0 and uv_y <= 1.0:
			var px = clamp(int(uv_x * img_width), 0, img_width - 1)
			var py = clamp(int(uv_y * img_height), 0, img_height - 1)
			
			var color = img.get_pixel(px, py)
			# R: Fire, G: Char, B: Fuel
			if color.g > 0.8:
				burnt += 1
			elif color.g > 0.05 or color.r > 0.05:
				damaged += 1
			else:
				healthy += 1
		else:
			healthy += 1
			
	call_deferred("_on_stats_calculated", total, healthy, damaged, burnt)

func _on_stats_calculated(total: int, healthy: int, damaged: int, burnt: int) -> void:
	tree_stats_updated.emit(total, healthy, damaged, burnt)
	_is_calculating_stats = false


func _on_fire_started(world_pos: Vector3) -> void:
	var uv_x = (world_pos.x / terrain_size) + 0.5
	var uv_y = (world_pos.z / terrain_size) + 0.5
	var uv = Vector2(uv_x, uv_y)
	
	sim_mat_a.set_shader_parameter("ignite_pos", uv)
	sim_mat_b.set_shader_parameter("ignite_pos", uv)
	_ignite_frames = 2 # Keep the ignition coordinate alive for 2 frames

func get_burn_map() -> ViewportTexture:
	return vp_a.get_texture()

func _start_ml_inference() -> void:
	var burn_tex = vp_a.get_texture()
	if not burn_tex: return
	
	_is_ml_predicting = true
	var start_time = Time.get_ticks_msec()
	
	var img = burn_tex.get_image()
	if not img:
		_is_ml_predicting = false
		return
	
	var get_image_time = Time.get_ticks_msec() - start_time
	
	var weather_mgr = get_parent().get_node_or_null("WeatherManager")
	var wind_speed = 0.0
	var temp = 20.0
	if weather_mgr and "current_wind" in weather_mgr:
		wind_speed = weather_mgr.current_wind
		temp = weather_mgr.current_temp
	
	WorkerThreadPool.add_task(_prepare_and_send_ml_data.bind(img, wind_speed, temp, start_time, get_image_time))

func _prepare_and_send_ml_data(img: Image, wind_speed: float, temp: float, og_start_time: int, get_img_time: int) -> void:
	# Downsample massive 2048 map to 64x64 grid for lightweight ML prediction
	var small_img = Image.create_empty(64, 64, false, img.get_format())
	small_img.copy_from(img)
	small_img.resize(64, 64, Image.INTERPOLATE_NEAREST)
	
	var cells = []
	var actually_burned = 0
	
	var pred_came_true = 0
	var pred_keys = _ml_predicted_burn_set.keys()
	for key in pred_keys:
		var parts = key.split(",")
		var cx = int(parts[0])
		var cy = int(parts[1])
		var pcolor = small_img.get_pixel(cx, cy)
		if pcolor.r > 0.1 or pcolor.g > 0.5:
			pred_came_true += 1
	
	for y in range(1, 63):
		for x in range(1, 63):
			var color = small_img.get_pixel(x, y)
			
			# If the cell is currently on fire (Red) OR has burned into ash (Green)
			if color.r > 0.1 or color.g > 0.5:
				actually_burned += 1
				
			# Skip cells that are already burning or are dead ash
			if color.r > 0 or color.g > 0.5: continue 
			
			var north = 1 if small_img.get_pixel(x, y-1).r > 0.1 else 0
			var south = 1 if small_img.get_pixel(x, y+1).r > 0.1 else 0
			var east = 1 if small_img.get_pixel(x+1, y).r > 0.1 else 0
			var west = 1 if small_img.get_pixel(x-1, y).r > 0.1 else 0
			var total = north + south + east + west
			
			if total == 0: continue # Optimization: Don't predict totally safe cells
			
			cells.append({
				"x": x,
				"y": y,
				"fire_north": north,
				"fire_south": south,
				"fire_east": east,
				"fire_west": west,
				"total_burning_neighbors": total,
				"erc": color.b * 80.0, # Fuel scaled to 0-80
				"vs": wind_speed * 3.0, # Scale up wind
				"tmmn": temp + 273.15, # Convert Celsius to Kelvin
				"tmmx": temp + 278.15, # Max Temp (Kelvin)
				"elevation": 1500.0, # Realistic forest elevation in meters
				"pdsi": -2.0, # Moderate drought
				"NDVI": color.b,
				"pr": 0.0,
				"sph": 0.005,
				"th": 180.0,
				"population": 10.0
			})
	
	if cells.is_empty():
		call_deferred("_reset_ml_flag")
		return
		
	var body = JSON.stringify({"cells": cells})
	var process_time = Time.get_ticks_msec() - (og_start_time + get_img_time)
	call_deferred("_send_ml_request", body, og_start_time, get_img_time, process_time, cells, actually_burned, pred_came_true)

func _reset_ml_flag() -> void:
	_is_ml_predicting = false

func _send_ml_request(body_json: String, og_start_time: int, get_img_time: int, process_time: int, req_cells: Array, actually_burned: int, pred_came_true: int) -> void:
	var headers = ["Content-Type: application/json"]
	var req_start = Time.get_ticks_msec()
	var err = ml_http_request.request("http://127.0.0.1:5000/predict", headers, HTTPClient.METHOD_POST, body_json)
	if err != OK:
		_is_ml_predicting = false
		print("[ML Bridge] Request failed to send!")
	
	# Store the timing data temporarily so the callback can access it
	ml_http_request.set_meta("start_time", og_start_time)
	ml_http_request.set_meta("get_img_time", get_img_time)
	ml_http_request.set_meta("process_time", process_time)
	ml_http_request.set_meta("req_cells", req_cells)
	ml_http_request.set_meta("actually_burned", actually_burned)
	ml_http_request.set_meta("pred_came_true", pred_came_true)

func _on_ml_prediction_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_ml_predicting = false
	var total_time = Time.get_ticks_msec() - ml_http_request.get_meta("start_time")
	var get_img_time = ml_http_request.get_meta("get_img_time")
	var process_time = ml_http_request.get_meta("process_time")
	var net_time = total_time - get_img_time - process_time
	if response_code == 200:
		var raw_str = body.get_string_from_utf8()
		var json = JSON.parse_string(raw_str)
		# print(raw_str) # Removed to avoid console spam
		if json and typeof(json) == TYPE_DICTIONARY and json.has("predictions"):
			var preds = json["predictions"]
			var req_cells = ml_http_request.get_meta("req_cells")
			var actually_burned = ml_http_request.get_meta("actually_burned")
			var pred_came_true = ml_http_request.get_meta("pred_came_true")
			
			for i in range(preds.size()):
				if preds[i] == 1.0:
					var cx = req_cells[i]["x"]
					var cy = req_cells[i]["y"]
					var key = str(cx) + "," + str(cy)
					_ml_predicted_burn_set[key] = true
			
			var total_preds = _ml_predicted_burn_set.size()
			var accuracy = 0.0
			if total_preds > 0:
				accuracy = float(pred_came_true) / float(total_preds) * 100.0
					
			print("[Accuracy Tester] ML Predictions: ", total_preds, " | Predictions that came true in Godot: ", pred_came_true, " | Accuracy: ", "%0.1f" % accuracy, "%")
	else:
		print("[ML Bridge] HTTP Request to Python server failed. Code: ", response_code)
