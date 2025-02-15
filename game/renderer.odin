package game

import "base:runtime"
import "core:math/linalg"
import "core:slice"
import stb "vendor:stb/image"

Camera :: struct {
    half_surface_size: Vec2,
    position:          Vec2,
    scale:             f32,
}

camera_update_surface_size :: proc(camera: ^Camera, w, h: f32) {
    new_half_size := Vec2{w, h} / 2
    camera.position -= new_half_size - camera.half_surface_size
    camera.half_surface_size = new_half_size
}

camera_to_screen :: proc(camera: ^Camera, position: Vec2) -> Vec2 {
    return(
        (position - camera.position - camera.half_surface_size) * camera.scale +
        camera.half_surface_size \
    )
}

Texture :: struct {
    data:     []u8,
    width:    u16,
    height:   u16,
    channels: u8,
}

texture_load :: proc(path: cstring) -> Texture {
    width: i32 = ---
    height: i32 = ---
    channels: i32 = ---
    image := stb.load(path, &width, &height, &channels, 4)
    assert(image != nil, "Loading texture error: %s", stb.failure_reason())
    defer stb.image_free(image)
    assert(channels == 4, "Trying to load texture with not 4 channels")

    total_bytes := width * height * 4
    texture_data, err := runtime.make_aligned([]u8, total_bytes, 4)
    assert(err == nil, "Cannot allocate memory for the texture: %s", path)

    image_data: []u8 = slice.from_ptr(image, cast(int)total_bytes)
    copy(texture_data, image_data)

    texture := Texture{texture_data, cast(u16)width, cast(u16)height, cast(u8)channels}
    log_info(
        "Loaded texture: %s width: %d height: %d channels: %d",
        path,
        texture.width,
        texture.height,
        texture.channels,
    )

    if ODIN_ARCH != .wasm32 do texture_convert_abgr_to_argb(&texture)

    return texture
}

texture_convert_abgr_to_argb :: proc(texture: ^Texture) {
    texture_colors := texture_as_colors(texture)
    for &color in texture_colors {
        color_abgr_to_argb(&color)
    }
}

texture_as_colors :: proc(texture: ^Texture) -> []Color {
    assert(
        texture.channels == 4,
        "Trying to convert texture with %d channels into a color slice",
        texture.channels,
    )
    return slice.from_ptr(cast([^]Color)raw_data(texture.data), len(texture.data) / 4)
}

DrawColorRectangleCommand :: struct {
    rectangle: Rectangle,
    color:     Color,
}

DrawTextureCommand :: struct {
    texture:        ^Texture,
    texture_area:   TextureArea,
    texture_center: Vec2,
    ignore_alpha:   bool,
    tint:           bool,
    tint_color:     Color,
}

DrawTextureScaleRotate :: struct {
    texture:         ^Texture,
    texture_area:    TextureArea,
    texture_center:  Vec2,
    scale:           f32,
    rotation:        f32,
    rotation_offset: Vec2,
    ignore_alpha:    bool,
}

RenderCommand :: union #no_nil {
    DrawColorRectangleCommand,
    DrawTextureCommand,
    DrawTextureScaleRotate,
}

RENDER_COMMANDS_MAX :: 8192
RenderCommands :: struct {
    in_world_space: [RENDER_COMMANDS_MAX]bool,
    commands:       [RENDER_COMMANDS_MAX]RenderCommand,
    commands_n:     u32,
}

render_commands_add_color_rect :: proc(
    render_commands: ^RenderCommands,
    command: DrawColorRectangleCommand,
    in_world_space := true,
) {
    if render_commands.commands_n == RENDER_COMMANDS_MAX {
        log_err("Trying to add more render commands than capacity")
        return
    }

    render_commands.commands[render_commands.commands_n] = command
    render_commands.in_world_space[render_commands.commands_n] = in_world_space
    render_commands.commands_n += 1
}
render_commands_add_texture :: proc(
    render_commands: ^RenderCommands,
    command: DrawTextureCommand,
    in_world_space := true,
) {
    if render_commands.commands_n == RENDER_COMMANDS_MAX {
        log_err("Trying to add more render commands than capacity")
        return
    }

    render_commands.commands[render_commands.commands_n] = command
    render_commands.in_world_space[render_commands.commands_n] = in_world_space
    render_commands.commands_n += 1
}
render_commands_add_texture_scale_rotate :: proc(
    render_commands: ^RenderCommands,
    command: DrawTextureScaleRotate,
    in_world_space := true,
) {
    if render_commands.commands_n == RENDER_COMMANDS_MAX {
        log_err("Trying to add more render commands than capacity")
        return
    }

    render_commands.commands[render_commands.commands_n] = command
    render_commands.in_world_space[render_commands.commands_n] = in_world_space
    render_commands.commands_n += 1
}
render_commands_add :: proc {
    render_commands_add_color_rect,
    render_commands_add_texture,
    render_commands_add_texture_scale_rotate,
    render_commands_add_text,
}

