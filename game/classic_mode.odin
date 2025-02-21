package game

import "core:math"
import "core:math/linalg"

BALL_NOT_SELECTED :: 255
ClassicMode :: struct {
    player:        PlayerInfo,
    opponent:      PlayerInfo,
    turn_owner:    TurnOwner,
    turn_state:    TurnState,
    selected_ball: u8,
    balls:         #soa[PLAYER_BALL_COUNT * 2]Ball,
    borders:       #soa[4]Border,
}

TurnOwner :: enum {
    Player,
    Opponent,
}

TurnState :: enum {
    NotTaken,
    Taken,
}

PLAYER_BALL_COUNT :: 15
PlayerInfo :: struct {
    hp:            i32,
    souls:         i32,
    selected_item: u8,
    items:         [5]Item,
    selected_cue:  u8,
    cues:          [2]Cue,
}

ITEM_WIDTH :: 53
ITEM_GAP :: 9
PLAYER_ITEMS_BACKGROUND :: Vec2{0, 320}
OPPONENT_ITEMS_BACKGROUND :: Vec2{0, -320}
ItemTag :: enum {
    Invalid,
    BallSpiky,
}
Item :: struct {
    tag:      ItemTag,
    position: Vec2,
}

CUE_TARGET_OFFSET :: 50
CUE_RETURN_TO_STORAGE_SPEED :: 500
CUE_RETURN_TO_STORAGE_ANGLE_SPEED :: 3
PLAYER_CUES_BACKGROUND :: Vec2{-570, 0}
OPPONENT_CUES_BACKGROUND :: Vec2{570, 0}
Cue :: struct {
    storage_position: Vec2,
    position:         Vec2,
    storage_rotation: f32,
    rotation:         f32,
    texture:          ^Texture,
    width:            f32,
    height:           f32,
}


BALL_RADIUS: f32 = 10
Ball :: struct {
    body:     PhysicsBody,
    collider: ColliderCircle,
}

Border :: struct {
    position: Vec2,
    collider: ColliderRectangle,
}

cm_new :: proc(game: ^Game) -> ClassicMode {
    mode := ClassicMode{}
    mode.player = {
        cues = {
            {
                storage_position = PLAYER_CUES_BACKGROUND + cm_cue_storage_offset(0),
                position = PLAYER_CUES_BACKGROUND + cm_cue_storage_offset(0),
                texture = &game.cue_default_texture,
                width = 10,
                height = 512,
            },
            {
                storage_position = PLAYER_CUES_BACKGROUND + cm_cue_storage_offset(1),
                position = PLAYER_CUES_BACKGROUND + cm_cue_storage_offset(1),
                texture = &game.cue_default_texture,
                width = 10,
                height = 512,
            },
        },
    }
    mode.opponent = {
        cues = {
            {
                storage_position = OPPONENT_CUES_BACKGROUND + cm_cue_storage_offset(0),
                position = OPPONENT_CUES_BACKGROUND + cm_cue_storage_offset(0),
                storage_rotation = math.PI,
                rotation = math.PI,
                texture = &game.cue_default_texture,
                width = 10,
                height = 512,
            },
            {
                storage_position = OPPONENT_CUES_BACKGROUND + cm_cue_storage_offset(1),
                position = OPPONENT_CUES_BACKGROUND + cm_cue_storage_offset(1),
                storage_rotation = math.PI,
                rotation = math.PI,
                texture = &game.cue_default_texture,
                width = 10,
                height = 512,
            },
        },
    }
    cm_init_items(mode.player.items[:], PLAYER_ITEMS_BACKGROUND)
    cm_init_items(mode.opponent.items[:], OPPONENT_ITEMS_BACKGROUND)
    mode.turn_owner = .Player
    mode.turn_state = .NotTaken

    PLAYER_TIP_POSITION :: Vec2{-200, 0}
    PLAYER_DIRECTION :: Vec2{-1, 0}
    OPPONENT_TIP_POSITION :: Vec2{200, 0}
    OPPONENT_DIRECTION :: Vec2{1, 0}

    for &collider in mode.balls.collider {
        collider = {BALL_RADIUS}
    }
    for &body in mode.balls.body {
        body = PhysicsBody {
            friction    = 0.5,
            restitution = 0.8,
            inv_mass    = 1.0,
        }
    }

    player_balls := mode.balls.body[:PLAYER_BALL_COUNT]
    opponent_balls := mode.balls.body[PLAYER_BALL_COUNT:]
    cm_position_balls(player_balls, PLAYER_TIP_POSITION, PLAYER_DIRECTION)
    cm_position_balls(opponent_balls, OPPONENT_TIP_POSITION, OPPONENT_DIRECTION)

    mode.selected_ball = BALL_NOT_SELECTED

    mode.borders[0] = {
        position = {0, -272},
        collider = {{998, 50}},
    }
    mode.borders[1] = {
        position = {0, 272},
        collider = {{998, 50}},
    }
    mode.borders[2] = {
        position = {-500, 0},
        collider = {{50, 545}},
    }
    mode.borders[3] = {
        position = {500, 0},
        collider = {{50, 545}},
    }

    return mode
}

