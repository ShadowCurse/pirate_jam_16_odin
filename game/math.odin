package game

Vec2 :: distinct [2]f32
Vec2i32 :: distinct [2]i32
Vec2u32 :: distinct [2]u32

vec2_cast :: proc {
    vec2_cast_i32_to_f32,
}

vec2_cast_i32_to_f32 :: proc(vec2: Vec2i32) -> Vec2 {
    return {cast(f32)vec2.x, cast(f32)vec2.y}
}
