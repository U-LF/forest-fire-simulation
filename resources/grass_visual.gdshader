shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

uniform float wind_strength : hint_range(0.0, 2.0) = 0.25;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.2;
uniform float wind_scale : hint_range(0.0, 1.0) = 0.05;

void vertex() {
    // World-space position of the vertex
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
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
    ALBEDO = tex.rgb * albedo_color.rgb;
    ALPHA = tex.a * albedo_color.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
    
    ROUGHNESS = 0.8;
    SPECULAR = 0.1;
}