cm_init_items :: proc(items: []Item, position: Vec2) {
    d: f32 = (ITEM_WIDTH + ITEM_GAP) / 2
    left_item := position - {d * 4, 0}
    for &item, i in items {
        item.tag = .BallSpiky
        item.position = left_item + {d * 2, 0} * cast(f32)i
    }
}

cm_position_balls :: proc(bodies: []PhysicsBody, tip_position: Vec2, direction: Vec2) {
    GAP :: 3
    // rotate direction 30 degrees for balls in one layer
    // -30 to get to the next layer
    angle: f32 = math.PI / 6.0
    direction_next := linalg.matrix2_rotate(angle) * direction
    direction_next_layer := linalg.matrix2_rotate(-angle) * direction
    origin_position := tip_position + direction * BALL_RADIUS
    index := 0
    for layer in 0 ..< 5 {
        for i in 0 ..< (5 - layer) {
            bodies[index].position =
                origin_position + direction_next * cast(f32)i * (BALL_RADIUS * 2.0 + GAP)
            index += 1
        }
        origin_position = origin_position + direction_next_layer * (BALL_RADIUS * 2.0 + GAP)
    }
}

cm_update_and_draw :: proc(mode: ^ClassicMode, game: ^Game, dt: f32) {
    process_physics(
        mode.balls.collider[:],
        mode.balls.body[:],
        mode.borders.collider[:],
        mode.borders.position[:],
        dt,
    )

    old_selection := mode.selected_ball
    cm_select_ball(mode, game)
    if mode.selected_ball != BALL_NOT_SELECTED {
        cm_cue_aim(
            &mode.player.cues[0],
            mode.balls[mode.selected_ball].body.position,
            game.input.mouse_world_positon,
        )
    } else {
        cm_cue_store(&mode.player.cues[0], dt)
    }

    if old_selection != mode.selected_ball {
        if old_selection != BALL_NOT_SELECTED {
            from_mouse := mode.balls[old_selection].body.position - game.input.mouse_world_positon
            mode.balls[old_selection].body.velocity = from_mouse * 100 * dt
        }
    }

    cm_draw_table(game)
    cm_draw_balls(mode, game)
    cm_draw_cues(mode, game)
    cm_draw_borders(mode, game)
    cm_draw_items(mode, game)

    back := ui_draw_button(game, {500, 320}, "Back")
    if back && game.input.lmb == .Pressed do game_state_change(game, MAIN_MENU_STATE)
}

cm_draw_table :: proc(game: ^Game) {
    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.table_texture,
            texture_area = texture_full_area(&game.table_texture),
            texture_center = {},
            ignore_alpha = true,
        },
    )
}

cm_select_ball :: proc(mode: ^ClassicMode, game: ^Game) {
    if game.input.lmb == .Pressed do mode.selected_ball = BALL_NOT_SELECTED
    for ball_body, i in mode.balls.body {
        if cm_ball_hovered(ball_body.position, game.input.mouse_world_positon) {
            if game.input.lmb == .Pressed {
                mode.selected_ball = cast(u8)i
                return
            }
        }
    }
}

cm_ball_hovered :: proc(ball_position: Vec2, mouse_position: Vec2) -> bool {
    return linalg.length2(mouse_position - ball_position) < BALL_RADIUS * BALL_RADIUS
}


cm_draw_balls :: proc(mode: ^ClassicMode, game: ^Game) {
    for ball_body, i in mode.balls.body {
        tint_color := Color {
            r = 255,
            a = 128,
        }
        if mode.selected_ball == cast(u8)i {
            tint_color = Color {
                b = 128,
                a = 128,
            }
        }
        render_commands_add(
            &game.render_commands,
            DrawTextureCommand {
                texture = &game.ball_texture,
                texture_area = texture_full_area(&game.ball_texture),
                texture_center = ball_body.position,
                ignore_alpha = false,
                tint = true,
                tint_color = tint_color,
            },
        )
    }
}

