package game

@(export)
runtime_main :: proc(
    entry_point: rawptr,
    memory: ^Memory,
    surface_texture: ^Texture,
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

    return game
}

Game :: struct {}

init_game :: proc(game: ^Game) {
}
