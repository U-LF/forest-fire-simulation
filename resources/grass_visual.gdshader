shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

uniform float wind_strength : hint_range(0.0, 2.0) = 0.25;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.2;
uniform float wind_scale : hint_range(0.0, 1.0) = 0.05;

uniform sampler2D burn_map : filter_linear;
uniform float terrain_size = 4000.0;
varying vec3 v_world_pos;

void vertex() {
    // World-space position of the vertex
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_pos = world_pos;
    
    // Height-based influence: Only move the top of the grass
    // Nature kit grass is usually around 0.5 to 1.5 units high
    float height_factor = smoothstep(0.0, 1.5, VERTEX.y);
    
    float time = TIME * wind_speed;
    
    // Simple harmonic wind
    float offset = sin(time + world_pos.x * wind_scale + world_pos.z * wind_scale) * 
                   cos(time * 0.4 + world_pos.x * 0.1) * wind_strength;
    
    VERTEX.x += offset * height_factor;
    VERTEX.z += offset * height_factor * 0.6;
}

void fragment() {
    vec4 tex = texture(albedo_texture, UV);
    vec3 final_color = tex.rgb * albedo_color.rgb;
    
    // Read char level and explicit heat from global burn map
    vec2 uv_burn = (v_world_pos.xz / terrain_size) + 0.5;
    vec4 burn_state = texture(burn_map, uv_burn);
    float char_lvl = burn_state.g;
    float heat = burn_state.a;
    
    // Base charring (deep charcoal)
    vec3 charcoal = vec3(0.04, 0.03, 0.03);
    final_color = mix(final_color, charcoal, char_lvl);
    
    // Ash phase (reveals as heat dissipates)
    float ash_presence = smoothstep(0.8, 1.0, char_lvl) * smoothstep(0.4, 0.0, heat);
    
    // Multi-directional wave function for organic, non-grid patches
    vec2 p1 = v_world_pos.xz * 0.05;
    vec2 p2 = vec2(p1.x * 0.8 + p1.y * 0.6, -p1.x * 0.6 + p1.y * 0.8) * 1.5;
    vec2 p3 = vec2(p2.x * 0.5 - p2.y * 0.866, p2.x * 0.866 + p2.y * 0.5) * 2.0;
    
    float n1 = sin(p1.x) * cos(p1.y);
    float n2 = sin(p2.x) * cos(p2.y);
    float n3 = sin(p3.x) * cos(p3.y);
    float combined_noise = (n1 + n2 + n3) / 3.0 * 0.5 + 0.5;
    
    float patch_mask = smoothstep(0.75, 0.85, combined_noise); // Only ash on peak patches
    
    float ash_mask = patch_mask * ash_presence;
    float settle_factor = smoothstep(0.2, 1.0, NORMAL.y); // Settle on very tips
    ash_mask *= settle_factor;
    
    vec3 ash_color = vec3(0.35, 0.35, 0.38); // Darker, less obtrusive grey
    final_color = mix(final_color, ash_color, ash_mask * 0.8); // Max 80% opacity
    
    // Ember effect: Delay until charred, fade using explicit heat
    float ember_phase = smoothstep(0.6, 0.9, char_lvl) * heat;
    
    // Smooth, low-frequency noise
    float ember_noise = (sin(v_world_pos.x * 2.5) * cos(v_world_pos.y * 2.5 + v_world_pos.z * 2.5)) * 0.5 + 0.5;
    
    // Slow, heavy pulse
    float ember_pulse = 0.6 + 0.4 * sin(TIME * 1.5 + ember_noise * 4.0);
    
    // Tighter mask
    float ember_mask = smoothstep(0.75, 0.95, ember_noise) * ember_phase;
    
    // Deep smoldering colors
    vec3 hot_color = vec3(0.9, 0.25, 0.05);
    vec3 cool_color = vec3(0.5, 0.05, 0.0);
    vec3 ember_color = mix(cool_color, hot_color, heat) * ember_mask * ember_pulse * 1.5;

    ALBEDO = final_color;
    EMISSION = ember_color;
    ALPHA = tex.a * albedo_color.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
    
    ROUGHNESS = 0.8;
    SPECULAR = 0.1;
}