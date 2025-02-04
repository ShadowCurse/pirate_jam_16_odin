package game

@(export)
runtime_main :: proc(
    memory: ^Memory,
    pixels: []u32,
    width: u32,
    height: u32,
    input_state: ^InputState,
) {
    for i := 0; i < 200; i += 1 {
        pixels[i] = 0xFF00FF00
    }
}
