extends Node3D

@export var day_night_cycle: Node
@export var rain_particles: GPUParticles3D
@export var lightning_light: DirectionalLight3D

@export var check_interval: float = 30.0 # How often to check for weather change
@export var rain_chance: float = 0.5 # 50% chance

var is_raining: bool = false
var rain_intensity: float = 0.0

var _time_since_last_check: float = 0.0
var _lightning_timer: float = 0.0

func _ready() -> void:
	if rain_particles:
		rain_particles.emitting = false
	if lightning_light:
		lightning_light.light_energy = 0.0
	
	# Start with a random weather state
	_check_weather()

func _process(delta: float) -> void:
	_time_since_last_check += delta
	if _time_since_last_check >= check_interval:
		_time_since_last_check = 0.0
		_check_weather()
	
	# Smoothly transition rain intensity
	var target_intensity = 1.0 if is_raining else 0.0
	rain_intensity = move_toward(rain_intensity, target_intensity, delta * 0.1) # 10 seconds to fully transition
	
	if day_night_cycle:
		day_night_cycle.rain_intensity = rain_intensity
	
	if rain_particles:
		if rain_intensity > 0.1 and not rain_particles.emitting:
			rain_particles.emitting = true
		elif rain_intensity <= 0.1 and rain_particles.emitting:
			rain_particles.emitting = false
			
		rain_particles.amount_ratio = rain_intensity
	
	_handle_lightning(delta)

func _check_weather() -> void:
	if randf() < rain_chance:
		is_raining = true
	else:
		is_raining = false

func _handle_lightning(delta: float) -> void:
	if not is_raining or rain_intensity < 0.5:
		return
		
	_lightning_timer -= delta
	
	# Handle existing lightning flash fade out
	if lightning_light and lightning_light.light_energy > 0.0:
		lightning_light.light_energy = lerp(lightning_light.light_energy, 0.0, delta * 15.0)
	
	if _lightning_timer <= 0.0:
		# Trigger lightning
		_lightning_timer = randf_range(2.0, 10.0) # Random time between strikes
		
		# Flash the sky
		if lightning_light:
			lightning_light.rotation.x = -PI/2.0 + randf_range(-0.5, 0.5)
			lightning_light.rotation.y = randf_range(0, 2.0 * PI)
			lightning_light.light_energy = randf_range(5.0, 15.0)
		
		# Spawn lightning strike on terrain (visual only)
		_spawn_lightning_strike()

func _spawn_lightning_strike() -> void:
	# Simple visual strike logic
	var strike_pos = Vector3(randf_range(-40, 40), 0, randf_range(-40, 40))
	
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.2
	cyl.height = 100.0
	mesh_inst.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.9, 1.0)
	mat.emission_energy_multiplier = 10.0
	mesh_inst.material_override = mat
	
	mesh_inst.position = strike_pos + Vector3(0, 50, 0)
	
	add_child(mesh_inst)
	
	# Flash light at strike point
	var omni = OmniLight3D.new()
	omni.light_color = Color(0.8, 0.9, 1.0)
	omni.light_energy = 20.0
	omni.omni_range = 50.0
	omni.position = strike_pos + Vector3(0, 2, 0)
	add_child(omni)
	
	# Clean up after a split second
	var tween = create_tween()
	tween.tween_interval(0.1)
	tween.tween_callback(mesh_inst.queue_free)
	tween.tween_callback(omni.queue_free)
