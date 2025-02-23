package game

import "core:math"
import "core:math/linalg"

ui_draw_button :: proc(game: ^Game, position: Vec2, format: string, args: ..any) -> bool {
    button_rect := Rectangle {
        position,
        {cast(f32)game.button_normal_texture.width, cast(f32)game.button_normal_texture.height},
    }
    hovered := rectangle_contains(&button_rect, game.input.mouse_world_positon)
    texture := &game.button_normal_texture
    if hovered do texture = &game.button_hover_texture

    render_commands_add(
        &game.render_commands,
        DrawTextureCommand {
            texture = texture,
            texture_area = texture_full_area(texture),
            texture_center = position,
            ignore_alpha = false,
        },
    )
    render_commands_add(
        &game.render_commands,
        &game.font,
        position + {0, game.font.size / 4},
        format,
        ..args,
        center = true,
        in_world_space = true,
    )

    return hovered
}


UiDashedLine :: struct {
    start:       Vec2,
    end:         Vec2,
    accumulator: f32,
}

ui_draw_dashed_line :: proc(line: ^UiDashedLine, game: ^Game, dt: f32) {
    COLOR :: WHITE
    WIDTH: f32 : 5.000
    SEGMENT_GAP :: 15.000
    SEGMENT_LENGTH: f32 : 20.000
    TOTAL_SEGMENT_LEN: f32 : 35.000
    ANIMATION_SPEED: f32 : 20.000

    ARROW_ANGLE: f32 : 0.785
    ARROW_H: f32 : 10.308
    ARROW_ANGLE_A: f32 : 0.245
    ARROW_ANGLE_A_ADJ: f32 : 0.540
    ARROW_ANGLE_C: f32 : 1.030
    ARROW_DELTA: f32 : 8.839
    ARROW_DELTA_PERP: f32 : 5.303

    line.accumulator += ANIMATION_SPEED * dt
    animation_offset: f32 = cast(f32)(cast(u32)line.accumulator %
        cast(u32)(SEGMENT_LENGTH + SEGMENT_GAP))

    delta := line.end - line.start
    delta_len := linalg.length(delta)
    delta_normalized := delta * (1.0 / delta_len)
    actual_len: f32 = delta_len - animation_offset
    if actual_len <= 0.0 do return

    c := linalg.cross(delta_normalized, Vec2{0, 1})
    d := linalg.dot(delta_normalized, Vec2{0, 1})
    rotation: f32 = ---
    if (c < 0.0) {
        rotation = -math.acos(d)
    } else {rotation = math.acos(d)}
    num_segments := cast(u32)math.floor(actual_len / TOTAL_SEGMENT_LEN)
    first_segment_len := animation_offset - SEGMENT_GAP
    last_segment_len := actual_len - cast(f32)num_segments * TOTAL_SEGMENT_LEN - ARROW_DELTA
    segment_position := line.start + delta_normalized * (SEGMENT_LENGTH / 2 + animation_offset)
    for _ in 0 ..< num_segments {
        size := Vec2{WIDTH, SEGMENT_LENGTH}

        render_commands_add(
            &game.render_commands,
            DrawColorRectangleCommand{rectangle = {segment_position, size}, color = COLOR},
        )

        segment_position = segment_position + delta_normalized * TOTAL_SEGMENT_LEN
    }

    if (0.0 < first_segment_len) {
        first_segment_positon := line.start + delta_normalized * (first_segment_len / 2.0)
        size := Vec2{WIDTH, first_segment_len}

        render_commands_add(
            &game.render_commands,
            DrawColorRectangleCommand{rectangle = {first_segment_positon, size}, color = COLOR},
        )
    }

    if (0.0 < last_segment_len) {
        last_segment_len := min(last_segment_len, SEGMENT_LENGTH)
        segment_position :=
            segment_position + delta_normalized * (-SEGMENT_LENGTH / 2 + last_segment_len / 2.0)
        size := Vec2{WIDTH, last_segment_len}

        render_commands_add(
            &game.render_commands,
            DrawColorRectangleCommand{rectangle = {segment_position, size}, color = COLOR},
        )
    }

    delta_perp := perp(delta_normalized)
    {
        arrow_left_segment_positon :=
            line.end + delta_normalized * -ARROW_DELTA + delta_perp * ARROW_DELTA_PERP
        size := Vec2{WIDTH, SEGMENT_LENGTH}

        render_commands_add(
            &game.render_commands,
            DrawColorRectangleCommand {
                rectangle = {arrow_left_segment_positon, size},
                color = COLOR,
            },
        )

    }

    {
        arrow_right_segment_positon :=
            line.end + delta_normalized * -ARROW_DELTA + delta_perp * -ARROW_DELTA_PERP
        size := Vec2{WIDTH, SEGMENT_LENGTH}

        render_commands_add(
            &game.render_commands,
            DrawColorRectangleCommand {
                rectangle = {arrow_right_segment_positon, size},
                color = COLOR,
            },
        )
    }
}