render_commands_render :: proc(
    render_commands: ^RenderCommands,
    surface: ^Texture,
    camera: ^Camera,
) {
    for &command, i in render_commands.commands[:render_commands.commands_n] {
        to_screen_space := render_commands.in_world_space[i]
        switch &c in command {
        case DrawColorRectangleCommand:
            if to_screen_space {
                c.rectangle.center = camera_to_screen(camera, c.rectangle.center)
            }
            draw_rectangle(surface, &c.rectangle, c.color)
        case DrawTextureCommand:
            if to_screen_space {
                c.texture_center = camera_to_screen(camera, c.texture_center)
            }
            draw_texture(
                surface,
                c.texture,
                &c.texture_area,
                c.texture_center,
                c.ignore_alpha,
                c.tint,
                c.tint_color,
            )
        case DrawTextureScaleRotate:
            if to_screen_space {
                c.texture_center = camera_to_screen(camera, c.texture_center)
            }
            draw_texture_scale_rotate(
                surface,
                c.texture,
                &c.texture_area,
                c.texture_center,
                c.scale,
                c.rotation,
                c.rotation_offset,
                c.ignore_alpha,
            )
        }
    }

    render_commands.commands_n = 0
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
    center: Vec2,
    size:   Vec2,
}

rectangle_left :: proc(rectangle: ^Rectangle) -> f32 {
    return rectangle.center.x - rectangle.size.x / 2
}
rectangle_right :: proc(rectangle: ^Rectangle) -> f32 {
    return rectangle.center.x + rectangle.size.x / 2
}
rectangle_top :: proc(rectangle: ^Rectangle) -> f32 {
    return rectangle.center.y - rectangle.size.y / 2
}
rectangle_bottom :: proc(rectangle: ^Rectangle) -> f32 {
    return rectangle.center.y + rectangle.size.y / 2
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
        0 <= aabb.min.x && aabb.min.x <= cast(u32)texture.width,
        "0 <= % <= %",
        aabb.min.x,
        texture.width,
    )
    assert(
        0 <= aabb.max.x && aabb.max.x <= cast(u32)texture.width,
        "0 <= % <= %",
        aabb.max.x,
        texture.width,
    )
    assert(
        0 <= aabb.min.y && aabb.min.y <= cast(u32)texture.height,
        "0 <= % <= %",
        aabb.min.x,
        texture.height,
    )
    assert(
        0 <= aabb.max.y && aabb.max.y <= cast(u32)texture.height,
        "0 <= % <= %",
        aabb.min.x,
        texture.height,
    )
    return aabb
}

draw_rectangle :: proc(surface: ^Texture, rectangle: ^Rectangle, color: Color) {
    intersection := texture_rectangle_intersection(surface, rectangle)

    width := width(&intersection)
    height := height(&intersection)
    if width == 0 || height == 0 do return

    surface_colors := texture_as_colors(surface)
    surface_data_start := intersection.min.x + intersection.min.y * cast(u32)surface.width

    for _ in 0 ..< height {
        for &c in surface_colors[surface_data_start:][:width] {
            c = color
        }
        surface_data_start += cast(u32)surface.width
    }
}

