@tool
extends Node3D

signal forest_ready

@export var terrain: StaticBody3D:
	set(value):
		terrain = value
		_update_capacity_info()

@export var tree_scenes: Array[PackedScene]

@export var meadow_noise: FastNoiseLite

@export_group("Forest Density")
@export var total_tree_count: int = 450000:
	set(value):
		var limit = get_max_tree_capacity()
		total_tree_count = clampi(value, 0, limit)

var _max_tree_limit_cache: int = 0
@export var max_tree_limit: int = 0:
	get:
		return _max_tree_limit_cache
	set(value): 
		# In tool mode, this setter might be called by the inspector.
		# We want to ignore user input but allow our internal _update_capacity_info to set it.
		# However, since we use _max_tree_limit_cache internally, we just block the export setter.
		pass

@export_group("Performance")
@export var chunk_size: float = 250.0
@export var visibility_distance: float = 1250.0

# Spatial indexing for fire logic

var spatial_index: Dictionary = {}
var _chunks: Array[MultiMeshInstance3D] = []
var _wind_materials: Array[ShaderMaterial] = []

var _is_generating: bool = false

func _enter_tree():
	if Engine.is_editor_hint():
		_update_capacity_info()

func _ready():
	_update_capacity_info()
	if Engine.is_editor_hint():
		return

	if not terrain:
		push_error("ForestGenerator: No terrain assigned!")
		return
		
	if not terrain.macro_image:
		await terrain.terrain_ready
	
	if not meadow_noise:
		meadow_noise = FastNoiseLite.new()
		meadow_noise.seed = randi()
		meadow_noise.frequency = 0.005 # Large sprawling meadows
		meadow_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	
	var map_size = 2048
	var fire_mgr = get_parent().get_node_or_null("FireManager")
	if fire_mgr and "map_size" in fire_mgr:
		map_size = fire_mgr.map_size
	
	# Start generation on a background thread
	# Using WorkerThreadPool for Godot 4 best practices
	WorkerThreadPool.add_task(_generate_forest_threaded.bind(map_size))

func _update_capacity_info():
	_max_tree_limit_cache = get_max_tree_capacity()
	# Trigger the setter for total_tree_count to apply clamping
	total_tree_count = total_tree_count
	# Notify the editor to refresh the displayed values
	notify_property_list_changed()

func get_max_tree_capacity() -> int:
	var area_width = 4000.0
	var area_depth = 4000.0
	if terrain:
		# If it's a Tool script, it might have the property set even if not in tree
		if "terrain_size" in terrain:
			area_width = terrain.terrain_size.x
			area_depth = terrain.terrain_size.y

	var cell_size = 1.8 
 # Matches occ_cell_size used in scattering
	# Use 3x3 grid logic for packing estimation
	# A 3x3 block is (cell_size * 3) by (cell_size * 3)
	# But actually every tree occupies one cell and blocks its neighbors.
	# Simplest conservative estimate for this occupancy grid is Area / (cell_size^2 * buffer_factor)
	# We want it to be 10% lower than the actual maximum density of the grid.
	# Max theoretical density is cells / (3*3) if perfectly packed, but we allow 90% of a safe distribution.
	
	var cols = area_width / cell_size
	var rows = area_depth / cell_size
	var total_cells = cols * rows
	
	# Since we check a 3x3 area, a tree effectively "owns" 9 cells in a dense packing scenario.
	var theoretical_max = total_cells / 9.0
	
	# Return 10% lower than the theoretical maximum
	return int(theoretical_max * 0.9)

