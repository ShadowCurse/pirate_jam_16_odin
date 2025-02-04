package game

Texture :: struct {
    data:   []u32,
    width:  u32,
    height: u32,
}

Rectangle :: struct {
    position: Vec2,
    size:     Vec2,
}

AABBu32 :: struct {
    min: Vec2u32,
    max: Vec2u32,
}

width :: proc(aabb: ^AABBu32) -> u32 {
    return aabb.max.x - aabb.min.x
}

height :: proc(aabb: ^AABBu32) -> u32 {
    return aabb.max.y - aabb.min.y
}

texture_rectangle_intersection :: proc(texture: ^Texture, rectangle: ^Rectangle) -> AABBu32 {
    aabb: AABBu32 = {
        min = {
            cast(u32)clamp(rectangle.position.x - rectangle.size.x / 2, 0, cast(f32)texture.width),
            cast(u32)clamp(
                rectangle.position.y - rectangle.size.y / 2,
                0,
                cast(f32)texture.height,
            ),
        },
        max = {
            cast(u32)clamp(rectangle.position.x + rectangle.size.x / 2, 0, cast(f32)texture.width),
            cast(u32)clamp(
                rectangle.position.y + rectangle.size.y / 2,
                0,
                cast(f32)texture.height,
            ),
        },
    }
    assert(
        0 <= aabb.min.x && aabb.min.x <= texture.width,
        "0 <= % <= %",
        aabb.min.x,
        texture.width,
    )
    assert(
        0 <= aabb.max.x && aabb.max.x <= texture.width,
        "0 <= % <= %",
        aabb.max.x,
        texture.width,
    )
    assert(
        0 <= aabb.min.y && aabb.min.y <= texture.height,
        "0 <= % <= %",
        aabb.min.x,
        texture.height,
    )
    assert(
        0 <= aabb.max.y && aabb.max.y <= texture.height,
        "0 <= % <= %",
        aabb.min.x,
        texture.height,
    )
    return aabb
}

draw_color_rectangle :: proc(texture: ^Texture, rectangle: ^Rectangle, color: Color) {
    intersection := texture_rectangle_intersection(texture, rectangle)

    width := width(&intersection)
    height := height(&intersection)
    if width == 0 || height == 0 do return

    texture_data_start := intersection.min.x + intersection.min.y * texture.width

    for _ in 0 ..< height {
        for &c in texture.data[texture_data_start:][:width] {
            c = transmute(u32)color
        }
        texture_data_start += texture.width
    }
}
