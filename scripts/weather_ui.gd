extends CanvasLayer

@export var weather_manager: Node3D
@export var day_night_cycle: Node

@onready var temp_big: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/LeftCol/TempBig
@onready var condition_big: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/LeftCol/ConditionBig
@onready var rh_label: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/RightCol/RHLabel
@onready var wind_label: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/RightCol/WindLabel
@onready var rain_label: Label = $Margin/Panel/Padding/MainVBox/CurrentHBox/RightCol/RainLabel
@onready var forecast_list: VBoxContainer = $Margin/Panel/Padding/MainVBox/ForecastList

var forecast_rows: Array[HBoxContainer] = []

func _ready() -> void:
	if not weather_manager:
		weather_manager = get_node_or_null("../WeatherManager")
		if not weather_manager:
			weather_manager = get_node_or_null("/root/Main/WeatherManager")
	if not day_night_cycle:
		day_night_cycle = get_node_or_null("../DayNightCycle")
		if not day_night_cycle:
			day_night_cycle = get_node_or_null("/root/Main/DayNightCycle")
			
	# Initialize 7 forecast rows dynamically so they align perfectly
	for i in range(7):
		var row = HBoxContainer.new()
		
		var day_lbl = Label.new()
		day_lbl.custom_minimum_size = Vector2(60, 0)
		day_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		day_lbl.add_theme_font_size_override("font_size", 14)
		
		var cond_lbl = Label.new()
		cond_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cond_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		cond_lbl.add_theme_font_size_override("font_size", 14)
		
		var details_lbl = Label.new()
		details_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		details_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		details_lbl.add_theme_font_size_override("font_size", 14)
		
		row.add_child(day_lbl)
		row.add_child(cond_lbl)
		row.add_child(details_lbl)
		forecast_list.add_child(row)
		forecast_rows.append(row)

func _process(_delta: float) -> void:
	if not weather_manager or not day_night_cycle:
		return
		
	# Update Current Weather
	var temp = weather_manager.current_temp
	var rh = weather_manager.current_rh
	var wind = weather_manager.current_wind
	var rain = weather_manager.current_rain
	
	var current_condition = "Clear"
	var cond_color = Color(0.6, 0.9, 0.6) # Sunny/Clear color
	if rain > 3.0: 
		current_condition = "Heavy Rain"
		cond_color = Color(0.4, 0.5, 0.8)
	elif rain > 0.0: 
		current_condition = "Rain"
		cond_color = Color(0.5, 0.7, 0.9)
	elif rh > 70.0: 
		current_condition = "Cloudy"
		cond_color = Color(0.7, 0.7, 0.75)
	elif rh > 45.0: 
		current_condition = "Partly Cloudy"
		cond_color = Color(0.8, 0.8, 0.7)
		
	temp_big.text = "%.1f°" % temp
	condition_big.text = current_condition
	condition_big.add_theme_color_override("font_color", cond_color)
	
	rh_label.text = "💧 %d %%" % int(rh)
	wind_label.text = "💨 %.1f km/h" % wind
	if rain > 0:
		rain_label.text = "☔ %.1f mm" % rain
		rain_label.show()
	else:
		rain_label.hide()
	
	# Update Forecast
	var day_offset = day_night_cycle.day_duration * weather_manager.time_scale
	var current_day_idx = floor(weather_manager._time_elapsed / day_offset)
	
	for i in range(7):
		var target_day = current_day_idx + i
		var time_eval = (target_day + 0.5) * day_offset
		
		var raw_temp = weather_manager.noise_temp.get_noise_1d(time_eval)
		var raw_rh = weather_manager.noise_rh.get_noise_1d(time_eval)
		var raw_wind = weather_manager.noise_wind.get_noise_1d(time_eval)
		
		var f_temp = remap(raw_temp, -1.0, 1.0, weather_manager.temp_min, weather_manager.temp_max)
		var f_rh = remap(raw_rh, -1.0, 1.0, weather_manager.rh_min, weather_manager.rh_max)
		
		var condition = "Clear"
		var f_cond_color = Color(0.6, 0.9, 0.6)
		if f_rh >= weather_manager.rh_rain_threshold:
			var raw_rain = weather_manager.noise_rain.get_noise_1d(time_eval)
			var f_rain = remap(raw_rain, -1.0, 1.0, weather_manager.rain_min, weather_manager.rain_max)
			if f_rain > 3.0: 
				condition = "Heavy Rain"
				f_cond_color = Color(0.4, 0.5, 0.8)
			else: 
				condition = "Rain"
				f_cond_color = Color(0.5, 0.7, 0.9)
		elif f_rh > 70.0:
			condition = "Cloudy"
			f_cond_color = Color(0.7, 0.7, 0.75)
		elif f_rh > 45.0:
			condition = "Partly Cloudy"
			f_cond_color = Color(0.8, 0.8, 0.7)
		
		var row = forecast_rows[i]
		var day_lbl = row.get_child(0) as Label
		var cond_lbl = row.get_child(1) as Label
		var details_lbl = row.get_child(2) as Label
		
		day_lbl.text = "Today" if i == 0 else "Day %d" % target_day
		
		cond_lbl.text = condition
		cond_lbl.add_theme_color_override("font_color", f_cond_color)
		
		details_lbl.text = "%.1f°  %d%%" % [f_temp, int(f_rh)]