func _generate_forest_threaded(map_size: int = 2048):
	if _is_generating: return
	_is_generating = true
	
	print("ForestGenerator: Threaded generation started...")
	
	var terrain_width = terrain.terrain_size.x
	var terrain_depth = terrain.terrain_size.y
	var half_width = terrain_width / 2.0
	var half_depth = terrain_depth / 2.0
	
	var cols = ceil(terrain_width / chunk_size)
	var rows = ceil(terrain_depth / chunk_size)
		
	var fuel_img = Image.create(map_size, map_size, false, Image.FORMAT_L8)
	fuel_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	
	var dirt_noise = FastNoiseLite.new()
	dirt_noise.seed = randi()
	dirt_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	dirt_noise.frequency = 0.05
	
	print("ForestGenerator: Generating Fuel Map...")
	for py in range(map_size):
		var world_z = (py / float(map_size) - 0.5) * terrain_depth
		for px in range(map_size):
			var world_x = (px / float(map_size) - 0.5) * terrain_width
			var normal = terrain.get_normal_at(world_x, world_z)
			if normal.dot(Vector3.UP) > 0.78:
				# Leave 15% to 20% dirt gaps for fire breaks
				if dirt_noise.get_noise_2d(world_x, world_z) > -0.3:
					fuel_img.set_pixel(px, py, Color(0.4, 0.4, 0.4, 1.0))
	
	# 1. Prepare data structures
	var tree_data = [] # [tree_type][chunk_idx] = Array[Transform3D]
	for i in range(tree_scenes.size()):
		var type_chunks = []
		type_chunks.resize(cols * rows)
		for j in range(type_chunks.size()):
			type_chunks[j] = []
		tree_data.append(type_chunks)
	
	# Clear previous spatial index
	spatial_index.clear()

	# 2. Extract meshes and materials
	var tree_meshes = []
	var tree_material_arrays = [] # [tree_type] = Array[Material]
	for scene in tree_scenes:
		if not scene: 
			tree_meshes.append(null)
			tree_material_arrays.append([])
			continue
		var node = scene.instantiate()
		var mesh_inst = _find_first_mesh_instance(node)
		if mesh_inst:
			var mesh = mesh_inst.mesh
			tree_meshes.append(mesh)
			var surface_mats = []
			for s in range(mesh.get_surface_count()):
				surface_mats.append(mesh_inst.get_active_material(s))
			tree_material_arrays.append(surface_mats)
		else:
			tree_meshes.append(null)
			tree_material_arrays.append([])
		node.queue_free()

	# 3. Scatter trees
	var rng = RandomNumberGenerator.new()
	
	# Occupancy grid for fast proximity checks (approximate minimum trunk distance)
	var occ_cell_size = 1.8 
	var occ_cols = int(terrain_width / occ_cell_size) + 1
	var occ_rows = int(terrain_depth / occ_cell_size) + 1
	var occupancy = PackedByteArray()
	occupancy.resize(occ_cols * occ_rows)
	occupancy.fill(0)
	
	var count_per_type = total_tree_count / float(tree_scenes.size())
	var buffer = 15.0
	
	for type_idx in range(tree_scenes.size()):
		if not tree_meshes[type_idx]: continue
		
		var placed = 0
		var attempts = 0
		var max_attempts = count_per_type * 24
		
		while placed < count_per_type and attempts < max_attempts:
			attempts += 1
			var x = rng.randf_range(-half_width, half_width)
			var z = rng.randf_range(-half_depth, half_depth)
			
			if abs(x) > half_width - buffer or abs(z) > half_depth - buffer: continue
			
			var normal = terrain.get_normal_at(x, z)
			if normal.dot(Vector3.UP) < 0.78: continue
			
			# --- Meadow Mask Check ---
			if meadow_noise.get_noise_2d(x, z) < 0.0: continue
			
			# --- Fast Proximity Check ---
			var occ_x = int((x + half_width) / occ_cell_size)
			var occ_z = int((z + half_depth) / occ_cell_size)
			
			var too_close = false
			for ox in range(occ_x - 1, occ_x + 2):
				for oz in range(occ_z - 1, occ_z + 2):
					if ox >= 0 and ox < occ_cols and oz >= 0 and oz < occ_rows:
						if occupancy[oz * occ_cols + ox] == 1:
							too_close = true
							break
				if too_close: break
			
			if too_close: continue
			
			var y = terrain.get_height_at(x, z)
			
			var local_x = x + half_width
			var local_z = z + half_depth
			var c = clamp(int(local_x / chunk_size), 0, cols - 1)
			var r = clamp(int(local_z / chunk_size), 0, rows - 1)
			var chunk_idx = r * cols + c
			
			var t = Transform3D()
			t = t.rotated(Vector3.UP, rng.randf_range(0, TAU))
			var up_vector = normal.lerp(Vector3.UP, 0.6).normalized()
			var forward = Vector3.FORWARD
			if abs(forward.dot(up_vector)) > 0.99: forward = Vector3.RIGHT
			var right = up_vector.cross(forward).normalized()
			forward = right.cross(up_vector).normalized()
			t.basis = Basis(right, up_vector, forward) * t.basis
			var tree_scale = rng.randf_range(5.0, 9.0)
			t.basis = t.basis.scaled(Vector3(tree_scale, tree_scale, tree_scale))
			t.origin = Vector3(x, y - 0.4, z)
			
			tree_data[type_idx][chunk_idx].append(t)
			
			# Mark as occupied
			occupancy[occ_z * occ_cols + occ_x] = 1
			
			# Store in Spatial Index for Fire using packed arrays for cache-locality
			var grid_key = Vector2i(c, r)
			if not spatial_index.has(grid_key):
				spatial_index[grid_key] = {
					"positions": PackedVector3Array(),
					"types": PackedInt32Array(),
					"states": PackedByteArray()
				}
			
			spatial_index[grid_key]["positions"].append(t.origin)
			spatial_index[grid_key]["types"].append(type_idx)
			spatial_index[grid_key]["states"].append(0)
			
			var fuel_px = clamp(int((local_x / terrain_width) * map_size), 0, map_size - 1)
			var fuel_py = clamp(int((local_z / terrain_depth) * map_size), 0, map_size - 1)
			fuel_img.set_pixel(fuel_px, fuel_py, Color(1.0, 1.0, 1.0, 1.0))
			
			placed += 1

	# 4. Finalize on Main Thread
	# We must instantiate nodes on the main thread
	call_deferred("_finalize_generation", tree_meshes, tree_material_arrays, tree_data, cols, rows, fuel_img)

