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
runtime_init :: proc(memory: ^platform.Memory, surface_width: u16, surface_height: u16) -> rawptr {
    log_info("Running the runtime for the first time")
    game_ptr, err := new(Game)
    assert(err == nil, "Cannot allocate game")
    game_init(game_ptr, surface_width, surface_height)
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
    camera_update_surface_size(&game.camera, cast(f32)surface_width, cast(f32)surface_height)
    game_update_input(game, input_state)
    game_state_animate(game, dt)
    defer render_commands_render(&game.render_commands, &surface, &game.camera)

    {
        position := Vec2{1280 / 2, 40}
        render_commands_add(
            &game.render_commands,
            &game.font,
            position,
            "FPS: %f.1 DT: %f.1",
            1 / dt,
            dt,
            center = true,
            in_world_space = false,
        )
    }

    if .MainMenu in game.state {
        game_main_menu(game)
    }
    if .InGame in game.state {
        game_in_game(game, dt)
    }

    area := TextureArea {
        position = {0, 0},
        size     = {cast(u32)game.hand_texture.width, cast(u32)game.hand_texture.height},
    }
    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.hand_texture,
            texture_area = area,
            texture_center = vec2_cast_f32(game.input.mouse_screen_positon),
        },
        in_world_space = false,
    )

    return game
}

Game :: struct {
    render_commands:            RenderCommands,
    table_texture:              Texture,
    ball_texture:               Texture,
    hand_texture:               Texture,
    button_normal_texture:      Texture,
    button_hover_texture:       Texture,
    font:                       Font,
    background:                 Soundtrack,
    hit:                        Soundtrack,
    audio:                      Audio,
    camera:                     Camera,
    balls:                      [9]Ball,
    borders:                    [4]Border,
    state:                      GlobalState,
    state_transition_animation: StateTransitionAnimation,
    mode:                       GameMode,
    input:                      GameInput,
}

GameInput :: struct {
    lmb:                  platform.KeyState,
    rmb:                  platform.KeyState,
    space:                platform.KeyState,
    mouse_screen_positon: Vec2i32,
    mouse_world_positon:  Vec2,
    mouse_delta:          Vec2i32,
}

game_update_input :: proc(game: ^Game, platform_input: ^platform.InputState) {
    game.input.lmb = platform_input.lmb
    game.input.rmb = platform_input.rmb
    game.input.space = platform_input.space
    game.input.mouse_screen_positon = cast(Vec2i32)platform_input.mouse_screen_positon
    game.input.mouse_world_positon = camera_to_world(
        &game.camera,
        vec2_cast_f32(game.input.mouse_screen_positon),
    )
    game.input.mouse_delta = cast(Vec2i32)platform_input.mouse_delta
}

GlobalStateInfo :: struct {
    state:    GlobalState,
    position: Vec2,
}

MAIN_MENU_STATE :: GlobalStateInfo{{.MainMenu}, {-1280 / 2 - 1280, -720 / 2}}
IN_GAME_STATE :: GlobalStateInfo{{.InGame}, {-1280 / 2, -720 / 2}}

States :: enum {
    MainMenu,
    InGame,
    InGameShop,
    Win,
    Lose,
}
GlobalState :: bit_set[States]

GameMode :: union {
    ClassicMode,
}

