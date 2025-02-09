package game

import "../platform"

log_debug :: platform.log_debug
log_info :: platform.log_info
log_warn :: platform.log_warn
log_err :: platform.log_err
panic :: platform.panic
assert :: platform.assert

Audio :: platform.Audio
audio_init :: platform.audio_init
audio_pause :: platform.audio_pause
audio_unpause :: platform.audio_unpause
audio_play :: platform.audio_play
audio_is_playing :: platform.audio_is_playing
audio_set_volume :: platform.audio_set_volume

Soundtrack :: platform.Soundtrack
soundtrack_load :: platform.soundtrack_load

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
            center = {200, 200},
            size   = {100, 100},
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
            size     = {cast(u32)game.table_texture.width, cast(u32)game.table_texture.height},
        }
        position := Vec2{cast(f32)surface_width / 2, cast(f32)surface_height / 2}
        draw_texture(&surface, &game.table_texture, &area, position)
    }

    // {
    //     area := TextureArea {
    //         position = {0, 0},
    //         size     = {cast(u32)game.font.texture.width, cast(u32)game.font.texture.height},
    //     }
    //     position := Vec2{400, 400}
    //     draw_texture(&surface, &game.font.texture, &area, position, ignore_alpha = false)
    // }

    {
        area := TextureArea {
            position = {0, 0},
            size     = {cast(u32)game.hand_texture.width, cast(u32)game.hand_texture.height},
        }
        position := vec2_cast_f32(cast(Vec2i32)input_state.mouse_screen_positon)
        draw_texture(&surface, &game.hand_texture, &area, position, ignore_alpha = false)
    }

    {
        position := Vec2{cast(f32)surface_width / 2, cast(f32)surface_height / 2}
        draw_text(
            &surface,
            &game.font,
            position,
            "}})}})}})}})}})}})}})}})}})}})}})",
            center = true,
        )
    }
    {
        position := Vec2{cast(f32)surface_width / 2, cast(f32)surface_height / 2 + 40.0}
        draw_text(
            &surface,
            &game.font,
            position,
            "}})}})}})}})}})}})}})}})}})}})}})",
            center = true,
            kerning = false,
        )
    }

    {
        right_volume := cast(f32)input_state.mouse_screen_positon.x / cast(f32)surface_width
        left_volume := 1 - right_volume
        if input_state.lmb == .Pressed {
            audio_play(&game.audio, game.hit, left_volume, right_volume)
        }
    }

    return game
}

Game :: struct {
    table_texture: Texture,
    hand_texture:  Texture,
    font:          Font,
    background:    Soundtrack,
    hit:           Soundtrack,
    audio:         Audio,
}

init_game :: proc(game: ^Game) {
    game.table_texture = texture_load("./assets/table.png")
    game.hand_texture = texture_load("./assets/player_hand.png")
    game.font = font_load("./assets/NewRocker-Regular.ttf", 32.0)
    game.background = soundtrack_load("./assets/background.wav")
    game.hit = soundtrack_load("./assets/ball_hit.wav")

    audio_init(&game.audio, 1.0)
    audio_unpause(&game.audio)
    audio_play(&game.audio, game.background, 1.0, 1.0)
}
