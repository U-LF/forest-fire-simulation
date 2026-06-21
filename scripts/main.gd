extends Node3D

@onready var forest = $Forest
@onready var weather_mgr = $WeatherManager
@onready var day_night = $DayNightCycle
@onready var fire_mgr = $FireManager
@onready var ui = $WeatherUI
@onready var camera = $FreeFlyCamera

var loading_layer: CanvasLayer
var _loading_subtitle: Label
var _loading_time: float = 0.0

func _ready():
	# Disable processing for environment, physics, and UI while loading
	weather_mgr.process_mode = Node.PROCESS_MODE_DISABLED
	day_night.process_mode = Node.PROCESS_MODE_DISABLED
	fire_mgr.process_mode = Node.PROCESS_MODE_DISABLED
	ui.process_mode = Node.PROCESS_MODE_DISABLED
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Create Loading Screen UI dynamically
	loading_layer = CanvasLayer.new()
	loading_layer.layer = 128
	
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Sleek dark charcoal background instead of pure black
	bg.color = Color(0.07, 0.08, 0.09, 1.0)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	
	var title = Label.new()
	title.text = "INITIALIZING ENVIRONMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 2)
	
	_loading_subtitle = Label.new()
	_loading_subtitle.text = "Generating procedural forest and topography..."
	_loading_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_subtitle.add_theme_font_size_override("font_size", 18)
	_loading_subtitle.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	
	vbox.add_child(title)
	vbox.add_child(_loading_subtitle)
	
	loading_layer.add_child(bg)
	loading_layer.add_child(vbox)
	add_child(loading_layer)
	
	# Modern pulsing animation on the title
	var pulse_tween = create_tween().set_loops()
	pulse_tween.tween_property(title, "modulate:a", 0.3, 1.0).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(title, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	
	# Connect to the forest generator's ready signal
	forest.forest_ready.connect(_on_forest_ready)

func _process(delta: float):
	if _loading_subtitle and is_instance_valid(_loading_subtitle):
		_loading_time += delta
		var dots = ""
		var num_dots = int(_loading_time * 3.0) % 4
		for i in range(num_dots):
			dots += "."
		_loading_subtitle.text = "Generating procedural forest and topography" + dots

func _input(event: InputEvent) -> void:
	# Handle mouse capture toggling while the camera is paused
	if loading_layer and is_instance_valid(loading_layer):
		if event.is_action_pressed("ui_cancel"):
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_forest_ready():
	# The system is ready. Re-enable all environment scripts and camera
	weather_mgr.process_mode = Node.PROCESS_MODE_INHERIT
	day_night.process_mode = Node.PROCESS_MODE_INHERIT
	fire_mgr.process_mode = Node.PROCESS_MODE_INHERIT
	ui.process_mode = Node.PROCESS_MODE_INHERIT
	camera.process_mode = Node.PROCESS_MODE_INHERIT
	
	# Smoothly fade out the loading screen
	var tween = create_tween()
	var bg = loading_layer.get_child(0)
	var vbox = loading_layer.get_child(1)
	tween.tween_property(bg, "modulate:a", 0.0, 1.0)
	tween.parallel().tween_property(vbox, "modulate:a", 0.0, 1.0)
	
	# Stop the process function from trying to animate the freed subtitle
	_loading_subtitle = null
	tween.tween_callback(loading_layer.queue_free)
