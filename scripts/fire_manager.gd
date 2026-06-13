extends Node

@export var map_size: int = 2048
@export var terrain_size: float = 4000.0

var vp_a: SubViewport
var vp_b: SubViewport
var rect_a: ColorRect
var rect_b: ColorRect
var sim_mat_a: ShaderMaterial
var sim_mat_b: ShaderMaterial

var current_vp_is_a: bool = true

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
	
	# Create debug overlay
	var debug_rect = TextureRect.new()
	debug_rect.texture = vp_a.get_texture()
	debug_rect.custom_minimum_size = Vector2(256, 256)
	debug_rect.layout_mode = 1 # Layout mode anchor
	debug_rect.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	debug_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(debug_rect)
	
	# Find camera and connect
	call_deferred("_connect_to_camera")

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
	
	var draw_mat = StandardMaterial3D.new()
	draw_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.9)
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(1.0, 0.4, 0.0)
	draw_mat.emission_energy_multiplier = 8.0
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	
	var quad = QuadMesh.new()
	quad.material = draw_mat
	
	fire_particles = GPUParticles3D.new()
	fire_particles.amount = 50000
	fire_particles.process_material = fire_proc_mat
	fire_particles.draw_pass_1 = quad
	fire_particles.lifetime = 1.5 # Short lifetime so they continuously respawn around the camera
	fire_particles.explosiveness = 0.0
	fire_particles.fixed_fps = 0
	fire_particles.local_coords = false # Critical: Lock particles to world space, preventing sliding
	fire_particles.visibility_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 300, 2000))
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
	ember_draw_mat.albedo_color = Color(1.0, 0.5, 0.1, 1.0)
	ember_draw_mat.emission_enabled = true
	ember_draw_mat.emission = Color(1.0, 0.4, 0.0)
	ember_draw_mat.emission_energy_multiplier = 10.0
	ember_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	
	var ember_quad = QuadMesh.new()
	ember_quad.material = ember_draw_mat
	
	ember_particles = GPUParticles3D.new()
	ember_particles.amount = 20000
	ember_particles.process_material = ember_proc_mat
	ember_particles.draw_pass_1 = ember_quad
	ember_particles.lifetime = 3.0
	ember_particles.explosiveness = 0.0
	ember_particles.fixed_fps = 0
	ember_particles.local_coords = false
	ember_particles.visibility_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 300, 2000))
	ember_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(ember_particles)

func _inject_to_terrain() -> void:
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.terrain_material:
		terrain.terrain_material.set_shader_parameter("burn_map", vp_a.get_texture())

func _connect_to_camera() -> void:
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_signal("fire_started"):
		cam.connect("fire_started", _on_fire_started)

var _ignite_frames: int = 0

func _process(_delta: float) -> void:
	if current_vp_is_a:
		vp_a.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp_b.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		vp_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp_b.render_target_update_mode = SubViewport.UPDATE_ONCE
		
	current_vp_is_a = not current_vp_is_a
	
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
			fire_particles.global_position = world_offset
			fire_proc_mat.set_shader_parameter("world_offset", world_offset)
			
			if ember_particles and ember_proc_mat:
				ember_particles.global_position = world_offset
				ember_proc_mat.set_shader_parameter("world_offset", world_offset)

func _on_fire_started(world_pos: Vector3) -> void:
	var uv_x = (world_pos.x / terrain_size) + 0.5
	var uv_y = (world_pos.z / terrain_size) + 0.5
	var uv = Vector2(uv_x, uv_y)
	
	sim_mat_a.set_shader_parameter("ignite_pos", uv)
	sim_mat_b.set_shader_parameter("ignite_pos", uv)
	_ignite_frames = 2 # Keep the ignition coordinate alive for 2 frames

func get_burn_map() -> ViewportTexture:
	return vp_a.get_texture()