func _finalize_generation(meshes, material_arrays, data, cols, rows, fuel_img):
	var wind_shader = load("res://resources/tree_wind.gdshader")
	_chunks.clear()
	
	var fire_mgr = get_parent().get_node_or_null("FireManager")
	var burn_map = null
	if fire_mgr:
		if not fire_mgr.vp_a:
			await fire_mgr.ready
		burn_map = fire_mgr.get_burn_map()
		if fuel_img:
			var fuel_tex = ImageTexture.create_from_image(fuel_img)
			fire_mgr.sim_mat_a.set_shader_parameter("fuel_map", fuel_tex)
			fire_mgr.sim_mat_b.set_shader_parameter("fuel_map", fuel_tex)
	
	for type_idx in range(tree_scenes.size()):
		var original_mesh = meshes[type_idx]
		var orig_mats = material_arrays[type_idx]
		if not original_mesh: continue
		
		# MultiMeshInstance3D does not support surface overrides.
		# We must duplicate the mesh and set materials on the surfaces of the duplicate.
		var mesh = original_mesh.duplicate()
		
		for s in range(orig_mats.size()):
			var orig_mat = orig_mats[s]
			var wind_mat = ShaderMaterial.new()
			wind_mat.shader = wind_shader
			
			var tex = null
			var color = Color.WHITE
			var alpha_scissor = 0.5
			
			if orig_mat:
				if "albedo_texture" in orig_mat:
					tex = orig_mat.albedo_texture
				if "albedo_color" in orig_mat:
					color = orig_mat.albedo_color
				if "alpha_scissor_threshold" in orig_mat:
					alpha_scissor = orig_mat.alpha_scissor_threshold
					
				if orig_mat is ShaderMaterial:
					tex = orig_mat.get_shader_parameter("albedo_texture")
					if not tex: tex = orig_mat.get_shader_parameter("main_texture")
					var s_color = orig_mat.get_shader_parameter("albedo_color")
					if s_color: color = s_color
			
			wind_mat.set_shader_parameter("albedo_texture", tex)
			wind_mat.set_shader_parameter("albedo_color", color)
			wind_mat.set_shader_parameter("alpha_scissor_threshold", alpha_scissor)
			
			if burn_map:
				wind_mat.set_shader_parameter("burn_map", burn_map)
			
			_wind_materials.append(wind_mat)
			
			# Set the material on the mesh surface
			mesh.surface_set_material(s, wind_mat)
		
		for chunk_idx in range(cols * rows):
			var transforms = data[type_idx][chunk_idx]
			if transforms.is_empty(): continue
			
			var multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.instance_count = transforms.size()
			multimesh.mesh = mesh
			
			for i in range(transforms.size()):
				multimesh.set_instance_transform(i, transforms[i])
			
			var mmi = MultiMeshInstance3D.new()
			mmi.multimesh = multimesh
			
			mmi.visibility_range_end = visibility_distance
			mmi.visibility_range_end_margin = 300.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			
			add_child(mmi)
			_chunks.append(mmi)
			
			# --- Billboard LOD ---
			# Create a simple billboard for distant trees to save massive polygon throughput
			var billboard_mmi = MultiMeshInstance3D.new()
			var bb_multimesh = MultiMesh.new()
			bb_multimesh.transform_format = MultiMesh.TRANSFORM_3D
			bb_multimesh.instance_count = transforms.size()
			
			# Create a simple quad for the billboard
			var quad = QuadMesh.new()
			quad.size = Vector2(1, 1) # Will be scaled by transforms
			
			var bb_mat = StandardMaterial3D.new()
			bb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			bb_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			bb_mat.billboard_keep_scale = true
			bb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			
			# Try to pick a representative color from the original materials
			var color = Color(0.2, 0.4, 0.1) # Default forest green
			if material_arrays[type_idx].size() > 0:
				var m = material_arrays[type_idx][0]
				if m is StandardMaterial3D: color = m.albedo_color
			bb_mat.albedo_color = color.lerp(Color.BLACK, 0.2) # Darken slightly for distance
			bb_mat.roughness = 0.8
			bb_mat.metallic_specular = 0.1
			quad.material = bb_mat
			
			bb_multimesh.mesh = quad
			for i in range(transforms.size()):
				bb_multimesh.set_instance_transform(i, transforms[i])
				
			billboard_mmi.multimesh = bb_multimesh
			billboard_mmi.visibility_range_begin = visibility_distance
			billboard_mmi.visibility_range_begin_margin = 300.0
			billboard_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			billboard_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # No shadows for billboards
			
			add_child(billboard_mmi)
			
			# Time-slicing initialization to prevent massive frame hitches
			if chunk_idx % 4 == 0:
				await get_tree().process_frame
			
	_is_generating = false
	print("ForestGenerator: All chunks finalized with Billboard LODs.")
	forest_ready.emit()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	# Update Wind Shader Parameters
	var weather_mgr = get_parent().get_node_or_null("WeatherManager")
	if weather_mgr and "current_wind" in weather_mgr:
		var wind = weather_mgr.current_wind
		# Map weather manager wind (0.4 - 9.4) to shader wind (approx 0.5 - 5.0 speed, 0.05 - 1.0 strength)
		var target_speed = wind * 0.5
		var target_strength = wind * 0.1
		
		for mat in _wind_materials:
			mat.set_shader_parameter("wind_speed", target_speed)
			mat.set_shader_parameter("wind_strength", target_strength)

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found = _find_first_mesh_instance(child)
		if found: return found
	return null

