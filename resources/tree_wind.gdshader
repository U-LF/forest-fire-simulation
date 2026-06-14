shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.2;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wind_scale : hint_range(0.0, 1.0) = 0.1;

uniform sampler2D burn_map : filter_linear;
uniform float terrain_size = 4000.0;
varying vec3 v_world_pos;

void vertex() {
    // World-space wind logic
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_pos = world_pos;
    
    // Height-based influence: Only move the top of the tree
    float height_factor = smoothstep(0.0, 12.0, VERTEX.y);
    
    float time = TIME * wind_speed;
    float offset = sin(time + world_pos.x * wind_scale + world_pos.z * wind_scale) * cos(time * 0.5 + world_pos.x * 0.2) * wind_strength;
    
    VERTEX.x += offset * height_factor;
    VERTEX.z += offset * height_factor * 0.5;
    
    // --- Structural Fire Damage (Deformation) ---
    // Read char level from global burn map for vertex manipulation
    vec2 uv_burn = (world_pos.xz / terrain_size) + 0.5;
    vec4 burn_state = textureLod(burn_map, uv_burn, 0.0);
    float char_lvl = burn_state.g;
    
    // Only deform when heavily charred
    float damage = smoothstep(0.5, 1.0, char_lvl);
    
    if (damage > 0.0) {
        // Generate a stable random angle based on the tree's world position
        float rand_angle = fract(sin(world_pos.x * 12.9898 + world_pos.z * 78.233) * 43758.5453) * 6.2831853;
        vec2 bend_dir = vec2(cos(rand_angle), sin(rand_angle));
        
        // Bend the tree over by offsetting X and Z based on height
        // Using a curve (pow) makes the bend look more like a leaning trunk rather than a sheer
        float bend_curve = pow(height_factor, 1.5);
        float bend_amount = damage * bend_curve * 4.5; // Increased bend horizontally up to 4.5 units at the top
        
        VERTEX.x += bend_dir.x * bend_amount;
        VERTEX.z += bend_dir.y * bend_amount;
        
        // Add a very slight sag to the outer branches without shrinking the overall volume
        float dist_from_trunk = length(VERTEX.xz);
        float droop = damage * height_factor * 0.8; 
        VERTEX.y -= droop * smoothstep(1.0, 4.0, dist_from_trunk);
    }
}

void fragment() {
    vec4 albedo_tex = texture(albedo_texture, UV);
    vec4 final_color = albedo_tex * albedo_color * COLOR;
    
    // Read char level and explicit heat from global burn map
    vec2 uv_burn = (v_world_pos.xz / terrain_size) + 0.5;
    vec4 burn_state = texture(burn_map, uv_burn);
    float char_lvl = burn_state.g;
    float heat = burn_state.a;
    
    // Base charring (deep charcoal) - Trees remain pure black when fully burned
    vec3 charcoal = vec3(0.04, 0.03, 0.03);
    final_color.rgb = mix(final_color.rgb, charcoal, char_lvl);
    
    // Ember effect: Only appear after heavily charred, and controlled by actual Heat
    float ember_phase = smoothstep(0.6, 0.9, char_lvl) * heat;
    
    // Smooth, stable 3D spatial noise for organic "cracks" of heat
    // Lower frequency (2.0) creates larger, more natural glowing patches instead of static
    float ember_noise = (sin(v_world_pos.x * 2.0 + v_world_pos.y) * cos(v_world_pos.y * 2.0 + v_world_pos.z * 2.0)) * 0.5 + 0.5;
    
    // Slow, heavy pulse (breathing heat)
    float ember_pulse = 0.6 + 0.4 * sin(TIME * 1.5 + ember_noise * 4.0); 
    
    // Tighter mask so only the "deepest" cracks glow, making it subtle
    float ember_mask = smoothstep(0.75, 0.95, ember_noise) * ember_phase;
    
    // Deep smoldering colors
    vec3 hot_color = vec3(0.9, 0.25, 0.05); // Rich orange-red, not yellow
    vec3 cool_color = vec3(0.5, 0.05, 0.0); // Very dark cherry red
    vec3 ember_color = mix(cool_color, hot_color, heat) * ember_mask * ember_pulse * 1.8; // Lower overall multiplier

    ALBEDO = final_color.rgb;
    EMISSION = ember_color;
    ALPHA = final_color.a;
    
    // Alpha Scissoring for clean leaf edges
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
    
    ROUGHNESS = 0.8;
    SPECULAR = 0.2;
}