cm_cue_storage_offset :: proc(cue_index: u8) -> Vec2 {
    OFFSET :: Vec2{30, 0}
    if cue_index == 0 do return -OFFSET
    else do return OFFSET
    return {}
}

cm_cue_aim_position_rotation :: proc(
    cue: ^Cue,
    target_position: Vec2,
    mouse_position: Vec2,
) -> (
    Vec2,
    f32,
) {
    to_mouse := linalg.normalize(mouse_position - target_position)
    new_cue_position := target_position + to_mouse * (CUE_TARGET_OFFSET + cue.height / 2)
    d_y := linalg.dot(to_mouse, Vec2{0, 1})
    d_x := linalg.dot(to_mouse, Vec2{1, 0})
    angle := math.acos(d_y)
    if 0 < d_x {
        angle = 2 * math.PI - angle
    }
    return new_cue_position, angle
}

cm_cue_store :: proc(cue: ^Cue, dt: f32) {
    d := cue.storage_position - cue.position
    d_len := linalg.length(d)
    if d_len < 5 {
        cue.position = cue.storage_position
    } else {
        cue.position += d / d_len * CUE_RETURN_TO_STORAGE_SPEED * dt
    }

    rd := cue.rotation - cue.storage_rotation
    if abs(rd) < 0.1 || cue.storage_rotation + 2 * math.PI - 0.1 < abs(rd) {
        cue.rotation = cue.storage_rotation
    } else {
        if math.PI < rd {
            rd = -2 * math.PI + rd
        }
        if 0 < rd {
            cue.rotation -= CUE_RETURN_TO_STORAGE_ANGLE_SPEED * dt
        } else {
            cue.rotation += CUE_RETURN_TO_STORAGE_ANGLE_SPEED * dt
        }
    }
}

cm_cue_aim :: proc(cue: ^Cue, target_position: Vec2, mouse_position: Vec2) {
    p, r := cm_cue_aim_position_rotation(cue, target_position, mouse_position)
    cue.position = p
    cue.rotation = r
}

cm_cue_draw :: proc(cue: ^Cue, game: ^Game) {
    render_commands_add(
        &game.render_commands,
        DrawTextureScaleRotate {
            texture = &game.cue_default_texture,
            texture_area = texture_full_area(&game.cue_default_texture),
            texture_center = cue.position,
            scale = 1,
            rotation = cue.rotation,
            ignore_alpha = false,
        },
    )
}

cm_draw_cues :: proc(mode: ^ClassicMode, game: ^Game) {
    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.cue_background_texture,
            texture_area = texture_full_area(&game.cue_background_texture),
            texture_center = PLAYER_CUES_BACKGROUND,
            ignore_alpha = true,
        },
    )

    for &cue in mode.player.cues {
        cm_cue_draw(&cue, game)
    }

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.cue_background_texture,
            texture_area = texture_full_area(&game.cue_background_texture),
            texture_center = OPPONENT_CUES_BACKGROUND,
            ignore_alpha = true,
        },
    )

    for &cue in mode.opponent.cues {
        cm_cue_draw(&cue, game)
    }
}

cm_draw_items :: proc(mode: ^ClassicMode, game: ^Game) {
    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.items_background_texture,
            texture_area = texture_full_area(&game.items_background_texture),
            texture_center = PLAYER_ITEMS_BACKGROUND,
            ignore_alpha = true,
        },
    )

    for item, i in mode.player.items {
        if item.tag != .Invalid {
            render_commands_add(
                &game.render_commands,
                DrawTextureCommand {
                    texture = &game.item_ball_spiky_texture,
                    texture_area = texture_full_area(&game.item_ball_spiky_texture),
                    texture_center = item.position,
                    ignore_alpha = false,
                },
            )
        }
    }

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.items_background_texture,
            texture_area = texture_full_area(&game.items_background_texture),
            texture_center = OPPONENT_ITEMS_BACKGROUND,
            ignore_alpha = true,
        },
    )

    for item, i in mode.opponent.items {
        if item.tag != .Invalid {
            render_commands_add(
                &game.render_commands,
                DrawTextureCommand {
                    texture = &game.item_ball_spiky_texture,
                    texture_area = texture_full_area(&game.item_ball_spiky_texture),
                    texture_center = item.position,
                    ignore_alpha = false,
                },
            )
        }
    }
}

cm_draw_borders :: proc(mode: ^ClassicMode, game: ^Game) {
    for border in mode.borders {
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
}
