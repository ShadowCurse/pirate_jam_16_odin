package game

import "../platform"

log_debug :: platform.log_debug
log_info :: platform.log_info
log_warn :: platform.log_warn
log_err :: platform.log_err
panic :: platform.panic
assert :: platform.assert

@(export)
runtime_main :: proc(
    entry_point: rawptr,
    memory: ^platform.Memory,
    surface_data: []u8,
    surface_width: u16,
    surface_height: u16,
    input_state: ^platform.InputState,
) -> rawptr {
    game := cast(^Game)entry_point
    if game == nil {
        log_info("Running the runtime for the first time")
        game_ptr, err := new(Game)
        assert(err == nil, "Cannot allocate game")
        game = game_ptr

        init_game(game)
    }


    surface := Texture {
        data     = surface_data,
        width    = surface_width,
        height   = surface_height,
        channels = 4,
    }

    {
        rectangle := Rectangle {
            position = {200, 200},
            size     = {100, 100},
        }
        color := Color {
            r = 255,
            g = 0,
            b = 128,
            a = 255,
        }
        draw_color_rectangle(&surface, &rectangle, color)
    }

    {
        area := TextureArea {
            position = {0, 0},
            size     = {cast(u32)game.sample_texture.width, cast(u32)game.sample_texture.height},
        }
        position := vec2_cast_f32(cast(Vec2i32)input_state.mouse_screen_positon)
        draw_texture(&surface, &game.sample_texture, &area, position)
    }

    return game
}

Game :: struct {
    sample_texture: Texture,
    font:           Font,
}

init_game :: proc(game: ^Game) {
    game.sample_texture = texture_load("./assets/table.png")
    game.font = font_load("./assets/NewRocker-Regular.ttf", 32.0)
}
