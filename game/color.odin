package game

import "core:math"

Color :: struct #align(4) {
    b: u8,
    g: u8,
    r: u8,
    a: u8,
}

WHITE :: Color {
    r = 255,
    g = 255,
    b = 255,
    a = 255,
}

color_abgr_to_argb :: proc(color: ^Color) {
    color.r, color.b = color.b, color.r
}

// dst - color blend onto
// src - color to blend in
color_blend :: proc(dst: ^Color, src: ^Color) -> Color {
    t := cast(f32)src.a / 255

    dst_r := cast(f32)dst.r
    dst_g := cast(f32)dst.g
    dst_b := cast(f32)dst.b

    src_r := cast(f32)src.r
    src_g := cast(f32)src.g
    src_b := cast(f32)src.b

    new_r := math.lerp(dst_r, src_r, t)
    new_g := math.lerp(dst_g, src_g, t)
    new_b := math.lerp(dst_b, src_b, t)

    return Color{r = cast(u8)new_r, g = cast(u8)new_g, b = cast(u8)new_b, a = dst.a}
}