draw_texture :: proc(
    surface: ^Texture,
    texture: ^Texture,
    texture_area: ^TextureArea,
    texture_center: Vec2,
    ignore_alpha := true,
    tint := false,
    tint_color := WHITE,
) {
    texture_rectangle_on_the_surface := Rectangle {
        center = texture_center,
        size   = {cast(f32)texture_area.size.x, cast(f32)texture_area.size.y},
    }
    intersection := texture_rectangle_intersection(surface, &texture_rectangle_on_the_surface)

    width := width(&intersection)
    height := height(&intersection)
    if width == 0 || height == 0 do return

    surface_colors := texture_as_colors(surface)
    surface_data_start := intersection.min.x + intersection.min.y * cast(u32)surface.width

    if texture.channels == 4 {
        texture_colors := texture_as_colors(texture)
        texture_x_offset :=
            cast(u32)abs(left(&texture_rectangle_on_the_surface)) - intersection.min.x
        texture_y_offset :=
            cast(u32)abs(top(&texture_rectangle_on_the_surface)) - intersection.min.y
        texture_data_start :=
            texture_area.position.x +
            texture_x_offset +
            (texture_area.position.y + texture_y_offset) * cast(u32)texture.width

        if ignore_alpha {
            if tint {
                tint_color := tint_color
                for _ in 0 ..< height {
                    for x in 0 ..< width {
                        color := texture_colors[texture_data_start:][x]
                        color = color_blend(&color, &tint_color)
                        surface_color := &surface_colors[surface_data_start:][x]
                        surface_color^ = color
                    }
                    surface_data_start += cast(u32)surface.width
                    texture_data_start += cast(u32)texture.width
                }

            } else {
                for _ in 0 ..< height {
                    copy(
                        surface_colors[surface_data_start:][:width],
                        texture_colors[texture_data_start:][:width],
                    )
                    surface_data_start += cast(u32)surface.width
                    texture_data_start += cast(u32)texture.width
                }
            }
        } else {
            if tint {
                tint_color := tint_color
                for _ in 0 ..< height {
                    for x in 0 ..< width {
                        color := texture_colors[texture_data_start:][x]
                        color = color_blend(&color, &tint_color)
                        surface_color := &surface_colors[surface_data_start:][x]
                        surface_color^ = color_blend(surface_color, &color)
                    }
                    surface_data_start += cast(u32)surface.width
                    texture_data_start += cast(u32)texture.width
                }
            } else {
                for _ in 0 ..< height {
                    for x in 0 ..< width {
                        color := texture_colors[texture_data_start:][x]
                        surface_color := &surface_colors[surface_data_start:][x]
                        surface_color^ = color_blend(surface_color, &color)
                    }
                    surface_data_start += cast(u32)surface.width
                    texture_data_start += cast(u32)texture.width
                }
            }
        }
    } else if texture.channels == 1 {
        texture_colors := texture.data
        texture_x_offset :=
            cast(u32)abs(left(&texture_rectangle_on_the_surface)) - intersection.min.x
        texture_y_offset :=
            cast(u32)abs(top(&texture_rectangle_on_the_surface)) - intersection.min.y
        texture_data_start :=
            texture_area.position.x +
            texture_x_offset +
            (texture_area.position.y + texture_y_offset) * cast(u32)texture.width

        if ignore_alpha {
            if tint {
                tint_color := tint_color
                for _ in 0 ..< height {
                    for x in 0 ..< width {
                        c := texture_colors[texture_data_start:][x]
                        color := Color {
                            r = c,
                            g = c,
                            b = c,
                            a = 255,
                        }
                        color = color_blend(&color, &tint_color)
                        surface_colors[surface_data_start:][x] = color
                    }
                    surface_data_start += cast(u32)surface.width
                    texture_data_start += cast(u32)texture.width
                }
            } else {
                for _ in 0 ..< height {
                    for x in 0 ..< width {
                        c := texture_colors[texture_data_start:][x]
                        color := Color {
                            r = c,
                            g = c,
                            b = c,
                            a = 255,
                        }
                        surface_colors[surface_data_start:][x] = color
                    }
                    surface_data_start += cast(u32)surface.width
                    texture_data_start += cast(u32)texture.width
                }
            }
        } else {
            if tint {
                tint_color := tint_color
                for _ in 0 ..< height {
                    for x in 0 ..< width {
                        c := texture_colors[texture_data_start:][x]
                        color := Color {
                            r = c,
                            g = c,
                            b = c,
                            a = c,
                        }
                        color = color_blend(&color, &tint_color)
                        surface_color := &surface_colors[surface_data_start:][x]
                        surface_color^ = color_blend(surface_color, &color)
                    }
                    surface_data_start += cast(u32)surface.width
                    texture_data_start += cast(u32)texture.width
                }
            } else {
                for _ in 0 ..< height {
                    for x in 0 ..< width {
                        c := texture_colors[texture_data_start:][x]
                        color := Color {
                            r = c,
                            g = c,
                            b = c,
                            a = c,
                        }
                        surface_color := &surface_colors[surface_data_start:][x]
                        surface_color^ = color_blend(surface_color, &color)
                    }
                    surface_data_start += cast(u32)surface.width
                    texture_data_start += cast(u32)texture.width
                }
            }
        }
    }
}

