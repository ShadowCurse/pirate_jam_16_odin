package game

import "../platform"
import "core:math/linalg"

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

    process_physics(game, dt)

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
        render_commands_add(
            &game.render_commands,
            DrawTextureCommand {
                texture = &game.table_texture,
                texture_area = area,
                texture_center = position,
                ignore_alpha = true,
            },
        )
    }

    for &border in game.borders {
        border_draw(&border, game)
    }

    if input_state.rmb == .Pressed {
        for &ball in game.balls {
            ball_screen_space := camera_to_screen(&game.camera, ball.body.position)
            to_ball :=
                ball_screen_space - vec2_cast_f32(cast(Vec2i32)input_state.mouse_screen_positon)
            ball.body.acceleration = to_ball * 500
        }
    } else {
        for &ball in game.balls {
            ball.body.acceleration = {}
        }
    }

    for &ball in game.balls {
        ball_draw(&ball, game)
    }

    {
        area := TextureArea {
            position = {0, 0},
            size     = {cast(u32)game.hand_texture.width, cast(u32)game.hand_texture.height},
        }
        position := vec2_cast_f32(cast(Vec2i32)input_state.mouse_screen_positon)
        render_commands_add(
            &game.render_commands,
            DrawTextureCommand {
                texture = &game.hand_texture,
                texture_area = area,
                texture_center = position,
            },
            in_world_space = false,
        )
    }

    {
        position := Vec2{cast(f32)surface_width / 2, 40}
        draw_text(
            &game.render_commands,
            &game.font,
            position,
            "FPS: %f.1 DT: %f.1",
            1 / dt,
            dt,
            center = true,
        )
    }

    {
        right_volume := cast(f32)input_state.mouse_screen_positon.x / cast(f32)surface_width
        left_volume := 1 - right_volume
        if input_state.lmb == .Pressed {
            audio_play(&game.audio, game.hit, left_volume, right_volume)
        }
    }

    render_commands_render(&game.render_commands, &surface, &game.camera)

    return game
}

Game :: struct {
    render_commands: RenderCommands,
    table_texture:   Texture,
    ball_texture:    Texture,
    hand_texture:    Texture,
    font:            Font,
    background:      Soundtrack,
    hit:             Soundtrack,
    audio:           Audio,
    camera:          Camera,
    balls:           [9]Ball,
    borders:         [4]Border,
}

game_init :: proc(game: ^Game, surface_width: u16, surface_height: u16) {
    game.render_commands.commands_n = 0
    game.table_texture = texture_load("./assets/table.png")
    game.ball_texture = texture_load("./assets/ball.png")
    game.hand_texture = texture_load("./assets/player_hand.png")
    game.font = font_load("./assets/NewRocker-Regular.ttf", 32.0)
    game.background = soundtrack_load("./assets/background.wav")
    game.hit = soundtrack_load("./assets/ball_hit.wav")
    half_surface_size := Vec2{cast(f32)surface_width / 2, cast(f32)surface_height / 2}
    game.camera = {half_surface_size, -half_surface_size, 1.0}

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

    audio_init(&game.audio, 1.0)
    audio_unpause(&game.audio)
    // audio_play(&game.audio, game.background, 1.0, 1.0)
}

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

ColliderRectangle :: struct {
    size: Vec2,
}

ColliderCircle :: struct {
    radius: f32,
}

PhysicsBody :: struct {
    acceleration: Vec2,
    velocity:     Vec2,
    position:     Vec2,
    friction:     f32,
    restitution:  f32,
    inv_mass:     f32,
}

Collision :: struct {
    position: Vec2,
    normal:   Vec2,
}

collision_circle_rectangle :: proc(
    circle: ColliderCircle,
    circle_position: Vec2,
    rectangle: ColliderRectangle,
    rectangle_position: Vec2,
) -> (
    Collision,
    bool,
) {
    rectangle_left := rectangle_position.x - rectangle.size.x / 2
    rectangle_right := rectangle_position.x + rectangle.size.x / 2
    rectangle_top := rectangle_position.y - rectangle.size.y / 2
    rectangle_bottom := rectangle_position.y + rectangle.size.y / 2
    p := Vec2 {
        min(max(circle_position.x, rectangle_left), rectangle_right),
        min(max(circle_position.y, rectangle_top), rectangle_bottom),
    }

    p_to_circle := circle_position - p
    if linalg.length2(p_to_circle) < circle.radius * circle.radius {
        normal := circle_position - p
        if (rectangle_left < p.x &&
               p.x < rectangle_right &&
               rectangle_top < p.y &&
               p.y < rectangle_bottom) {
            distance_left := p.x - rectangle_left
            distance_right := rectangle_right - p.x
            distance_top := p.y - rectangle_top
            distance_bottom := rectangle_bottom - p.y
            m := min(distance_left, distance_right, distance_top, distance_bottom)
            switch {
            case m == distance_left:
                p.x = rectangle_left
            case m == distance_right:
                p.x = rectangle_right
            case m == distance_top:
                p.y = rectangle_top
            case m == distance_bottom:
                p.y = rectangle_bottom
            }
            normal = p - circle_position
        }
        normal = linalg.normalize(normal)
        return {p, normal}, true
    }
    return {}, false
}

