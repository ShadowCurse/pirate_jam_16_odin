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
    texture:  struct {
        data:   []u8,
        width:  u32,
        height: u32,
    },
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
        texture = {bitmap, 512, 512},
    }
}

font_get_kerning :: proc(font: ^Font, char_1: u8, char_2: u8) -> f32 {
    index := char_1 - ALL_CHARS[0]
    offset := char_2 - ALL_CHARS[0]
    return font.kerning[index * len(ALL_CHARS) + offset]
}
