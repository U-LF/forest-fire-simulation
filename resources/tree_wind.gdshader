shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.2;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wind_scale : hint_range(0.0, 1.0) = 0.1;

void vertex() {
    // World-space wind logic
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
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
    
    ALBEDO = final_color.rgb;
    ALPHA = final_color.a;
    
    // Alpha Scissoring for clean leaf edges
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
    
    ROUGHNESS = 0.8;
    SPECULAR = 0.2;
}