game_init :: proc(game: ^Game, surface_width: u16, surface_height: u16) {
    game.render_commands.commands_n = 0
    game.table_texture = texture_load("./assets/table.png")
    game.ball_texture = texture_load("./assets/ball.png")
    game.hand_texture = texture_load("./assets/player_hand.png")
    game.button_normal_texture = texture_load("./assets/button.png")
    game.button_hover_texture = texture_load("./assets/button_hover.png")
    game.font = font_load("./assets/NewRocker-Regular.ttf", 32.0)
    game.background = soundtrack_load("./assets/background.wav")
    game.hit = soundtrack_load("./assets/ball_hit.wav")
    half_surface_size := Vec2{cast(f32)surface_width / 2, cast(f32)surface_height / 2}
    game.camera = {half_surface_size, MAIN_MENU_STATE.position, 1.0}

    ball_grid_left_top := Vec2{-11 * 2, -11 * 2}
    for i in 0 ..< 3 {
        for j in 0 ..< 3 {
            game.balls[i * 3 + j] = ball_init(
                ball_grid_left_top + {cast(f32)j * 22, cast(f32)i * 22},
            )
        }
    }
    game.borders[0] = {
        position = {0, -272},
        collider = {{998, 50}},
    }
    game.borders[1] = {
        position = {0, 272},
        collider = {{998, 50}},
    }
    game.borders[2] = {
        position = {-500, 0},
        collider = {{50, 545}},
    }
    game.borders[3] = {
        position = {500, 0},
        collider = {{50, 545}},
    }

    game.state = {.MainMenu}
    game.state_transition_animation = {
        progress = 1.0,
    }

    game.mode = nil

    audio_init(&game.audio, 1.0)
    audio_unpause(&game.audio)
    // audio_play(&game.audio, game.background, 1.0, 1.0)
}

game_main_menu :: proc(game: ^Game) {
    position := Vec2{-1280, -80}
    render_commands_add(
        &game.render_commands,
        &game.font,
        position,
        "Main menu",
        center = true,
        in_world_space = true,
    )

    classic_mode := ui_draw_button(game, position + {0, 80}, "Classic")
    if classic_mode && game.input.lmb == .Pressed {
        game.mode = cm_new(game)
        game_state_change(game, IN_GAME_STATE)
    }
}

game_in_game :: proc(game: ^Game, dt: f32) {
    switch &m in game.mode {
    case ClassicMode:
        cm_update_and_draw(&m, game, dt)
    }
}

STATE_TRANSITION_ANIMATION_TIME :: 1
StateTransitionAnimation :: struct {
    new_state: GlobalState,
    velocity:  Vec2,
    progress:  f32,
}

game_state_change :: proc(game: ^Game, state_info: GlobalStateInfo) {
    log_info("Transitioning to global state: %w", state_info.state)
    game.state |= state_info.state
    velocity := (state_info.position - game.camera.position) / STATE_TRANSITION_ANIMATION_TIME
    game.state_transition_animation = {state_info.state, velocity, 0}
}

game_state_animate :: proc(game: ^Game, dt: f32) {
    if game.state_transition_animation.progress == 1.0 do return

    game.camera.position += game.state_transition_animation.velocity * dt
    game.state_transition_animation.progress += dt
    if 1.0 <= game.state_transition_animation.progress {
        game.state_transition_animation.progress = 1.0
        game.state = game.state_transition_animation.new_state
    }
}

BALL_RADIUS: f32 = 10
Ball :: struct {
    body:     PhysicsBody,
    collider: ColliderCircle,
}

ball_init :: proc(position: Vec2) -> Ball {
    return {
        body = {position = position, friction = 0.5, restitution = 0.8, inv_mass = 1.0},
        collider = {10},
    }
}

ball_draw :: proc(ball: ^Ball, game: ^Game) {
    area := TextureArea {
        position = {0, 0},
        size     = {cast(u32)game.ball_texture.width, cast(u32)game.ball_texture.height},
    }
    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.ball_texture,
            texture_area = area,
            texture_center = ball.body.position,
            ignore_alpha = false,
            tint = true,
            tint_color = Color{r = 255, a = 128},
        },
    )
}

Border :: struct {
    position: Vec2,
    collider: ColliderRectangle,
}

border_draw :: proc(border: ^Border, game: ^Game) {
    rectangle := Rectangle {
        center = border.position,
        size   = border.collider.size * game.camera.scale,
    }
    color := Color {
        r = 38,
        g = 249,
        b = 74,
        a = 255,
    }
    render_commands_add(&game.render_commands, DrawColorRectangleCommand{rectangle, color})
}
