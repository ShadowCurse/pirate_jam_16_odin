package game

import "core:slice"
import stb "vendor:stb/image"

Texture :: struct {
    data:   []u32,
    width:  u32,
    height: u32,
}

texture_load :: proc(path: cstring) -> Texture {
    width: i32 = ---
    height: i32 = ---
    channels: i32 = ---
    image := stb.load(path, &width, &height, &channels, 4)
    assert(image != nil, "Loading texture error: %s", stb.failure_reason())
    defer stb.image_free(image)
    assert(channels == 4, "Trying to load texture with not 4 channels")
    total_bytes := width * height
    texture_data, err := make([]u32, total_bytes)
    assert(err == nil, "Cannot allocate memory for the texture: %s", path)
    copy(texture_data, slice.from_ptr(cast([^]u32)image, cast(int)total_bytes))
    log_info("Loaded texture: %s width: %d height: %d channels: %d", path, width, height, channels)
    texture := Texture{texture_data, cast(u32)width, cast(u32)height}

    if ODIN_ARCH != .wasm32 do texture_convert_abgr_to_argb(&texture)

    return texture
}

texture_convert_abgr_to_argb :: proc(texture: ^Texture) {
    texture_colors := transmute([]Color)texture.data
    for &color in texture_colors {
        color_abgr_to_argb(&color)
    }
}

// Note: everyting in the renderer is in the screen space coordinate
// system. So Y is looking down. This means the TOP is at the lowest
// Y coord, while BOTTOM is at the highest Y.

// Area of a texture with center of 
// corrdinates at the top left corner in the
// screen space
TextureArea :: struct {
    position: Vec2u32,
    size:     Vec2u32,
}

texture_area_left :: proc(area: ^TextureArea) -> u32 {
    return area.position.x
}
texture_area_right :: proc(area: ^TextureArea) -> u32 {
    return area.position.x + area.size.x
}
texture_area_top :: proc(area: ^TextureArea) -> u32 {
    return area.position.y
}
texture_area_bottom :: proc(area: ^TextureArea) -> u32 {
    return area.position.y + area.size.y
}

// Rectangle shape with the position at it's center
Rectangle :: struct {
    position: Vec2,
    size:     Vec2,
}

rectangle_left :: proc(rectangle: ^Rectangle) -> f32 {
    return rectangle.position.x - rectangle.size.x / 2
}
rectangle_right :: proc(rectangle: ^Rectangle) -> f32 {
    return rectangle.position.x + rectangle.size.x / 2
}
rectangle_top :: proc(rectangle: ^Rectangle) -> f32 {
    return rectangle.position.y - rectangle.size.y / 2
}
rectangle_bottom :: proc(rectangle: ^Rectangle) -> f32 {
    return rectangle.position.y + rectangle.size.y / 2
}

left :: proc {
    texture_area_left,
    rectangle_left,
}
right :: proc {
    texture_area_right,
    rectangle_right,
}
top :: proc {
    texture_area_top,
    rectangle_top,
}
bottom :: proc {
    texture_area_bottom,
    rectangle_bottom,
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
            cast(u32)clamp(left(rectangle), 0, cast(f32)texture.width),
            cast(u32)clamp(top(rectangle), 0, cast(f32)texture.height),
        },
        max = {
            cast(u32)clamp(right(rectangle), 0, cast(f32)texture.width),
            cast(u32)clamp(bottom(rectangle), 0, cast(f32)texture.height),
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

draw_color_rectangle :: proc(surface: ^Texture, rectangle: ^Rectangle, color: Color) {
    intersection := texture_rectangle_intersection(surface, rectangle)

    width := width(&intersection)
    height := height(&intersection)
    if width == 0 || height == 0 do return

    surface_data_start := intersection.min.x + intersection.min.y * surface.width

    for _ in 0 ..< height {
        for &c in surface.data[surface_data_start:][:width] {
            c = transmute(u32)color
        }
        surface_data_start += surface.width
    }
}

draw_texture :: proc(
    surface: ^Texture,
    texture: ^Texture,
    texture_area: ^TextureArea,
    texture_position: Vec2,
) {
    texture_rectangle_on_the_surface := Rectangle {
        position = texture_position,
        size     = {cast(f32)texture.width, cast(f32)texture.height},
    }
    intersection := texture_rectangle_intersection(surface, &texture_rectangle_on_the_surface)

    width := width(&intersection)
    height := height(&intersection)
    if width == 0 || height == 0 do return

    surface_data_start := intersection.min.x + intersection.min.y * surface.width

    texture_x_offset := cast(u32)abs(left(&texture_rectangle_on_the_surface)) - intersection.min.x
    texture_y_offset := cast(u32)abs(top(&texture_rectangle_on_the_surface)) - intersection.min.y
    texture_data_start :=
        texture_area.position.x +
        texture_x_offset +
        (texture_area.position.y + texture_y_offset) * texture.width

    for _ in 0 ..< height {
        copy(surface.data[surface_data_start:][:width], texture.data[texture_data_start:][:width])
        surface_data_start += surface.width
        texture_data_start += texture.width
    }
}
