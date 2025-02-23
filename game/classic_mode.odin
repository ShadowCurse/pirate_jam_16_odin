package game

import "core:math"
import "core:math/linalg"

BALL_NOT_SELECTED :: 255
ClassicMode :: struct {
    player:                    PlayerInfo,
    opponent:                  PlayerInfo,
    turn_owner:                TurnOwner,
    turn_state:                TurnState,
    selected_ball:             u8,
    balls:                     #soa[PLAYER_BALL_COUNT * 2]Ball,
    borders:                   #soa[4]Border,
    shop_items:                [3]Item,
    cue_adjust_position:       Vec2,
    cue_adjust_mouse_position: Vec2,
    cue_hit_animation:         SmoothStepAnimation,
    item_use_dashed_line:      UiDashedLine,
}

TurnOwner :: enum {
    Player,
    Opponent,
}

TurnState :: enum {
    NotTaken,
    Aim,
    StrengthAdjust,
    Hit,
    Taken,
}

PLAYER_BALL_COUNT :: 15
ITEM_NOT_SELECTED :: 254
PlayerInfo :: struct {
    hp:            i32,
    souls:         i32,
    selected_item: u8,
    items:         [5]Item,
    selected_cue:  u8,
    cues:          [2]Cue,
}

cm_player_info_add_item :: proc(player_info: ^PlayerInfo, tag: ItemTag) -> bool {
    for &item in player_info.items {
        if item.tag == .Invalid {
            item.tag = tag
            return true
        }
    }
    log_warn("Trying to add more items than allowed")
    return false
}

ITEM_SIZE :: 53
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
    scope:            bool,
    silencer:         bool,
    rocket_booster:   bool,
}


BALL_RADIUS: f32 = 10
Ball :: struct {
    body:     PhysicsBody,
    collider: ColliderCircle,
    hp:       f32,
    max_hp:   f32,
    damage:   f32,
    heal:     f32,
    armor:    f32,
}

Border :: struct {
    position: Vec2,
    collider: ColliderRectangle,
}

