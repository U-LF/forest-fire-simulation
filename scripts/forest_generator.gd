extends Node3D

@export var terrain: StaticBody3D # Must point to the Terrain node with terrain_generator.gd
@export var tree_scenes: Array[PackedScene]
@export var count_per_tree_type: int = 10000

func _ready():
	if not terrain:
		push_error("ForestGenerator: No terrain assigned!")
		return
		
	# Wait until the terrain has finished generating its heightmap
	# If Terrain (a sibling) already finished its _ready, macro_image will be set.
	if not terrain.macro_image:
		print("ForestGenerator: Waiting for terrain_ready signal...")
		await terrain.terrain_ready
		
	if not terrain.macro_image:
		push_error("ForestGenerator: Terrain macro_image is still null after initialization!")
		return
		
	_generate_forest()

func _generate_forest():
	print("Generating forest...")
	for scene in tree_scenes:
		if not scene: continue
		
		# Instantiate temporarily to extract the mesh
		var node = scene.instantiate()
		var mesh = _find_first_mesh(node)
		node.queue_free()
		
		if not mesh:
			continue
			
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.instance_count = count_per_tree_type
		multimesh.mesh = mesh
		
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = multimesh
		add_child(mmi)
		
		_scatter_trees(multimesh)
		
	print("Forest generation complete.")

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
