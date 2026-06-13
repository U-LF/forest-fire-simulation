extends Node3D

@export var terrain: StaticBody3D # Must point to the Terrain node with terrain_generator.gd
@export var tree_scenes: Array[PackedScene]
@export var total_tree_count: int = 50000
@export var chunk_size: float = 500.0
@export var visibility_distance: float = 2000.0

func _ready():
	if not terrain:
		push_error("ForestGenerator: No terrain assigned!")
		return
		
	if not terrain.macro_image:
		print("ForestGenerator: Waiting for terrain_ready signal...")
		await terrain.terrain_ready
		
	if not terrain.macro_image:
		push_error("ForestGenerator: Terrain macro_image is still null after initialization!")
		return
		
	_generate_forest_chunked()

func _generate_forest_chunked():
	print("Generating chunked forest...")
	
	var terrain_width = terrain.terrain_size.x
	var terrain_depth = terrain.terrain_size.y
	var half_width = terrain_width / 2.0
	var half_depth = terrain_depth / 2.0
	
	var cols = ceil(terrain_width / chunk_size)
	var rows = ceil(terrain_depth / chunk_size)
	
	# 1. Prepare data structures
	var tree_data = [] # Array of Arrays: [tree_type_index][chunk_index] = Array[Transform3D]
	for i in range(tree_scenes.size()):
		var type_chunks = []
		type_chunks.resize(cols * rows)
		for j in range(type_chunks.size()):
			type_chunks[j] = []
		tree_data.append(type_chunks)
	
	# 2. Extract meshes from scenes
	var tree_meshes = []
	for scene in tree_scenes:
		if not scene: 
			tree_meshes.append(null)
			continue
		var node = scene.instantiate()
		var mesh = _find_first_mesh(node)
		node.queue_free()
		tree_meshes.append(mesh)

	# 3. Scatter trees into data structure
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var count_per_type = total_tree_count / tree_scenes.size()
	var buffer = 10.0
	
	for type_idx in range(tree_scenes.size()):
		if not tree_meshes[type_idx]: continue
		
		var placed = 0
		var attempts = 0
		var max_attempts = count_per_type * 4
		
		while placed < count_per_type and attempts < max_attempts:
			attempts += 1
			var x = rng.randf_range(-half_width, half_width)
			var z = rng.randf_range(-half_depth, half_depth)
			
			if abs(x) > half_width - buffer or abs(z) > half_depth - buffer: continue
			
			var normal = terrain.get_normal_at(x, z)
			if normal.dot(Vector3.UP) < 0.85: continue
			
			var y = terrain.get_height_at(x, z)
			
			# Calculate chunk index
			var local_x = x + half_width
			var local_z = z + half_depth
			var c = int(local_x / chunk_size)
			var r = int(local_z / chunk_size)
			c = clamp(c, 0, cols - 1)
			r = clamp(r, 0, rows - 1)
			var chunk_idx = r * cols + c
			
			# Create transform
			var t = Transform3D()
			t = t.rotated(Vector3.UP, rng.randf_range(0, TAU))
			var up_vector = normal.lerp(Vector3.UP, 0.5).normalized()
			var forward = Vector3.FORWARD
			if abs(forward.dot(up_vector)) > 0.99: forward = Vector3.RIGHT
			var right = up_vector.cross(forward).normalized()
			forward = right.cross(up_vector).normalized()
			t.basis = Basis(right, up_vector, forward) * t.basis
			var scale = rng.randf_range(4.0, 8.0)
			t.basis = t.basis.scaled(Vector3(scale, scale, scale))
			t.origin = Vector3(x, y - 0.5, z)
			
			tree_data[type_idx][chunk_idx].append(t)
			placed += 1

	# 4. Instantiate MultiMeshInstances for each chunk
	for type_idx in range(tree_scenes.size()):
		var mesh = tree_meshes[type_idx]
		if not mesh: continue
		
		for chunk_idx in range(cols * rows):
			var transforms = tree_data[type_idx][chunk_idx]
			if transforms.is_empty(): continue
			
			var multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.instance_count = transforms.size()
			multimesh.mesh = mesh
			
			for i in range(transforms.size()):
				multimesh.set_instance_transform(i, transforms[i])
			
			var mmi = MultiMeshInstance3D.new()
			mmi.multimesh = multimesh
			
			# Optimization: Visibility Range (Culling far chunks)
			mmi.visibility_range_end = visibility_distance
			mmi.visibility_range_end_margin = 200.0 # Soft fade margin
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			
			add_child(mmi)
			
	print("Chunked forest generation complete.")

func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh:
		return node.mesh
	for child in node.get_children():
		var mesh = _find_first_mesh(child)
		if mesh: return mesh
	return null

func _scatter_trees(multimesh: MultiMesh):
	var valid_count = 0
	var attempts = 0
	var max_attempts = multimesh.instance_count * 5
	
	# Determine extent from terrain size
	var extent_x = terrain.terrain_size.x / 2.0
	var extent_z = terrain.terrain_size.y / 2.0
	var buffer = 10.0
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
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
		var scale = rng.randf_range(4.0, 8.0)
		t.basis = t.basis.scaled(Vector3(scale, scale, scale))
		
		# Place trees slightly into the terrain for a more grounded look
		t.origin = Vector3(x, y - 0.5, z)
		
		multimesh.set_instance_transform(valid_count, t)
		valid_count += 1
		
	if valid_count < multimesh.instance_count:
		multimesh.visible_instance_count = valid_count