collision_circle_circle :: proc(
    circle1: ColliderCircle,
    circle1_position: Vec2,
    circle2: ColliderCircle,
    circle2_position: Vec2,
) -> (
    Collision,
    bool,
) {
    to_circle1 := circle1_position - circle2_position
    distance := linalg.length(to_circle1)
    if distance < circle1.radius + circle2.radius {
        to_circle1_norm := linalg.normalize(to_circle1)
        p := circle2_position + to_circle1_norm * circle2.radius
        normal := to_circle1_norm
        return {p, normal}, true

    }
    return {}, false
}

resolve_ball_border_collision :: proc(ball_body: ^PhysicsBody, collision: ^Collision) {
    contact_velocity := linalg.dot(ball_body.velocity, collision.normal)
    // If velocities are already in opposite directions,
    // do nothing
    if 0 < contact_velocity do return

    impulse_magnitude := -(1.0 + ball_body.restitution) * contact_velocity / ball_body.inv_mass
    impulse := collision.normal * impulse_magnitude
    ball_body.velocity += impulse * ball_body.inv_mass
}

resolve_ball_ball_collision :: proc(
    ball1: ^PhysicsBody,
    ball2: ^PhysicsBody,
    collision: ^Collision,
) {
    relative_velocity := ball1.velocity - ball2.velocity
    contact_velocity := linalg.dot(relative_velocity, collision.normal)
    // If velocities are already in opposite directions,
    // do nothing
    if 0 < contact_velocity do return

    min_restitution := min(ball1.restitution, ball2.restitution)
    impulse_magnitude :=
        -(1.0 + min_restitution) * contact_velocity / (ball1.inv_mass + ball2.inv_mass)
    impulse := collision.normal * impulse_magnitude

    ball1.velocity = ball1.velocity + impulse * ball1.inv_mass
    ball2.velocity = ball2.velocity + -impulse * ball2.inv_mass
}

physics_body_move :: proc(body: ^PhysicsBody, dt: f32) {
    body.acceleration += -body.velocity * body.friction
    body.position = body.position + body.velocity * dt + body.acceleration * 0.5 * dt * dt
    body.velocity += body.acceleration * dt
}

CollisionInfo :: struct {
    ball_idx:   u32,
    other_type: enum {
        Ball,
        Border,
    },
    other_idx:  u32,
    collision:  Collision,
}

process_physics :: proc(game: ^Game, dt: f32) {
    dt := dt / 4
    for _ in 0 ..< 4 {
        for &ball in game.balls {
            physics_body_move(&ball.body, dt)
        }

        collision_infoss, _ := make(
            [dynamic]CollisionInfo,
            0,
            len(game.borders) * len(game.balls) * len(game.balls),
            allocator = context.temp_allocator,
        )
        for &ball, i in game.balls {
            for &ball2, j in game.balls[i + 1:] {
                collision, hit := collision_circle_circle(
                    ball.collider,
                    ball.body.position,
                    ball2.collider,
                    ball2.body.position,
                )
                if hit {
                    append(
                        &collision_infoss,
                        CollisionInfo{cast(u32)i, .Ball, cast(u32)(i + 1 + j), collision},
                    )
                }
            }
            for &border in game.borders {
                collision, hit := collision_circle_rectangle(
                    ball.collider,
                    ball.body.position,
                    border.collider,
                    border.position,
                )
                if hit do append(&collision_infoss, CollisionInfo{cast(u32)i, .Border, 0, collision})
            }
        }
        for &info in collision_infoss {
            ball := &game.balls[info.ball_idx]
            switch info.other_type {
            case .Ball:
                ball2 := &game.balls[info.other_idx]
                resolve_ball_ball_collision(&ball.body, &ball2.body, &info.collision)
            case .Border:
                resolve_ball_border_collision(&ball.body, &info.collision)
            }
        }
    }
}