draw_texture_scale_rotate :: proc(
    surface: ^Texture,
    texture: ^Texture,
    texture_area: ^TextureArea,
    texture_center: Vec2,
    scale: f32 = 1,
    rotation: f32 = 0,
    rotation_offset := Vec2{},
    ignore_alpha := true,
) {
    inv_scale := 1 / scale
    cos, sin := linalg.cos(rotation), linalg.sin(rotation)
    new_texture_center :=
        texture_center +
        rotation_offset -
        Vec2 {
                cos * rotation_offset.x - sin * rotation_offset.y,
                sin * rotation_offset.x + cos * rotation_offset.y,
            }
    x_axis := Vec2{cos, sin}
    y_axis := Vec2{-sin, cos}

    half_rect_size := vec2_cast_f32(texture_area.size) * scale / 2
    // a - b
    // |   |
    // c - d
    a := new_texture_center - x_axis * half_rect_size.x - y_axis * half_rect_size.y
    b := new_texture_center + x_axis * half_rect_size.x - y_axis * half_rect_size.y
    c := new_texture_center - x_axis * half_rect_size.x + y_axis * half_rect_size.y
    d := new_texture_center + x_axis * half_rect_size.x + y_axis * half_rect_size.y

    texture_rectangle_on_the_surface := Rectangle {
        center = new_texture_center,
        size   = {
            max(a.x, b.x, c.x, d.x) - min(a.x, b.x, c.x, d.x),
            max(a.y, b.y, c.y, d.y) - min(a.y, b.y, c.y, d.y),
        },
    }
    intersection := texture_rectangle_intersection(surface, &texture_rectangle_on_the_surface)

    width := width(&intersection)
    height := height(&intersection)
    if width == 0 || height == 0 do return

    surface_colors := texture_as_colors(surface)
    surface_data_start := intersection.min.x + intersection.min.y * cast(u32)surface.width

    if texture.channels == 4 {
        texture_colors := texture_as_colors(texture)
        texture_data_start :=
            texture_area.position.x + texture_area.position.y * cast(u32)texture.width

        ab_perp := perp(b - a)
        bd_perp := perp(d - b)
        dc_perp := perp(c - d)
        ca_perp := perp(a - c)

        for y in 0 ..< height {
            for x in 0 ..< width {
                p := vec2_cast_f32(intersection.min + {x, y})

                ap := p - a
                bp := p - b
                dp := p - d
                cp := p - c

                if 0 < linalg.dot(ab_perp, ap) &&
                   0 < linalg.dot(bd_perp, bp) &&
                   0 < linalg.dot(dc_perp, dp) &&
                   0 < linalg.dot(ca_perp, cp) {
                    u := cast(u32)(linalg.dot(ap, x_axis) * inv_scale)
                    v := cast(u32)(linalg.dot(ap, y_axis) * inv_scale)
                    u = clamp(u, 0, texture_area.size.x - 1)
                    v = clamp(v, 0, texture_area.size.y - 1)

                    color := texture_colors[texture_data_start + u + v * cast(u32)texture.width]
                    surface_color := &surface_colors[surface_data_start:][x]
                    surface_color^ = color_blend(surface_color, &color)
                }
            }
            surface_data_start += cast(u32)surface.width
        }
    } else if texture.channels == 1 {
        texture_colors := texture.data
        texture_data_start :=
            texture_area.position.x + texture_area.position.y * cast(u32)texture.width

        ab_perp := perp(b - a)
        bd_perp := perp(d - b)
        dc_perp := perp(c - d)
        ca_perp := perp(a - c)

        for y in 0 ..< height {
            for x in 0 ..< width {
                p := vec2_cast_f32(intersection.min + {x, y})

                ap := p - a
                bp := p - b
                dp := p - d
                cp := p - c

                if 0 < linalg.dot(ab_perp, ap) &&
                   0 < linalg.dot(bd_perp, bp) &&
                   0 < linalg.dot(dc_perp, dp) &&
                   0 < linalg.dot(ca_perp, cp) {
                    u := cast(u32)(linalg.dot(ap, x_axis) * inv_scale)
                    v := cast(u32)(linalg.dot(ap, y_axis) * inv_scale)
                    u = clamp(u, 0, texture_area.size.x - 1)
                    v = clamp(v, 0, texture_area.size.y - 1)

                    c := texture_colors[texture_data_start + u + v * cast(u32)texture.width]
                    color := Color {
                        r = c,
                        g = c,
                        b = c,
                        a = c,
                    }
                    surface_color := &surface_colors[surface_data_start:][x]
                    surface_color^ = color_blend(surface_color, &color)
                }
            }
            surface_data_start += cast(u32)surface.width
        }
    }
}
