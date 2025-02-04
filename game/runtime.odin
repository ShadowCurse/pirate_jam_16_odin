package game

@(export)
runtime_main :: proc(memory: ^Memory, surface_texture: ^Texture, input_state: ^InputState) {
    rectangle := Rectangle {
        position = vec2_cast(input_state.mouse_screen_positon),
        size     = {100, 100},
    }
    color := Color {
        r = 255,
        g = 0,
        b = 128,
        a = 255,
    }
    draw_color_rectangle(surface_texture, &rectangle, color)
}
