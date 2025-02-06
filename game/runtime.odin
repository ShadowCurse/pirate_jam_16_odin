package game

@(export)
runtime_main :: proc(
    entry_point: rawptr,
    memory: ^Memory,
    surface: ^Texture,
    input_state: ^InputState,
) -> rawptr {
    game := cast(^Game)entry_point
    if game == nil {
        log_info("Running the runtime for the first time")
        game_ptr, err := new(Game)
        assert(err == nil, "Cannot allocate game")
        game = game_ptr

        init_game(game)
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
        draw_color_rectangle(surface, &rectangle, color)
    }

    {
        area := TextureArea {
            position = {0, 0},
            size     = {game.sample_texture.width, game.sample_texture.height},
        }
        position := vec2_cast_f32(input_state.mouse_screen_positon)
        draw_texture(surface, &game.sample_texture, &area, position)
    }

    return game
}

Game :: struct {
    sample_texture: Texture,
}

init_game :: proc(game: ^Game) {
    game.sample_texture = texture_load("./assets/table.png")
}
