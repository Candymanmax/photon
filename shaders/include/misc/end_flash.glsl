#if !defined INCLUDE_MISC_END_FLASH
#define INCLUDE_MISC_END_FLASH

#if defined WORLD_END && defined IS_IRIS
uniform vec3 endFlashPosition;
uniform float endFlashIntensity;
#endif

float get_end_flash_fade() {
#if defined WORLD_END && defined IS_IRIS
    if (length(endFlashPosition) > eps) {
        return smoothstep(0.1, 0.35, endFlashIntensity);
    }
#endif

    return 0.0;
}

float get_end_flash_shadow_fade() {
#if defined WORLD_END && defined IS_IRIS
    return get_end_flash_fade();
#else
    return 1.0;
#endif
}

#endif
