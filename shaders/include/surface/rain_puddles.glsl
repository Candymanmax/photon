#if !defined INCLUDE_MISC_RAIN_PUDDLES
#define INCLUDE_MISC_RAIN_PUDDLES

#include "/include/misc/material_masks.glsl"
#include "/include/utility/random.glsl"

const float min_ripple_scale = 2.0;
const float max_ripple_scale = 10.0;

float get_legacy_ripple_height(vec2 coord) {
    const float ripple_frequency = 0.2;
    const float ripple_speed = 0.05;
    const vec2 ripple_dir_0 = vec2(3.0, 4.0) / 5.0;
    const vec2 ripple_dir_1 = vec2(-5.0, -12.0) / 13.0;

    float ripple_noise_1 = texture(
        noisetex,
        coord * ripple_frequency + frameTimeCounter * ripple_speed * ripple_dir_0
    ).y;
    float ripple_noise_2 = texture(
        noisetex,
        coord * ripple_frequency + frameTimeCounter * ripple_speed * ripple_dir_1
    ).y;

    return mix(ripple_noise_1, ripple_noise_2, 0.5);
}

float ripples_layer(vec2 base_uvs, float scale) {
    float time = frameTimeCounter * 0.85 + 100.0 * scale;

    vec2 scaled_uvs = base_uvs * scale;
    vec2 tile = floor(scaled_uvs);
    vec2 fr = fract(scaled_uvs);

    vec2 seed0 = hash2(tile + scale);
    float cycle = mix(0.7, 1.6, seed0.x);
    float event_id = floor(time / cycle);
    float age = fract(time / cycle);

    vec2 seed1 = hash2(tile + scale + event_id * 0.37);
    vec2 point = mix(vec2(0.12), vec2(0.88), seed1);

    float ring_size = mix(0.35, 0.95, seed1.y);
    float max_radius = mix(0.18, 0.42, ring_size);
    float radius = max_radius * smoothstep(0.0, 0.92, age);
    float dist = length(fr - point);

    float band = mix(0.03, 0.08, ring_size);
    float phase = (dist - radius) / band;
    float circles = exp(-phase * phase)
        * (0.5 + 0.5 * cos(phase * tau));
    circles *= exp(-dist * mix(1.8, 3.5, seed0.y));

    float life = sin(age * tau * 0.5);
    life *= life;
    life *= smoothstep(0.0, 0.10, age);
    life *= 1.0 - smoothstep(0.88, 1.0, age);
    circles *= life;
    circles *= circles;

    return circles * 0.9;
}

float get_ripple_height(vec2 coord) {
    vec2 base_uvs = coord * 0.55;
    float circles = 0.0;

    for (float scale = min_ripple_scale; scale < max_ripple_scale;
        scale += 1.0) {
        circles = max(circles, ripples_layer(base_uvs, scale));
    }

    circles = max(circles, 0.35 * get_legacy_ripple_height(coord));

    return circles * 0.7;
}

float get_puddle_noise(
    vec3 world_pos,
    vec3 flat_normal,
    vec2 light_levels
) {
    const float puddle_frequency = 0.025;

    float puddle = texture(noisetex, world_pos.xz * puddle_frequency).w;
    puddle = linear_step(0.45, 0.55, puddle) * wetness * biome_may_rain
        * step(0.99, flat_normal.y);

    // Prevent puddles from appearing indoors
    puddle *= (1.0 - cube(light_levels.x))
        * linear_step(14.0 / 15.0, 1.0, light_levels.y);

    return puddle;
}

bool get_rain_puddles(
    vec3 world_pos,
    vec3 flat_normal,
    vec2 light_levels,
    float porosity,
    uint material_mask,
    inout vec3 normal,
    inout vec3 albedo,
    inout vec3 f0,
    inout float roughness,
    inout float ssr_multiplier
) {
#ifndef RAIN_PUDDLES
    return false;
#endif

    const float puddle_f0 = 0.02;
    const float puddle_roughness = 0.002;
    const float puddle_darkening_factor = 0.33;
    const float puddle_darkening_factor_porous = 0.67;

    if (wetness < 0.0 || biome_may_rain < 0.0
        || material_mask == MATERIAL_LEAVES) {
        return false;
    }

    float puddle = get_puddle_noise(world_pos, flat_normal, light_levels);

    if (puddle < eps) {
        return false;
    }

    // Puddle darkening
    albedo *= 1.0 - puddle_darkening_factor_porous * porosity * puddle;
    puddle *= 1.0 - porosity;
    albedo *= 1.0 - puddle_darkening_factor * puddle;

    // Replace material with puddle material
    f0 = max(f0, mix(f0, vec3(puddle_f0), puddle));
    roughness = puddle_roughness;
    ssr_multiplier = max(ssr_multiplier, puddle);

    // Ripple animation
    const float h = 0.03;
    float ripple_x0 = get_ripple_height(world_pos.xz - vec2(h, 0.0));
    float ripple_x1 = get_ripple_height(world_pos.xz + vec2(h, 0.0));
    float ripple_y0 = get_ripple_height(world_pos.xz - vec2(0.0, h));
    float ripple_y1 = get_ripple_height(world_pos.xz + vec2(0.0, h));

    vec2 ripple_gradient = vec2(
        ripple_x1 - ripple_x0,
        ripple_y1 - ripple_y0
    );

    float ripple_view_fade = smoothstep(
        0.0,
        0.1,
        abs(dot(flat_normal, normalize(world_pos - cameraPosition)))
    );

    vec3 ripple_normal = normalize(vec3(-ripple_gradient, 2.0 * h));
    ripple_normal.xy *= 0.025 * ripple_view_fade;
    ripple_normal = ripple_normal.xzy; // convert to world space

    normal = mix(normal, flat_normal, puddle);
    normal = mix(normal, ripple_normal, puddle * rainStrength);
    normal = normalize_safe(normal);

    return true;
}

#endif // INCLUDE_MISC_RAIN_PUDDLES
