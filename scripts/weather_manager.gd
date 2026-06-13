extends Node3D

@export var day_night_cycle: Node
@export var rain_particles: GPUParticles3D
@export var lightning_light: DirectionalLight3D
@export var terrain: Node3D

@export var check_interval: float = 20.0 # Evaluate weather shifts more frequently
var _time_since_last_check: float = 0.0
var _lightning_timer: float = 0.0

var cloud_coverage: float = 0.0
var rain_intensity: float = 0.0

var target_cloud_coverage: float = 0.0
var target_rain_intensity: float = 0.0
var rain_shift_speed: float = 0.05

func _ready() -> void:
	if rain_particles:
		rain_particles.emitting = false
		if terrain:
			var size = terrain.terrain_size
			var process_mat = rain_particles.process_material as ParticleProcessMaterial
			if process_mat:
				# Use duplicate to avoid affecting other materials if shared
				rain_particles.process_material = process_mat.duplicate()
				(rain_particles.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(size.x / 2.0, 2.0, size.y / 2.0)
			
			rain_particles.visibility_aabb = AABB(
				Vector3(-size.x / 2.0, -180.0, -size.y / 2.0),
				Vector3(size.x, 200.0, size.y)
			)

	if lightning_light:
		lightning_light.light_energy = 0.0
	
	_check_weather()
	# Apply initial state immediately so we don't start at 0 if the roll is rain
	cloud_coverage = target_cloud_coverage
	rain_intensity = min(target_rain_intensity, smoothstep(0.3, 0.8, cloud_coverage))

func _process(delta: float) -> void:
	_time_since_last_check += delta
	if _time_since_last_check >= check_interval:
		_time_since_last_check = 0.0
		_check_weather()
	
	# Clouds form or dissipate smoothly and continuously
	cloud_coverage = move_toward(cloud_coverage, target_cloud_coverage, delta * 0.03)
	
	# Rain MUST wait for clouds. We clamp the target rain by the current cloud coverage.
	# e.g., 100% rain requires 80%+ clouds. If clouds are at 50%, rain is capped low.
	var max_allowed_rain = smoothstep(0.3, 0.8, cloud_coverage)
	var current_target_rain = min(target_rain_intensity, max_allowed_rain)
	
	# Move actual rain intensity toward the allowed target
	rain_intensity = move_toward(rain_intensity, current_target_rain, delta * rain_shift_speed)
	
	# Update External Systems
	if day_night_cycle:
		day_night_cycle.cloud_coverage = cloud_coverage
		day_night_cycle.rain_intensity = rain_intensity
	
	if rain_particles:
		if rain_intensity > 0.01 and not rain_particles.emitting:
			rain_particles.emitting = true
		elif rain_intensity <= 0.01 and rain_particles.emitting:
			rain_particles.emitting = false
			
		rain_particles.amount_ratio = max(0.01, rain_intensity)
	
	_handle_lightning(delta)

func _check_weather() -> void:
	# Procedural Weather Roll
	var rand_weather = randf()
	
	if rand_weather < 0.50:
		# 50% chance: Clear / Partly Cloudy
		target_cloud_coverage = randf_range(0.0, 0.3)
		target_rain_intensity = 0.0
		rain_shift_speed = randf_range(0.05, 0.1) # Stop rain gradually
		
	elif rand_weather < 0.80:
		# 30% chance: Overcast / Gloomy (maybe light drizzle)
		target_cloud_coverage = randf_range(0.5, 0.8)
		if randf() > 0.5:
			target_rain_intensity = randf_range(0.05, 0.2) # Very light drizzle
		else:
			target_rain_intensity = 0.0
		rain_shift_speed = randf_range(0.02, 0.05) # Very slow, ambient transition
		
	else:
		# 20% chance: Proper Rain / Storm
		target_cloud_coverage = randf_range(0.8, 1.0)
		
		# Roll for storm severity
		if randf() > 0.7:
			# Sudden heavy downpour
			target_rain_intensity = randf_range(0.7, 1.0)
			rain_shift_speed = randf_range(0.1, 0.2) # Speeds up fast once clouds are ready
		else:
			# Normal steady rain
			target_rain_intensity = randf_range(0.3, 0.6)
			rain_shift_speed = randf_range(0.02, 0.06) # Gradual build-up

func _handle_lightning(delta: float) -> void:
	# Lightning only occurs during heavy rain and thick clouds
	if target_cloud_coverage < 0.8 or rain_intensity < 0.5:
		# Make sure lightning flash fades out if storm ends
		if lightning_light and lightning_light.light_energy > 0.0:
			lightning_light.light_energy = lerp(lightning_light.light_energy, 0.0, delta * 15.0)
		return
		
	_lightning_timer -= delta
	
	# Fade out existing flash
	if lightning_light and lightning_light.light_energy > 0.0:
		lightning_light.light_energy = lerp(lightning_light.light_energy, 0.0, delta * 15.0)
	
	if _lightning_timer <= 0.0:
		# Trigger lightning - more frequent in heavier rain
		var frequency_modifier = 1.0 - rain_intensity
		_lightning_timer = randf_range(2.0, 6.0 + (frequency_modifier * 10.0)) 
		
		if lightning_light:
			lightning_light.rotation.x = -PI/2.0 + randf_range(-0.5, 0.5)
			lightning_light.rotation.y = randf_range(0, 2.0 * PI)
			lightning_light.light_energy = randf_range(5.0, 15.0)
		
		_spawn_lightning_strike()

func _spawn_lightning_strike() -> void:
	var range_x = 40.0
	var range_z = 40.0
	
	if terrain:
		range_x = terrain.terrain_size.x / 2.0
		range_z = terrain.terrain_size.y / 2.0
		
	var strike_pos = Vector3(randf_range(-range_x, range_x), 0, randf_range(-range_z, range_z))
	
	if terrain:
		strike_pos.y = terrain.get_height_at(strike_pos.x, strike_pos.z)
		
	var start_pos = strike_pos + Vector3(0, 100, 0) # Start high in the clouds
	
	# Generate jagged points
	var points = PackedVector3Array()
	points.append(start_pos)
	
	var current_pos = start_pos
	var segments = randi_range(8, 15)
	var segment_length = 100.0 / segments
	
	for i in range(segments):
		if i == segments - 1:
			points.append(strike_pos) # Guarantee it hits the ground target
		else:
			# Jitter the next point
			var jitter_x = randf_range(-10.0, 10.0)
			var jitter_z = randf_range(-10.0, 10.0)
			current_pos -= Vector3(jitter_x, segment_length, jitter_z)
			points.append(current_pos)
	
	# Create an ImmediateMesh for the lightning line
	var mesh_inst = MeshInstance3D.new()
	var imm_mesh = ImmediateMesh.new()
	mesh_inst.mesh = imm_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.9, 1.0)
	mat.emission_energy_multiplier = 15.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	
	# Draw the line
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		imm_mesh.surface_add_vertex(p)
	imm_mesh.surface_end()
	
	add_child(mesh_inst)
	
	var omni = OmniLight3D.new()
	omni.light_color = Color(0.8, 0.9, 1.0)
	omni.light_energy = 20.0
	omni.omni_range = 50.0
	omni.position = strike_pos + Vector3(0, 2, 0)
	add_child(omni)
	
	# Fade out animation
	var tween = create_tween()
	tween.tween_interval(0.05)
	# Fade alpha for a more realistic disappearance
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.parallel().tween_property(omni, "light_energy", 0.0, 0.2)
	tween.tween_callback(mesh_inst.queue_free)
	tween.tween_callback(omni.queue_free)
