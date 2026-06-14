shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_back, unshaded;

uniform vec4 root_color : source_color = vec4(1.0, 0.75, 0.1, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 0.15, 0.0, 1.0);
uniform float fire_speed = 4.0;

// 2D Noise
vec2 random(vec2 uv) {
    uv = vec2(dot(uv,vec2(127.1,311.7)), dot(uv,vec2(269.5,183.3)));
    return -1.0 + 2.0*fract(sin(uv)*43758.5453123);
}
float noise(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec2 u = f*f*(3.0-2.0*f);
    return mix( mix( dot( random(i + vec2(0.0,0.0) ), f - vec2(0.0,0.0) ), 
                     dot( random(i + vec2(1.0,0.0) ), f - vec2(1.0,0.0) ), u.x),
                mix( dot( random(i + vec2(0.0,1.0) ), f - vec2(0.0,1.0) ), 
                     dot( random(i + vec2(1.0,1.0) ), f - vec2(1.0,1.0) ), u.x), u.y);
}

void fragment() {
    vec2 uv = UV;
    // Godot 3D UVs: y=0 is top, y=1 is bottom. Invert for easier math.
    float y = 1.0 - uv.y; 
    
    // Scroll noise upwards
    vec2 noise_uv = uv * vec2(1.5, 1.0) + vec2(0.0, TIME * fire_speed);
    float n = noise(noise_uv * 4.0) * 0.5 + 0.5; 
    
    // Teardrop / Flame base shape
    float x_dist = abs(uv.x - 0.5) * 2.0; 
    float shape = 1.0 - pow(x_dist, 1.5) - pow(y, 1.5); 
    
    // Combine shape with noise to create flickering edges
    float flame = smoothstep(0.0, 0.4, shape + (n * 0.8 - 0.4));
    
    // Soft fade at the very bottom to prevent hard clipping against the terrain
    flame *= smoothstep(0.0, 0.1, y); 
    
    // Color gradient from tip (red) to root (bright orange/yellow)
    vec3 color = mix(tip_color.rgb, root_color.rgb, pow(1.0 - y, 1.5));
    
    ALBEDO = color;
    ALPHA = flame * COLOR.a; 
}