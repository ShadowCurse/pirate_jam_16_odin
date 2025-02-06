package game

Color :: struct #align (4) {
    using inner: [4]u8,
}

color_abgr_to_argb :: proc(color: ^Color) {
    color.r, color.b = color.b, color.r
}
