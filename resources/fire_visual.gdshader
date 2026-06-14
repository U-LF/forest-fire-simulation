shader_type spatial;
// Changed from blend_add to blend_mix to completely eliminate the white "flashbang" overlapping artifact
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec4 root_color : source_color = vec4(1.0, 0.9, 0.2, 1.0); // Bright yellow core
uniform vec4 tip_color : source_color = vec4(1.0, 0.3, 0.0, 1.0); // Vibrant orange/red
uniform float fire_speed = 1.2; // Slower, heavier natural burn

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
    // 0 at bottom, 1 at top
    float y = 1.0 - uv.y; 
    
    // Organic sway: Flames wave left/right as they rise
    float wave = sin(TIME * fire_speed * 1.5 + y * 4.0) * 0.15 * y;
    vec2 distorted_uv = vec2(uv.x + wave, uv.y);
    
    // Dual-layer noise for chaotic breakdown (prevents repetitive patterns)
    vec2 noise_uv1 = distorted_uv * vec2(2.0, 1.5) + vec2(0.0, TIME * fire_speed);
    vec2 noise_uv2 = distorted_uv * vec2(3.0, 2.5) + vec2(0.0, TIME * fire_speed * 1.3);
    float n1 = noise(noise_uv1 * 3.0) * 0.5 + 0.5;
    float n2 = noise(noise_uv2 * 4.0) * 0.5 + 0.5;
    float n = n1 * 0.7 + n2 * 0.3;
    
    // Base organic column: Softer horizontal falloff, tapering at the top
    float x_dist = abs(distorted_uv.x - 0.5) * 2.0;
    float profile = smoothstep(1.0, 0.3, x_dist); 
    float height_mask = smoothstep(1.0, 0.1, y); 
    float shape = profile * height_mask;
    
    // Cut out the flame using the noise
    float flame = smoothstep(0.3, 0.5, shape * n * 1.8);
    
    // Ground fade to prevent hard geometric clipping against the terrain
    flame *= smoothstep(0.0, 0.1, y); 
    
    // Natural Color: Gradient driven by height and noise
    vec3 color = mix(tip_color.rgb, root_color.rgb, smoothstep(0.1, 0.7, y * n * 1.5));
    
    ALBEDO = color;
    ALPHA = flame * COLOR.a; 
}