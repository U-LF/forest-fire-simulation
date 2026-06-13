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
}

void fragment() {
    vec4 albedo_tex = texture(albedo_texture, UV);
    vec4 final_color = albedo_tex * albedo_color * COLOR;
    
    // Read char level from global burn map
    vec2 uv_burn = (v_world_pos.xz / terrain_size) + 0.5;
    vec4 burn_state = texture(burn_map, uv_burn);
    float char_lvl = burn_state.g;
    
    // Apply charring effect (turn tree black where burnt)
    final_color.rgb = mix(final_color.rgb, vec3(0.02, 0.02, 0.02), char_lvl);
    
    // Ember effect
    float ember_noise = fract(sin(dot(floor(v_world_pos.xz * 2.0 + v_world_pos.y * 2.0), vec2(12.9898, 78.233))) * 43758.5453);
    float ember_pulse = 0.5 + 0.5 * sin(TIME * 2.5 + ember_noise * 15.0);
    float ember_mask = smoothstep(0.85, 1.0, ember_noise) * char_lvl;
    vec3 ember_color = vec3(1.0, 0.3, 0.0) * ember_mask * ember_pulse * 1.5;

    ALBEDO = final_color.rgb;
    EMISSION = ember_color;
    ALPHA = final_color.a;
    
    // Alpha Scissoring for clean leaf edges
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
    
    ROUGHNESS = 0.8;
    SPECULAR = 0.2;
}