#if !defined INCLUDE_SURFACE_WATER_MATERIAL
#define INCLUDE_SURFACE_WATER_MATERIAL

Material get_water_material_from_sample(
    vec4 sampled_color,
    vec4 tint,
    vec3 direction_world,
    vec3 normal,
    vec2 light_levels,
    float layer_dist,
    out float alpha
) {
    Material material = water_material;
    alpha = 0.01;

#if WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT \
    || WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT_UNDERGROUND
    float texture_highlight = dampen(
        0.5 * sqr(linear_step(0.63, 1.0, sampled_color.r))
        + 0.03 * sampled_color.r
    );
#if WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT_UNDERGROUND
    texture_highlight *= 1.0 - cube(linear_step(0.0, 0.5, light_levels.y));
#endif

    sampled_color *= tint;
    material.albedo
        = clamp01(0.5 * exp(-2.0 * water_absorption_coeff) * texture_highlight);
    material.roughness += 0.3 * texture_highlight;
    alpha += texture_highlight;
#elif WATER_TEXTURE == WATER_TEXTURE_VANILLA
    sampled_color *= tint;
    material.albedo = srgb_eotf_inv(sampled_color.rgb * sampled_color.a)
        * rec709_to_working_color;
    alpha = sampled_color.a;
#endif

#ifdef WATER_EDGE_HIGHLIGHT
    float dist = layer_dist * max(abs(direction_world.y), eps);

#if WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT \
    || WATER_TEXTURE == WATER_TEXTURE_HIGHLIGHT_UNDERGROUND
    float edge_highlight
        = cube(max0(1.0 - 2.0 * dist)) * (1.0 + 8.0 * texture_highlight);
#else
    float edge_highlight = cube(max0(1.0 - 2.0 * dist));
#endif
    edge_highlight *= WATER_EDGE_HIGHLIGHT_INTENSITY * max0(normal.y)
        * (1.0 - 0.5 * sqr(light_levels.y));

    material.albedo += 0.1 * edge_highlight
        / mix(1.0,
              max(dot(ambient_color, luminance_weights_rec2020), 0.5),
              light_levels.y);
    material.albedo = clamp01(material.albedo);
    alpha += edge_highlight;
#endif

    return material;
}

#endif
