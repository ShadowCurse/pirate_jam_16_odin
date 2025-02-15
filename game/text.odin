package game

import "../platform"
import stb "vendor:stb/truetype"

ALL_CHARS :: " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

Font :: struct {
    size:     f32,
    scale:    f32,
    line_gap: f32,
    chars:    []stb.bakedchar,
    kerning:  []f32,
    texture:  Texture,
}

font_load :: proc(path: cstring, font_size: f32) -> Font {
    using platform

    file_memory := file_memory_open(path)
    defer file_memory_close(&file_memory)

    offset := stb.GetFontOffsetForIndex(raw_data(file_memory), 0)
    font: stb.fontinfo = ---
    stb.InitFont(&font, raw_data(file_memory), offset)

    chars, chars_err := make([]stb.bakedchar, font.numGlyphs)
    assert(chars_err == nil, "Cannot allocate memory for font char info. Font path: %s", path)

    bitmap, bitmap_err := make([]u8, 512 * 512)
    assert(bitmap_err == nil, "Cannot allocate memory for font bitmap. Font path: %s", path)

    stb.BakeFontBitmap(
        raw_data(file_memory),
        0,
        font_size,
        raw_data(bitmap),
        512,
        512,
        0,
        font.numGlyphs,
        raw_data(chars),
    )

    ascent: i32 = ---
    decent: i32 = ---
    lg: i32 = ---
    stb.GetFontVMetrics(&font, &ascent, &decent, &lg)

    scale := font_size / cast(f32)ascent
    line_gap := cast(f32)(ascent - decent + lg)

    kerning, kerning_err := make([]f32, len(ALL_CHARS) * len(ALL_CHARS))
    assert(
        kerning_err == nil,
        "Cannot allocate memory for font kerning table. Font path: %s",
        path,
    )
    kerning_index := 0
    for c1 in ALL_CHARS {
        for c2 in ALL_CHARS {
            kerning[kerning_index] = cast(f32)stb.GetCodepointKernAdvance(&font, c1, c2)
            kerning_index += 1
        }
    }

    log_info(
        "Loaded font: %s size: %f scale: %f chars: %d",
        path,
        font_size,
        scale,
        font.numGlyphs,
    )

    return {
        size = font_size,
        scale = scale,
        line_gap = line_gap,
        chars = chars,
        kerning = kerning,
        texture = {bitmap, 512, 512, 1},
    }
}

font_get_kerning :: proc(font: ^Font, prev_char: u8, char: u8) -> f32 {
    index := prev_char - ALL_CHARS[0]
    offset := char - ALL_CHARS[0]
    kerning_index := cast(u32)index * len(ALL_CHARS) + cast(u32)offset
    return font.kerning[kerning_index]
}

import "core:fmt"

CharDrawInfo :: struct {
    screen_position: Vec2,
    texture_area:    TextureArea,
}

draw_text :: proc(
    render_commands: ^RenderCommands,
    font: ^Font,
    position: Vec2,
    format: string,
    args: ..any,
    center := false,
    kerning := true,
) {
    str := fmt.tprintf(format, ..args)
    char_draw_infos := make([]CharDrawInfo, len(str), allocator = context.temp_allocator)

    line_start_index := 0
    global_offset := Vec2{}
    for i in 0 ..< len(str) {
        char := str[i]
        char_draw_info := &char_draw_infos[i]

        if char == '\n' {
            draw_text_line(
                render_commands,
                font,
                char_draw_infos[line_start_index:i],
                global_offset.x,
                center,
            )
            line_start_index = i + 1
            global_offset.x = 0
            global_offset.y = font.line_gap * font.scale
            continue
        }

        char_info := font.chars[char]
        char_width := char_info.x1 - char_info.x0
        char_height := char_info.y1 - char_info.y0

        if (kerning && i != line_start_index) {
            prev_char := str[i - 1]
            char_kerning := font_get_kerning(font, prev_char, char)
            global_offset.x += char_kerning * font.scale
        }

        char_offset := Vec2 {
            char_info.xoff + cast(f32)char_width * 0.5,
            char_info.yoff + cast(f32)char_height * 0.5,
        }
        char_draw_info^ = {
            screen_position = position + global_offset + char_offset,
            texture_area    = {
                {cast(u32)char_info.x0, cast(u32)char_info.y0},
                {cast(u32)char_width, cast(u32)char_height},
            },
        }

        global_offset.x += char_info.xadvance
    }

    draw_text_line(
        render_commands,
        font,
        char_draw_infos[line_start_index:],
        global_offset.x,
        center,
    )
}

draw_text_line :: proc(
    render_commands: ^RenderCommands,
    font: ^Font,
    char_draw_infos: []CharDrawInfo,
    total_width: f32,
    center := false,
) {
    if center {
        half_width := total_width / 2
        for &cdi in char_draw_infos {
            cdi.screen_position -= {half_width, 0}
        }
    }

    for &cdi in char_draw_infos {
        render_commands_add(
            render_commands,
            DrawTextureCommand {
                texture = &font.texture,
                texture_area = cdi.texture_area,
                texture_center = cdi.screen_position,
                ignore_alpha = false,
            },
            in_world_space = false,
        )
    }
}
