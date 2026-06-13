shader_type particles;

uniform sampler2D terrain_heightmap;
uniform float terrain_scale = 4000.0;
uniform float height_scale = 120.0;
uniform vec3 world_offset;

float get_height(vec2 world_xz) {
    vec2 uv = (world_xz / terrain_scale) + 0.5;
    float h = texture(terrain_heightmap, uv).r;
    h = smoothstep(0.1, 0.95, h);
    return h * height_scale;
}

float hash(uint x) {
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = (x >> 16u) ^ x;
    return float(x) / 4294967295.0;
}

void start() {
	CUSTOM.x = hash(uint(INDEX) * 5831u);
	CUSTOM.y = hash(uint(INDEX) * 1234u);
	CUSTOM.z = hash(uint(INDEX) * 9999u);
	CUSTOM.w = hash(uint(INDEX) * 7777u);
}

void process() {
	float emission_size = 400.0;
	vec3 pos;
	pos.x = (CUSTOM.x - 0.5) * emission_size;
	pos.z = (CUSTOM.y - 0.5) * emission_size;
	
	// Wrapping logic centered on camera
	pos.x = pos.x + floor((world_offset.x - pos.x + (emission_size * 0.5)) / emission_size) * emission_size;
	pos.z = pos.z + floor((world_offset.z - pos.z + (emission_size * 0.5)) / emission_size) * emission_size;
	
	float h = get_height(pos.xz);
	pos.y = h;

	// Simple slope check
	float e = 1.0;
    float hL = get_height(pos.xz + vec2(-e, 0.0));
    float hR = get_height(pos.xz + vec2(e, 0.0));
    float hD = get_height(pos.xz + vec2(0.0, -e));
    float hU = get_height(pos.xz + vec2(0.0, e));
    vec3 normal = normalize(vec3(hL - hR, 2.0 * e, hD - hU));
    float slope = dot(normal, vec3(0.0, 1.0, 0.0));

	if (slope < 0.7 || h < 0.0 || abs(pos.x) > 1995.0 || abs(pos.z) > 1995.0) {
		ACTIVE = false;
	} else {
		ACTIVE = true;
		float angle = CUSTOM.z * 6.28318;
		float scale = 3.0 + CUSTOM.w * 3.0;
		
		TRANSFORM[0].xyz = vec3(cos(angle), 0.0, sin(angle)) * scale;
		TRANSFORM[1].xyz = vec3(0.0, 1.0, 0.0) * scale;
		TRANSFORM[2].xyz = vec3(-sin(angle), 0.0, cos(angle)) * scale;
		TRANSFORM[3].xyz = pos;
	}
}
