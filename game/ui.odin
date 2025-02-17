package game

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
