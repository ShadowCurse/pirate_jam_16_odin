package game

import "core:math"
import "core:math/linalg"

ClassicMode :: struct {
    player:     PlayerInfo,
    opponent:   PlayerInfo,
    turn_owner: TurnOwner,
    turn_state: TurnState,
    balls:      #soa[PLAYER_BALL_COUNT * 2]Ball,
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

Item :: struct {}
Cue :: struct {}

cm_new :: proc(game: ^Game) -> ClassicMode {
    mode := ClassicMode{}
    mode.player = {}
    mode.opponent = {}
    mode.turn_owner = .Player
    mode.turn_state = .NotTaken

    PLAYER_TIP_POSITION :: Vec2{-200, 0}
    PLAYER_DIRECTION :: Vec2{-1, 0}
    OPPONENT_TIP_POSITION :: Vec2{200, 0}
    OPPONENT_DIRECTION :: Vec2{1, 0}
    player_balls := mode.balls.body[:PLAYER_BALL_COUNT]
    opponent_balls := mode.balls.body[PLAYER_BALL_COUNT:]

    cm_position_balls(player_balls, PLAYER_TIP_POSITION, PLAYER_DIRECTION)
    cm_position_balls(opponent_balls, OPPONENT_TIP_POSITION, OPPONENT_DIRECTION)

    return mode
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
    cm_draw_table(game)
    cm_draw_balls(mode, game)
    cm_draw_cues(mode, game)

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

cm_draw_balls :: proc(mode: ^ClassicMode, game: ^Game) {
    for ball_body in mode.balls.body {
        render_commands_add(
            &game.render_commands,
            DrawTextureCommand {
                texture = &game.ball_texture,
                texture_area = texture_full_area(&game.ball_texture),
                texture_center = ball_body.position,
                ignore_alpha = false,
                tint = true,
                tint_color = Color{r = 255, a = 128},
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

cm_draw_cues :: proc(mode: ^ClassicMode, game: ^Game) {
    PLAYER_CUES_BACKGROUND :: Vec2{-570, 0}
    OPPONENT_CUES_BACKGROUND :: Vec2{570, 0}

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.cue_background_texture,
            texture_area = texture_full_area(&game.cue_background_texture),
            texture_center = PLAYER_CUES_BACKGROUND,
            ignore_alpha = true,
        },
    )

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.cue_default_texture,
            texture_area = texture_full_area(&game.cue_default_texture),
            texture_center = PLAYER_CUES_BACKGROUND + cm_cue_storage_offset(0),
            ignore_alpha = false,
        },
    )

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.cue_default_texture,
            texture_area = texture_full_area(&game.cue_default_texture),
            texture_center = PLAYER_CUES_BACKGROUND + cm_cue_storage_offset(1),
            ignore_alpha = false,
        },
    )

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.cue_background_texture,
            texture_area = texture_full_area(&game.cue_background_texture),
            texture_center = OPPONENT_CUES_BACKGROUND,
            ignore_alpha = true,
        },
    )

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.cue_default_texture,
            texture_area = texture_full_area(&game.cue_default_texture),
            texture_center = OPPONENT_CUES_BACKGROUND + cm_cue_storage_offset(0),
            ignore_alpha = false,
        },
    )

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.cue_default_texture,
            texture_area = texture_full_area(&game.cue_default_texture),
            texture_center = OPPONENT_CUES_BACKGROUND + cm_cue_storage_offset(1),
            ignore_alpha = false,
        },
    )
}