cm_new :: proc(game: ^Game) -> ClassicMode {
    mode := ClassicMode{}
    mode.player = {
        hp    = 11,
        souls = 69,
        cues  = {
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
        hp    = 22,
        souls = 322,
        cues  = {
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

    mode.shop_items = {
        {.BallSpiky, in_state_position(IN_GAME_SHOP_STATE, {-400, 0})},
        {.BallSpiky, in_state_position(IN_GAME_SHOP_STATE, {})},
        {.BallSpiky, in_state_position(IN_GAME_SHOP_STATE, {400, 0})},
    }

    return mode
}

cm_init_items :: proc(items: []Item, position: Vec2) {
    d: f32 = (ITEM_SIZE + ITEM_GAP) / 2
    left_item := position - {d * 4, 0}
    for &item, i in items {
        item.tag = .Invalid
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

cm_in_game :: proc(mode: ^ClassicMode, game: ^Game, dt: f32) {
    switch mode.turn_state {
    case .NotTaken:
        cm_select_ball(mode, game)
        cm_use_item(mode, game, dt)
        if mode.selected_ball != BALL_NOT_SELECTED do mode.turn_state = .Aim
    case .Aim:
        cm_cue_aim(
            &mode.player.cues[0],
            mode.balls[mode.selected_ball].body.position,
            game.input.mouse_world_positon,
        )
        if game.input.lmb == .Pressed {
            mode.turn_state = .StrengthAdjust
            mode.cue_adjust_position = mode.player.cues[0].position
            mode.cue_adjust_mouse_position = game.input.mouse_world_positon
        }
    case .StrengthAdjust:
        cm_cue_adjust(
            &mode.player.cues[0],
            mode.cue_adjust_position,
            mode.balls[mode.selected_ball].body.position,
            mode.cue_adjust_mouse_position,
            game.input.mouse_world_positon,
        )
        if game.input.lmb == .Released {
            cm_cue_start_hit(
                &mode.player.cues[0],
                &mode.cue_hit_animation,
                mode.balls[mode.selected_ball].body.position,
            )
            mode.turn_state = .Hit
        }
    case .Hit:
        if cm_cue_hit(&mode.player.cues[0], &mode.cue_hit_animation, dt) {
            from_mouse :=
                mode.balls[mode.selected_ball].body.position - game.input.mouse_world_positon
            mode.balls[mode.selected_ball].body.velocity = from_mouse * 100 * dt
            mode.selected_ball = BALL_NOT_SELECTED
            mode.turn_state = .Taken
        }
    case .Taken:
        cm_cue_store(&mode.player.cues[0], dt)
        process_physics(
            mode.balls.collider[:],
            mode.balls.body[:],
            mode.borders.collider[:],
            mode.borders.position[:],
            dt,
        )
        all_stationary := true
        for &body in mode.balls.body {
            if body.velocity != {} do all_stationary = false
        }
        if all_stationary {
            mode.turn_owner = cast(TurnOwner)!cast(bool)mode.turn_owner
            mode.turn_state = .NotTaken
        }
    }

    cm_draw_table(game)
    cm_draw_balls(mode, game)
    cm_draw_ball_info(mode, game)
    cm_draw_cues(mode, game)
    cm_draw_cue_info(mode, game)
    // cm_draw_borders(mode, game)
    cm_draw_items(mode, game)
    cm_draw_item_use_line(mode, game, dt)
    cm_draw_player_infos(mode, game)

    shop := ui_draw_button(game, {320, 320}, "Show")
    if shop && game.input.lmb == .Pressed {
        if .InGameShop in game.state {
            game_state_change(game, IN_GAME_STATE)
        } else {
            game_state_change(game, IN_GAME_SHOP_STATE)
        }
    }

    back := ui_draw_button(game, {500, 320}, "Back")
    if back && game.input.lmb == .Pressed do game_state_change(game, MAIN_MENU_STATE)
}

cm_in_game_shop :: proc(mode: ^ClassicMode, game: ^Game, dt: f32) {
    reroll := ui_draw_button(game, in_state_position(IN_GAME_SHOP_STATE, {0, 320}), "Reroll")

    if reroll && game.input.lmb == .Pressed {
        cm_shop_reroll(mode)
    }

    for &item in mode.shop_items {
        if item.tag == .Invalid do continue
        hovered := cm_draw_item_info_panel(&item, game, {}, true, true)
        if hovered && game.input.lmb == .Pressed {
            if cm_player_info_add_item(&mode.player, item.tag) {
                item.tag = .Invalid
                continue
            }
        }
    }
}

cm_shop_reroll :: proc(mode: ^ClassicMode) {
    for &si in mode.shop_items {
        si.tag = .BallSpiky
    }
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

cm_draw_ball_info :: proc(mode: ^ClassicMode, game: ^Game) {
    PANEL_OFFSET :: Vec2{0, -180}
    PANEL_TEXT_OFFSET :: Vec2{-120, -100}

    for ball_body, i in mode.balls.body {
        if cm_ball_hovered(ball_body.position, game.input.mouse_world_positon) {
            offset := PANEL_OFFSET
            if ball_body.position.y < 0 do offset = -offset

            render_commands_add(
                &game.render_commands,
                DrawTextureCommand {
                    texture = &game.ball_info_panel_texture,
                    texture_area = texture_full_area(&game.ball_info_panel_texture),
                    texture_center = ball_body.position + offset,
                    ignore_alpha = false,
                },
            )

            render_commands_add(
                &game.render_commands,
                &game.font,
                ball_body.position + offset + PANEL_TEXT_OFFSET,
                "HP: %.01f\nDAMAGE: %.01f\nHEAL: %.01f\nARMOR: %.01f",
                mode.balls[i].hp,
                mode.balls[i].damage,
                mode.balls[i].heal,
                mode.balls[i].armor,
                center = false,
            )

            return
        }
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

cm_cue_adjust :: proc(
    cue: ^Cue,
    cue_default_position: Vec2,
    target_position: Vec2,
    mouse_default_position: Vec2,
    mouse_position: Vec2,
) {
    to_cue := linalg.normalize(cue.position - target_position)
    to_mp := mouse_position - mouse_default_position
    p := max(0, linalg.dot(to_mp, to_cue))
    cue.position = cue_default_position + to_cue * p
}

cm_cue_start_hit :: proc(
    cue: ^Cue,
    cue_hit_animation: ^SmoothStepAnimation,
    target_position: Vec2,
) {
    end_position, _ := cm_cue_aim_position_rotation(cue, target_position, cue.position)
    cue_hit_animation^ = {
        start_position = cue.position,
        end_position   = end_position,
        duration       = 1,
    }
}

cm_cue_hit :: proc(cue: ^Cue, cue_hit_animation: ^SmoothStepAnimation, dt: f32) -> bool {
    return ssa_update(cue_hit_animation, &cue.position, dt)
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

cm_cue_hovered :: proc(cue: ^Cue, mouse_positon: Vec2) -> bool {
    rect := Rectangle{cue.storage_position, {cue.width, cue.height}}
    return rectangle_contains(&rect, mouse_positon)
}

cm_draw_cue_info :: proc(mode: ^ClassicMode, game: ^Game) {
    PANEL_OFFSET :: Vec2{160, 0}
    PANEL_TEXT_OFFSET :: Vec2{-120, -35}

    draw_info :: proc(cue: ^Cue, game: ^Game, panel_offset: Vec2, text_offset: Vec2) {
        render_commands_add(
            &game.render_commands,
            DrawTextureCommand {
                texture = &game.cue_info_panel_texture,
                texture_area = texture_full_area(&game.cue_info_panel_texture),
                texture_center = cue.storage_position + panel_offset,
                ignore_alpha = false,
            },
        )

        render_commands_add(
            &game.render_commands,
            &game.font,
            cue.storage_position + panel_offset + text_offset,
            "Scope: %t\nSilencer: %t\nRocket booster: %t",
            cue.scope,
            cue.silencer,
            cue.rocket_booster,
            center = false,
        )
    }

    for &cue in mode.player.cues {
        if cm_cue_hovered(&cue, game.input.mouse_world_positon) {
            draw_info(&cue, game, PANEL_OFFSET, PANEL_TEXT_OFFSET)
        }
    }

    for &cue in mode.opponent.cues {
        if cm_cue_hovered(&cue, game.input.mouse_world_positon) {
            draw_info(&cue, game, -PANEL_OFFSET, PANEL_TEXT_OFFSET)
        }
    }
}

cm_item_hovered :: proc(item_position: Vec2, mouse_position: Vec2) -> bool {
    half_size: f32 = ITEM_SIZE / 2
    left := item_position.x - half_size
    right := item_position.x + half_size
    top := item_position.y - half_size
    bot := item_position.y + half_size

    return(
        left <= mouse_position.x &&
        mouse_position.x <= right &&
        top <= mouse_position.y &&
        mouse_position.y <= bot \
    )
}

cm_draw_items :: proc(mode: ^ClassicMode, game: ^Game) {
    INFO_PANEL_OFFSET := Vec2{0, -310}

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.items_background_texture,
            texture_area = texture_full_area(&game.items_background_texture),
            texture_center = PLAYER_ITEMS_BACKGROUND,
            ignore_alpha = true,
        },
    )

    for &item, i in mode.player.items {
        if item.tag == .Invalid do continue

        render_commands_add(
            &game.render_commands,
            DrawTextureCommand {
                texture = &game.item_ball_spiky_texture,
                texture_area = texture_full_area(&game.item_ball_spiky_texture),
                texture_center = item.position,
                ignore_alpha = false,
            },
        )

        if cm_item_hovered(item.position, game.input.mouse_world_positon) {
            if .InGameShop in game.state {
                cm_draw_item_info_panel(&item, game, -INFO_PANEL_OFFSET, false, false)
            } else {
                cm_draw_item_info_panel(&item, game, INFO_PANEL_OFFSET, false, false)
            }
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

    for &item, i in mode.opponent.items {
        if item.tag == .Invalid do continue

        render_commands_add(
            &game.render_commands,
            DrawTextureCommand {
                texture = &game.item_ball_spiky_texture,
                texture_area = texture_full_area(&game.item_ball_spiky_texture),
                texture_center = item.position,
                ignore_alpha = false,
            },
        )
        if cm_item_hovered(item.position, game.input.mouse_world_positon) {
            cm_draw_item_info_panel(&item, game, -INFO_PANEL_OFFSET, false, false)
        }
    }
}

cm_use_item :: proc(mode: ^ClassicMode, game: ^Game, dt: f32) {
    if mode.player.selected_item == ITEM_NOT_SELECTED {
        for &item, i in mode.player.items {
            if item.tag == .Invalid do continue
            if cm_item_hovered(item.position, game.input.mouse_world_positon) &&
               game.input.lmb == .Pressed {
                mode.player.selected_item = cast(u8)i
                log_info("Player selected: %d item", i)
            }
        }
    } else {
        if game.input.lmb == .Pressed {
            mode.player.selected_item = ITEM_NOT_SELECTED
        }
    }

    if mode.opponent.selected_item == ITEM_NOT_SELECTED {
        for &item, i in mode.opponent.items {
            if item.tag == .Invalid do continue
            if cm_item_hovered(item.position, game.input.mouse_world_positon) &&
               game.input.lmb == .Pressed {
                mode.opponent.selected_item = cast(u8)i
                log_info("Opponent selected: %d item", i)
            }
        }
    } else {
        if game.input.lmb == .Pressed {
            mode.opponent.selected_item = ITEM_NOT_SELECTED
        }
    }
}

cm_draw_item_use_line :: proc(mode: ^ClassicMode, game: ^Game, dt: f32) {
    {
        if mode.player.selected_item == ITEM_NOT_SELECTED do return
        item := &mode.player.items[mode.player.selected_item]
        mode.item_use_dashed_line.start = item.position
        mode.item_use_dashed_line.end = game.input.mouse_world_positon
        ui_draw_dashed_line(&mode.item_use_dashed_line, game, dt)
    }

    {
        if mode.opponent.selected_item == ITEM_NOT_SELECTED do return
        item := &mode.opponent.items[mode.opponent.selected_item]
        mode.item_use_dashed_line.start = item.position
        mode.item_use_dashed_line.end = game.input.mouse_world_positon
        ui_draw_dashed_line(&mode.item_use_dashed_line, game, dt)
    }
}

cm_draw_item_info_panel :: proc(
    item: ^Item,
    game: ^Game,
    offset: Vec2,
    hover_tint: bool,
    price: bool,
) -> bool {
    position := item.position + offset
    hovered := false
    if hover_tint {
        button_rect := Rectangle {
            position,
            {cast(f32)game.shop_panel_texture.width, cast(f32)game.shop_panel_texture.height},
        }
        hovered = rectangle_contains(&button_rect, game.input.mouse_world_positon)
    }

    tint := false
    tint_color := Color {
        a = 0,
    }
    if hovered {
        tint = true
        tint_color = Color {
            r = 128,
            a = 64,
        }
    }

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.shop_panel_texture,
            texture_area = texture_full_area(&game.shop_panel_texture),
            texture_center = position,
            ignore_alpha = false,
            tint = tint,
            tint_color = tint_color,
        },
    )

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.item_ball_spiky_texture,
            texture_area = texture_full_area(&game.item_ball_spiky_texture),
            texture_center = position,
            ignore_alpha = false,
        },
    )

    return hovered
}

cm_draw_player_info :: proc(info: ^PlayerInfo, position: Vec2, turn_owner: bool, game: ^Game) {
    BLOOD_OFFSET :: Vec2{-50, 0}
    SOULS_OFFSET :: Vec2{50, 0}
    UNDER_HP_PANEL_OFFSET :: Vec2{0, 25}

    render_commands_add(
        &game.render_commands,
        &game.font,
        position,
        "  %d  %d",
        info.hp,
        info.souls,
        center = true,
    )

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.blood_icon_texture,
            texture_area = texture_full_area(&game.blood_icon_texture),
            texture_center = position + BLOOD_OFFSET,
            ignore_alpha = true,
        },
    )
    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = &game.souls_icon_texture,
            texture_area = texture_full_area(&game.souls_icon_texture),
            texture_center = position + SOULS_OFFSET,
            ignore_alpha = true,
        },
    )

    panel_texture := &game.under_hp_bar_texture
    if turn_owner do panel_texture = &game.under_hp_bar_turn_texture
    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = panel_texture,
            texture_area = texture_full_area(panel_texture),
            texture_center = position + UNDER_HP_PANEL_OFFSET,
            ignore_alpha = true,
        },
    )
}

cm_draw_player_infos :: proc(mode: ^ClassicMode, game: ^Game) {
    PLAYER_INFO_POSITION :: Vec2{-520, 325}
    OPPONENT_INFO_POSITION :: Vec2{520, -310}

    cm_draw_player_info(&mode.player, PLAYER_INFO_POSITION, mode.turn_owner == .Player, game)
    cm_draw_player_info(&mode.opponent, OPPONENT_INFO_POSITION, mode.turn_owner == .Opponent, game)
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
