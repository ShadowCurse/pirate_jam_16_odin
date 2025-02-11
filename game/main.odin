package game

import "../platform"
import "core:fmt"

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
runtime_init :: proc(memory: ^platform.Memory, surface_width: u16, surface_height: u16) -> rawptr {
    log_info("Running the runtime for the first time")
    game_ptr, err := new(Game)
    assert(err == nil, "Cannot allocate game")
    init_game(game_ptr, surface_width, surface_height)
    return game_ptr
}

@(export)
runtime_run :: proc(
    dt_ns: u64,
    entry_point: rawptr,
    memory: ^platform.Memory,
    surface_data: []u8,
    surface_width: u16,
    surface_height: u16,
    input_state: ^platform.InputState,
) -> rawptr {
    dt := cast(f32)dt_ns / 1000_000_000
    game := cast(^Game)entry_point

    surface := Texture {
        data     = surface_data,
        width    = surface_width,
        height   = surface_height,
        channels = 4,
    }

    @(static) camera_enabled: bool = false
    if camera_enabled || input_state.lmb == .Pressed {
        camera_enabled = true
        game.camera.position += vec2_cast_f32(cast(Vec2i32)input_state.mouse_delta)
    }
    if input_state.lmb == .Released {
        camera_enabled = false
    }

    {
        area := TextureArea {
            position = {0, 0},
            size     = {cast(u32)game.table_texture.width, cast(u32)game.table_texture.height},
        }
        position := Vec2{}
        sp := camera_to_screen(&game.camera, position)
        draw_texture(&surface, &game.table_texture, &area, sp, ignore_alpha = true)
    }

    {
        area := TextureArea {
            position = {0, 0},
            size     = {cast(u32)game.hand_texture.width, cast(u32)game.hand_texture.height},
        }
        position := vec2_cast_f32(cast(Vec2i32)input_state.mouse_screen_positon)
        draw_texture(&surface, &game.hand_texture, &area, position, ignore_alpha = false)
    }

    {
        position := Vec2{cast(f32)surface_width / 2, 40}
        draw_text(&surface, &game.font, position, "FPS: %f.1 DT: %f.1", 1 / dt, dt, center = true)
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
    camera:        Camera,
}

init_game :: proc(game: ^Game, surface_width: u16, surface_height: u16) {
    game.table_texture = texture_load("./assets/table.png")
    game.hand_texture = texture_load("./assets/player_hand.png")
    game.font = font_load("./assets/NewRocker-Regular.ttf", 32.0)
    game.background = soundtrack_load("./assets/background.wav")
    game.hit = soundtrack_load("./assets/ball_hit.wav")
    half_surface_size := Vec2{cast(f32)surface_width / 2, cast(f32)surface_height / 2}
    game.camera = {half_surface_size, -half_surface_size, 0.3}

    audio_init(&game.audio, 1.0)
    audio_unpause(&game.audio)
    // audio_play(&game.audio, game.background, 1.0, 1.0)
}