# Helper function for future fire logic
func get_trees_in_chunk(world_pos: Vector3) -> Dictionary:
	var half_width = terrain.terrain_size.x / 2.0
	var half_depth = terrain.terrain_size.y / 2.0
	var c = int((world_pos.x + half_width) / chunk_size)
	var r = int((world_pos.z + half_depth) / chunk_size)
	return spatial_index.get(Vector2i(c, r), {
		"positions": PackedVector3Array(),
		"types": PackedInt32Array(),
		"states": PackedByteArray()
	})

func get_all_tree_positions() -> Array[Vector3]:
	var all_positions: Array[Vector3] = []
	for chunk_data in spatial_index.values():
		var pos_array = chunk_data.get("positions")
		if pos_array is PackedVector3Array:
			for p in pos_array:
				all_positions.append(p)
	return all_positions


func _scatter_trees_logic(multimesh: MultiMesh):
	var valid_count = 0
	var attempts = 0
	var max_attempts = multimesh.instance_count * 24
	
	# Determine extent from terrain size
	var extent_x = terrain.terrain_size.x / 2.0
	var extent_z = terrain.terrain_size.y / 2.0
	var buffer = 10.0
	
	var rng = RandomNumberGenerator.new()
	
	while valid_count < multimesh.instance_count and attempts < max_attempts:
		attempts += 1
		
		var x = rng.randf_range(-extent_x, extent_x)
		var z = rng.randf_range(-extent_z, extent_z)
		
		# Don't spawn too close to the absolute edge
		if abs(x) > extent_x - buffer or abs(z) > extent_z - buffer: continue
		
		var normal = terrain.get_normal_at(x, z)
		var slope = normal.dot(Vector3.UP)
		
		# Trees usually don't grow on steep cliffs (slope < 0.85 means it's a rocky area)
		if slope < 0.85:
			continue
			
		# --- Meadow Mask Check ---
		if meadow_noise.get_noise_2d(x, z) < 0.0:
			continue
			
		var y = terrain.get_height_at(x, z)
		
		var t = Transform3D()
		# Random rotation around Y axis
		t = t.rotated(Vector3.UP, rng.randf_range(0, TAU))
		# Align slightly to the terrain normal, but mostly pointing up
		var up_vector = normal.lerp(Vector3.UP, 0.5).normalized()
		# Create a basis looking at an arbitrary direction
		var forward = Vector3.FORWARD
		if abs(forward.dot(up_vector)) > 0.99:
			forward = Vector3.RIGHT
		var right = up_vector.cross(forward).normalized()
		forward = right.cross(up_vector).normalized()
		
		t.basis = Basis(right, up_vector, forward) * t.basis
		
		# Apply random scale (increased to match the massive 1000x1000 terrain)
		var tree_scale = rng.randf_range(4.0, 8.0)
		t.basis = t.basis.scaled(Vector3(tree_scale, tree_scale, tree_scale))
		
		# Place trees slightly into the terrain for a more grounded look
		t.origin = Vector3(x, y - 0.5, z)
		
		multimesh.set_instance_transform(valid_count, t)
		valid_count += 1
		
	if valid_count < multimesh.instance_count:
		multimesh.visible_instance_count = valid_count
