shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float terrain_scale = 4000.0;
uniform float terrain_size = 4000.0;
uniform float height_scale = 120.0;

// Noise textures for displacement
uniform sampler2D macro_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D micro_noise : repeat_enable, filter_linear_mipmap;

// Colors for "texturing"
uniform vec3 color_grass_base = vec3(0.15, 0.25, 0.10);
uniform vec3 color_grass_dark = vec3(0.08, 0.15, 0.05);
uniform vec3 color_rock_base = vec3(0.35, 0.33, 0.30);
uniform vec3 color_rock_dark = vec3(0.20, 0.18, 0.15);
uniform vec3 color_dirt = vec3(0.25, 0.20, 0.12);

uniform sampler2D burn_map : filter_linear;

varying float v_height;
varying vec3 v_normal;
varying vec3 v_world_pos;

// Function to calculate exact height at a given world position
float get_height(vec2 world_xz) {
    // Correct UV mapping: Map world [-500, 500] to UV [0, 1]
    // world_xz / terrain_scale gives [-0.5, 0.5], so we add 0.5
    vec2 uv_macro = (world_xz / terrain_scale) + 0.5;
    
    // Sample large sweeping hills
    float macro_h = texture(macro_noise, uv_macro).r;
    
    // Smoothstep creates the plateau/valley separation. 
    macro_h = smoothstep(0.1, 0.95, macro_h);
    
    return macro_h * height_scale;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    // 1. Calculate Height
    float h = get_height(world_pos.xyz.xz);
    v_height = h;
    VERTEX.y += h;
    
    // 2. Calculate High-Quality Normals via Central Difference
    float e = 1.0; // Sample distance (1 meter)
    float hL = get_height(world_pos.xyz.xz + vec2(-e, 0.0));
    float hR = get_height(world_pos.xyz.xz + vec2(e, 0.0));
    float hD = get_height(world_pos.xyz.xz + vec2(0.0, -e));
    float hU = get_height(world_pos.xyz.xz + vec2(0.0, e));
    
    vec3 n;
    n.x = hL - hR;
    n.y = 2.0 * e;
    n.z = hD - hU;
    v_normal = normalize(n);
    v_world_pos = world_pos;
}

void fragment() {
    // Re-assign accurate normal
    NORMAL = (VIEW_MATRIX * vec4(v_normal, 0.0)).xyz;
    
    // 1. Slope Calculation (1.0 = flat, 0.0 = sheer cliff)
    float slope = dot(v_normal, vec3(0.0, 1.0, 0.0));
    
    // 2. Generate detailed "fake" textures using the micro noise
    // We sample it at a very high frequency
    vec2 detail_uv = v_world_pos.xz / 20.0;
    float detail = texture(micro_noise, detail_uv).r;
    
    // 3. Define Biome Colors
    vec3 grass_color = mix(color_grass_dark, color_grass_base, detail);
    vec3 rock_color = mix(color_rock_dark, color_rock_base, detail);
    vec3 dirt_color = mix(color_dirt, color_rock_base, detail * 0.5);
    
    vec3 final_color;
    
    // 4. Slope-Based Blending
    if (slope < 0.75) {
        // Steep Cliff -> Rock
        final_color = rock_color;
    } else if (slope < 0.85) {
        // Transition Zone -> Dirt/Rocky
        float t = smoothstep(0.75, 0.85, slope);
        final_color = mix(rock_color, dirt_color, t);
    } else if (slope < 0.9) {
        // Transition Zone -> Dirt/Grass
        float t = smoothstep(0.85, 0.9, slope);
        final_color = mix(dirt_color, grass_color, t);
    } else {
        // Flat -> Grass
        final_color = grass_color;
    }
    
    // Add a slight darkening based on height to simulate atmospheric depth in valleys
    float height_factor = clamp(v_height / height_scale, 0.0, 1.0);
    final_color = mix(final_color * 0.8, final_color, height_factor);
    
    // Read raw values from global burn map
    vec2 uv_burn = (v_world_pos.xz / terrain_size) + 0.5;
    vec4 burn_state = texture(burn_map, uv_burn);
    float char_lvl = burn_state.g;
    float heat = burn_state.a;
    
    // Base charring (deep charcoal)
    vec3 charcoal = vec3(0.06, 0.05, 0.05);
    final_color = mix(final_color, charcoal, char_lvl);
    
    // Ash phase (reveals as heat dissipates)
    float ash_presence = smoothstep(0.8, 1.0, char_lvl) * smoothstep(0.3, 0.0, heat);
    
    // Multi-directional wave function for organic, non-grid patches
    vec2 p1 = v_world_pos.xz * 0.05;
    vec2 p2 = vec2(p1.x * 0.8 + p1.y * 0.6, -p1.x * 0.6 + p1.y * 0.8) * 1.5;
    vec2 p3 = vec2(p2.x * 0.5 - p2.y * 0.866, p2.x * 0.866 + p2.y * 0.5) * 2.0;
    
    float n1 = sin(p1.x) * cos(p1.y);
    float n2 = sin(p2.x) * cos(p2.y);
    float n3 = sin(p3.x) * cos(p3.y);
    float combined_noise = (n1 + n2 + n3) / 3.0 * 0.5 + 0.5;
    
    // Aggressively tighten the mask: Ash only appears where combined noise is very high
    float patch_mask = smoothstep(0.75, 0.85, combined_noise);
    
    float ash_mask = patch_mask * ash_presence;
    
    // Terrain naturally collects more ash in flatter areas, less on sheer cliffs
    float settle_factor = smoothstep(0.8, 1.0, slope); // Only settle on very flat ground
    ash_mask *= settle_factor;
    
    vec3 ash_color = vec3(0.35, 0.35, 0.38); // Darker, less obtrusive grey
    final_color = mix(final_color, ash_color, ash_mask * 0.85); // Max 85% opacity
    
    // Ember effect: Delay until charred, fade using explicit heat
    float ember_phase = smoothstep(0.6, 0.9, char_lvl) * heat;
    
    // Smooth, low-frequency noise for larger glowing "veins" in the ground
    float ember_noise = (sin(v_world_pos.x * 1.5) * cos(v_world_pos.z * 1.5)) * 0.5 + 0.5;
    
    // Slow, breathing heat
    float ember_pulse = 0.6 + 0.4 * sin(TIME * 1.2 + ember_noise * 3.0); 
    
    // Tight mask for subtlety
    float ember_mask = smoothstep(0.8, 0.98, ember_noise) * ember_phase;
    
    // Deep smoldering colors
    vec3 hot_color = vec3(0.9, 0.25, 0.05);
    vec3 cool_color = vec3(0.4, 0.05, 0.0);
    vec3 ember_color = mix(cool_color, hot_color, heat) * ember_mask * ember_pulse * 1.5;
    
    ALBEDO = final_color;
    EMISSION = ember_color;
    ROUGHNESS = mix(0.8, 0.95, detail); // Break up reflections
    SPECULAR = 0.0;
}